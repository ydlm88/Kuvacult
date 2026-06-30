// Authentication routes for register, verify email, login, token refresh,
// forgot/reset password, and logout. Rate-limited via authLimiter; works behind
// Cloudflare Tunnel by trusting CF-Connecting-IP from loopback requests only.
const crypto = require('crypto');
const express = require('express');
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const rateLimit = require('express-rate-limit');
const { query } = require('../db');
const { sendVerificationEmail, sendPasswordResetEmail } = require('../mailer');

const router = express.Router();

// Behind Cloudflare Tunnel all requests arrive from 127.0.0.1, so we trust
// CF-Connecting-IP only from loopback to prevent a direct caller forging it.
const authLimiter = rateLimit({
    windowMs: 15 * 60 * 1000,
    max: 10,
    message: { error: 'Too many attempts, please try again in 15 minutes' },
    standardHeaders: true,
    legacyHeaders: false,
    validate: { keyGeneratorIpFallback: false },
    keyGenerator: (req) => {
        const fromLoopback =
            req.ip === '127.0.0.1' || req.ip === '::1' || req.ip === '::ffff:127.0.0.1';
        const cfIp = req.headers['cf-connecting-ip'];
        return fromLoopback && cfIp ? cfIp : req.ip;
    },
});

const SALT_ROUNDS = 12;
const ACCESS_TTL = '15m';
const REFRESH_DAYS = 30;

function issueAccessToken(user) {
    return jwt.sign(
        { sub: user.id, username: user.username, email: user.email },
        process.env.JWT_SECRET,
        { expiresIn: ACCESS_TTL }
    );
}

function makeRefreshToken() {
    return crypto.randomBytes(40).toString('hex');
}
function hashToken(token) {
    return crypto.createHash('sha256').update(token).digest('hex');
}

function userShape(row) {
    return {
        id: row.id,
        username: row.username,
        email: row.email,
        displayName: row.display_name,
        avatarUrl: row.avatar_url,
        avatarBg: row.avatar_bg,
        roomKey: row.room_key,
        friendIds: row.friend_ids ?? [],
        watchlistIds: row.watchlist_ids ?? [],
    };
}

// POST /auth/register
router.post('/register', authLimiter, async (req, res) => {
    try {
        const { username, email, password, displayName = '' } = req.body;
        if (!username || !email || !password) {
            return res.status(400).json({ error: 'username, email and password are required' });
        }
        if (password.length < 8) {
            return res.status(400).json({ error: 'Password must be at least 8 characters' });
        }
        if (username.trim().length < 2 || !/^[a-zA-Z0-9_]+$/.test(username.trim())) {
            return res
                .status(400)
                .json({
                    error: 'Username must be 2+ characters: letters, numbers, underscores only',
                });
        }
        if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim())) {
            return res.status(400).json({ error: 'Invalid email address' });
        }

        const passwordHash = await bcrypt.hash(password, SALT_ROUNDS);
        const id = crypto.randomUUID();
        const verificationToken = crypto.randomBytes(32).toString('hex');

        const result = await query(
            `INSERT INTO users
         (id, username, email, password_hash, display_name, email_verified, verification_token)
       VALUES ($1, $2, $3, $4, $5, FALSE, $6)
       RETURNING *`,
            [
                id,
                username.trim(),
                email.trim().toLowerCase(),
                passwordHash,
                displayName.trim() || username.trim(),
                verificationToken,
            ]
        );
        const user = result.rows[0];

        try {
            await sendVerificationEmail(user.email, verificationToken);
        } catch (mailErr) {
            console.warn('Email send failed (SMTP not configured?):', mailErr.message);
        }

        res.status(201).json({
            message: 'Account created. Check your email to verify before logging in.',
            userId: user.id,
        });
    } catch (err) {
        if (err.code === '23505') {
            const field = err.constraint?.includes('email') ? 'email' : 'username';
            return res.status(409).json({ error: `${field} already taken` });
        }
        res.status(500).json({ error: err.message });
    }
});

// GET /auth/verify?token=
router.get('/verify', async (req, res) => {
    const { token } = req.query;
    if (!token) return res.status(400).send('Missing token.');

    try {
        const r = await query(
            `UPDATE users SET email_verified = TRUE, verification_token = NULL
       WHERE verification_token = $1 RETURNING id, username`,
            [token]
        );
        if (!r.rows.length) {
            return res.status(400).send('Invalid or expired verification link.');
        }
        res.send(`
      <html><body style="font-family:sans-serif;text-align:center;padding:60px">
        <h2>Email verified!</h2>
        <p>Your Kuvacult account is now active. You can close this tab and sign in.</p>
      </body></html>
    `);
    } catch (err) {
        res.status(500).send('Something went wrong.');
    }
});

// POST /auth/resend-verification
router.post('/resend-verification', authLimiter, async (req, res) => {
    try {
        const { email } = req.body;
        if (!email) return res.status(400).json({ error: 'email required' });

        const r = await query('SELECT id, email, email_verified FROM users WHERE email = $1', [
            email.trim().toLowerCase(),
        ]);
        const user = r.rows[0];
        if (!user || user.email_verified) {
            // Don't leak whether email exists — always return success
            return res.json({ ok: true });
        }

        const newToken = crypto.randomBytes(32).toString('hex');
        await query('UPDATE users SET verification_token = $1 WHERE id = $2', [newToken, user.id]);
        try {
            await sendVerificationEmail(user.email, newToken);
        } catch (_) {}

        res.json({ ok: true });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// POST /auth/login
router.post('/login', authLimiter, async (req, res) => {
    try {
        const { email, password } = req.body;
        if (!email || !password) {
            return res.status(400).json({ error: 'email and password are required' });
        }

        const result = await query('SELECT * FROM users WHERE email = $1', [
            email.trim().toLowerCase(),
        ]);
        const user = result.rows[0];

        const dummyHash = '$2b$12$invalidhashXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX';
        const match = await bcrypt.compare(password, user?.password_hash ?? dummyHash);
        if (!user || !match) return res.status(401).json({ error: 'Invalid credentials' });

        if (!user.email_verified) {
            return res.status(403).json({
                error: 'Please verify your email before logging in.',
                code: 'email_not_verified',
            });
        }

        const accessToken = issueAccessToken(user);
        const refreshToken = makeRefreshToken();
        const expiresAt = new Date(Date.now() + REFRESH_DAYS * 86400 * 1000);

        await query(
            `INSERT INTO refresh_tokens (id, user_id, token_hash, expires_at)
       VALUES ($1, $2, $3, $4)`,
            [crypto.randomUUID(), user.id, hashToken(refreshToken), expiresAt]
        );

        res.json({ accessToken, refreshToken, user: userShape(user) });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// POST /auth/refresh
router.post('/refresh', async (req, res) => {
    try {
        const { refreshToken } = req.body;
        if (!refreshToken) return res.status(400).json({ error: 'refreshToken required' });

        const hash = hashToken(refreshToken);
        const r = await query(
            `SELECT rt.user_id, rt.expires_at, u.*
       FROM refresh_tokens rt JOIN users u ON u.id = rt.user_id
       WHERE rt.token_hash = $1`,
            [hash]
        );
        const row = r.rows[0];
        if (!row) return res.status(401).json({ error: 'Invalid refresh token' });
        if (new Date(row.expires_at) < new Date()) {
            await query('DELETE FROM refresh_tokens WHERE token_hash = $1', [hash]);
            return res.status(401).json({ error: 'Refresh token expired' });
        }

        const accessToken = issueAccessToken(row);
        res.json({ accessToken });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// POST /auth/forgot-password
// Always returns 200 regardless of whether the email exists to prevent enumeration.
router.post('/forgot-password', authLimiter, async (req, res) => {
    try {
        const { email } = req.body;
        if (!email) return res.status(400).json({ error: 'email required' });

        const r = await query('SELECT id, email_verified FROM users WHERE email = $1', [
            email.trim().toLowerCase(),
        ]);
        const user = r.rows[0];

        // Silently skip unregistered/unverified addresses
        if (user && user.email_verified) {
            const rawToken = crypto.randomBytes(32).toString('hex');
            const tokenHash = hashToken(rawToken);
            const expires = new Date(Date.now() + 60 * 60 * 1000);

            await query(
                'UPDATE users SET reset_token_hash = $1, reset_token_expires = $2 WHERE id = $3',
                [tokenHash, expires, user.id]
            );

            try {
                await sendPasswordResetEmail(email.trim().toLowerCase(), rawToken);
            } catch (mailErr) {
                console.warn('Password reset email failed:', mailErr.message);
            }
        }

        res.json({ ok: true });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// GET /auth/reset-password?token=
router.get('/reset-password', async (req, res) => {
    const { token } = req.query;
    if (!token || !/^[0-9a-f]{64}$/.test(token)) {
        return res.status(400).send('<p>Invalid or missing reset token.</p>');
    }

    try {
        const r = await query(
            'SELECT id FROM users WHERE reset_token_hash = $1 AND reset_token_expires > NOW()',
            [hashToken(token)]
        );
        if (!r.rows.length) {
            return res.status(400).send(`
        <html><body style="font-family:sans-serif;text-align:center;padding:60px">
          <h2>Link expired</h2>
          <p>This reset link has expired or already been used. Request a new one in the app.</p>
        </body></html>
      `);
        }

        res.send(`
      <html>
      <head><meta name="viewport" content="width=device-width,initial-scale=1"></head>
      <body style="font-family:sans-serif;max-width:400px;margin:60px auto;padding:0 20px">
        <h2>Reset your password</h2>
        <form method="POST" action="/auth/reset-password">
          <input type="hidden" name="token" value="${token}">
          <div style="margin-bottom:16px">
            <label style="display:block;margin-bottom:6px;color:#555">New password</label>
            <input type="password" name="password" required minlength="8"
              style="width:100%;padding:10px;border:1px solid #ddd;border-radius:6px;font-size:15px;box-sizing:border-box">
          </div>
          <div style="margin-bottom:20px">
            <label style="display:block;margin-bottom:6px;color:#555">Confirm password</label>
            <input type="password" name="confirm" required minlength="8"
              style="width:100%;padding:10px;border:1px solid #ddd;border-radius:6px;font-size:15px;box-sizing:border-box">
          </div>
          <button type="submit"
            style="width:100%;padding:12px;background:#F6C453;border:none;border-radius:8px;font-size:16px;font-weight:600;cursor:pointer">
            Set new password
          </button>
        </form>
      </body>
      </html>
    `);
    } catch (err) {
        res.status(500).send('Something went wrong.');
    }
});

// POST /auth/reset-password
router.post('/reset-password', async (req, res) => {
    const { token, password, confirm } = req.body;

    if (!token || !password || !confirm) {
        return res.status(400).send('All fields are required.');
    }
    if (!/^[0-9a-f]{64}$/.test(token)) {
        return res.status(400).send('Invalid token.');
    }
    if (password !== confirm) {
        return res.status(400).send('Passwords do not match.');
    }
    if (password.length < 8) {
        return res.status(400).send('Password must be at least 8 characters.');
    }

    try {
        const r = await query(
            'SELECT id, password_hash FROM users WHERE reset_token_hash = $1 AND reset_token_expires > NOW()',
            [hashToken(token)]
        );
        if (!r.rows.length) {
            return res.status(400).send(`
        <html><body style="font-family:sans-serif;text-align:center;padding:60px">
          <h2>Link expired</h2>
          <p>This reset link has expired or already been used. Request a new one in the app.</p>
        </body></html>
      `);
        }

        const { id: userId, password_hash: currentHash } = r.rows[0];

        const isSamePassword = await bcrypt.compare(password, currentHash);
        if (isSamePassword) {
            return res
                .status(400)
                .send('New password must be different from your current password.');
        }

        const passwordHash = await bcrypt.hash(password, SALT_ROUNDS);

        await query(
            'UPDATE users SET password_hash = $1, reset_token_hash = NULL, reset_token_expires = NULL WHERE id = $2',
            [passwordHash, userId]
        );
        // Revoke all active sessions so the old password can no longer be used
        await query('DELETE FROM refresh_tokens WHERE user_id = $1', [userId]);

        res.send(`
      <html><body style="font-family:sans-serif;text-align:center;padding:60px">
        <h2>Password updated!</h2>
        <p>Your password has been reset. You can now sign in with your new password.</p>
      </body></html>
    `);
    } catch (err) {
        res.status(500).send('Something went wrong.');
    }
});

// POST /auth/logout
router.post('/logout', async (req, res) => {
    try {
        const { refreshToken } = req.body;
        if (refreshToken) {
            await query('DELETE FROM refresh_tokens WHERE token_hash = $1', [
                hashToken(refreshToken),
            ]);
        }
        res.json({ ok: true });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

module.exports = router;
