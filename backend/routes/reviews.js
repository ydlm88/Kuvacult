const express = require('express');
const router = express.Router();
const { db } = require('../firebase');

// ─── GET /reviews — all public reviews, newest first ─────────────────────────
router.get('/', async (req, res) => {
    try {
        const limit = parseInt(req.query.limit) || 50;
        const snap = await db.collection('reviews')
            .orderBy('at', 'desc')
            .limit(limit)
            .get();
        const reviews = snap.docs.map(d => ({ id: d.id, ...d.data() }));
        res.json(reviews);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ─── POST /reviews — submit a new review ─────────────────────────────────────
router.post('/', async (req, res) => {
    try {
        const {
            byId, movieId, movieTitle, movieYear,
            movieDirector = '', moviePosterUrl = null,
            stars, text, rewatch = false,
        } = req.body;

        if (!byId || !movieId || !movieTitle || stars == null || !text) {
            return res.status(400).json({ error: 'byId, movieId, movieTitle, stars, and text are required' });
        }

        // Fetch author display info from their user doc
        const userDoc = await db.collection('users').doc(byId).get();
        const userData = userDoc.exists ? userDoc.data() : {};

        const review = {
            byId,
            byName: userData.displayName || userData.username || byId,
            byHandle: userData.username || byId,
            byAvatarUrl: userData.avatarUrl || null,
            movieId,
            movieTitle,
            movieYear: parseInt(movieYear) || 0,
            movieDirector,
            moviePosterUrl,
            stars: parseFloat(stars),
            text: text.trim(),
            rewatch: Boolean(rewatch),
            likes: 0,
            likedBy: [],
            commentCount: 0,
            at: new Date().toISOString(),
        };

        const ref = await db.collection('reviews').add(review);
        res.status(201).json({ id: ref.id, ...review });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ─── GET /reviews/:id — single review ────────────────────────────────────────
router.get('/:id', async (req, res) => {
    try {
        const doc = await db.collection('reviews').doc(req.params.id).get();
        if (!doc.exists) return res.status(404).json({ error: 'Review not found' });
        res.json({ id: doc.id, ...doc.data() });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ─── PATCH /reviews/:id/like — toggle like ───────────────────────────────────
router.patch('/:id/like', async (req, res) => {
    try {
        const { userId } = req.body;
        if (!userId) return res.status(400).json({ error: 'userId required' });

        const ref = db.collection('reviews').doc(req.params.id);
        const doc = await ref.get();
        if (!doc.exists) return res.status(404).json({ error: 'Review not found' });

        const { likedBy = [], likes = 0 } = doc.data();
        const alreadyLiked = likedBy.includes(userId);

        if (alreadyLiked) {
            await ref.update({
                likedBy: likedBy.filter(id => id !== userId),
                likes: Math.max(0, likes - 1),
            });
        } else {
            await ref.update({
                likedBy: [...likedBy, userId],
                likes: likes + 1,
            });
        }

        const updated = await ref.get();
        res.json({ id: updated.id, ...updated.data() });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ─── GET /movies/:movieId/reviews — reviews for a specific movie ──────────────
// Mounted at /movies in server.js
router.get('/by-movie/:movieId', async (req, res) => {
    try {
        const snap = await db.collection('reviews')
            .where('movieId', '==', req.params.movieId)
            .orderBy('at', 'desc')
            .get();
        res.json(snap.docs.map(d => ({ id: d.id, ...d.data() })));
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

module.exports = router;
