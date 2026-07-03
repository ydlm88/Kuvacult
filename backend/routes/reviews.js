// Review routes — create, fetch, like, and delete movie reviews and their
// comments. Broadcasts new reviews to watchlist members via WebSocket.
const crypto = require('crypto');
const express = require('express');
const { query } = require('../db');
const { requireAuth } = require('../middleware/auth');

module.exports = function (broadcastToUser) {
    const router = express.Router();

    function commentShape(row) {
        return {
            id: row.id,
            reviewId: row.review_id,
            byId: row.by_id,
            byName: row.by_name,
            byHandle: row.by_handle,
            byAvatarUrl: row.by_avatar_url,
            text: row.text,
            likes: row.likes,
            likedBy: row.liked_by ?? [],
            at: row.at,
        };
    }

    function reviewShape(row) {
        return {
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
        };
    }

    // GET /reviews — all public reviews, newest first
    router.get('/', async (req, res) => {
        try {
            const limit = Math.min(parseInt(req.query.limit) || 500, 2000);
            const r = await query('SELECT * FROM reviews ORDER BY at DESC LIMIT $1', [limit]);
            res.json(r.rows.map(reviewShape));
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    // POST /reviews — submit a review
    router.post('/', requireAuth, async (req, res) => {
        try {
            const {
                byId,
                movieId,
                movieTitle,
                movieYear,
                movieDirector = '',
                moviePosterUrl = null,
                stars,
                text,
                rewatch = false,
            } = req.body;

            if (!byId || !movieId || !movieTitle || stars == null || !text) {
                return res
                    .status(400)
                    .json({ error: 'byId, movieId, movieTitle, stars, and text are required' });
            }
            if (req.user.sub !== byId) return res.status(403).json({ error: 'Forbidden' });

            const userR = await query(
                'SELECT display_name, username, avatar_url FROM users WHERE id = $1',
                [byId]
            );
            const u = userR.rows[0] ?? {};

            const byName     = u.display_name || u.username || byId;
            const byHandle   = u.username || byId;
            const byAvatarUrl = u.avatar_url || null;

            // Check if this user already reviewed this movie and update instead of insert
            const existing = await query(
                'SELECT id FROM reviews WHERE by_id = $1 AND movie_id = $2',
                [byId, movieId]
            );

            let r;
            if (existing.rows.length > 0) {
                r = await query(
                    `UPDATE reviews SET
                       stars = $1, text = $2, rewatch = $3,
                       by_name = $4, by_handle = $5, by_avatar_url = $6,
                       at = NOW()
                     WHERE id = $7 RETURNING *`,
                    [
                        parseFloat(stars),
                        text.trim(),
                        Boolean(rewatch),
                        byName,
                        byHandle,
                        byAvatarUrl,
                        existing.rows[0].id,
                    ]
                );
            } else {
                const id = crypto.randomUUID();
                r = await query(
                    `INSERT INTO reviews
             (id, by_id, by_name, by_handle, by_avatar_url,
              movie_id, movie_title, movie_year, movie_director, movie_poster_url,
              stars, text, rewatch)
            VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)
            RETURNING *`,
                    [
                        id,
                        byId,
                        byName,
                        byHandle,
                        byAvatarUrl,
                        movieId,
                        movieTitle,
                        parseInt(movieYear) || 0,
                        movieDirector,
                        moviePosterUrl,
                        parseFloat(stars),
                        text.trim(),
                        Boolean(rewatch),
                    ]
                );
            }

            try {
                const authorR = await query('SELECT friend_ids FROM users WHERE id = $1', [byId]);
                const friendIds = authorR.rows[0]?.friend_ids ?? [];
                if (friendIds.length > 0 && typeof broadcastToUser === 'function') {
                    const friendMsg = {
                        type: 'friend_review',
                        fromId: byId,
                        fromName: u.display_name || u.username || byId,
                        fromAvatarUrl: u.avatar_url || null,
                        movieId,
                        movieTitle,
                        stars: parseFloat(stars),
                        at: new Date().toISOString(),
                    };
                    for (const friendId of friendIds) {
                        broadcastToUser(friendId, friendMsg);
                    }
                }
            } catch (_) {}

            res.status(201).json(reviewShape(r.rows[0]));
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    // GET /reviews/:id
    router.get('/:id', async (req, res) => {
        try {
            const r = await query('SELECT * FROM reviews WHERE id = $1', [req.params.id]);
            if (!r.rows.length) return res.status(404).json({ error: 'Review not found' });
            res.json(reviewShape(r.rows[0]));
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    // PATCH /reviews/:id/like — toggle likes
    router.patch('/:id/like', requireAuth, async (req, res) => {
        try {
            const { userId } = req.body;
            if (!userId) return res.status(400).json({ error: 'userId required' });
            if (req.user.sub !== userId) return res.status(403).json({ error: 'Forbidden' });

            const r = await query('SELECT liked_by, likes FROM reviews WHERE id = $1', [
                req.params.id,
            ]);
            if (!r.rows.length) return res.status(404).json({ error: 'Review not found' });
            const likedBy = r.rows[0].liked_by ?? [];
            const alreadyLiked = likedBy.includes(userId);
            const newLikedBy = alreadyLiked
                ? likedBy.filter((id) => id !== userId)
                : [...likedBy, userId];
            const newLikes = Math.max(0, (r.rows[0].likes ?? 0) + (alreadyLiked ? -1 : 1));

            const updated = await query(
                'UPDATE reviews SET liked_by = $1, likes = $2 WHERE id = $3 RETURNING *',
                [JSON.stringify(newLikedBy), newLikes, req.params.id]
            );
            const row = updated.rows[0];
            if (!alreadyLiked && row.by_id !== userId) {
                const likerR = await query(
                    'SELECT display_name, username, avatar_url FROM users WHERE id = $1',
                    [userId]
                );
                const liker = likerR.rows[0] ?? {};
                broadcastToUser(row.by_id, {
                    type: 'like_review',
                    reviewId: row.id,
                    movieTitle: row.movie_title,
                    fromId: userId,
                    fromName: liker.display_name || liker.username || userId,
                    fromHandle: liker.username || '',
                    fromAvatarUrl: liker.avatar_url || null,
                });
            }
            res.json(reviewShape(row));
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    // GET /reviews/by-movie/:movieId
    router.get('/by-movie/:movieId', async (req, res) => {
        try {
            const r = await query('SELECT * FROM reviews WHERE movie_id = $1 ORDER BY at DESC', [
                req.params.movieId,
            ]);
            res.json(r.rows.map(reviewShape));
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    // DELETE /reviews/:id
    router.delete('/:id', requireAuth, async (req, res) => {
        try {
            const r = await query('SELECT by_id FROM reviews WHERE id = $1', [req.params.id]);
            if (!r.rows.length) return res.status(404).json({ error: 'Review not found' });
            if (r.rows[0].by_id !== req.user.sub)
                return res.status(403).json({ error: 'Forbidden' });
            await query('DELETE FROM reviews WHERE id = $1', [req.params.id]);
            res.json({ deleted: req.params.id });
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    // GET /reviews/:id/comments
    router.get('/:id/comments', async (req, res) => {
        try {
            const r = await query(
                'SELECT * FROM review_comments WHERE review_id = $1 ORDER BY at ASC',
                [req.params.id]
            );
            res.json(r.rows.map(commentShape));
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    // POST /reviews/:id/comments
    router.post('/:id/comments', requireAuth, async (req, res) => {
        try {
            const { byId, text } = req.body;
            if (!byId || !text?.trim())
                return res.status(400).json({ error: 'byId and text required' });
            if (req.user.sub !== byId) return res.status(403).json({ error: 'Forbidden' });

            const userR = await query(
                'SELECT display_name, username, avatar_url FROM users WHERE id = $1',
                [byId]
            );
            const u = userR.rows[0] ?? {};

            const id = crypto.randomUUID();
            await query(
                `INSERT INTO review_comments (id, review_id, by_id, by_name, by_handle, by_avatar_url, text)
       VALUES ($1,$2,$3,$4,$5,$6,$7)`,
                [
                    id,
                    req.params.id,
                    byId,
                    u.display_name || u.username || byId,
                    u.username || byId,
                    u.avatar_url || null,
                    text.trim(),
                ]
            );
            await query('UPDATE reviews SET comment_count = comment_count + 1 WHERE id = $1', [
                req.params.id,
            ]);

            const r = await query('SELECT * FROM review_comments WHERE id = $1', [id]);
            res.status(201).json(commentShape(r.rows[0]));
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    // DELETE /reviews/:id/comments/:commentId
    router.delete('/:id/comments/:commentId', requireAuth, async (req, res) => {
        try {
            const r = await query(
                'SELECT by_id FROM review_comments WHERE id = $1 AND review_id = $2',
                [req.params.commentId, req.params.id]
            );
            if (!r.rows.length) return res.status(404).json({ error: 'Comment not found' });
            if (r.rows[0].by_id !== req.user.sub)
                return res.status(403).json({ error: 'Forbidden' });
            await query('DELETE FROM review_comments WHERE id = $1', [req.params.commentId]);
            await query(
                'UPDATE reviews SET comment_count = GREATEST(0, comment_count - 1) WHERE id = $1',
                [req.params.id]
            );
            res.json({ deleted: req.params.commentId });
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    // PATCH /reviews/:id/comments/:commentId/like
    router.patch('/:id/comments/:commentId/like', requireAuth, async (req, res) => {
        try {
            const { userId } = req.body;
            if (!userId) return res.status(400).json({ error: 'userId required' });
            if (req.user.sub !== userId) return res.status(403).json({ error: 'Forbidden' });

            const r = await query(
                'SELECT liked_by, likes FROM review_comments WHERE id = $1 AND review_id = $2',
                [req.params.commentId, req.params.id]
            );
            if (!r.rows.length) return res.status(404).json({ error: 'Comment not found' });
            const likedBy = r.rows[0].liked_by ?? [];
            const already = likedBy.includes(userId);
            const newLikedBy = already
                ? likedBy.filter((id) => id !== userId)
                : [...likedBy, userId];
            const newLikes = Math.max(0, (r.rows[0].likes ?? 0) + (already ? -1 : 1));

            const updated = await query(
                'UPDATE review_comments SET liked_by = $1, likes = $2 WHERE id = $3 RETURNING *',
                [JSON.stringify(newLikedBy), newLikes, req.params.commentId]
            );
            res.json(commentShape(updated.rows[0]));
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    return router;
};
