const nodemailer = require('nodemailer');

const transporter = nodemailer.createTransport({
    host: process.env.SMTP_HOST,
    port: parseInt(process.env.SMTP_PORT),
    secure: false,
    auth: {
        user: process.env.SMTP_USER,
        pass: process.env.SMTP_PASS,
    },
});

const APP_URL = process.env.APP_URL;
const FROM = process.env.SMTP_FROM;

async function sendVerificationEmail(email, token) {
    const link = `${APP_URL}/auth/verify?token=${token}`;
    await transporter.sendMail({
        from: `"Kuvacult" <${FROM}>`,
        to: email,
        subject: 'Verify your Kuvacult account',
        html: `
      <div style="font-family:sans-serif;max-width:480px;margin:0 auto;padding:32px">
        <h2 style="margin:0 0 8px">Your initiation begins now</h2>
        <p style="color:#888;margin:0 0 24px">Click the button below to verify your email and activate your account.</p>
        <a href="${link}"
           style="display:inline-block;padding:14px 28px;background:#F6C453;color:#000;
                  font-weight:600;border-radius:10px;text-decoration:none">
          Verify Email
        </a>
        <p style="color:#aaa;font-size:12px;margin-top:24px">
          Or paste this link into your browser:<br>${link}
        </p>
      </div>
    `,
    });
}

async function sendBugReport({ text, fromUserId, fromUsername, fromEmail }) {
    const who = fromUsername
        ? `${fromUsername}${fromEmail ? ` <${fromEmail}>` : ''} (id: ${fromUserId})`
        : 'Guest / unauthenticated user';
    await transporter.sendMail({
        from: `"Kuvacult Bug Reports" <${FROM}>`,
        to: 'kuvacult@gmail.com',
        subject: `[Bug Report] from ${fromUsername ?? 'guest'}`,
        html: `
      <div style="font-family:sans-serif;max-width:560px;margin:0 auto;padding:32px">
        <h2 style="margin:0 0 4px;color:#c0392b">Bug Report</h2>
        <p style="color:#888;font-size:12px;margin:0 0 20px">Submitted via the Kuvacult app</p>
        <p style="color:#555;font-size:12px;margin:0 0 16px"><strong>From:</strong> ${who}</p>
        <div style="background:#f8f8f8;border-left:3px solid #F6C453;padding:16px 20px;
                    border-radius:0 8px 8px 0;white-space:pre-wrap;font-size:14px;
                    line-height:1.6;color:#222">
          ${text.replace(/</g, '&lt;').replace(/>/g, '&gt;')}
        </div>
      </div>
    `,
    });
}

async function sendPasswordResetEmail(email, token) {
    const link = `${APP_URL}/auth/reset-password?token=${token}`;
    await transporter.sendMail({
        from: `"Kuvacult" <${FROM}>`,
        to: email,
        subject: 'Reset your Kuvacult password',
        html: `
      <div style="font-family:sans-serif;max-width:480px;margin:0 auto;padding:32px">
        <h2 style="margin:0 0 8px">Reset your password</h2>
        <p style="color:#888;margin:0 0 24px">Click the button below to set a new password. This link expires in 1 hour.</p>
        <a href="${link}"
           style="display:inline-block;padding:14px 28px;background:#F6C453;color:#000;
                  font-weight:600;border-radius:10px;text-decoration:none">
          Reset Password
        </a>
        <p style="color:#aaa;font-size:12px;margin-top:24px">
          If you didn't request this, ignore this email — your password won't change.<br>
          Or paste this link: ${link}
        </p>
      </div>
    `,
    });
}

module.exports = { sendVerificationEmail, sendPasswordResetEmail, sendBugReport };
