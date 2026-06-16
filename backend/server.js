require('dotenv').config();
const express = require('express');
const cors = require('cors');
const http = require('http');
const { WebSocketServer, OPEN } = require('ws');
const { db } = require('./firebase');

const app = express();
app.use(cors());
app.use(express.json());

app.use('/users', require('./routes/users'));
app.use('/friend-requests', require('./routes/friendRequests'));
app.use('/movies', require('./routes/movies'));

app.get('/', (req, res) => res.json({ status: 'Marquee API running' }));

const server = http.createServer(app);

// ─── WebSocket server ─────────────────────────────────────────────────────────
const wss = new WebSocketServer({ server });
const rooms = new Map();     // watchlistId -> Set<WebSocket>
const userRooms = new Map(); // userId      -> Set<WebSocket>
const bjDecks = new Map();   // watchlistId -> Card[]  (in-memory deck)

const wlRouter = require('./routes/watchlists');
app.use('/watchlists', wlRouter(rooms));

wss.on('connection', (ws, req) => {
    const { searchParams } = new URL(req.url, 'http://localhost');
    const watchlistId = searchParams.get('watchlistId');
    const userId = searchParams.get('userId');

    if (watchlistId) {
        if (!rooms.has(watchlistId)) rooms.set(watchlistId, new Set());
        rooms.get(watchlistId).add(ws);
        sendCurrentSession(ws, watchlistId);

        ws.on('message', (data) => {
            try { handleMessage(watchlistId, JSON.parse(data.toString())); }
            catch (_) {}
        });
        ws.on('close', () => {
            rooms.get(watchlistId)?.delete(ws);
            if (rooms.get(watchlistId)?.size === 0) rooms.delete(watchlistId);
        });
    } else if (userId) {
        if (!userRooms.has(userId)) userRooms.set(userId, new Set());
        userRooms.get(userId).add(ws);
        ws.on('close', () => {
            userRooms.get(userId)?.delete(ws);
            if (userRooms.get(userId)?.size === 0) userRooms.delete(userId);
        });
    } else {
        ws.close(1008, 'watchlistId or userId required');
    }
});

function broadcast(watchlistId, msg) {
    const room = rooms.get(watchlistId);
    if (!room) return;
    const payload = JSON.stringify(msg);
    room.forEach(client => { if (client.readyState === OPEN) client.send(payload); });
}

function broadcastToUser(userId, msg) {
    const room = userRooms.get(userId);
    if (!room) return;
    const payload = JSON.stringify(msg);
    room.forEach(client => { if (client.readyState === OPEN) client.send(payload); });
}

async function sendCurrentSession(ws, watchlistId) {
    try {
        const doc = await db.collection('vetoSessions').doc(watchlistId).get();
        if (doc.exists) ws.send(JSON.stringify({ type: 'veto_state', ...doc.data() }));
    } catch (_) {}
}

// ─── Blackjack deck helpers ───────────────────────────────────────────────────
function createDeck() {
    const suits = ['♥', '♦', '♣', '♠'];
    const ranks = ['A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K'];
    const deck = [];
    for (const suit of suits) for (const rank of ranks) deck.push({ suit, rank });
    return deck;
}

function shuffle(deck) {
    for (let i = deck.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [deck[i], deck[j]] = [deck[j], deck[i]];
    }
    return deck;
}

function cardValue(card) {
    if (card.rank === 'A') return 11;
    if (['J', 'Q', 'K'].includes(card.rank)) return 10;
    return parseInt(card.rank);
}

function handValue(hand) {
    let total = hand.reduce((s, c) => s + cardValue(c), 0);
    let aces = hand.filter(c => c.rank === 'A').length;
    while (total > 21 && aces > 0) { total -= 10; aces--; }
    return total;
}

function drawCard(watchlistId) {
    if (!bjDecks.has(watchlistId) || bjDecks.get(watchlistId).length < 8) {
        bjDecks.set(watchlistId, shuffle(createDeck()));
    }
    return bjDecks.get(watchlistId).pop();
}

// ─── Blackjack game flow ──────────────────────────────────────────────────────

// Start a fresh betting round (no cards yet — players choose their film first)
async function startBlackjack(watchlistId) {
    bjDecks.set(watchlistId, shuffle(createDeck()));
    const ref = db.collection('vetoSessions').doc(watchlistId);
    await ref.update({
        status: 'blackjack_betting',
        blackjack: {
            status: 'betting',
            players: [],
            house: [],
            houseRevealed: false,
            winnerId: null,
            activePlayerId: null,
        },
    });
    broadcast(watchlistId, { type: 'blackjack_start', status: 'betting' });
}

// Deal cards to everyone (called once all expected bets are in, or on redeal)
async function dealCards(watchlistId, bettedPlayers) {
    const houseCards = [drawCard(watchlistId), drawCard(watchlistId)];
    const dealtPlayers = bettedPlayers.map(p => ({
        ...p,
        hand: [drawCard(watchlistId), drawCard(watchlistId)],
        stood: false,
        bust: false,
    }));
    const activePlayerId = dealtPlayers.length > 0 ? dealtPlayers[0].playerId : null;

    const updatedBj = {
        status: 'playing',
        players: dealtPlayers,
        house: houseCards,
        houseRevealed: false,
        winnerId: null,
        activePlayerId,
    };

    const ref = db.collection('vetoSessions').doc(watchlistId);
    await ref.update({ status: 'blackjack_playing', blackjack: updatedBj });
    broadcast(watchlistId, { type: 'blackjack_update', blackjack: updatedBj });
}

// After all players are done, House draws to 17, then resolve vs House
async function resolveRound(watchlistId, session) {
    const bj = session.blackjack;
    if (!bj.players.every(p => p.stood || p.bust)) return;

    // House draws to 17
    const houseHand = [...(bj.house || [])];
    while (handValue(houseHand) < 17) houseHand.push(drawCard(watchlistId));
    const houseTotal = handValue(houseHand);
    const houseBust = houseTotal > 21;

    // Winner = player with highest total ≤ 21 that beats the house
    let winner = null;
    let bestVal = -1;
    for (const p of bj.players) {
        const v = handValue(p.hand);
        const beatsHouse = v <= 21 && (houseBust || v > houseTotal);
        if (beatsHouse && v > bestVal) { bestVal = v; winner = p; }
    }

    const updatedBj = {
        ...bj,
        house: houseHand,
        houseRevealed: true,
        status: winner ? 'done' : 'redeal',
        winnerId: winner ? winner.betMovieId : null,
    };

    const ref = db.collection('vetoSessions').doc(watchlistId);

    if (winner) {
        await ref.update({ status: 'done', winnerId: winner.betMovieId, blackjack: updatedBj });
        broadcast(watchlistId, { type: 'blackjack_update', blackjack: updatedBj });
        broadcast(watchlistId, { type: 'veto_winner', winnerId: winner.betMovieId, via: 'blackjack' });
        await db.collection('watchlists').doc(watchlistId).collection('activity').add({
            kind: 'vetoPick', who: session.pickerId, picks: session.pickedIds,
            at: new Date().toISOString(),
        });
    } else {
        // House wins — wait for players to request a redeal
        await ref.update({ blackjack: updatedBj });
        broadcast(watchlistId, { type: 'blackjack_update', blackjack: updatedBj });
    }
}

// ─── Main WebSocket message handler ──────────────────────────────────────────
async function handleMessage(watchlistId, msg) {

    if (msg.type === 'veto_start') {
        const pickCount = msg.pickCount || 3;
        const maxVetos = Math.max(0, pickCount - 1);
        const session = {
            watchlistId,
            pickedIds: msg.pickedIds,
            vetoedIds: [],
            winnerId: null,
            pickerId: msg.pickerId,
            pickerName: msg.pickerName,
            pickCount,
            maxVetosPerPlayer: maxVetos,
            vetosByPlayer: { [msg.pickerId]: 0 },
            picksPerPlayer: { [msg.pickerId]: pickCount },
            status: pickCount === 1 ? 'blackjack_betting' : 'vetoing',
            startedAt: new Date().toISOString(),
        };

        if (pickCount === 1) {
            session.blackjack = { status: 'betting', players: [], house: [], houseRevealed: false, winnerId: null, activePlayerId: null };
        }

        await db.collection('vetoSessions').doc(watchlistId).set(session);
        broadcast(watchlistId, { type: 'veto_started', ...session });

        if (msg.sendInvite !== false) {
            try {
                const wlDoc = await db.collection('watchlists').doc(watchlistId).get();
                if (wlDoc.exists) {
                    const { memberIds = [], name = 'Watchlist' } = wlDoc.data();
                    memberIds.forEach(memberId => {
                        if (memberId !== msg.pickerId) {
                            broadcastToUser(memberId, {
                                type: 'veto_invite', fromId: msg.pickerId,
                                fromName: msg.pickerName, watchlistId, watchlistName: name,
                            });
                        }
                    });
                }
            } catch (_) {}
        }

        if (pickCount === 1) {
            broadcast(watchlistId, { type: 'blackjack_start', status: 'betting' });
        }

    } else if (msg.type === 'veto_add_picks') {
        const ref = db.collection('vetoSessions').doc(watchlistId);
        const doc = await ref.get();
        if (!doc.exists) return;
        const session = doc.data();

        const pickCount = msg.pickCount || 3;
        const maxVetos = Math.max(0, pickCount - 1);
        const updatedPickedIds = [...new Set([...session.pickedIds, ...msg.additionalPickIds])];
        const vetosByPlayer = { ...(session.vetosByPlayer || {}), [msg.pickerId]: 0 };
        const picksPerPlayer = { ...(session.picksPerPlayer || {}), [msg.pickerId]: pickCount };

        const update = { pickedIds: updatedPickedIds, vetosByPlayer, picksPerPlayer, maxVetosPerPlayer: maxVetos };

        const allPickCounts = Object.values(picksPerPlayer);
        const allPicked1 = allPickCounts.length >= 2 && allPickCounts.every(c => c === 1);

        if (allPicked1) {
            update.status = 'blackjack_betting';
            update.blackjack = { status: 'betting', players: [], house: [], houseRevealed: false, winnerId: null, activePlayerId: null };
        }

        await ref.update(update);
        broadcast(watchlistId, { type: 'picks_added', pickedIds: updatedPickedIds, maxVetosPerPlayer: maxVetos });

        if (allPicked1) {
            broadcast(watchlistId, { type: 'blackjack_start', status: 'betting' });
        }

    } else if (msg.type === 'veto_action') {
        const ref = db.collection('vetoSessions').doc(watchlistId);
        const doc = await ref.get();
        if (!doc.exists) return;
        const session = doc.data();

        const vetosByPlayer = { ...(session.vetosByPlayer || {}) };
        vetosByPlayer[msg.vetoerId] = (vetosByPlayer[msg.vetoerId] || 0) + 1;
        const vetoedIds = [...session.vetoedIds, msg.vetoedId];
        const remaining = session.pickedIds.filter(id => !vetoedIds.includes(id));
        const maxVetos = session.maxVetosPerPlayer || 2;
        const allVetosUsed = Object.values(vetosByPlayer).length >= 2 &&
            Object.values(vetosByPlayer).every(v => v >= maxVetos);

        const update = { vetoedIds, vetosByPlayer };

        if (remaining.length === 1) {
            update.winnerId = remaining[0];
            update.status = 'done';
            await ref.update(update);
            broadcast(watchlistId, { type: 'veto_actioned', vetoedId: msg.vetoedId });
            broadcast(watchlistId, { type: 'veto_winner', winnerId: remaining[0] });
            await db.collection('watchlists').doc(watchlistId).collection('activity').add({
                kind: 'vetoPick', who: session.pickerId, picks: session.pickedIds,
                at: new Date().toISOString(),
            });
        } else if (remaining.length === 2 && allVetosUsed) {
            await ref.update(update);
            broadcast(watchlistId, { type: 'veto_actioned', vetoedId: msg.vetoedId });
            await startBlackjack(watchlistId);
        } else {
            await ref.update(update);
            broadcast(watchlistId, { type: 'veto_actioned', vetoedId: msg.vetoedId });
        }

    } else if (msg.type === 'blackjack_bet') {
        const ref = db.collection('vetoSessions').doc(watchlistId);
        const doc = await ref.get();
        if (!doc.exists) return;
        const session = doc.data();
        const bj = session.blackjack || { players: [], status: 'betting' };

        if (bj.players.some(p => p.playerId === msg.playerId)) return;

        const updatedPlayers = [...bj.players, {
            playerId: msg.playerId,
            playerName: msg.playerName,
            betMovieId: msg.betMovieId,
            hand: [], stood: false, bust: false,
        }];

        const updatedBj = { ...bj, players: updatedPlayers };
        await ref.update({ blackjack: updatedBj });

        if (updatedPlayers.length >= 2) {
            // All players have bet — check for unanimous pick
            const allSame = updatedPlayers.every(p => p.betMovieId === updatedPlayers[0].betMovieId);
            if (allSame) {
                // Everyone agrees — no need for cards, that movie wins immediately
                const winningMovieId = updatedPlayers[0].betMovieId;
                const doneBj = { ...updatedBj, status: 'done', winnerId: winningMovieId, houseRevealed: true };
                await ref.update({ status: 'done', winnerId: winningMovieId, blackjack: doneBj });
                broadcast(watchlistId, { type: 'blackjack_update', blackjack: doneBj });
                broadcast(watchlistId, { type: 'veto_winner', winnerId: winningMovieId, via: 'unanimous' });
            } else {
                // Different picks — deal cards and play
                bjDecks.set(watchlistId, shuffle(createDeck()));
                await dealCards(watchlistId, updatedPlayers);
            }
        } else {
            // First bet — broadcast so the other player sees it
            broadcast(watchlistId, { type: 'blackjack_update', blackjack: updatedBj });
        }

    } else if (msg.type === 'blackjack_hit') {
        const ref = db.collection('vetoSessions').doc(watchlistId);
        const doc = await ref.get();
        if (!doc.exists) return;
        const session = doc.data();
        const bj = session.blackjack;
        if (!bj || bj.activePlayerId !== msg.playerId) return;

        const newCard = drawCard(watchlistId);
        const updatedPlayers = bj.players.map(p => {
            if (p.playerId !== msg.playerId) return p;
            const newHand = [...p.hand, newCard];
            return { ...p, hand: newHand, bust: handValue(newHand) > 21 };
        });

        const hitPlayer = updatedPlayers.find(p => p.playerId === msg.playerId);
        let nextActiveId = bj.activePlayerId;

        if (hitPlayer.bust) {
            const idx = updatedPlayers.findIndex(p => p.playerId === msg.playerId);
            const next = updatedPlayers.slice(idx + 1).find(p => !p.stood && !p.bust);
            nextActiveId = next ? next.playerId : null;
        }

        const updatedBj = { ...bj, players: updatedPlayers, activePlayerId: nextActiveId };
        await ref.update({ blackjack: updatedBj });
        broadcast(watchlistId, { type: 'blackjack_update', blackjack: updatedBj });

        if (updatedPlayers.every(p => p.stood || p.bust)) {
            await resolveRound(watchlistId, { ...session, blackjack: updatedBj });
        }

    } else if (msg.type === 'blackjack_stand') {
        const ref = db.collection('vetoSessions').doc(watchlistId);
        const doc = await ref.get();
        if (!doc.exists) return;
        const session = doc.data();
        const bj = session.blackjack;
        if (!bj || bj.activePlayerId !== msg.playerId) return;

        const updatedPlayers = bj.players.map(p =>
            p.playerId === msg.playerId ? { ...p, stood: true } : p
        );
        const idx = updatedPlayers.findIndex(p => p.playerId === msg.playerId);
        const next = updatedPlayers.slice(idx + 1).find(p => !p.stood && !p.bust);
        const nextActiveId = next ? next.playerId : null;

        const updatedBj = { ...bj, players: updatedPlayers, activePlayerId: nextActiveId };
        await ref.update({ blackjack: updatedBj });
        broadcast(watchlistId, { type: 'blackjack_update', blackjack: updatedBj });

        if (updatedPlayers.every(p => p.stood || p.bust)) {
            await resolveRound(watchlistId, { ...session, blackjack: updatedBj });
        }

    } else if (msg.type === 'blackjack_deal_again') {
        const ref = db.collection('vetoSessions').doc(watchlistId);
        const doc = await ref.get();
        if (!doc.exists) return;
        const bj = doc.data().blackjack;
        if (!bj || bj.status !== 'redeal') return;
        bjDecks.set(watchlistId, shuffle(createDeck()));
        await dealCards(watchlistId, bj.players);

    } else if (msg.type === 'veto_reset') {
        try {
            await db.collection('vetoSessions').doc(watchlistId).delete();
            bjDecks.delete(watchlistId);
        } catch (_) {}
        broadcast(watchlistId, { type: 'veto_reset' });
    }
}

server.listen(process.env.PORT, () =>
    console.log(`Server running on port ${process.env.PORT}`)
);
