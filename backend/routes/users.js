
const crypto = require('crypto');
const express = require('express');
const router = express.Router();
const { db, storage } = require('../firebase');

//POST /users
router.post('/', async(req, res) => {
    try {
        const { auth0Sub, username, email, displayName } = req.body;
        if(!auth0Sub || !email){
            return res.status(400).json({ error: 'auth0Sub and email are required' });
        }

        const ref = db.collection('users').doc(auth0Sub);
        const existing = await ref.get();

        if (!existing.exists){
            //First login, create the full document
            await ref.set({
                auth0Sub, username, email, displayName,
                avatarUrl: null,
                roomKey: null,
                friendIds: [],
                watchlistIds: [],
                createdAt: new Date().toISOString(),
                updatedAt: new Date().toISOString(),
            });
        } else {
            //Returning user — sync email/username from Auth0 but preserve any custom displayName
            await ref.update({
                username, email,
                updatedAt: new Date().toISOString(),
            });
        }

        const doc = await ref.get();
        res.json({ id: doc.id, ...doc.data()});

    } catch(err) {
        res.status(500).json({ error: err.message});
    }

});

//Get /users/:auth0Sub - finds user through auth0
// Pass ?requesterId=<auth0Sub> to receive the displayName (only returned to self or friends)
router.get('/:auth0Sub', async(req, res) => {
    try {
        const doc = await db.collection('users').doc(req.params.auth0Sub).get();
        if(!doc.exists) return res.status(404).json({ error: 'User not found' });
        const data = doc.data();
        const requesterId = req.query.requesterId;
        const isSelf = requesterId && requesterId === req.params.auth0Sub;
        const isFriend = requesterId && (data.friendIds || []).includes(requesterId);
        // displayName is private — only the user themselves or their friends can see it
        const displayName = (isSelf || isFriend) ? data.displayName : null;
        res.json({
            id: doc.id,
            username: data.username,
            displayName,
            avatarUrl: data.avatarUrl,
            friendIds: data.friendIds,
            roomKey: isSelf ? data.roomKey : undefined,
            watchlistIds: isSelf ? data.watchlistIds : undefined,
        });
    } catch(err) {
        res.status(500).json({ error: err.message });
    }
});

//PATCH /users/:auth0Sub - update displayName, avatarUrl, or roomKey
router.patch('/:auth0Sub', async(req, res) => {
    try {
        const { displayName, avatarUrl, roomKey} = req.body;
        const update = {updatedAt: new Date().toISOString()};
        if (displayName !== undefined) update.displayName = displayName;
        if(avatarUrl !== undefined) update.avatarUrl = avatarUrl;
        if(roomKey !== undefined) update.roomKey = roomKey;

        await db.collection('users').doc(req.params.auth0Sub).update(update);
        const doc = await db.collection('users').doc(req.params.auth0Sub).get();
        res.json({ id: doc.id, ...doc.data()});
    } catch(err){
        res.status(500).json({ error: err.message});
    }
});

//GET /users/:auth0Sub/watchlists - returns all watchlists with movies + member profiles
router.get('/:auth0Sub/watchlists', async (req, res) => {
    try {
        const userDoc = await db.collection('users').doc(req.params.auth0Sub).get();
        if (!userDoc.exists) return res.status(404).json({ error: 'User not found' });

        const { watchlistIds = [] } = userDoc.data();

        const watchlists = await Promise.all(
            watchlistIds.map(async (id) => {
                const wlDoc = await db.collection('watchlists').doc(id).get();
                if (!wlDoc.exists) return null;
                const wlData = wlDoc.data();
                const moviesSnap = await wlDoc.ref.collection('movies').get();
                const movies = moviesSnap.docs.map(m => ({ id: m.id, ...m.data() }));
                // Include basic profiles for each member so clients can show names/avatars
                const members = await Promise.all(
                    (wlData.memberIds || []).map(async (memberId) => {
                        const mDoc = await db.collection('users').doc(memberId).get();
                        if (!mDoc.exists) return { id: memberId };
                        const d = mDoc.data();
                        return { id: memberId, displayName: d.displayName, avatarUrl: d.avatarUrl, username: d.username };
                    })
                );
                return { id: wlDoc.id, ...wlData, movies, members };
            })
        );

        res.json(watchlists.filter(Boolean));
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

//GET /users?roomKey=ABC123 — check uniqueness
//GET /users?q=term      — search users by username prefix
router.get('/', async (req, res) => {
    try {
        const { roomKey, q } = req.query;

        if (roomKey) {
            const snap = await db.collection('users').where('roomKey', '==', roomKey).limit(1).get();
            return res.json({ exists: !snap.empty });
        }

        if (q) {
            const term = q.trim();
            const snap = await db.collection('users')
                .where('username', '>=', term)
                .where('username', '<=', term + '')
                .limit(20)
                .get();
            return res.json(snap.docs.map(doc => ({ id: doc.id, ...doc.data() })));
        }

        return res.status(400).json({ error: 'roomKey or q query param required' });
    } catch(err) {
        res.status(500).json({ error : err.message });
    }
});

//GET /users/:auth0Sub/friend-requests - pending incoming requests
router.get('/:auth0Sub/friend-requests', async (req, res) => {
    try {
        const snap = await db.collection('friendRequests')
        .where('toId', '==', req.params.auth0Sub)
        .where('status', '==', 'pending')
        .get();

        const requests = snap.docs.map(doc => ({
            id: doc.id, ...doc.data()
        }));
        res.json(requests);
    } catch(err) {
        res.status(500).json({error: err.message});
    }
});

//GET /users/:auth0Sub/friends - full profiles for each friend
router.get('/:auth0Sub/friends', async (req, res) => {
    try {
        const userDoc = await db.collection('users')
        .doc(req.params.auth0Sub)
        .get();
        if(!userDoc.exists) return res.status(404).json({error: 'User not found' });

        const { friendIds = [] } = userDoc.data();
        const friends = await Promise.all(
            friendIds.map(async (id) =>{
                const doc = await db.collection('users').doc(id).get();
                return doc.exists ? { id: doc.id, ...doc.data()} : null;
            })
        );
        res.json(friends.filter(Boolean));
    } catch(err) {
        res.status(500).json({ error: err.message });
    }
});

// POST /users/:auth0Sub/avatar — upload profile photo to Firebase Storage
// Body: { imageBase64: string, mimeType: string }
// Accepts images compressed by image_picker (already 512x512, quality 85)
router.post('/:auth0Sub/avatar', async (req, res) => {
    try {
        const { auth0Sub } = req.params;
        const { imageBase64, mimeType = 'image/jpeg' } = req.body;
        if (!imageBase64) return res.status(400).json({ error: 'imageBase64 required' });

        const buffer = Buffer.from(imageBase64, 'base64');
        const ext = mimeType === 'image/png' ? 'png' : 'jpg';
        // Replace | in auth0 sub so it works as a safe filename
        const safeSub = auth0Sub.replace(/[|]/g, '_');
        const filename = `avatars/${safeSub}.${ext}`;
        const token = crypto.randomBytes(16).toString('hex');

        const bucket = storage.bucket();
        const file = bucket.file(filename);
        await file.save(buffer, {
            metadata: {
                contentType: mimeType,
                metadata: { firebaseStorageDownloadTokens: token },
            },
        });

        const avatarUrl = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(filename)}?alt=media&token=${token}`;
        await db.collection('users').doc(auth0Sub).update({ avatarUrl, updatedAt: new Date().toISOString() });
        res.json({ avatarUrl });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

module.exports = router;