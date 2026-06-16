
const express = require('express');
const router = express.Router();
const { db, admin } = require('../firebase');
const FieldValue = admin.firestore.FieldValue;

// POST /friend-requests - send a friend request
// body: { fromId, toId}
router.post('/', async (req, res) => {
    try {
        const { fromId, toId } = req.body;
        if (!fromId || !toId) return res.status(400).json({ error: 'fromId and toId are required' });
        if (fromId == toId) return res.status(400).json({error : 'Cannot send friend requests to yourself'});

        const fromDoc = await db.collection('users').doc(fromId).get();
        if (!fromDoc.exists) return res.status(404).json({ error: 'Sender not found'});
        
        const { friendIds = [] } = fromDoc.data();
        if (friendIds.includes(toId)) return res.status(409).json({error: 'Already friends'});

        const existing = await db.collection('friendRequests')
        .where('fromId', '==', fromId)
        .where('toId', '==', toId)
        .where('status', '==', 'pending')
        .limit(1)
        .get();
        if(!existing.empty) return res.status(409).json({ error: 'Friend request already pending'});

        const ref = await db.collection('friendRequests').add({
            fromId,
            toId,
            status: 'pending',
            createdAt: new Date().toISOString(),
        });
        res.status(201).json({ 
            id: ref.id, fromId, toId, 
            status: 'pending'
        });
    } catch(err) {
        res.status(500).json({error: err.message});
    }
});

//PATCH /friend-requests/:id/accept - accept a pending request
router.patch('/:id/accept', async (req, res) => {
    try {
        const reqDoc = await db.collection('friendRequests').doc(req.params.id).get();
        if (!reqDoc.exists) return res.status(404).json({error: 'Friend request not found'});

        const { fromId, toId, status } = reqDoc.data();
        if (status !== 'pending') return res.status(409).json({ error: 'Request is no longer pending' });
        await db.collection('friendRequests').doc(req.params.id).update({
            status: 'accepted'
        });

        //Add users to eachothers friendlists, arrayUnion to prevent duplicates
        await db.collection('users').doc(toId).update({
            friendIds: FieldValue.arrayUnion(fromId)
        });
        await db.collection('users').doc(fromId).update({
            friendIds: FieldValue.arrayUnion(toId)
        });
        res.json({
            id: req.params.id,
            status: 'accepted'
        });
    } catch(err) {
        res.status(500).json({ error: err.message });
    }
});

//DELETE /friend-requests/:id - decline or cancel a request
router.delete('/:id', async (req, res) => {
    try {
        const reqDoc = await db.collection('friendRequests').doc(req.params.id).get();
        if (!reqDoc.exists) return res.status(404).json({ error: 'Friend request not found' });
        
        await db.collection('friendRequests').doc(req.params.id).update({
            status: 'declined'
        });
        res.json({ 
            id: req.params.id, 
            status: 'declined'
        });
    } catch(err) {
        res.status(500).json({error: err.message});
    }
});

module.exports = router;