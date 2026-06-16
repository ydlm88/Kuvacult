const {db, admin} = require('../firebase');
const { OPEN } = require('ws');

//Websocket
module.exports = function(rooms) {
    const router = require('express').Router();
    function broadcast(watchlistId, msg){
        rooms.get(watchlistId)?.forEach(ws => {
            if (ws.readyState == OPEN) ws.send(JSON.stringify(msg));
        });
    }

    //POST /watchlists - creates watchlist
    router.post('/', async (req, res) => {
    try {
        const { name, listKey, memberIds = [] } = req.body;
        if (!name) return res.status(400).json({ error: 'name is required'});
        const ref = await db.collection('watchlists').add({
            name,
            listKey: listKey ?? null,
            memberIds,
            createdAt: new Date().toISOString(),
        });

        for(const auth0Sub of memberIds) { //adds new watchlist to each members watchlistIds array
            await db.collection('users').doc(auth0Sub).update({
                watchlistIds: admin.firestore.FieldValue.arrayUnion(ref.id),
            });
        }

        res.status(201).json({ id: ref.id, name, listKey, memberIds});
    } catch(err){
        res.status(500).json({ error: err.message});
    } 
    });

    //POST /watchlists/join - joins by list key
    router.post('/join', async (req, res) => {
        try{
            const {listKey, auth0Sub} = req.body;
            if (!listKey || !auth0Sub){
                return res.status(400).json({ error: 'listKey and auth0Sub are required'});
            }
            const snap = await db.collection('watchlists')
            .where('listKey', '==', listKey.trim().toUpperCase())
            .get();

            if(snap.empty) return res.status(404).json({error: 'Room not found' });
            const doc = snap.docs[0];

            //add member to watchlist and watchlist to user
            const batch = db.batch();
            batch.update(doc.ref, {
                memberIds: admin.firestore.FieldValue.arrayUnion(auth0Sub),
            });
            batch.update(db.collection('users').doc(auth0Sub), {
                watchlistIds: admin.firestore.FieldValue.arrayUnion(doc.id),
            });
            await batch.commit();

            const moviesSnap = await doc.ref.collection('movies').get();
            const movies = moviesSnap.docs.map(m => ({ id: m.id, ...m.data()}));
            res.json({ id: doc.id, ...doc.data(), movies});
        } catch(err){
            res.status(500).json({ error: err.message});
        }
    });

    //GET /watchlists/find?code=ABC123 - read-only lookup by list key (guests)
    router.get('/find', async (req, res) => {
        try {
            const { code } = req.query;
            if (!code) return res.status(400).json({ error: 'code is required' });
            const snap = await db.collection('watchlists')
                .where('listKey', '==', code.trim().toUpperCase())
                .get();
            if (snap.empty) return res.status(404).json({ error: 'Room not found' });
            const doc = snap.docs[0];
            const moviesSnap = await doc.ref.collection('movies').get();
            const movies = moviesSnap.docs.map(m => ({ id: m.id, ...m.data() }));
            res.json({ id: doc.id, ...doc.data(), movies });
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    //GET /watchlists/:id/veto - get current veto session for a watchlist (used on reconnect)
    router.get('/:id/veto', async (req, res) => {
        try {
            const doc = await db.collection('vetoSessions').doc(req.params.id).get();
            res.json(doc.exists ? doc.data() : null);
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    //GET /watchlists/:id - gets watchlist by id
    router.get('/:id', async (req, res) => {
        try{
            const doc = await db.collection('watchlists').doc(req.params.id).get();
            if (!doc.exists) return res.status(404).json({ error: 'Not found' });
            
            const moviesSnap = await doc.ref.collection('movies').get();
            const movies = moviesSnap.docs.map(m => ({ id: m.id, ...m.data() }));
            
            res.json({ id: doc.id, ...doc.data(), movies });
        } catch(err) {
            res.status(500).json({ error: err.message});
        }
    });

    //POST /watchlists/:id/movies - add movies by id
    router.post('/:id/movies', async (req, res) => {
        try {
            const {
                movieId, title, year, runtime, rating,
                genres = [], director = '', streamId = '',
                synopsis = '', addedBy = 'guest', imageUrl = '',
            } = req.body;

            if(!movieId || !title){ return res.status(400).json({ error: 'movieId and title are required' });}

            const watchlistRef = db.collection('watchlists').doc(req.params.id);
            const movieRef = watchlistRef.collection('movies').doc(movieId);

            //movieId doubles as the document ID
            const existing = await movieRef.get();
            if(existing.exists) return res.status(409).json({ error: 'Alread in list'});

            const movieDoc = {
                movieId, title, year, runtime, rating, genres, director, streamId, synopsis, addedBy,
                imageUrl,
                section: 'want',
                reactions: {},
                stars: {},
                createdAt: new Date().toISOString(),
            };

            await movieRef.set(movieDoc);

            await watchlistRef.collection('activity').add({
                kind: 'added',
                who: addedBy,
                movieId,
                at: new Date().toISOString(),
            });

            //After POST /:id/movies
            broadcast(req.params.id, {
                type: 'movie_added',
                movie: {
                    id: movieId,
                    ...movieDoc 
                }
            });

            broadcast(req.params.id, {
                type:'activity_added',
                event: {
                    kind: 'added',
                    who: addedBy,
                    movieId,
                    at: new Date().toISOString()
                }
            });

            res.status(201).json({ id: movieId, ...movieDoc});
        } catch(err){
            res.status(500).json({ error: err.message});
        }
    });

    
    

    //PATCH /watchlists/:id/movies/:movieId - Endpoint for moveMovie, rateMovie, and reactToMovie
    router.patch('/:id/movies/:movieId', async (req, res) => {
        try {
            const movieRef = db.collection('watchlists').doc(req.params.id)
            .collection('movies').doc(req.params.movieId);

            const update = {};
            if(req.body.section) update.section = req.body.section; //moveMovie
            if(req.body.stars !== undefined && req.body.memberId){ //rateMovie
                update[`stars.${req.body.memberId}`] = req.body.stars;
            }
            if(req.body.reaction && req.body.memberId){ //reactToMovie
                update[`reactions.${req.body.memberId}`] = req.body.reaction;
            }

            await movieRef.update(update);
            const doc = await movieRef.get();

            broadcast(req.params.id, {
                type: 'movie_updated',
                movie: { id: doc.id, ...doc.data() }
            });

            const now = new Date().toISOString();
            if (req.body.stars !== undefined && req.body.memberId) {
                await db.collection('watchlists').doc(req.params.id).collection('activity').add({
                    kind: 'rated', who: req.body.memberId, movieId: req.params.movieId, stars: req.body.stars, at: now,
                });
                broadcast(req.params.id, { type: 'activity_added', event: {
                    kind: 'rated', who: req.body.memberId, movieId: req.params.movieId, stars: req.body.stars, at: now,
                }});
            } else if (req.body.reaction && req.body.memberId) {
                await db.collection('watchlists').doc(req.params.id).collection('activity').add({
                    kind: 'reacted', who: req.body.memberId, movieId: req.params.movieId, reaction: req.body.reaction, at: now,
                });
                broadcast(req.params.id, { type: 'activity_added', event: {
                    kind: 'reacted', who: req.body.memberId, movieId: req.params.movieId, reaction: req.body.reaction, at: now,
                }});
            } else if (req.body.section && req.body.memberId) {
                await db.collection('watchlists').doc(req.params.id).collection('activity').add({
                    kind: 'moved', who: req.body.memberId, movieId: req.params.movieId, to: req.body.section, at: now,
                });
                broadcast(req.params.id, { type: 'activity_added', event: {
                    kind: 'moved', who: req.body.memberId, movieId: req.params.movieId, to: req.body.section, at: now,
                }});
            }

            res.json({ id: doc.id, ...doc.data()});
        } catch(err){
            res.status(500).json({ error: err.message});
        }
    });

    //POST /watchlists/:id/movies/:movieId/notes - notes
    router.post('/:id/movies/:movieId/notes', async (req, res) => {
        try{ 
            const {by, text} = req.body;
            if(!by || !text) return res.status(400).json({ error: 'by and text are required'});

            const watchlistRef = db.collection('watchlists').doc(req.params.id);
            const noteRef = await watchlistRef.collection('movies')
            .doc(req.params.movieId)
            .collection('notes').add({
                by, text, 
                at: new Date().toISOString()
            });

            await watchlistRef.collection('activity').add({
                kind: 'note',
                who: by,
                movieId: req.params.movieId,
                text,
                at: new Date().toISOString(),
            });

            broadcast(req.params.id, {
                type:'activity_added',
                event: {
                    kind: 'note',
                    who: by,
                    movieId: req.params.movieId,
                    text,
                    at: new Date().toISOString()
                }
            });

            res.status(201).json({ id: noteRef.id, by, text});        
        } catch(err){
            res.status(500).json({ error: err.message});
        }
    });

    //DELETE /watchlists/:id/movies/:movieId - deletes movie from watchlist by id
    router.delete('/:id/movies/:movieId', async (req, res) => {
        try { 
            await db.collection('watchlists').doc(req.params.id)
            .collection('movies').doc(req.params.movieId).delete();
            
            //After DELETE /:id/movies/:movieId
            broadcast(req.params.id, {
                type: 'movie_removed',
                movieId: req.params.movieId
            });

            res.json({ deleted: req.params.movieId});
        } catch(err) {
            res.status(500).json({error: err.message});
        }
    });

    //PATCH /watchlists/:id/members - add a member by auth0Sub
    router.patch('/:id/members', async (req, res) => {
        try {
            const { auth0Sub } = req.body;
            if (!auth0Sub) return res.status(400).json({ error: 'auth0Sub is required' });

            const watchlistRef = db.collection('watchlists').doc(req.params.id);
            const watchlistDoc = await watchlistRef.get();
            if (!watchlistDoc.exists) return res.status(404).json({ error: 'Watchlist not found' });

            const batch = db.batch();
            batch.update(watchlistRef, {
                memberIds: admin.firestore.FieldValue.arrayUnion(auth0Sub),
            });
            batch.update(db.collection('users').doc(auth0Sub), {
                watchlistIds: admin.firestore.FieldValue.arrayUnion(req.params.id),
            });
            await batch.commit();

            const updated = await watchlistRef.get();
            res.json({ id: updated.id, ...updated.data() });
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    //PATCH /watchlists/:id/regenerate-key - generate a new list key
    router.patch('/:id/regenerate-key', async (req, res) => {
        try {
            const { listKey } = req.body;
            if (!listKey) return res.status(400).json({ error: 'listKey is required' });
            const ref = db.collection('watchlists').doc(req.params.id);
            await ref.update({ listKey: listKey.trim().toUpperCase() });
            res.json({ id: req.params.id, listKey: listKey.trim().toUpperCase() });
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    //PATCH /watchlists/:id - rename a watchlist
    router.patch('/:id', async (req, res) => {
        try {
            const { name } = req.body;
            if(!name) return res.status(400).json({ error: 'Name is required'});
            
            const ref = db.collection('watchlists').doc(req.params.id);
            await ref.update({name});

            const doc = await ref.get();
            res.json({ 
                id: doc.id, 
                ...doc.data()
            });
        } catch (err) {
            res.status(500).json({ error: err.message });
        }
    });

    //DELETE /watchlists/:id - watchlist and remove it from all members
    router.delete('/:id', async (req, res) => {
        try {
            const ref = db.collection('watchlists').doc(req.params.id);
            const doc = await ref.get();
            if(!doc.exists) return res.status(404).json({ error: 'Watchlist not found'});
            
            const {memberIds = [] } = doc.data();
            
            //Remove watchlistId from each member's watchlistIds array
            const batch = db.batch();
            for (const memberId of memberIds) {
                batch.update(db.collection('users').doc(memberId), {
                    watchlistIds: admin.firestore.FieldValue.arrayRemove(req.params.id),
                });
            }
        await batch.commit();

        //Recursively delete watchlist doc and all its subcollections
        await db.recursiveDelete(ref);
        res.json({ deleted: req.params.id});
        } catch(err) {
            res.status(500).json({error: err.message});
        }
    });

    return router;
}
