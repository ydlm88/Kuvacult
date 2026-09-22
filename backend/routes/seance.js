// seance.js — Start, join, end, and query active séance sessions.
// LiveKit handles the WebRTC media; this route mints access tokens and
// tracks the active session in seance_sessions.
const express = require('express');
const { AccessToken } = require('livekit-server-sdk');
const { query } = require('../db');
const { requireAuth } = require('../middleware/auth');

const router = express.Router();

let _broadcastToUser = () => {};
let _broadcastToWatchlist = () => {};

async function mintToken(userId, displayName, roomName, canPublish, metadata = '') {
    const at = new AccessToken(
        process.env.LIVEKIT_API_KEY,
        process.env.LIVEKIT_API_SECRET,
        { identity: userId, name: displayName, metadata }
    );
    at.addGrant({
        roomJoin: true,
        room: roomName,
        canPublish,
        canSubscribe: true,
        canPublishData: true,
    });
    return await at.toJwt();
}

// POST /seance/start
router.post('/start', requireAuth, async (req, res) => {
    try {
        const { watchlistId } = req.body;
        if (!watchlistId) return res.status(400).json({ error: 'watchlistId required' });
        const userId = req.user.sub;

        const wlR = await query('SELECT member_ids FROM watchlists WHERE id = $1', [watchlistId]);
        if (!wlR.rows.length) return res.status(404).json({ error: 'Watchlist not found' });
        const memberIds = wlR.rows[0].member_ids ?? [];
        if (!memberIds.includes(userId)) return res.status(403).json({ error: 'Forbidden' });

        // Clear any stale session this user is hosting (e.g. after an app crash).
        const hosting = await query(
            'SELECT watchlist_id FROM seance_sessions WHERE host_id = $1', [userId]
        );
        if (hosting.rows.length) {
            const staleWlId = hosting.rows[0].watchlist_id;
            await query('DELETE FROM seance_sessions WHERE host_id = $1', [userId]);
            _broadcastToWatchlist(staleWlId, { type: 'seance_ended', watchlistId: staleWlId });
        }

        const existing = await query(
            'SELECT watchlist_id FROM seance_sessions WHERE watchlist_id = $1', [watchlistId]
        );
        if (existing.rows.length) return res.status(409).json({ error: 'A séance is already active for this watchlist' });

        const userR = await query('SELECT display_name, avatar_url FROM users WHERE id = $1', [userId]);
        const hostName = userR.rows[0]?.display_name || '';
        const hostAvatarUrl = userR.rows[0]?.avatar_url || null;

        const livekitRoom = `seance_${watchlistId}`;
        const token = await mintToken(userId, hostName || userId, livekitRoom, true, JSON.stringify({ avatarUrl: hostAvatarUrl }));

        await query(
            `INSERT INTO seance_sessions (watchlist_id, host_id, host_name, host_avatar_url, livekit_room)
             VALUES ($1, $2, $3, $4, $5)`,
            [watchlistId, userId, hostName, hostAvatarUrl, livekitRoom]
        );

        const wsBroadcast = {
            type: 'seance_started',
            watchlistId,
            hostId: userId,
            hostName,
            hostAvatarUrl,
            livekitRoom,
        };
        memberIds.filter((id) => id !== userId).forEach((memberId) => {
            _broadcastToUser(memberId, wsBroadcast);
        });
        // Notify the watchlist WS room so VetoScreen updates in real-time
        _broadcastToWatchlist(watchlistId, { type: 'seance_started', hostId: userId, hostName, hostAvatarUrl });

        res.status(201).json({
            token,
            livekitHost: process.env.LIVEKIT_HOST,
            livekitRoom,
            hostId: userId,
            hostName,
            hostAvatarUrl,
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// POST /seance/join
router.post('/join', requireAuth, async (req, res) => {
    try {
        const { watchlistId } = req.body;
        if (!watchlistId) return res.status(400).json({ error: 'watchlistId required' });
        const userId = req.user.sub;

        const wlR = await query('SELECT member_ids FROM watchlists WHERE id = $1', [watchlistId]);
        if (!wlR.rows.length) return res.status(404).json({ error: 'Watchlist not found' });
        if (!(wlR.rows[0].member_ids ?? []).includes(userId))
            return res.status(403).json({ error: 'Forbidden' });

        const sR = await query('SELECT * FROM seance_sessions WHERE watchlist_id = $1', [watchlistId]);
        if (!sR.rows.length) return res.status(404).json({ error: 'No active séance' });
        const session = sR.rows[0];

        const userR = await query('SELECT display_name, avatar_url FROM users WHERE id = $1', [userId]);
        const viewerName = userR.rows[0]?.display_name || userId;
        const viewerAvatarUrl = userR.rows[0]?.avatar_url || null;

        const token = await mintToken(userId, viewerName, session.livekit_room, true, JSON.stringify({ avatarUrl: viewerAvatarUrl }));

        res.json({
            token,
            livekitHost: process.env.LIVEKIT_HOST,
            livekitRoom: session.livekit_room,
            hostId: session.host_id,
            hostName: session.host_name,
            hostAvatarUrl: session.host_avatar_url,
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// DELETE /seance/:watchlistId
router.delete('/:watchlistId', requireAuth, async (req, res) => {
    try {
        const { watchlistId } = req.params;
        const userId = req.user.sub;

        const sR = await query(
            'SELECT host_id FROM seance_sessions WHERE watchlist_id = $1', [watchlistId]
        );
        if (!sR.rows.length) return res.status(404).json({ error: 'No active séance' });
        if (sR.rows[0].host_id !== userId)
            return res.status(403).json({ error: 'Only the host can end the séance' });

        await query('DELETE FROM seance_sessions WHERE watchlist_id = $1', [watchlistId]);

        const wlR = await query('SELECT member_ids FROM watchlists WHERE id = $1', [watchlistId]);
        const memberIds = wlR.rows[0]?.member_ids ?? [];
        const endPayload = { type: 'seance_ended', watchlistId };
        memberIds.forEach((memberId) => _broadcastToUser(memberId, endPayload));
        _broadcastToWatchlist(watchlistId, endPayload);

        res.json({ watchlistId, status: 'ended' });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// GET /seance/active — all joinable séances across the user's watchlists
router.get('/active', requireAuth, async (req, res) => {
    try {
        const userId = req.user.sub;
        // Prune sessions abandoned without an explicit end (host crash, network loss).
        await query(`DELETE FROM seance_sessions WHERE started_at < NOW() - INTERVAL '8 hours'`);
        // member_ids is JSONB — use @> containment, not ANY() which only works on native arrays.
        const sR = await query(
            `SELECT s.watchlist_id, s.host_id, s.host_name, s.host_avatar_url, s.livekit_room
             FROM seance_sessions s
             JOIN watchlists w ON w.id = s.watchlist_id
             WHERE w.member_ids @> to_jsonb($1::text)
               AND s.host_id != $1`,
            [userId]
        );
        res.json({ sessions: sR.rows.map((s) => ({
            watchlistId: s.watchlist_id,
            hostId: s.host_id,
            hostName: s.host_name,
            hostAvatarUrl: s.host_avatar_url,
            livekitRoom: s.livekit_room,
        }))});
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// GET /seance/:watchlistId/host-token — mint a fresh token for the host to re-enter
router.get('/:watchlistId/host-token', requireAuth, async (req, res) => {
    try {
        const { watchlistId } = req.params;
        const userId = req.user.sub;
        const sR = await query(
            'SELECT * FROM seance_sessions WHERE watchlist_id = $1 AND host_id = $2',
            [watchlistId, userId]
        );
        if (!sR.rows.length) return res.status(404).json({ error: 'No active séance found for this host' });
        const session = sR.rows[0];
        const userR = await query('SELECT display_name, avatar_url FROM users WHERE id = $1', [userId]);
        const hostName = userR.rows[0]?.display_name || userId;
        const hostAvatarUrl = userR.rows[0]?.avatar_url || null;
        const token = await mintToken(userId, hostName, session.livekit_room, true, JSON.stringify({ avatarUrl: hostAvatarUrl }));
        res.json({ token, livekitHost: process.env.LIVEKIT_HOST, livekitRoom: session.livekit_room,
            hostId: userId, hostName, hostAvatarUrl });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// GET /seance/:watchlistId — check for active session (late joiners)
router.get('/:watchlistId', requireAuth, async (req, res) => {
    try {
        const { watchlistId } = req.params;
        const userId = req.user.sub;

        const wlR = await query('SELECT member_ids FROM watchlists WHERE id = $1', [watchlistId]);
        if (!wlR.rows.length) return res.status(404).json({ error: 'Watchlist not found' });
        if (!(wlR.rows[0].member_ids ?? []).includes(userId))
            return res.status(403).json({ error: 'Forbidden' });

        const sR = await query('SELECT * FROM seance_sessions WHERE watchlist_id = $1', [watchlistId]);
        if (!sR.rows.length) return res.json({ active: false });

        const s = sR.rows[0];
        res.json({
            active: true,
            watchlistId,
            hostId: s.host_id,
            hostName: s.host_name,
            hostAvatarUrl: s.host_avatar_url,
            livekitRoom: s.livekit_room,
            startedAt: s.started_at,
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

module.exports = (broadcastToUser, broadcastToWatchlist) => {
    _broadcastToUser = broadcastToUser;
    _broadcastToWatchlist = broadcastToWatchlist;
    return router;
};
