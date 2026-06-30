// Watchlist CRUD routes — create, read, rename, delete watchlists and their
// movies; handle membership invites; broadcast mutations to connected members
// over WebSocket so the UI stays in sync across devices in real time.
const crypto = require('crypto');
const express = require('express');
const { query } = require('../db');
const { requireAuth } = require('../middleware/auth');
const { OPEN } = require('ws');

// LEFT JOIN with media so imported movies get their enriched details.
const MOVIES_WITH_MEDIA = `
  SELECT m.id, m.watchlist_id, m.title, m.year, m.stream_id, m.added_by,
         m.section, m.stars, m.reactions, m.notes, m.added_at, m.watched_by,
         CASE WHEN m.runtime > 0 THEN m.runtime ELSE COALESCE(med.runtime, 0) END AS runtime,
         CASE WHEN m.rating  > 0 THEN m.rating  ELSE COALESCE(med.rating,  0) END AS rating,
         CASE WHEN m.genres IS DISTINCT FROM '[]'::jsonb THEN m.genres ELSE COALESCE(med.genres, '[]'::jsonb) END AS genres,
         CASE WHEN COALESCE(m.director, '') <> '' THEN m.director ELSE COALESCE(med.director,  '') END AS director,
         CASE WHEN COALESCE(m.synopsis, '') <> '' THEN m.synopsis ELSE COALESCE(med.synopsis,  '') END AS synopsis,
         COALESCE(NULLIF(m.image_url, ''), med.poster_url) AS image_url
  FROM movies m LEFT JOIN media med ON med.id = m.id
`;

module.exports = function (rooms, broadcastToUser) {
    const router = express.Router();

    function broadcast(watchlistId, msg) {
        rooms.get(watchlistId)?.forEach((ws) => {
            if (ws.readyState === OPEN) ws.send(JSON.stringify(msg));
        });
    }

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
            reactions: row.reactions ?? {},
            notes: row.notes ?? [],
            watchedBy: row.watched_by ?? [],
            addedAt: row.added_at,
        };
    }

    async function arrayAdd(table, col, id, rowId) {
        await query(
            `UPDATE ${table}
       SET ${col} = CASE WHEN ${col} @> $1::jsonb THEN ${col}
                         ELSE ${col} || $1::jsonb END
       WHERE id = $2`,
            [JSON.stringify([id]), rowId]
        );
    }

    async function arrayRemove(table, col, val, rowId) {
        await query(
            `UPDATE ${table}
       SET ${col} = (
         SELECT COALESCE(jsonb_agg(v), '[]'::jsonb)
         FROM jsonb_array_elements(${col}) v
         WHERE v::text != $1::text
       )
       WHERE id = $2`,
            [JSON.stringify(val), rowId]
        );
    }

    // POST /watchlists
    router.post('/', requireAuth, async (req, res) => {
        try {
            const { name, listKey, memberIds = [] } = req.body;
            if (!name) return res.status(400).json({ error: 'name is required' });
            const id = crypto.randomUUID();
            await query(
                `INSERT INTO watchlists (id, name, list_key, member_ids) VALUES ($1, $2, $3, $4)`,
                [id, name, listKey ?? null, JSON.stringify(memberIds)]
            );
            for (const uid of memberIds) await arrayAdd('users', 'watchlist_ids', id, uid);
            res.status(201).json({ id, name, listKey, memberIds });
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    // POST /watchlists/join
    router.post('/join', requireAuth, async (req, res) => {
        try {
            const { listKey, userId } = req.body;
            if (!listKey || !userId)
                return res.status(400).json({ error: 'listKey and userId are required' });

            const wlR = await query('SELECT * FROM watchlists WHERE list_key = $1', [
                listKey.trim().toUpperCase(),
            ]);
            if (!wlR.rows.length) return res.status(404).json({ error: 'Room not found' });
            const wl = wlR.rows[0];

            await arrayAdd('watchlists', 'member_ids', userId, wl.id);
            await arrayAdd('users', 'watchlist_ids', wl.id, userId);

            const moviesR = await query(
                `${MOVIES_WITH_MEDIA} WHERE m.watchlist_id = $1 ORDER BY m.added_at ASC`,
                [wl.id]
            );
            const updated = await query('SELECT * FROM watchlists WHERE id = $1', [wl.id]);
            res.json({ ...updated.rows[0], id: wl.id, movies: moviesR.rows.map(movieShape) });
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    // GET /watchlists/top — community top watchlists by likes
    router.get('/top', async (req, res) => {
        try {
            const limit = Math.min(parseInt(req.query.limit) || 20, 50);
            const r = await query(
                `SELECT w.id, w.name, w.member_ids, w.likes,
                (SELECT COUNT(*)::int FROM movies WHERE watchlist_id = w.id) AS movie_count
         FROM watchlists w
         ORDER BY w.likes DESC, w.id
         LIMIT $1`,
                [limit]
            );
            res.json(
                r.rows.map((row) => ({
                    id: row.id,
                    name: row.name,
                    memberIds: row.member_ids,
                    likes: row.likes,
                    movieCount: row.movie_count,
                }))
            );
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    // GET /watchlists/find?code= — read-only guest lookup
    router.get('/find', async (req, res) => {
        try {
            const { code } = req.query;
            if (!code) return res.status(400).json({ error: 'code is required' });
            const wlR = await query('SELECT * FROM watchlists WHERE list_key = $1', [
                code.trim().toUpperCase(),
            ]);
            if (!wlR.rows.length) return res.status(404).json({ error: 'Room not found' });
            const wl = wlR.rows[0];
            const moviesR = await query(
                `${MOVIES_WITH_MEDIA} WHERE m.watchlist_id = $1 ORDER BY m.added_at ASC`,
                [wl.id]
            );
            res.json({
                id: wl.id,
                name: wl.name,
                listKey: wl.list_key,
                memberIds: wl.member_ids,
                movies: moviesR.rows.map(movieShape),
            });
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    // GET /watchlists/:id/activity
    router.get('/:id/activity', async (req, res) => {
        try {
            const limit = Math.min(parseInt(req.query.limit) || 50, 200);
            const r = await query(
                `SELECT id, kind, who, movie_id, text, to_section, reaction, stars, at
         FROM activity
         WHERE watchlist_id = $1
         ORDER BY at DESC
         LIMIT $2`,
                [req.params.id, limit]
            );
            res.json(
                r.rows.map((row) => ({
                    id: row.id,
                    kind: row.kind,
                    who: row.who,
                    movieId: row.movie_id,
                    text: row.text,
                    to: row.to_section,
                    reaction: row.reaction,
                    stars: row.stars,
                    at: row.at,
                }))
            );
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    // GET /watchlists/:id/veto — current veto session
    router.get('/:id/veto', async (req, res) => {
        try {
            const r = await query('SELECT data FROM veto_sessions WHERE watchlist_id = $1', [
                req.params.id,
            ]);
            res.json(r.rows[0]?.data ?? null);
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    // GET /watchlists/:id
    router.get('/:id', async (req, res) => {
        try {
            const wlR = await query('SELECT * FROM watchlists WHERE id = $1', [req.params.id]);
            if (!wlR.rows.length) return res.status(404).json({ error: 'Not found' });
            const wl = wlR.rows[0];
            const memberIds = wl.member_ids ?? [];
            const [moviesR, membersR] = await Promise.all([
                query(`${MOVIES_WITH_MEDIA} WHERE m.watchlist_id = $1 ORDER BY m.added_at ASC`, [
                    wl.id,
                ]),
                memberIds.length
                    ? query(
                          'SELECT id, display_name, avatar_url, username FROM users WHERE id = ANY($1::text[])',
                          [memberIds]
                      )
                    : Promise.resolve({ rows: [] }),
            ]);
            res.json({
                id: wl.id,
                name: wl.name,
                listKey: wl.list_key,
                memberIds,
                movies: moviesR.rows.map(movieShape),
                members: membersR.rows.map((r) => ({
                    id: r.id,
                    displayName: r.display_name,
                    avatarUrl: r.avatar_url,
                    username: r.username,
                })),
            });
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    // POST /watchlists/:id/movies
    router.post('/:id/movies', requireAuth, async (req, res) => {
        try {
            const {
                movieId,
                title,
                year,
                runtime = 0,
                rating = 0,
                genres = [],
                director = '',
                streamId = '',
                synopsis = '',
                addedBy,
                imageUrl = null,
            } = req.body;
            if (!movieId || !title)
                return res.status(400).json({ error: 'movieId and title are required' });

            const exists = await query(
                'SELECT id FROM movies WHERE id = $1 AND watchlist_id = $2',
                [movieId, req.params.id]
            );
            if (exists.rows.length) return res.status(409).json({ error: 'Already in list' });

            const userId = addedBy || req.user.sub;
            await query(
                `INSERT INTO movies
          (id, watchlist_id, title, year, runtime, rating, genres, director, stream_id, synopsis, added_by, image_url)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)`,
                [
                    movieId,
                    req.params.id,
                    title,
                    year || 0,
                    runtime,
                    rating,
                    JSON.stringify(genres),
                    director,
                    streamId,
                    synopsis,
                    userId,
                    imageUrl || null,
                ]
            );

            const activityId = crypto.randomUUID();
            await query(
                `INSERT INTO activity (id, watchlist_id, kind, who, movie_id, at) VALUES ($1,$2,'added',$3,$4,NOW())`,
                [activityId, req.params.id, userId, movieId]
            );

            // Pre-populate watched_by so it stays accurate if a member already watched this movie.
            const wlMembersR = await query('SELECT member_ids FROM watchlists WHERE id = $1', [
                req.params.id,
            ]);
            const memberIds = wlMembersR.rows[0]?.member_ids ?? [];
            if (memberIds.length > 0) {
                const alreadyWatchedR = await query(
                    `SELECT u.id FROM users u
           WHERE EXISTS (
             SELECT 1 FROM jsonb_array_elements_text($1::jsonb) AS mid WHERE mid = u.id
           )
           AND EXISTS (
             SELECT 1 FROM jsonb_array_elements(u.watched_movies) e WHERE e->>'movieId' = $2
           )`,
                    [JSON.stringify(memberIds), movieId]
                );
                const alreadyWatched = alreadyWatchedR.rows.map((r) => r.id);
                if (alreadyWatched.length > 0) {
                    await query(
                        `UPDATE movies SET watched_by = $1::jsonb WHERE id = $2 AND watchlist_id = $3`,
                        [JSON.stringify(alreadyWatched), movieId, req.params.id]
                    );
                    if (memberIds.every((id) => alreadyWatched.includes(id))) {
                        await query(
                            `UPDATE movies SET section = 'watched' WHERE id = $1 AND watchlist_id = $2`,
                            [movieId, req.params.id]
                        );
                    }
                }
            }

            const movieR = await query(
                `${MOVIES_WITH_MEDIA} WHERE m.id = $1 AND m.watchlist_id = $2`,
                [movieId, req.params.id]
            );
            const movie = movieShape(movieR.rows[0]);
            broadcast(req.params.id, { type: 'movie_added', movie });
            broadcast(req.params.id, {
                type: 'activity_added',
                event: { kind: 'added', who: userId, movieId, at: new Date().toISOString() },
            });

            res.status(201).json(movie);
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    // PATCH /watchlists/:id/movies/:movieId
    router.patch('/:id/movies/:movieId', requireAuth, async (req, res) => {
        try {
            const { id: watchlistId, movieId } = req.params;
            const { section, stars, reaction, memberId } = req.body;
            let didUpdate = false;

            if (section === 'watched' && memberId) {
                await query(
                    `UPDATE movies
           SET watched_by = CASE WHEN watched_by @> $1::jsonb THEN watched_by
                                 ELSE watched_by || $1::jsonb END
           WHERE id = $2 AND watchlist_id = $3`,
                    [JSON.stringify([memberId]), movieId, watchlistId]
                );
                // Promote to watched only when ALL watchlist members have watched
                const [wlR, mvR] = await Promise.all([
                    query('SELECT member_ids FROM watchlists WHERE id = $1', [watchlistId]),
                    query('SELECT watched_by FROM movies WHERE id = $1 AND watchlist_id = $2', [
                        movieId,
                        watchlistId,
                    ]),
                ]);
                const allMemberIds = wlR.rows[0]?.member_ids ?? [];
                const watchedBy = mvR.rows[0]?.watched_by ?? [];
                if (allMemberIds.length > 0 && allMemberIds.every((id) => watchedBy.includes(id))) {
                    await query(
                        `UPDATE movies SET section = 'watched' WHERE id = $1 AND watchlist_id = $2`,
                        [movieId, watchlistId]
                    );
                }
                didUpdate = true;
            } else if (section && memberId) {
                //Moving to want/watching: clear this member's watched_by entry and set section
                await query(
                    `UPDATE movies
           SET section = $1,
               watched_by = COALESCE(
                 (SELECT jsonb_agg(elem)
                  FROM jsonb_array_elements_text(watched_by) elem
                  WHERE elem != $2),
                 '[]'::jsonb
               )
           WHERE id = $3 AND watchlist_id = $4`,
                    [section, memberId, movieId, watchlistId]
                );
                didUpdate = true;
            } else if (section) {
                await query(`UPDATE movies SET section = $1 WHERE id = $2 AND watchlist_id = $3`, [
                    section,
                    movieId,
                    watchlistId,
                ]);
                didUpdate = true;
            }

            if (stars !== undefined && memberId) {
                await query(
                    `UPDATE movies SET stars = stars || jsonb_build_object($1::text, $2::float)
           WHERE id = $3 AND watchlist_id = $4`,
                    [memberId, stars, movieId, watchlistId]
                );
                didUpdate = true;
            }

            if (reaction && memberId) {
                await query(
                    `UPDATE movies SET reactions = reactions || jsonb_build_object($1::text, $2::text)
           WHERE id = $3 AND watchlist_id = $4`,
                    [memberId, reaction, movieId, watchlistId]
                );
                didUpdate = true;
            }

            if (!didUpdate) return res.status(400).json({ error: 'No valid fields to update' });

            const movieR = await query(
                `${MOVIES_WITH_MEDIA} WHERE m.id = $1 AND m.watchlist_id = $2`,
                [movieId, watchlistId]
            );
            const movie = movieShape(movieR.rows[0]);
            broadcast(watchlistId, { type: 'movie_updated', movie });

            const now = new Date().toISOString();
            const aid = crypto.randomUUID();
            if (stars !== undefined && memberId) {
                await query(
                    `INSERT INTO activity (id,watchlist_id,kind,who,movie_id,stars,at) VALUES ($1,$2,'rated',$3,$4,$5,NOW())`,
                    [aid, watchlistId, memberId, movieId, stars]
                );
                broadcast(watchlistId, {
                    type: 'activity_added',
                    event: { kind: 'rated', who: memberId, movieId, stars, at: now },
                });
            } else if (reaction && memberId) {
                await query(
                    `INSERT INTO activity (id,watchlist_id,kind,who,movie_id,reaction,at) VALUES ($1,$2,'reacted',$3,$4,$5,NOW())`,
                    [aid, watchlistId, memberId, movieId, reaction]
                );
                broadcast(watchlistId, {
                    type: 'activity_added',
                    event: { kind: 'reacted', who: memberId, movieId, reaction, at: now },
                });
            } else if (section && memberId) {
                await query(
                    `INSERT INTO activity (id,watchlist_id,kind,who,movie_id,to_section,at) VALUES ($1,$2,'moved',$3,$4,$5,NOW())`,
                    [aid, watchlistId, memberId, movieId, section]
                );
                broadcast(watchlistId, {
                    type: 'activity_added',
                    event: { kind: 'moved', who: memberId, movieId, to: section, at: now },
                });
            }

            res.json(movie);
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    // POST /watchlists/:id/movies/:movieId/promote
    router.post('/:id/movies/:movieId/promote', requireAuth, async (req, res) => {
        try {
            const { id: watchlistId, movieId } = req.params;
            const { promotedBy } = req.body;
            broadcast(watchlistId, { type: 'movie_promoted', movieId, promotedBy });
            res.json({ ok: true });
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    // POST /watchlists/:id/movies/:movieId/notes
    router.post('/:id/movies/:movieId/notes', requireAuth, async (req, res) => {
        try {
            const { id: watchlistId, movieId } = req.params;
            const { by, text } = req.body;
            if (!by || !text) return res.status(400).json({ error: 'by and text are required' });

            const note = { id: crypto.randomUUID(), by, text, at: new Date().toISOString() };
            await query(
                `UPDATE movies SET notes = notes || $1::jsonb WHERE id = $2 AND watchlist_id = $3`,
                [JSON.stringify([note]), movieId, watchlistId]
            );

            const aid = crypto.randomUUID();
            await query(
                `INSERT INTO activity (id,watchlist_id,kind,who,movie_id,text,at) VALUES ($1,$2,'note',$3,$4,$5,NOW())`,
                [aid, watchlistId, by, movieId, text]
            );
            broadcast(watchlistId, {
                type: 'activity_added',
                event: { kind: 'note', who: by, movieId, text, at: note.at },
            });

            res.status(201).json(note);
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    // DELETE /watchlists/:id/movies/:movieId
    router.delete('/:id/movies/:movieId', requireAuth, async (req, res) => {
        try {
            await query('DELETE FROM movies WHERE id = $1 AND watchlist_id = $2', [
                req.params.movieId,
                req.params.id,
            ]);
            broadcast(req.params.id, { type: 'movie_removed', movieId: req.params.movieId });
            res.json({ deleted: req.params.movieId });
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    // PATCH /watchlists/:id/members — send invite
    router.patch('/:id/members', requireAuth, async (req, res) => {
        try {
            const { userId } = req.body;
            const inviterId = req.user.sub;
            if (!userId) return res.status(400).json({ error: 'userId is required' });
            const wlR = await query('SELECT member_ids, name FROM watchlists WHERE id = $1', [
                req.params.id,
            ]);
            if (!wlR.rows.length) return res.status(404).json({ error: 'Watchlist not found' });
            const memberIds = wlR.rows[0].member_ids ?? [];
            if (memberIds.includes(userId))
                return res.status(409).json({ error: 'Already a member' });
            const inviteId = crypto.randomUUID();
            const insertR = await query(
                `INSERT INTO watchlist_invites (id, watchlist_id, inviter_id, invitee_id)
         VALUES ($1, $2, $3, $4) ON CONFLICT (watchlist_id, invitee_id) DO NOTHING
         RETURNING id`,
                [inviteId, req.params.id, inviterId, userId]
            );
            // Only notify if a new invite row was created
            if (insertR.rows.length && typeof broadcastToUser === 'function') {
                const inviterR = await query(
                    'SELECT display_name, avatar_url FROM users WHERE id = $1',
                    [inviterId]
                );
                broadcastToUser(userId, {
                    type: 'watchlist_invite',
                    inviteId,
                    watchlistId: req.params.id,
                    watchlistName: wlR.rows[0].name ?? '',
                    inviterId,
                    inviterName: inviterR.rows[0]?.display_name ?? '',
                    inviterAvatarUrl: inviterR.rows[0]?.avatar_url ?? null,
                });
            }
            res.json({ invited: userId });
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    // POST /watchlists/:id/invites/:inviteId/accept
    router.post('/:id/invites/:inviteId/accept', requireAuth, async (req, res) => {
        try {
            const { id: watchlistId, inviteId } = req.params;
            const userId = req.user.sub;
            const invR = await query(
                'SELECT * FROM watchlist_invites WHERE id = $1 AND watchlist_id = $2 AND invitee_id = $3',
                [inviteId, watchlistId, userId]
            );
            if (!invR.rows.length) return res.status(404).json({ error: 'Invite not found' });
            await arrayAdd('watchlists', 'member_ids', userId, watchlistId);
            await arrayAdd('users', 'watchlist_ids', watchlistId, userId);
            await query('DELETE FROM watchlist_invites WHERE id = $1', [inviteId]);
            broadcast(watchlistId, { type: 'member_joined', userId });
            const wlR = await query('SELECT * FROM watchlists WHERE id = $1', [watchlistId]);
            const moviesR = await query(
                `${MOVIES_WITH_MEDIA} WHERE m.watchlist_id = $1 ORDER BY m.added_at ASC`,
                [watchlistId]
            );
            res.json({
                id: watchlistId,
                name: wlR.rows[0].name,
                listKey: wlR.rows[0].list_key,
                memberIds: wlR.rows[0].member_ids,
                movies: moviesR.rows.map(movieShape),
            });
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    // DELETE /watchlists/:id/invites/:inviteId — decline
    router.delete('/:id/invites/:inviteId', requireAuth, async (req, res) => {
        try {
            const { id: watchlistId, inviteId } = req.params;
            const userId = req.user.sub;
            await query(
                'DELETE FROM watchlist_invites WHERE id = $1 AND watchlist_id = $2 AND invitee_id = $3',
                [inviteId, watchlistId, userId]
            );
            res.json({ declined: inviteId });
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    // DELETE /watchlists/:id/members — leave list
    router.delete('/:id/members', requireAuth, async (req, res) => {
        try {
            const userId = req.user.sub;
            const watchlistId = req.params.id;
            await arrayRemove('watchlists', 'member_ids', userId, watchlistId);
            await arrayRemove('users', 'watchlist_ids', watchlistId, userId);
            broadcast(watchlistId, { type: 'member_left', userId });
            res.json({ left: watchlistId });
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    // PATCH /watchlists/:id/regenerate-key
    router.patch('/:id/regenerate-key', requireAuth, async (req, res) => {
        try {
            const { listKey } = req.body;
            if (!listKey) return res.status(400).json({ error: 'listKey is required' });
            const key = listKey.trim().toUpperCase();
            await query('UPDATE watchlists SET list_key = $1 WHERE id = $2', [key, req.params.id]);
            res.json({ id: req.params.id, listKey: key });
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    // POST /watchlists/:id/like
    router.post('/:id/like', requireAuth, async (req, res) => {
        try {
            const { userId } = req.body;
            if (!userId) return res.status(400).json({ error: 'userId required' });
            if (req.user.sub !== userId) return res.status(403).json({ error: 'Forbidden' });

            const r = await query(
                'SELECT liked_by, likes, name, member_ids FROM watchlists WHERE id = $1',
                [req.params.id]
            );
            if (!r.rows.length) return res.status(404).json({ error: 'Watchlist not found' });
            const likedBy = r.rows[0].liked_by ?? [];
            if (likedBy.includes(userId)) return res.json({ likes: r.rows[0].likes, likedBy });

            const newLikedBy = [...likedBy, userId];
            const newLikes = (r.rows[0].likes ?? 0) + 1;
            await query('UPDATE watchlists SET liked_by = $1, likes = $2 WHERE id = $3', [
                JSON.stringify(newLikedBy),
                newLikes,
                req.params.id,
            ]);

            const likerR = await query(
                'SELECT display_name, username, avatar_url FROM users WHERE id = $1',
                [userId]
            );
            const liker = likerR.rows[0] ?? {};
            const memberIds = r.rows[0].member_ids ?? [];
            for (const memberId of memberIds) {
                if (memberId !== userId) {
                    broadcastToUser(memberId, {
                        type: 'like_watchlist',
                        watchlistId: req.params.id,
                        watchlistName: r.rows[0].name,
                        fromId: userId,
                        fromName: liker.display_name || liker.username || userId,
                        fromHandle: liker.username || '',
                        fromAvatarUrl: liker.avatar_url || null,
                    });
                }
            }
            res.json({ likes: newLikes, likedBy: newLikedBy });
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    // DELETE /watchlists/:id/like
    router.delete('/:id/like', requireAuth, async (req, res) => {
        try {
            const userId = req.query.userId;
            if (!userId) return res.status(400).json({ error: 'userId required' });
            if (req.user.sub !== userId) return res.status(403).json({ error: 'Forbidden' });

            const r = await query('SELECT liked_by, likes FROM watchlists WHERE id = $1', [
                req.params.id,
            ]);
            if (!r.rows.length) return res.status(404).json({ error: 'Watchlist not found' });
            const likedBy = r.rows[0].liked_by ?? [];
            if (!likedBy.includes(userId)) return res.json({ likes: r.rows[0].likes, likedBy });

            const newLikedBy = likedBy.filter((id) => id !== userId);
            const newLikes = Math.max(0, (r.rows[0].likes ?? 0) - 1);
            await query('UPDATE watchlists SET liked_by = $1, likes = $2 WHERE id = $3', [
                JSON.stringify(newLikedBy),
                newLikes,
                req.params.id,
            ]);
            res.json({ likes: newLikes, likedBy: newLikedBy });
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    // PATCH /watchlists/:id — rename
    router.patch('/:id', requireAuth, async (req, res) => {
        try {
            const { name } = req.body;
            if (!name) return res.status(400).json({ error: 'name is required' });
            const r = await query('UPDATE watchlists SET name = $1 WHERE id = $2 RETURNING *', [
                name,
                req.params.id,
            ]);
            if (!r.rows.length) return res.status(404).json({ error: 'Watchlist not found' });
            res.json({ id: r.rows[0].id, name: r.rows[0].name });
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    // DELETE /watchlists/:id
    router.delete('/:id', requireAuth, async (req, res) => {
        try {
            const wlR = await query('SELECT member_ids FROM watchlists WHERE id = $1', [
                req.params.id,
            ]);
            if (!wlR.rows.length) return res.status(404).json({ error: 'Watchlist not found' });
            const memberIds = wlR.rows[0].member_ids ?? [];
            if (memberIds.length > 0 && memberIds[0] !== req.user.sub) {
                return res.status(403).json({ error: 'Only the host can delete this list' });
            }

            // Remove this watchlist from every member's watchlist_ids array.
            for (const uid of memberIds)
                await arrayRemove('users', 'watchlist_ids', req.params.id, uid);

            //CASCADE delete handles movies, activity, and veto_sessions rows.
            await query('DELETE FROM watchlists WHERE id = $1', [req.params.id]);
            res.json({ deleted: req.params.id });
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    return router;
};
