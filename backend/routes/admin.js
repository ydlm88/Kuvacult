const express = require('express');
const { query } = require('../db');
const { getStats } = require('../req_stats');
const { sendBugReport } = require('../mailer');

const router = express.Router();

const TABLES = [
    'users',
    'watchlists',
    'movies',
    'reviews',
    'review_comments',
    'friend_requests',
    'activity',
    'media',
];

const ORDER_BY = {
    users: 'ORDER BY created_at DESC',
    watchlists: 'ORDER BY created_at DESC',
    movies: 'ORDER BY added_at DESC',
    reviews: 'ORDER BY at DESC',
    review_comments: 'ORDER BY at DESC',
    friend_requests: 'ORDER BY created_at DESC',
    activity: 'ORDER BY at DESC',
    media: 'ORDER BY updated_at DESC',
};

// GET /admin/tables/:table
router.get('/tables/:table', async (req, res) => {
    const { table } = req.params;
    if (!TABLES.includes(table)) {
        return res.status(400).json({ error: `Unknown table: ${table}` });
    }
    try {
        const order = ORDER_BY[table] ?? '';
        const result = await query(`SELECT * FROM ${table} ${order} LIMIT 500`);
        res.json({ rows: result.rows });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// DELETE /admin/tables/:table/:id
router.delete('/tables/:table/:id', async (req, res) => {
    const { table } = req.params;
    const id = req.params.id;
    if (!TABLES.includes(table)) {
        return res.status(400).json({ error: `Unknown table: ${table}` });
    }
    try {
        // Cascade-safe cleanup for watchlists before deleting the parent row
        if (table === 'watchlists') {
            await query('DELETE FROM movies              WHERE watchlist_id = $1', [id]);
            await query('DELETE FROM activity            WHERE watchlist_id = $1', [id]);
            try {
                await query('DELETE FROM veto_sessions WHERE watchlist_id = $1', [id]);
            } catch (_) {}
            try {
                await query('DELETE FROM watchlist_invites WHERE watchlist_id = $1', [id]);
            } catch (_) {}
        }
        const r = await query(`DELETE FROM ${table} WHERE id = $1 RETURNING id`, [id]);
        if (r.rows.length === 0) return res.status(404).json({ error: 'Row not found' });
        res.json({ deleted: id, table });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// GET /admin/counts
router.get('/counts', async (req, res) => {
    try {
        const counts = {};
        for (const t of TABLES) {
            const r = await query(`SELECT COUNT(*)::int AS n FROM ${t}`);
            counts[t] = r.rows[0].n;
        }
        res.json(counts);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// POST /admin/sql
router.post('/sql', async (req, res) => {
    const { sql } = req.body;
    if (!sql || typeof sql !== 'string') {
        return res.status(400).json({ error: 'sql string required' });
    }
    const trimmed = sql.trim().toUpperCase();
    if (!trimmed.startsWith('SELECT') && !trimmed.startsWith('EXPLAIN')) {
        return res.status(403).json({ error: 'Only SELECT queries are allowed via this endpoint' });
    }
    try {
        const result = await query(sql);
        res.json({ rows: result.rows, rowCount: result.rowCount });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// GET /admin/system
router.get('/system', async (req, res) => {
    try {
        const sizeR = await query(
            `SELECT pg_size_pretty(pg_database_size(current_database())) AS pretty,
              pg_database_size(current_database())                  AS bytes`
        );
        const mem = process.memoryUsage();
        res.json({
            dbSizePretty: sizeR.rows[0].pretty,
            dbSizeBytes: parseInt(sizeR.rows[0].bytes),
            uptimeSeconds: Math.round(process.uptime()),
            memRssMb: Math.round(mem.rss / 1024 / 1024),
            memHeapMb: Math.round(mem.heapUsed / 1024 / 1024),
            traffic: getStats(),
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// POST /admin/bug-report
router.post('/bug-report', async (req, res) => {
    const { text, userId } = req.body;
    if (!text || typeof text !== 'string' || text.trim().length === 0) {
        return res.status(400).json({ error: 'text is required' });
    }
    if (text.length > 1000) {
        return res.status(400).json({ error: 'text must be 1000 characters or fewer' });
    }
    try {
        let fromUsername = null;
        let fromEmail = null;
        if (userId) {
            const r = await query('SELECT username, email FROM users WHERE id = $1', [userId]);
            if (r.rows.length) {
                fromUsername = r.rows[0].username;
                fromEmail = r.rows[0].email;
            }
        }
        await sendBugReport({ text: text.trim(), fromUserId: userId, fromUsername, fromEmail });
        res.json({ ok: true });
    } catch (err) {
        console.error('Bug report mail failed:', err.message);
        res.status(500).json({ error: 'Failed to send report' });
    }
});

module.exports = router;
