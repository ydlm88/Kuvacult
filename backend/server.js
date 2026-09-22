require('dotenv').config();
const path = require('path');
const express = require('express');
const cors = require('cors');
const http = require('http');
const { WebSocketServer, OPEN } = require('ws');
const { query, migrate } = require('./db');

const { middleware: reqStatsMiddleware } = require('./req_stats');

const app = express();
app.use(cors());
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: false }));
app.use(reqStatsMiddleware);

app.use('/uploads', express.static(path.join(__dirname, 'uploads')));
app.use('/posters', express.static(path.join(__dirname, 'posters')));

// Restrict /admin to loopback only
function requireLocalhost(req, res, next) {
    const raw = req.ip || req.socket?.remoteAddress || '';
    const ip = raw.replace('::ffff:', '');
    if (ip !== '127.0.0.1' && ip !== '::1') {
        return res.status(403).json({ error: 'Admin access is restricted to localhost' });
    }
    next();
}

app.use('/auth', require('./routes/auth'));
app.use('/friend-requests', require('./routes/friendRequests')(broadcastToUser));
app.use('/movies', require('./routes/movies'));
app.use('/reviews', require('./routes/reviews')(broadcastToUser));
app.use('/import', require('./routes/import'));
app.use('/admin', requireLocalhost, require('./routes/admin'));
app.use('/seance', require('./routes/seance')(broadcastToUser, broadcast));

app.get('/', (req, res) => res.json({ status: 'Kuvacult API running' }));

const server = http.createServer(app);

const wss = new WebSocketServer({ server });
const rooms = new Map();
const userRooms = new Map();
const bjDecks = new Map();

const wlRouter = require('./routes/watchlists');
const usersRouter = require('./routes/users');
app.use('/watchlists', wlRouter(rooms, broadcastToUser));
app.use('/users', usersRouter(rooms, broadcastToUser));

wss.on('connection', (ws, req) => {
    const { searchParams } = new URL(req.url, 'http://localhost');
    const watchlistId = searchParams.get('watchlistId');
    const userId = searchParams.get('userId');

    if (watchlistId) {
        if (!rooms.has(watchlistId)) rooms.set(watchlistId, new Set());
        rooms.get(watchlistId).add(ws);
        sendCurrentSession(ws, watchlistId);

        ws.on('message', (data) => {
            try {
                handleMessage(watchlistId, JSON.parse(data.toString()));
            } catch (_) {}
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
    room.forEach((c) => {
        if (c.readyState === OPEN) c.send(payload);
    });
}

function broadcastToUser(userId, msg) {
    const room = userRooms.get(userId);
    if (!room) return;
    const payload = JSON.stringify(msg);
    room.forEach((c) => {
        if (c.readyState === OPEN) c.send(payload);
    });
}

//Veto DB helpers
async function getSession(watchlistId) {
    const r = await query('SELECT data FROM veto_sessions WHERE watchlist_id = $1', [watchlistId]);
    return r.rows[0]?.data ?? null;
}

async function setSession(watchlistId, data) {
    await query(
        `INSERT INTO veto_sessions (watchlist_id, data, updated_at)
         VALUES ($1, $2::jsonb, NOW())
         ON CONFLICT (watchlist_id) DO UPDATE SET data = $2::jsonb, updated_at = NOW()`,
        [watchlistId, JSON.stringify(data)]
    );
}

async function updateSession(watchlistId, patch) {
    await query(
        `UPDATE veto_sessions SET data = data || $2::jsonb, updated_at = NOW()
         WHERE watchlist_id = $1`,
        [watchlistId, JSON.stringify(patch)]
    );
}

async function deleteSession(watchlistId) {
    await query('DELETE FROM veto_sessions WHERE watchlist_id = $1', [watchlistId]);
}

async function sendCurrentSession(ws, watchlistId) {
    try {
        const session = await getSession(watchlistId);
        if (session) ws.send(JSON.stringify({ type: 'veto_state', ...session }));
    } catch (_) {}
}

//Blackjack deck helpers
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

function cardValue(c) {
    if (c.rank === 'A') return 11;
    if (['J', 'Q', 'K'].includes(c.rank)) return 10;
    return parseInt(c.rank);
}

function handValue(hand) {
    let total = hand.reduce((s, c) => s + cardValue(c), 0);
    let aces = hand.filter((c) => c.rank === 'A').length;
    while (total > 21 && aces > 0) {
        total -= 10;
        aces--;
    }
    return total;
}

function drawCard(watchlistId) {
    if (!bjDecks.has(watchlistId) || bjDecks.get(watchlistId).length < 8) {
        bjDecks.set(watchlistId, shuffle(createDeck()));
    }
    return bjDecks.get(watchlistId).pop();
}

// Blackjack flow
async function startBlackjack(watchlistId, expectedBetters, pickedIds = []) {
    bjDecks.set(watchlistId, shuffle(createDeck()));
    const bj = {
        status: 'betting',
        players: [],
        house: [],
        houseRevealed: false,
        winnerId: null,
        activePlayerId: null,
        expectedBetters,
    };
    await updateSession(watchlistId, { status: 'blackjack_betting', blackjack: bj });
    broadcast(watchlistId, {
        type: 'blackjack_start',
        status: 'betting',
        expectedBetters,
        pickedIds,
    });
}

async function dealCards(watchlistId, bettedPlayers, expectedBetters) {
    const houseCards = [drawCard(watchlistId), drawCard(watchlistId)];
    const dealtPlayers = bettedPlayers.map((p) => ({
        ...p,
        hand: [drawCard(watchlistId), drawCard(watchlistId)],
        stood: false,
        bust: false,
    }));
    const bj = {
        status: 'playing',
        players: dealtPlayers,
        house: houseCards,
        houseRevealed: false,
        winnerId: null,
        activePlayerId: dealtPlayers[0]?.playerId ?? null,
        expectedBetters,
    };
    await updateSession(watchlistId, { status: 'blackjack_playing', blackjack: bj });
    broadcast(watchlistId, { type: 'blackjack_update', blackjack: bj });
}

async function resolveRound(watchlistId, session) {
    const bj = session.blackjack;
    if (!bj.players.every((p) => p.stood || p.bust)) return;

    const houseHand = [...(bj.house || [])];
    while (handValue(houseHand) < 17) houseHand.push(drawCard(watchlistId));
    const houseTotal = handValue(houseHand);
    const houseBust = houseTotal > 21;

    // All players who beat the house; winner movie chosen randomly among them
    const beaters = bj.players.filter((p) => {
        const v = handValue(p.hand);
        return v <= 21 && (houseBust || v > houseTotal);
    });
    const winMovieId = beaters.length
        ? beaters[Math.floor(Math.random() * beaters.length)].betMovieId
        : null;

    const updatedBj = {
        ...bj,
        house: houseHand,
        houseRevealed: true,
        status: winMovieId ? 'done' : 'redeal',
        winnerId: winMovieId,
    };

    if (winMovieId) {
        await updateSession(watchlistId, {
            status: 'done',
            winnerId: winMovieId,
            blackjack: updatedBj,
        });
        broadcast(watchlistId, { type: 'blackjack_update', blackjack: updatedBj });
        broadcast(watchlistId, {
            type: 'veto_winner',
            winnerId: winMovieId,
            via: 'blackjack',
        });
        await query(
            `INSERT INTO activity (id, watchlist_id, kind, who, picks, at)
             VALUES ($1, $2, 'vetoPick', $3, $4::jsonb, NOW())`,
            [
                require('crypto').randomUUID(),
                watchlistId,
                session.pickerId,
                JSON.stringify(session.pickedIds),
            ]
        );
    } else {
        await updateSession(watchlistId, { status: 'blackjack_redeal', blackjack: updatedBj });
        broadcast(watchlistId, { type: 'blackjack_update', blackjack: updatedBj });
    }
}

// Per-watchlist lock to serialize veto_add_picks and prevent race conditions
// when two players submit simultaneously.
const _pickLocks = new Map();
function withPickLock(watchlistId, fn) {
    const prev = _pickLocks.get(watchlistId) ?? Promise.resolve();
    const next = prev.then(fn).catch(() => {});
    _pickLocks.set(watchlistId, next);
    return next;
}

//WebSocket message handler
async function handleMessage(watchlistId, msg) {
    // veto_create
    if (msg.type === 'veto_create') {
        let memberIds = [],
            watchlistName = 'Watchlist';
        try {
            const r = await query('SELECT name, member_ids FROM watchlists WHERE id = $1', [
                watchlistId,
            ]);
            if (r.rows.length) {
                memberIds = r.rows[0].member_ids || [];
                watchlistName = r.rows[0].name || 'Watchlist';
            }
        } catch (_) {}

        const pickCount = Math.max(1, Math.min(5, msg.pickCount || 2));
        const session = {
            watchlistId,
            pickerId: msg.pickerId,
            pickerName: msg.pickerName,
            pickCount,
            lobbyPlayers: [{ id: msg.pickerId, name: msg.pickerName }],
            picksSubmitted: {},
            pickedIds: [],
            vetoedIds: [],
            winnerId: null,
            maxVetosByPlayer: {},
            vetosByPlayer: {},
            status: 'lobby',
            startedAt: new Date().toISOString(),
        };
        await setSession(watchlistId, session);
        broadcast(watchlistId, { type: 'veto_lobby_created', ...session });

        if (msg.notifyAll) {
            memberIds.forEach((memberId) => {
                if (memberId !== msg.pickerId) {
                    broadcastToUser(memberId, {
                        type: 'veto_invite',
                        fromId: msg.pickerId,
                        fromName: msg.pickerName,
                        watchlistId,
                        watchlistName,
                        pickCount,
                    });
                }
            });
        }

        // veto_join
    } else if (msg.type === 'veto_join') {
        const session = await getSession(watchlistId);
        if (!session || session.status !== 'lobby') return;
        if (session.lobbyPlayers.some((p) => p.id === msg.playerId)) return;
        const lobbyPlayers = [...session.lobbyPlayers, { id: msg.playerId, name: msg.playerName }];
        await updateSession(watchlistId, { lobbyPlayers });
        broadcast(watchlistId, {
            type: 'veto_player_joined',
            playerId: msg.playerId,
            playerName: msg.playerName,
            lobbyPlayers,
        });

        // veto_start_game
    } else if (msg.type === 'veto_start_game') {
        const session = await getSession(watchlistId);
        if (!session || session.status !== 'lobby') return;
        if (msg.hostId !== session.pickerId) return;
        if (session.lobbyPlayers.length < 2) return;
        await updateSession(watchlistId, { status: 'picking' });
        broadcast(watchlistId, {
            type: 'veto_picking_started',
            pickCount: session.pickCount,
            lobbyPlayers: session.lobbyPlayers,
        });

        // veto_add_picks — serialized per-watchlist to prevent race conditions
    } else if (msg.type === 'veto_add_picks') {
        await withPickLock(watchlistId, async () => {
        const session = await getSession(watchlistId);
        if (!session || session.status !== 'picking') return;
        if (!session.lobbyPlayers.some((p) => p.id === msg.playerId)) return;

        const playerPicks = (msg.pickedIds || []).slice(0, session.pickCount);

        const otherPickedIds = Object.entries(session.picksSubmitted || {})
            .filter(([pid]) => pid !== msg.playerId)
            .flatMap(([, ids]) => ids);
        const conflicting = playerPicks.filter((id) => otherPickedIds.includes(id));
        if (conflicting.length > 0) {
            broadcast(watchlistId, {
                type: 'picks_conflict',
                playerId: msg.playerId,
                takenIds: otherPickedIds,
            });
            return;
        }

        const picksSubmitted = { ...(session.picksSubmitted || {}), [msg.playerId]: playerPicks };
        const pickedIds = [...new Set(Object.values(picksSubmitted).flat())];
        const patch = { picksSubmitted, pickedIds };
        const allSubmitted = session.lobbyPlayers.every((p) => p.id in picksSubmitted);

        if (allSubmitted) {
            const maxVetosEach = session.pickCount - 1;
            const maxVetosByPlayer = {},
                vetosByPlayer = {};
            for (const player of session.lobbyPlayers) {
                maxVetosByPlayer[player.id] = maxVetosEach;
                vetosByPlayer[player.id] = 0;
            }

            if (maxVetosEach === 0) {
                //1v1: skip veto phase, go straight to blackjack
                patch.maxVetosByPlayer = maxVetosByPlayer;
                patch.vetosByPlayer = vetosByPlayer;
                await updateSession(watchlistId, patch);
                await startBlackjack(watchlistId, session.lobbyPlayers.length, pickedIds);
            } else {
                patch.status = 'vetoing';
                patch.maxVetosByPlayer = maxVetosByPlayer;
                patch.vetosByPlayer = vetosByPlayer;
                await updateSession(watchlistId, patch);
                broadcast(watchlistId, {
                    type: 'veto_phase_started',
                    pickedIds,
                    maxVetosByPlayer,
                    vetosByPlayer,
                    lobbyPlayers: session.lobbyPlayers,
                });
            }
        } else {
            await updateSession(watchlistId, patch);
            broadcast(watchlistId, {
                type: 'picks_submitted',
                playerId: msg.playerId,
                submittedCount: Object.keys(picksSubmitted).length,
                totalCount: session.lobbyPlayers.length,
                takenIds: pickedIds,
            });
        }
        }); // end withPickLock

        // veto_action
    } else if (msg.type === 'veto_action') {
        const session = await getSession(watchlistId);
        if (!session || session.status !== 'vetoing') return;

        const maxVetosByPlayer = session.maxVetosByPlayer || {};
        if (!(msg.vetoerId in maxVetosByPlayer)) return;
        const playerCap = maxVetosByPlayer[msg.vetoerId];
        const currentVetos = (session.vetosByPlayer || {})[msg.vetoerId] || 0;
        if (currentVetos >= playerCap) return;

        const vetosByPlayer = { ...(session.vetosByPlayer || {}) };
        vetosByPlayer[msg.vetoerId] = currentVetos + 1;
        const vetoedIds = [...session.vetoedIds, msg.vetoedId];
        const remaining = session.pickedIds.filter((id) => !vetoedIds.includes(id));

        const registeredIds = Object.keys(maxVetosByPlayer);
        const allVetosUsed =
            registeredIds.length >= 2 &&
            registeredIds.every((id) => (vetosByPlayer[id] || 0) >= maxVetosByPlayer[id]);

        const patch = { vetoedIds, vetosByPlayer };

        if (remaining.length === 1) {
            patch.winnerId = remaining[0];
            patch.status = 'done';
            await updateSession(watchlistId, patch);
            broadcast(watchlistId, { type: 'veto_actioned', vetoedId: msg.vetoedId });
            broadcast(watchlistId, { type: 'veto_winner', winnerId: remaining[0] });
            await query(
                `INSERT INTO activity (id, watchlist_id, kind, who, picks, at)
                 VALUES ($1, $2, 'vetoPick', $3, $4::jsonb, NOW())`,
                [
                    require('crypto').randomUUID(),
                    watchlistId,
                    session.pickerId,
                    JSON.stringify(session.pickedIds),
                ]
            );
        } else if (allVetosUsed) {
            await updateSession(watchlistId, patch);
            broadcast(watchlistId, { type: 'veto_actioned', vetoedId: msg.vetoedId });
            await startBlackjack(watchlistId, registeredIds.length, session.pickedIds ?? []);
        } else {
            await updateSession(watchlistId, patch);
            broadcast(watchlistId, { type: 'veto_actioned', vetoedId: msg.vetoedId });
        }

        // blackjack_bet
    } else if (msg.type === 'blackjack_bet') {
        const session = await getSession(watchlistId);
        if (!session) return;
        const bj = session.blackjack || { players: [], status: 'betting', expectedBetters: 2 };
        if (bj.players.some((p) => p.playerId === msg.playerId)) return;

        const updatedPlayers = [
            ...bj.players,
            {
                playerId: msg.playerId,
                playerName: msg.playerName,
                betMovieId: msg.betMovieId,
                hand: [],
                stood: false,
                bust: false,
            },
        ];
        const expectedBetters = bj.expectedBetters || 2;
        const updatedBj = { ...bj, players: updatedPlayers };
        await updateSession(watchlistId, { blackjack: updatedBj });

        if (updatedPlayers.length >= expectedBetters) {
            const betCounts = {};
            for (const p of updatedPlayers)
                betCounts[p.betMovieId] = (betCounts[p.betMovieId] || 0) + 1;
            const maxBets = Math.max(...Object.values(betCounts));
            const topMovies = Object.keys(betCounts).filter((id) => betCounts[id] === maxBets);

            if (maxBets >= 2 && topMovies.length === 1) {
                const winningMovieId = topMovies[0];
                const doneBj = {
                    ...updatedBj,
                    status: 'done',
                    winnerId: winningMovieId,
                    houseRevealed: true,
                };
                await updateSession(watchlistId, {
                    status: 'done',
                    winnerId: winningMovieId,
                    blackjack: doneBj,
                });
                broadcast(watchlistId, { type: 'blackjack_update', blackjack: doneBj });
                broadcast(watchlistId, {
                    type: 'veto_winner',
                    winnerId: winningMovieId,
                    via: 'majority',
                });
            } else {
                bjDecks.set(watchlistId, shuffle(createDeck()));
                await dealCards(watchlistId, updatedPlayers, expectedBetters);
            }
        } else {
            broadcast(watchlistId, { type: 'blackjack_update', blackjack: updatedBj });
        }

        // blackjack_hit
    } else if (msg.type === 'blackjack_hit') {
        const session = await getSession(watchlistId);
        if (!session) return;
        const bj = session.blackjack;
        if (!bj || bj.activePlayerId !== msg.playerId) return;

        const newCard = drawCard(watchlistId);
        const updatedPlayers = bj.players.map((p) => {
            if (p.playerId !== msg.playerId) return p;
            const newHand = [...p.hand, newCard];
            return { ...p, hand: newHand, bust: handValue(newHand) > 21 };
        });
        const hitPlayer = updatedPlayers.find((p) => p.playerId === msg.playerId);
        let nextActiveId = bj.activePlayerId;
        if (hitPlayer.bust) {
            const idx = updatedPlayers.findIndex((p) => p.playerId === msg.playerId);
            const next = updatedPlayers.slice(idx + 1).find((p) => !p.stood && !p.bust);
            nextActiveId = next?.playerId ?? null;
        }
        const updatedBj = { ...bj, players: updatedPlayers, activePlayerId: nextActiveId };
        await updateSession(watchlistId, { blackjack: updatedBj });
        broadcast(watchlistId, { type: 'blackjack_update', blackjack: updatedBj });
        if (updatedPlayers.every((p) => p.stood || p.bust)) {
            await resolveRound(watchlistId, { ...session, blackjack: updatedBj });
        }

        // blackjack_stand
    } else if (msg.type === 'blackjack_stand') {
        const session = await getSession(watchlistId);
        if (!session) return;
        const bj = session.blackjack;
        if (!bj || bj.activePlayerId !== msg.playerId) return;

        const updatedPlayers = bj.players.map((p) =>
            p.playerId === msg.playerId ? { ...p, stood: true } : p
        );
        const idx = updatedPlayers.findIndex((p) => p.playerId === msg.playerId);
        const next = updatedPlayers.slice(idx + 1).find((p) => !p.stood && !p.bust);
        const updatedBj = {
            ...bj,
            players: updatedPlayers,
            activePlayerId: next?.playerId ?? null,
        };
        await updateSession(watchlistId, { blackjack: updatedBj });
        broadcast(watchlistId, { type: 'blackjack_update', blackjack: updatedBj });
        if (updatedPlayers.every((p) => p.stood || p.bust)) {
            await resolveRound(watchlistId, { ...session, blackjack: updatedBj });
        }

        // blackjack_deal_again
    } else if (msg.type === 'blackjack_deal_again') {
        const session = await getSession(watchlistId);
        if (!session) return;
        const bj = session.blackjack;
        if (!bj || bj.status !== 'redeal') return;
        const freshPlayers = bj.players.map(({ playerId, playerName, betMovieId }) => ({
            playerId,
            playerName,
            betMovieId,
            hand: [],
            stood: false,
            bust: false,
        }));
        bjDecks.set(watchlistId, shuffle(createDeck()));
        await dealCards(watchlistId, freshPlayers, bj.expectedBetters || 2);

        // veto_cancel — works from any phase so the host is never locked out
    } else if (msg.type === 'veto_cancel') {
        const session = await getSession(watchlistId);
        if (!session) return;
        if (msg.hostId !== session.pickerId) return;
        await deleteSession(watchlistId);
        bjDecks.delete(watchlistId);
        broadcast(watchlistId, { type: 'veto_cancelled' });

        // veto_reset
    } else if (msg.type === 'veto_reset') {
        await deleteSession(watchlistId);
        bjDecks.delete(watchlistId);
        broadcast(watchlistId, { type: 'veto_reset' });
    }
}

// Start
migrate()
    .then(async () => {
        // Séances are ephemeral — clear any stale sessions left from the previous run.
        await query('DELETE FROM seance_sessions').catch(() => {});
        server.listen(process.env.PORT || 3000, () =>
            console.log(`Server running on port ${process.env.PORT || 3000}`)
        );
    })
    .catch((err) => {
        console.error('DB migration failed:', err.message || err.code || err);
        process.exit(1);
    });
