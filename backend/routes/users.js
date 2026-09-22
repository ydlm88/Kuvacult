// User profile routes — fetch profiles, update display name/avatar, manage
// the watched-movies list, follow/unfollow, and serve avatar uploads.
const crypto = require('crypto');
const path = require('path');
const fs = require('fs');
const express = require('express');
const { OPEN } = require('ws');
const { query } = require('../db');
const { requireAuth } = require('../middleware/auth');

module.exports = function (rooms, broadcastToUser) {
    const router = express.Router();

    function broadcastToRoom(watchlistId, msg) {
        rooms.get(watchlistId)?.forEach((ws) => {
            if (ws.readyState === OPEN) ws.send(JSON.stringify(msg));
        });
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
            followingIds: row.following_ids ?? [],
            followerCount: row.follower_count ?? 0,
            bannerUrls: row.banner_urls ?? [],
        };
    }

    // GET /users?roomKey=  or  /users?q=
    router.get('/', async (req, res) => {
        try {
            const { roomKey, q } = req.query;

            if (roomKey) {
                const r = await query('SELECT id FROM users WHERE room_key = $1', [roomKey]);
                return res.json({ exists: r.rows.length > 0 });
            }

            if (q) {
                const term = q.trim();
                const r = await query(
                    `SELECT id, username, display_name, avatar_url, avatar_bg
         FROM users WHERE username ILIKE $1 LIMIT 20`,
                    [`${term}%`]
                );
                return res.json(
                    r.rows.map((row) => ({
                        id: row.id,
                        username: row.username,
                        displayName: row.display_name,
                        avatarUrl: row.avatar_url,
                    }))
                );
            }

            return res.status(400).json({ error: 'roomKey or q query param required' });
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    // GET /users/:id
    router.get('/:id', async (req, res) => {
        try {
            const r = await query('SELECT * FROM users WHERE id = $1', [req.params.id]);
            if (!r.rows.length) return res.status(404).json({ error: 'User not found' });
            const data = r.rows[0];
            const requesterId = req.query.requesterId;
            const isSelf = requesterId && requesterId === req.params.id;
            const isFriend = requesterId && (data.friend_ids ?? []).includes(requesterId);
            res.json({
                id: data.id,
                username: data.username,
                displayName: isSelf || isFriend ? data.display_name : null,
                avatarUrl: data.avatar_url,
                avatarBg: data.avatar_bg,
                friendIds: data.friend_ids ?? [],
                roomKey: isSelf ? data.room_key : undefined,
                watchlistIds: isSelf ? data.watchlist_ids : undefined,
                bannerUrls: data.banner_urls ?? [],
            });
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    // PATCH /users/:id — update displayName, avatarUrl, roomKey, avatarBg, or bannerUrls
    router.patch('/:id', requireAuth, async (req, res) => {
        try {
            if (req.user.sub !== req.params.id) return res.status(403).json({ error: 'Forbidden' });
            const { displayName, avatarUrl, roomKey, avatarBg, bannerUrls } = req.body;
            const sets = ['updated_at = NOW()'];
            const vals = [];
            let i = 1;
            if (displayName !== undefined) {
                sets.push(`display_name = $${i++}`);
                vals.push(displayName);
            }
            if (avatarUrl !== undefined) {
                sets.push(`avatar_url = $${i++}`);
                vals.push(avatarUrl);
            }
            if (roomKey !== undefined) {
                sets.push(`room_key = $${i++}`);
                vals.push(roomKey);
            }
            if (avatarBg !== undefined) {
                sets.push(`avatar_bg = $${i++}`);
                vals.push(avatarBg);
            }
            if (bannerUrls !== undefined) {
                sets.push(`banner_urls = $${i++}`);
                vals.push(JSON.stringify(Array.isArray(bannerUrls) ? bannerUrls : []));
            }
            vals.push(req.params.id);
            const r = await query(
                `UPDATE users SET ${sets.join(', ')} WHERE id = $${i} RETURNING *`,
                vals
            );
            if (avatarUrl !== undefined) {
                await query('UPDATE reviews SET by_avatar_url = $1 WHERE by_id = $2', [
                    avatarUrl,
                    req.params.id,
                ]);
                await query('UPDATE review_comments SET by_avatar_url = $1 WHERE by_id = $2', [
                    avatarUrl,
                    req.params.id,
                ]);
            }
            if (displayName !== undefined) {
                await query('UPDATE reviews SET by_name = $1 WHERE by_id = $2', [
                    displayName,
                    req.params.id,
                ]);
                await query('UPDATE review_comments SET by_name = $1 WHERE by_id = $2', [
                    displayName,
                    req.params.id,
                ]);
            }
            res.json(userShape(r.rows[0]));
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    // GET /users/:id/watchlists — full watchlists with movies + member profiles
    router.get('/:id/watchlists', requireAuth, async (req, res) => {
        try {
            const userR = await query('SELECT watchlist_ids FROM users WHERE id = $1', [
                req.params.id,
            ]);
            if (!userR.rows.length) return res.status(404).json({ error: 'User not found' });
            const watchlistIds = userR.rows[0].watchlist_ids ?? [];
            if (!watchlistIds.length) return res.json([]);

            const wlR = await query(`SELECT * FROM watchlists WHERE id = ANY($1::text[])`, [
                watchlistIds,
            ]);

            const results = await Promise.all(
                wlR.rows.map(async (wl) => {
                    const moviesR = await query(
                        `${MOVIES_WITH_MEDIA} WHERE m.watchlist_id = $1 ORDER BY m.added_at ASC`,
                        [wl.id]
                    );
                    const memberIds = wl.member_ids ?? [];
                    const membersR = memberIds.length
                        ? await query(
                              'SELECT id, display_name, avatar_url, username FROM users WHERE id = ANY($1::text[])',
                              [memberIds]
                          )
                        : { rows: [] };
                    return {
                        id: wl.id,
                        name: wl.name,
                        listKey: wl.list_key,
                        memberIds: wl.member_ids,
                        likes: wl.likes,
                        likedBy: wl.liked_by,
                        movies: moviesR.rows.map(movieShape),
                        members: membersR.rows.map((r) => ({
                            id: r.id,
                            displayName: r.display_name,
                            avatarUrl: r.avatar_url,
                            username: r.username,
                        })),
                    };
                })
            );

            res.json(results);
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    // GET /users/:id/friend-requests — pending incoming requests
    router.get('/:id/friend-requests', requireAuth, async (req, res) => {
        try {
            const r = await query(
                `SELECT fr.id, fr.from_id, fr.to_id, fr.status, fr.created_at,
              u.username AS from_username, u.display_name AS from_display_name, u.avatar_url AS from_avatar_url
       FROM friend_requests fr
       LEFT JOIN users u ON u.id = fr.from_id
       WHERE fr.to_id = $1 AND fr.status = 'pending'
       ORDER BY fr.created_at DESC`,
                [req.params.id]
            );
            res.json(
                r.rows.map((fr) => ({
                    id: fr.id,
                    fromId: fr.from_id,
                    toId: fr.to_id,
                    status: fr.status,
                    createdAt: fr.created_at,
                    fromUsername: fr.from_username,
                    fromDisplayName: fr.from_display_name,
                    fromAvatarUrl: fr.from_avatar_url,
                }))
            );
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    // GET /users/:id/friends — full profiles for each friend
    router.get('/:id/friends', requireAuth, async (req, res) => {
        try {
            const r = await query('SELECT friend_ids FROM users WHERE id = $1', [req.params.id]);
            if (!r.rows.length) return res.status(404).json({ error: 'User not found' });
            const friendIds = r.rows[0].friend_ids ?? [];
            if (!friendIds.length) return res.json([]);
            const fr = await query('SELECT * FROM users WHERE id = ANY($1::text[])', [friendIds]);
            res.json(fr.rows.map(userShape));
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    // POST /users/:id/avatar — save base64 image to local disk
    router.post('/:id/avatar', requireAuth, async (req, res) => {
        try {
            if (req.user.sub !== req.params.id) return res.status(403).json({ error: 'Forbidden' });
            const { imageBase64, mimeType = 'image/jpeg' } = req.body;
            if (!imageBase64) return res.status(400).json({ error: 'imageBase64 required' });

            const buffer = Buffer.from(imageBase64, 'base64');
            if (buffer.length > 50 * 1024)
                return res.status(413).json({ error: 'Image exceeds 50 KB limit' });

            const ext = mimeType === 'image/png' ? 'png' : 'jpg';
            const dir = path.join(__dirname, '..', 'uploads', 'avatars');
            fs.mkdirSync(dir, { recursive: true });
            const filename = `${req.params.id}.${ext}`;
            fs.writeFileSync(path.join(dir, filename), buffer);

            // Append a version timestamp so every upload produces a unique URL.
            // express.static ignores query params when resolving the file path,
            // so the same file is served — but clients see a new URL and bypass
            // their image cache, fixing stale-avatar bugs across app restarts.
            const avatarUrl = `/uploads/avatars/${filename}?v=${Date.now()}`;
            await query('UPDATE users SET avatar_url = $1, updated_at = NOW() WHERE id = $2', [
                avatarUrl,
                req.params.id,
            ]);
            // Keep denormalized avatar in existing reviews in sync
            await query('UPDATE reviews SET by_avatar_url = $1 WHERE by_id = $2', [
                avatarUrl,
                req.params.id,
            ]);
            res.json({ avatarUrl });
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    // POST /users/:id/follow — current user follows :id
    router.post('/:id/follow', async (req, res) => {
        try {
            const targetId = req.params.id;
            const { followerId } = req.body;
            if (!followerId) return res.status(400).json({ error: 'followerId required' });
            if (followerId === targetId)
                return res.status(400).json({ error: 'Cannot follow yourself' });

            await query(
                `UPDATE users SET following_ids = following_ids || $1::jsonb, updated_at = NOW()
       WHERE id = $2 AND NOT (following_ids @> $1::jsonb)`,
                [JSON.stringify([targetId]), followerId]
            );
            await query(
                `UPDATE users SET follower_count = follower_count + 1, updated_at = NOW() WHERE id = $1`,
                [targetId]
            );
            const followerR = await query(
                'SELECT display_name, username, avatar_url FROM users WHERE id = $1',
                [followerId]
            );
            const follower = followerR.rows[0] ?? {};
            broadcastToUser(targetId, {
                type: 'follow',
                fromId: followerId,
                fromName: follower.display_name || follower.username || followerId,
                fromHandle: follower.username || '',
                fromAvatarUrl: follower.avatar_url || null,
            });
            res.json({ ok: true });
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    // DELETE /users/:id/follow — current user unfollows :id
    router.delete('/:id/follow', async (req, res) => {
        try {
            const targetId = req.params.id;
            const followerId = req.query.followerId;
            if (!followerId) return res.status(400).json({ error: 'followerId required' });

            await query(
                `UPDATE users SET following_ids = (
         SELECT jsonb_agg(x) FROM jsonb_array_elements_text(following_ids) x WHERE x <> $1
       ), updated_at = NOW() WHERE id = $2`,
                [targetId, followerId]
            );
            await query(
                `UPDATE users SET follower_count = GREATEST(0, follower_count - 1), updated_at = NOW() WHERE id = $1`,
                [targetId]
            );
            res.json({ ok: true });
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    // GET /users/:id/social — follower / following counts
    router.get('/:id/social', async (req, res) => {
        try {
            const r = await query(
                'SELECT follower_count, jsonb_array_length(following_ids) AS following_count FROM users WHERE id = $1',
                [req.params.id]
            );
            if (!r.rows.length) return res.status(404).json({ error: 'User not found' });
            res.json({
                followerCount: r.rows[0].follower_count ?? 0,
                followingCount: r.rows[0].following_count ?? 0,
            });
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    // GET /users/:id/following — list of IDs this user follows
    router.get('/:id/following', async (req, res) => {
        try {
            const r = await query('SELECT following_ids FROM users WHERE id = $1', [req.params.id]);
            if (!r.rows.length) return res.status(404).json({ error: 'User not found' });
            res.json(r.rows[0].following_ids ?? []);
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    // GET /users/:id/invites — pending watchlist invites
    router.get('/:id/invites', requireAuth, async (req, res) => {
        try {
            const r = await query(
                `SELECT wi.id, wi.watchlist_id, wi.inviter_id, wi.created_at,
              w.name  AS watchlist_name,
              u.display_name AS inviter_name,
              u.username     AS inviter_username,
              u.avatar_url   AS inviter_avatar_url
       FROM watchlist_invites wi
       JOIN watchlists w ON w.id = wi.watchlist_id
       JOIN users u ON u.id = wi.inviter_id
       WHERE wi.invitee_id = $1
       ORDER BY wi.created_at DESC`,
                [req.params.id]
            );
            res.json(
                r.rows.map((row) => ({
                    id: row.id,
                    watchlistId: row.watchlist_id,
                    watchlistName: row.watchlist_name,
                    inviterId: row.inviter_id,
                    inviterName: row.inviter_name,
                    inviterUsername: row.inviter_username,
                    inviterAvatarUrl: row.inviter_avatar_url,
                    createdAt: row.created_at,
                }))
            );
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    // GET /users/:id/sent-invites — watchlist invites sent by this user
    router.get(':id/sent-invites', requireAuth, async (req, res) => {
        try {
            const r = await query(
                `SELECT wi.id, wi.watchlist_id, w.name AS watchlist_name,
              u.display_name AS invitee_name, u.username AS invitee_handle
       FROM watchlist_invites wi
       JOIN watchlists w ON w.id = wi.watchlist_id
       JOIN users u ON u.id = wi.invitee_id
       WHERE wi.inviter_id = $1
       ORDER BY wi.id DESC`,
                [req.params.id]
            );
            res.json(
                r.rows.map((row) => ({
                    id: row.id,
                    watchlistId: row.watchlist_id,
                    watchlistName: row.watchlist_name,
                    inviteeName: row.invitee_name,
                    inviteeHandle: row.invitee_handle,
                }))
            );
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    // GET /users/:id/watched — public list of watched movies
    router.get('/:id/watched', async (req, res) => {
        try {
            const r = await query('SELECT watched_movies FROM users WHERE id = $1', [
                req.params.id,
            ]);
            if (!r.rows.length) return res.status(404).json({ error: 'User not found' });
            res.json(r.rows[0].watched_movies ?? []);
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    // POST /users/:id/watched — mark a movie as watched
    router.post('/:id/watched', requireAuth, async (req, res) => {
        try {
            if (req.user.sub !== req.params.id) return res.status(403).json({ error: 'Forbidden' });
            const { movieId, posterUrl, title, year } = req.body;
            if (!movieId) return res.status(400).json({ error: 'movieId required' });
            const entry = JSON.stringify([
                { movieId, posterUrl: posterUrl || null, title: title || '', year: year || 0 },
            ]);
            await query(
                `UPDATE users SET watched_movies = CASE
         WHEN NOT EXISTS (
           SELECT 1 FROM jsonb_array_elements(watched_movies) e WHERE e->>'movieId' = $2
         ) THEN watched_movies || $1::jsonb
         ELSE watched_movies
       END, updated_at = NOW() WHERE id = $3`,
                [entry, movieId, req.params.id]
            );

            const wlsR = await query(
                `SELECT w.id AS watchlist_id, w.member_ids,
              (SELECT COUNT(*)::int FROM unnest(w.member_ids) AS mid
               WHERE EXISTS (
                 SELECT 1 FROM users u,
                              jsonb_array_elements(u.watched_movies) e
                 WHERE u.id = mid AND e->>'movieId' = $1
               )) AS watched_count
       FROM watchlists w
       JOIN movies m ON m.watchlist_id = w.id AND m.id = $1 AND m.section <> 'watched'
       WHERE array_length(w.member_ids, 1) > 0`,
                [movieId]
            );
            for (const row of wlsR.rows) {
                if (row.watched_count > 0 && row.watched_count === (row.member_ids?.length ?? 0)) {
                    await query(
                        `UPDATE movies SET section = 'watched' WHERE id = $1 AND watchlist_id = $2`,
                        [movieId, row.watchlist_id]
                    );
                    const mR = await query(
                        `${MOVIES_WITH_MEDIA} WHERE m.id = $1 AND m.watchlist_id = $2`,
                        [movieId, row.watchlist_id]
                    );
                    if (mR.rows.length) {
                        broadcastToRoom(row.watchlist_id, {
                            type: 'movie_updated',
                            movie: movieShape(mR.rows[0]),
                        });
                    }
                }
            }

            res.json({ ok: true });
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    // DELETE /users/:id/watched/:movieId — unmark a watched movie
    router.delete('/:id/watched/:movieId', requireAuth, async (req, res) => {
        try {
            if (req.user.sub !== req.params.id) return res.status(403).json({ error: 'Forbidden' });
            await query(
                `UPDATE users SET watched_movies = COALESCE(
         (SELECT jsonb_agg(e) FROM jsonb_array_elements(watched_movies) e WHERE e->>'movieId' <> $1),
         '[]'::jsonb
       ), updated_at = NOW() WHERE id = $2`,
                [req.params.movieId, req.params.id]
            );
            res.json({ ok: true });
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    // Shared helpers
    const MOVIES_WITH_MEDIA = `
  SELECT m.id, m.watchlist_id, m.title, m.year, m.stream_id, m.added_by,
         m.section, m.stars, m.notes, m.added_at,
         CASE WHEN m.runtime > 0 THEN m.runtime ELSE COALESCE(med.runtime, 0) END AS runtime,
         CASE WHEN m.rating  > 0 THEN m.rating  ELSE COALESCE(med.rating,  0) END AS rating,
         CASE WHEN m.genres IS DISTINCT FROM '[]'::jsonb THEN m.genres ELSE COALESCE(med.genres, '[]'::jsonb) END AS genres,
         CASE WHEN COALESCE(m.director, '') <> '' THEN m.director ELSE COALESCE(med.director,  '') END AS director,
         CASE WHEN COALESCE(m.synopsis, '') <> '' THEN m.synopsis ELSE COALESCE(med.synopsis,  '') END AS synopsis,
         COALESCE(NULLIF(m.image_url, ''), med.poster_url) AS image_url
  FROM movies m LEFT JOIN media med ON med.id = m.id
`;

    function movieShape(row) {
        return {
            id: row.id,
            watchlistId: row.watchlist_id,
            title: row.title,
            year: row.year,
            runtime: row.runtime,
            rating: row.rating,
            genres: row.genres ?? [],
            director: row.director,
            streamId: row.stream_id,
            addedBy: row.added_by,
            section: row.section,
            synopsis: row.synopsis,
            imageUrl: row.image_url,
            stars: row.stars ?? {},
            notes: row.notes ?? [],
            addedAt: row.added_at,
        };
    }

    // GET /users/:id/reviews — all reviews written by a user
    router.get('/:id/reviews', async (req, res) => {
        try {
            const r = await query('SELECT * FROM reviews WHERE by_id = $1 ORDER BY at DESC', [
                req.params.id,
            ]);
            res.json(
                r.rows.map((row) => ({
                    id: row.id,
                    byId: row.by_id,
                    byName: row.by_name,
                    byHandle: row.by_handle,
                    byAvatarUrl: row.by_avatar_url,
                    movieId: row.movie_id,
                    movieTitle: row.movie_title,
                    movieYear: row.movie_year,
                    movieDirector: row.movie_director,
                    moviePosterUrl: row.movie_poster_url,
                    stars: row.stars,
                    text: row.text,
                    rewatch: row.rewatch,
                    likes: row.likes,
                    likedBy: row.liked_by ?? [],
                    commentCount: row.comment_count,
                    at: row.at,
                }))
            );
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    return router;
};
