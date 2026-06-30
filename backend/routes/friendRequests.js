// Friend request routes — send, accept, decline, and list friend requests.
const crypto = require('crypto');
const express = require('express');
const { query } = require('../db');
const { requireAuth } = require('../middleware/auth');

const router = express.Router();

async function arrayAdd(table, col, val, rowId) {
    await query(
        `UPDATE ${table}
     SET ${col} = CASE WHEN ${col} @> $1::jsonb THEN ${col}
                       ELSE ${col} || $1::jsonb END
     WHERE id = $2`,
        [JSON.stringify([val]), rowId]
    );
}

// POST /friend-requests
router.post('/', requireAuth, async (req, res) => {
    try {
        const { fromId, toId } = req.body;
        if (!fromId || !toId)
            return res.status(400).json({ error: 'fromId and toId are required' });
        if (fromId === toId)
            return res.status(400).json({ error: 'Cannot send a friend request to yourself' });
        if (req.user.sub !== fromId) return res.status(403).json({ error: 'Forbidden' });

        const fromR = await query('SELECT friend_ids FROM users WHERE id = $1', [fromId]);
        if (!fromR.rows.length) return res.status(404).json({ error: 'Sender not found' });
        if ((fromR.rows[0].friend_ids ?? []).includes(toId))
            return res.status(409).json({ error: 'Already friends' });

        const dupR = await query(
            `SELECT id FROM friend_requests WHERE from_id = $1 AND to_id = $2 AND status = 'pending' LIMIT 1`,
            [fromId, toId]
        );
        if (dupR.rows.length)
            return res.status(409).json({ error: 'Friend request already pending' });

        const id = crypto.randomUUID();
        await query(
            `INSERT INTO friend_requests (id, from_id, to_id, status) VALUES ($1, $2, $3, 'pending')`,
            [id, fromId, toId]
        );
        res.status(201).json({ id, fromId, toId, status: 'pending' });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// PATCH /friend-requests/:id/accept
router.patch('/:id/accept', requireAuth, async (req, res) => {
    try {
        const r = await query('SELECT * FROM friend_requests WHERE id = $1', [req.params.id]);
        if (!r.rows.length) return res.status(404).json({ error: 'Friend request not found' });
        const { from_id: fromId, to_id: toId, status } = r.rows[0];
        if (status !== 'pending')
            return res.status(409).json({ error: 'Request is no longer pending' });
        if (req.user.sub !== toId) return res.status(403).json({ error: 'Forbidden' });

        await query(`UPDATE friend_requests SET status = 'accepted' WHERE id = $1`, [
            req.params.id,
        ]);
        await arrayAdd('users', 'friend_ids', fromId, toId);
        await arrayAdd('users', 'friend_ids', toId, fromId);

        res.json({ id: req.params.id, status: 'accepted' });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// DELETE /friend-requests/:id — decline or cancel
router.delete('/:id', requireAuth, async (req, res) => {
    try {
        const r = await query('SELECT from_id, to_id FROM friend_requests WHERE id = $1', [
            req.params.id,
        ]);
        if (!r.rows.length) return res.status(404).json({ error: 'Friend request not found' });
        const { from_id: fromId, to_id: toId } = r.rows[0];
        if (req.user.sub !== fromId && req.user.sub !== toId)
            return res.status(403).json({ error: 'Forbidden' });

        await query(`UPDATE friend_requests SET status = 'declined' WHERE id = $1`, [
            req.params.id,
        ]);
        res.json({ id: req.params.id, status: 'declined' });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

module.exports = router;
