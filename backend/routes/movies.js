const express = require('express');
const Database = require('better-sqlite3');
const path = require('path');
const { query: pgQuery } = require('../db');
const { cachePosterBackground, isLocalPosterUrl } = require('../services/posterService');

const router = express.Router();

const {
    searchTmdb,
    fetchTmdbByImdbId,
    enrichTmdbStubs,
    fetchTmdbTrending,
    fetchTmdbGenre,
    fetchTmdbPopular,
    stripTmdbId,
    TMDB_GENRE_IDS,
} = require('../services/tmdbService');

const OMDB_BASE = 'https://www.omdbapi.com';
const OMDB_POSTER_BASE = 'https://img.omdbapi.com';

function omdbPosterUrl(imdbId) {
    if (!imdbId) return null;
    return `${OMDB_POSTER_BASE}/?i=${imdbId}&apikey=${process.env.OMDB_API_KEY}`;
}

function isAdultContent(m) {
    return (m.genres || []).some(
        (g) => typeof g === 'string' && g.toLowerCase() === 'adult'
    );
}

//SQLite cache
const db = new Database(path.join(__dirname, '..', 'movie_cache.db'));
db.exec(`
  CREATE TABLE IF NOT EXISTS movies (
    id         TEXT PRIMARY KEY,
    title      TEXT NOT NULL,
    raw_json   TEXT NOT NULL,
    cached_at  INTEGER NOT NULL
  );
  CREATE TABLE IF NOT EXISTS searches (
    cache_key  TEXT PRIMARY KEY,
    raw_json   TEXT NOT NULL,
    cached_at  INTEGER NOT NULL
  );
`);
// Remove adult content from SQLite — runs every startup, instant no-op once clean
db.exec(`
    DELETE FROM movies WHERE id IN (
        SELECT m.id FROM movies m, json_each(json_extract(m.raw_json, '$.genres')) g
        WHERE lower(g.value) = 'adult'
    );
    DELETE FROM searches;
`);
const stmts = {
    saveMovie: db.prepare(
        'INSERT OR REPLACE INTO movies   (id, title, raw_json, cached_at) VALUES (?, ?, ?, ?)'
    ),
    saveSearch: db.prepare(
        'INSERT OR REPLACE INTO searches (cache_key, raw_json, cached_at) VALUES (?, ?, ?)'
    ),
    getMovie: db.prepare('SELECT raw_json FROM movies   WHERE id = ?'),
    getSearch: db.prepare('SELECT raw_json FROM searches WHERE cache_key = ?'),
    fuzzySearch: db.prepare('SELECT raw_json FROM movies   WHERE title LIKE ? LIMIT 20'),
};


async function omdbJson(params) {
    const url = new URL(OMDB_BASE);
    url.searchParams.set('apikey', process.env.OMDB_API_KEY);
    for (const [k, v] of Object.entries(params)) url.searchParams.set(k, v);
    const r = await fetch(url.toString(), { signal: AbortSignal.timeout(10000) });
    if (!r.ok) throw new Error(`omdb_${r.status}`);
    const data = await r.json();
    if (data.Response === 'False') {
        const msg = data.Error || 'omdb_no_results';
        if (/limit|exceeded|over|quota/i.test(msg)) throw new Error(`omdb_rate_limited: ${msg}`);
        throw new Error(msg);
    }
    return data;
}

// Normalizers
function omdbToImdb(o) {
    const runtimeMins = parseInt(o.Runtime) || 0;
    const ratingVal = o.imdbRating && o.imdbRating !== 'N/A' ? parseFloat(o.imdbRating) : null;
    return {
        id: o.imdbID,
        primaryTitle: o.Title,
        originalTitle: o.Title,
        startYear: parseInt(o.Year) || 0,
        runtimeSeconds: runtimeMins * 60,
        rating: ratingVal != null ? { aggregateRating: ratingVal } : null,
        genres: o.Genre && o.Genre !== 'N/A' ? o.Genre.split(', ') : [],
        directors:
            o.Director && o.Director !== 'N/A'
                ? o.Director.split(', ').map((name) => ({ primaryName: name }))
                : [],
        plot: o.Plot && o.Plot !== 'N/A' ? o.Plot : '',
        primaryImage: o.Poster && o.Poster !== 'N/A' ? { url: o.Poster } : null,
        mediaType: o.Type || 'movie',
    };
}

// OMDB search result stub — runtime/rating/genres/director/plot are empty by default.
function omdbSearchItemToImdb(o) {
    return {
        id: o.imdbID,
        primaryTitle: o.Title,
        originalTitle: o.Title,
        startYear: parseInt(o.Year) || 0,
        runtimeSeconds: 0,
        rating: null,
        genres: [],
        directors: [],
        plot: '',
        primaryImage: o.Poster && o.Poster !== 'N/A' ? { url: o.Poster } : null,
        mediaType: o.Type || 'movie',
    };
}

function pgRowToImdb(row) {
    return {
        id: row.id,
        primaryTitle: row.title,
        originalTitle: row.title,
        startYear: row.year,
        runtimeSeconds: (row.runtime || 0) * 60,
        rating: row.rating ? { aggregateRating: row.rating } : null,
        genres: row.genres || [],
        directors: row.director ? [{ primaryName: row.director }] : [],
        plot: row.synopsis || '',
        primaryImage: row.poster_url
            ? { url: row.poster_url }
            : row.id ? { url: omdbPosterUrl(row.id) } : null,
        mediaType: row.media_type || 'movie',
    };
}

//SQLite cache helpers
function cacheTitles(titles) {
    const now = Date.now();
    const save = db.transaction((list) => {
        for (const t of list) {
            if (t.id)
                stmts.saveMovie.run(t.id, t.primaryTitle || t.title || '', JSON.stringify(t), now);
        }
    });
    save(titles);
}

//PostgreSQL catalog helpers
// Upsert one movie into media. Preserves any existing non-empty field values
// so stubs can't overwrite richer data already in the catalog.
async function pgSaveMovie(m, hasDetails = true) {
    if (isAdultContent(m)) return;
    const id = m.id;
    const title = m.primaryTitle || m.title || '';
    if (!id || !title) return;

    const year = m.startYear || 0;
    const runtime = Math.round((m.runtimeSeconds || 0) / 60);
    const rating = m.rating?.aggregateRating ?? 0;
    const genres = JSON.stringify(m.genres || []);
    const director = m.directors?.[0]?.primaryName ?? '';
    const synopsis = m.plot || '';
    const posterUrl = m.primaryImage?.url ?? null;
    const mediaType = m.mediaType || 'movie';

    await pgQuery(
        `INSERT INTO media
       (id, title, year, runtime, rating, genres, director, synopsis, poster_url, media_type, has_details)
     VALUES ($1,$2,$3,$4,$5,$6::jsonb,$7,$8,$9,$10,$11)
     ON CONFLICT (id) DO UPDATE SET
       title       = EXCLUDED.title,
       year        = EXCLUDED.year,
       runtime     = CASE WHEN EXCLUDED.runtime  > 0           THEN EXCLUDED.runtime  ELSE media.runtime  END,
       rating      = CASE WHEN EXCLUDED.rating   > 0           THEN EXCLUDED.rating   ELSE media.rating   END,
       genres      = CASE WHEN EXCLUDED.genres  != '[]'::jsonb THEN EXCLUDED.genres   ELSE media.genres   END,
       director    = CASE WHEN EXCLUDED.director != ''          THEN EXCLUDED.director ELSE media.director END,
       synopsis    = CASE WHEN EXCLUDED.synopsis != ''          THEN EXCLUDED.synopsis ELSE media.synopsis END,
       poster_url  = CASE
                       WHEN media.poster_url LIKE '%/posters/tt%' THEN media.poster_url
                       ELSE COALESCE(EXCLUDED.poster_url, media.poster_url)
                     END,
       media_type  = EXCLUDED.media_type,
       has_details = EXCLUDED.has_details OR media.has_details,
       updated_at  = NOW()`,
        [id, title, year, runtime, rating, genres, director, synopsis, posterUrl, mediaType, hasDetails]
    );

    // Background poster download — fire and forget
    if (posterUrl && !isLocalPosterUrl(posterUrl)) {
        cachePosterBackground(id, posterUrl, pgQuery);
    }
}

async function pgSaveMovies(list, hasDetails = true) {
    await Promise.allSettled(list.map((m) => pgSaveMovie(m, hasDetails)));
}

async function pgSearchMovies(q) {
    const r = await pgQuery(
        `SELECT id, title, year, runtime, rating, genres, director, synopsis, poster_url
     FROM media
     WHERE title ILIKE $1
     ORDER BY rating DESC, has_details DESC
     LIMIT 20`,
        [`%${q}%`]
    );
    return r.rows.map(pgRowToImdb);
}

async function pgGetMovie(id) {
    const r = await pgQuery(
        `SELECT id, title, year, runtime, rating, genres, director, synopsis, poster_url
     FROM media WHERE id = $1`,
        [id]
    );
    return r.rows[0] ? pgRowToImdb(r.rows[0]) : null;
}


const OMDB_INLINE_LIMIT = 8;

// Merge helper — prefer `next` value only when `current` is empty/absent.
function mergeField(current, next) {
    if (current && (!Array.isArray(current) || current.length)) return current;
    return next || current;
}

async function enrichResultsInline(titles) {
    if (!titles.length) return titles;

    const ids = titles.map((t) => t.id).filter(Boolean);
    const dbMap = {};
    if (ids.length) {
        try {
            const r = await pgQuery(
                `SELECT id, director, synopsis, runtime, rating, genres, poster_url
         FROM media WHERE id = ANY($1) AND has_details = TRUE`,
                [ids]
            );
            for (const row of r.rows) dbMap[row.id] = row;
        } catch (_) {}
    }

    const list = titles.map((t) => {
        const db = dbMap[t.id];
        if (!db) return t;
        return {
            ...t,
            directors: db.director ? [{ primaryName: db.director }] : t.directors || [],
            plot: db.synopsis || t.plot || '',
            runtimeSeconds: db.runtime > 0 ? db.runtime * 60 : t.runtimeSeconds || 0,
            rating: db.rating > 0 ? { aggregateRating: db.rating } : t.rating,
            genres: db.genres?.length ? db.genres : t.genres || [],
            primaryImage: db.poster_url
                ? { url: db.poster_url }
                : t.primaryImage ?? (t.id ? { url: omdbPosterUrl(t.id) } : null),
        };
    });

    const afterPg = list
        .map((t, i) => ({ t, i }))
        .filter(({ t }) => !t.plot || !t.directors?.length);

    const needOmdb = list
        .map((t, i) => ({ t, i }))
        .filter(({ t }) => !t.plot || !t.directors?.length)
        .slice(0, OMDB_INLINE_LIMIT);

    if (!needOmdb.length) return list;

    const omdbResults = await Promise.allSettled(
        needOmdb.map(({ t }) => omdbJson({ i: t.id, plot: 'full' }).then(omdbToImdb))
    );

    const omdbSaved = [];
    omdbResults.forEach((result, n) => {
        if (result.status !== 'fulfilled' || !result.value?.id) return;
        if (isAdultContent(result.value)) return;
        const full = result.value;
        const { i } = needOmdb[n];
        const t = list[i];
        list[i] = {
            ...t,
            directors: mergeField(t.directors, full.directors),
            plot: mergeField(t.plot, full.plot),
            runtimeSeconds: mergeField(t.runtimeSeconds, full.runtimeSeconds),
            rating: mergeField(t.rating, full.rating),
            genres: mergeField(t.genres, full.genres),
            primaryImage: mergeField(t.primaryImage, full.primaryImage),
        };
        omdbSaved.push(full);
    });

    if (omdbSaved.length) {
        cacheTitles(omdbSaved);
        pgSaveMovies(omdbSaved, true).catch(() => {});
    }

    return list;
}

// Sequential to respect API rate limits. Fire-and-forget — never awaited.
async function enrichStubs(ids) {
    for (const id of ids) {
        try {
            const existing = await pgQuery('SELECT has_details FROM media WHERE id = $1', [id]);
            if (existing.rows[0]?.has_details) continue;

            let full = null;
            try {
                const data = await fetchTmdbByImdbId(id);
                stmts.saveMovie.run(id, data.primaryTitle || '', JSON.stringify(data), Date.now());
                full = data;
            } catch (_) {
                try {
                    const raw = await omdbJson({ i: id, plot: 'full' });
                    full = omdbToImdb(raw);
                    stmts.saveMovie.run(
                        id,
                        full.primaryTitle || '',
                        JSON.stringify(full),
                        Date.now()
                    );
                } catch (_) {}
            }

            if (full) await pgSaveMovie(full, true);
        } catch (_) {}
    }
}

// GET /movies/search?q=
// Fallback chain: IMDb -> OMDB by name -> PG catalog -> SQLite cache
router.get('/search', async (req, res) => {
    const q = (req.query.q || '').trim();
    const pageToken = req.query.pageToken;
    const cacheKey = `search:${q.toLowerCase()}`;

    if (!q) return res.json({ titles: [], nextPageToken: null });

    let titles = null;
    let nextToken = null;

    try {
        const tmdbPage = parseInt(pageToken) || 1;
        const data = await searchTmdb(q, tmdbPage);
        if (data.titles.length) {
            const enriched = await enrichTmdbStubs(data.titles);
            const valid = enriched.filter((m) => m.id).map(stripTmdbId);
            if (valid.length) {
                titles = valid;
                nextToken = data.nextPageToken;
            }
        }
    } catch (_) {}

    if (!titles && !pageToken) {
        try {
            const raw = await omdbJson({ s: q, type: 'movie' });
            const stubs = (raw.Search || []).map(omdbSearchItemToImdb);
            if (stubs.length) {
                titles = stubs;
                nextToken = null;
            }
        } catch (_) {}
    }

    if (!titles) {
        try {
            const pg = await pgSearchMovies(q);
            if (pg.length) return res.json({ titles: pg, nextPageToken: null });
        } catch (_) {}
    }

    if (!titles) {
        const hit = stmts.getSearch.get(cacheKey);
        if (hit) return res.json(JSON.parse(hit.raw_json));
        const rows = stmts.fuzzySearch.all(`%${q}%`);
        return res.json({ titles: rows.map((r) => JSON.parse(r.raw_json)), nextPageToken: null });
    }

    const enriched = await enrichResultsInline(titles);

    cacheTitles(enriched);
    if (!pageToken)
        stmts.saveSearch.run(
            cacheKey,
            JSON.stringify({ titles: enriched, nextPageToken: nextToken }),
            Date.now()
        );
    pgSaveMovies(enriched, true).catch(() => {});

    return res.json({ titles: enriched, nextPageToken: nextToken });
});

// GET /movies/trending
// Fallback chain: TMDB -> SQLite cache -> PG catalog
router.get('/trending', async (req, res) => {
    try {
        const data = await fetchTmdbTrending(1);
        const enriched = (await enrichTmdbStubs(data.titles)).filter((m) => m.id).map(stripTmdbId);
        if (enriched.length) {
            cacheTitles(enriched);
            stmts.saveSearch.run(
                'trending',
                JSON.stringify({ titles: enriched, nextPageToken: data.nextPageToken }),
                Date.now()
            );
            pgSaveMovies(enriched, true).catch(() => {});
            return res.json({ titles: enriched, nextPageToken: data.nextPageToken });
        }
    } catch (_) {}

    const hit = stmts.getSearch.get('trending');
    if (hit) return res.json(JSON.parse(hit.raw_json));

    try {
        const r = await pgQuery(
            `SELECT id, title, year, runtime, rating, genres, director, synopsis, poster_url
       FROM media WHERE has_details = TRUE ORDER BY rating DESC LIMIT 20`
        );
        if (r.rows.length)
            return res.json({ titles: r.rows.map(pgRowToImdb), nextPageToken: null });
    } catch (_) {}

    return res.status(503).json({ titles: [], error: 'unavailable' });
});

// GET /movies/genre?g=genre[&pageToken=...]
// Fallback chain: TMDB -> SQLite cache -> PG catalog
router.get('/genre', async (req, res) => {
    const genre = (req.query.g || '').trim();
    const pageToken = req.query.pageToken;
    const cacheKey = `genre:${genre.toLowerCase()}`;

    try {
        const tmdbPage = parseInt(pageToken) || 1;
        const data = await fetchTmdbGenre(genre, tmdbPage);
        const enriched = (await enrichTmdbStubs(data.titles)).filter((m) => m.id).map(stripTmdbId);
        if (enriched.length) {
            cacheTitles(enriched);
            if (!pageToken)
                stmts.saveSearch.run(
                    cacheKey,
                    JSON.stringify({ titles: enriched, nextPageToken: data.nextPageToken }),
                    Date.now()
                );
            pgSaveMovies(enriched, true).catch(() => {});
            return res.json({ titles: enriched, nextPageToken: data.nextPageToken });
        }
    } catch (_) {}

    const hit = stmts.getSearch.get(cacheKey);
    if (hit) return res.json(JSON.parse(hit.raw_json));

    try {
        const r = await pgQuery(
            `SELECT id, title, year, runtime, rating, genres, director, synopsis, poster_url
       FROM media WHERE genres @> $1::jsonb ORDER BY rating DESC LIMIT 20`,
            [JSON.stringify([genre])]
        );
        if (r.rows.length)
            return res.json({ titles: r.rows.map(pgRowToImdb), nextPageToken: null });
    } catch (_) {}

    return res.status(503).json({ titles: [], error: 'unavailable' });
});

// GET /movies/:movieId/watchers
router.get('/:movieId/watchers', async (req, res) => {
    const { movieId } = req.params;
    try {
        const r = await pgQuery(
            `SELECT u.id, u.display_name, u.username, u.avatar_url
       FROM users u, jsonb_array_elements(u.watched_movies) e
       WHERE e->>'movieId' = $1
       ORDER BY u.display_name`,
            [movieId]
        );
        res.json(
            r.rows.map((row) => ({
                id: row.id,
                displayName: row.display_name,
                username: row.username,
                avatarUrl: row.avatar_url,
            }))
        );
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// GET /movies/catalog
router.get('/catalog', async (req, res) => {
    try {
        const limit  = Math.min(parseInt(req.query.limit)  || 20, 100);
        const offset = Math.max(parseInt(req.query.offset) || 0,   0);
        const q      = (req.query.q    || '').trim();
        const year   = parseInt(req.query.year) || null;

        const sort = (req.query.sort || '').trim();
        const cols = `m.id, m.title, m.year, m.runtime, m.rating, m.genres,
                      m.director, m.synopsis, m.poster_url, m.media_type, m.has_details,
                      COUNT(DISTINCT wm.watchlist_id) AS watchlist_count`;

        let orderBy;
        if (sort === 'year_asc')  orderBy = 'm.year ASC NULLS LAST, m.rating DESC';
        else if (sort === 'year_desc') orderBy = 'm.year DESC NULLS LAST, m.rating DESC';
        else if (sort === 'newest') orderBy = 'm.cached_at DESC';
        else orderBy = 'watchlist_count DESC, m.rating DESC, m.updated_at DESC NULLS LAST';

        // Build WHERE clauses dynamically
        const where = [];
        const params = [];

        if (q) {
            params.push(`%${q}%`);
            const n = params.length;
            where.push(`(m.title ILIKE $${n} OR m.director ILIKE $${n}
                         OR CAST(m.year AS TEXT) = $${n + 1}
                         OR EXISTS (
                           SELECT 1 FROM jsonb_array_elements_text(m.genres) g
                           WHERE g ILIKE $${n}
                         ))`);
            params.push(q); // $n+1 for exact year match
        }

        if (year) {
            params.push(year);
            where.push(`m.year = $${params.length}`);
        }

        const whereClause = where.length ? `WHERE ${where.join(' AND ')}` : '';

        const entriesR = await pgQuery(
            `SELECT ${cols}
             FROM media m
             LEFT JOIN movies wm ON wm.id = m.id
             ${whereClause}
             GROUP BY m.id
             ORDER BY ${orderBy}
             LIMIT $${params.length + 1} OFFSET $${params.length + 2}`,
            [...params, limit, offset]
        );

        const totalR = await pgQuery(
            `SELECT COUNT(*) FROM media m ${whereClause}`,
            params
        );

        res.json({
            entries: entriesR.rows.map((row) => ({
                ...pgRowToImdb(row),
                watchlistCount: parseInt(row.watchlist_count) || 0,
            })),
            total: parseInt(totalR.rows[0].count),
            limit,
            offset,
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// DELETE /movies/catalog/:id
router.delete('/catalog/:id', async (req, res) => {
    try {
        await pgQuery('DELETE FROM media WHERE id = $1', [req.params.id]);
        db.prepare('DELETE FROM movies WHERE id = ?').run(req.params.id);
        res.json({ deleted: req.params.id });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

const TMDB_POPULAR_PAGES = 50;
const TMDB_GENRE_PAGES   = 10;

// In-memory job state, survives as long as the server process is running.
let _pullJob   = null; // { status: 'running'|'done'|'error', stats: {}, error: null }
let _enrichJob = null;

// OMDB genre search terms — mirror TMDB genres for consistent coverage.
const OMDB_DISCOVERY_TERMS = [
    'Action', 'Comedy', 'Drama', 'Thriller', 'Horror', 'Romance',
    'Documentary', 'Animation', 'Adventure', 'Crime', 'Fantasy',
    'Mystery', 'War', 'Western', 'History', 'Music', 'Family',
];

// Searches OMDB for movies and series not already in the media catalog.
// Bails immediately if OMDB rate-limits. Episodes are explicitly rejected.
async function runOmdbDiscovery(stats, sleep) {
    const TYPES = ['movie', 'series'];
    const PAGES_PER_TERM = 3; // up to 30 results per term/type
    const DETAIL_BATCH = 10;
    const seenIds = new Set();
    let rateLimited = false;

    for (const type of TYPES) {
        if (rateLimited) break;
        for (const term of OMDB_DISCOVERY_TERMS) {
            if (rateLimited) break;
            for (let page = 1; page <= PAGES_PER_TERM; page++) {
                if (rateLimited) break;
                try {
                    const raw = await omdbJson({ s: term, type, page: String(page) });
                    const items = (raw.Search || []).filter(
                        (o) => (o.Type === 'movie' || o.Type === 'series') &&
                               o.imdbID && !seenIds.has(o.imdbID)
                    );
                    if (!items.length) break;

                    const ids = items.map((o) => o.imdbID);
                    const existingR = await pgQuery('SELECT id FROM media WHERE id = ANY($1)', [ids]);
                    const existingIds = new Set(existingR.rows.map((r) => r.id));
                    const newItems = items.filter((o) => !existingIds.has(o.imdbID));
                    for (const o of newItems) seenIds.add(o.imdbID);

                    for (let i = 0; i < newItems.length; i += DETAIL_BATCH) {
                        if (rateLimited) break;
                        await Promise.allSettled(
                            newItems.slice(i, i + DETAIL_BATCH).map(async (o) => {
                                if (rateLimited) return;
                                try {
                                    const detail = await omdbJson({ i: o.imdbID, plot: 'full' });
                                    if (detail.Type === 'episode') return;
                                    const full = omdbToImdb(detail);
                                    if (isAdultContent(full)) return;
                                    if (!full.primaryImage?.url) full.primaryImage = { url: omdbPosterUrl(o.imdbID) };
                                    cacheTitles([full]);
                                    await pgSaveMovie(full, true);
                                    stats.omdbDiscovered++;
                                } catch (e) {
                                    const msg = e.message || '';
                                    if (msg.includes('rate_limit') || msg.startsWith('omdb_4')) {
                                        rateLimited = true;
                                        stats.omdbErrors.push(`discover ${o.imdbID}: ${msg}`);
                                    }
                                }
                            })
                        );
                        await sleep(150);
                    }

                    const totalResults = parseInt(raw.totalResults) || 0;
                    if (page * 10 >= totalResults) break;
                    await sleep(200);
                } catch (e) {
                    const msg = e.message || '';
                    if (msg.includes('rate_limit') || msg.startsWith('omdb_4')) {
                        rateLimited = true;
                        stats.omdbErrors.push(`search ${type}/${term} p${page}: ${msg}`);
                    }
                    break;
                }
            }
        }
    }
}

async function runBulkPull() {
    // Unique genre names only — no aliases
    const genres = Object.keys(TMDB_GENRE_IDS).filter((k) => k !== 'Science-Fiction');

    const stats = {
        tmdbPopular: 0,
        tmdbGenre: 0,
        tmdbAdded: 0,
        tmdbErrors: [],
        omdbDiscovered: 0,
        omdbById: 0,
        omdbErrors: [],
        totalBefore: 0,
        totalAfter: 0,
    };

    try {
        const beforeR = await pgQuery('SELECT COUNT(*) FROM media');
        stats.totalBefore = parseInt(beforeR.rows[0].count);

        const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
        let tmdbFailed = false;

        // Phase 1: Popular movies sweep
        for (let page = 1; page <= TMDB_POPULAR_PAGES; page++) {
            try {
                const data = await fetchTmdbPopular(page);
                const valid = (await enrichTmdbStubs(data.titles))
                    .filter((m) => m.id)
                    .map(stripTmdbId);
                if (valid.length) {
                    cacheTitles(valid);
                    await pgSaveMovies(valid, true);
                    stats.tmdbPopular += valid.length;
                    stats.tmdbAdded  += valid.length;
                }
                if (!data.nextPageToken) break;
                await sleep(100);
            } catch (e) {
                stats.tmdbErrors.push(`popular p${page}: ${e.message}`);
                tmdbFailed = true;
                break;
            }
        }

        // Phase 2: Genre sweeps
        for (const genre of genres) {
            for (let page = 1; page <= TMDB_GENRE_PAGES; page++) {
                try {
                    const data = await fetchTmdbGenre(genre, page);
                    const valid = (await enrichTmdbStubs(data.titles))
                        .filter((m) => m.id)
                        .map(stripTmdbId);
                    if (valid.length) {
                        cacheTitles(valid);
                        await pgSaveMovies(valid, true);
                        stats.tmdbGenre += valid.length;
                        stats.tmdbAdded += valid.length;
                    }
                    if (!data.nextPageToken) break;
                    await sleep(100);
                } catch (e) {
                    stats.tmdbErrors.push(`${genre} p${page}: ${e.message}`);
                    tmdbFailed = true;
                    break;
                }
            }
        }

        // Phase 3: OMDB discovery fallback — only when TMDB was declined.
        // Searches for movies and series not already in the catalog.
        if (tmdbFailed) {
            await runOmdbDiscovery(stats, sleep);
        }

        // Phase 4: OMDB enrichment for stubs still missing synopsis or poster
        const needsEnrichR = await pgQuery(
            `SELECT id FROM media
             WHERE synopsis = '' OR poster_url IS NULL
             ORDER BY rating DESC NULLS LAST
             LIMIT 500`
        );
        const enrichIds = needsEnrichR.rows.map((r) => r.id);
        const BATCH = 15;
        for (let i = 0; i < enrichIds.length; i += BATCH) {
            await Promise.allSettled(
                enrichIds.slice(i, i + BATCH).map(async (id) => {
                    try {
                        const raw = await omdbJson({ i: id, plot: 'full' });
                        const full = omdbToImdb(raw);
                        if (isAdultContent(full)) return;
                        if (!full.primaryImage?.url) full.primaryImage = { url: omdbPosterUrl(id) };
                        cacheTitles([full]);
                        await pgSaveMovie(full, true);
                        stats.omdbById++;
                    } catch (e) {
                        stats.omdbErrors.push(`omdb-id ${id}: ${e.message}`);
                    }
                })
            );
            await sleep(200);
        }

        const finalR = await pgQuery('SELECT COUNT(*) FROM media');
        stats.totalAfter = parseInt(finalR.rows[0].count);

        stats.tmdbErrors = stats.tmdbErrors.slice(0, 20);
        stats.omdbErrors = stats.omdbErrors.slice(0, 20);

        return stats;
    } catch (err) {
        throw err;
    }
}

// POST /movies/bulk-pull — starts a background job and returns immediately.
router.post('/bulk-pull', (req, res) => {
    if (_pullJob?.status === 'running') {
        return res.json({ status: 'running', stats: _pullJob.stats });
    }
    _pullJob = { status: 'running', stats: null, error: null };
    runBulkPull()
        .then((stats) => { _pullJob = { status: 'done', stats, error: null }; })
        .catch((err) => { _pullJob = { status: 'error', stats: null, error: err.message }; });
    res.json({ status: 'started' });
});

// GET /movies/bulk-pull/status — poll for job progress.
router.get('/bulk-pull/status', (req, res) => {
    if (!_pullJob) return res.json({ status: 'idle' });
    res.json(_pullJob);
});

// Enrichment-only job: takes existing stubs and fills synopsis + poster via OMDB.
// No ID scan, no trending/genre fetches — pure enrichment, rated titles first.
// Mutates `stats` in place so the status endpoint can return live progress.
async function runEnrichOnly(stats) {
    const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

    const beforeR = await pgQuery('SELECT COUNT(*)::int AS n FROM media WHERE has_details = TRUE');
    stats.totalBefore = beforeR.rows[0].n;

    const needsR = await pgQuery(
        `SELECT id FROM media
         WHERE synopsis = '' OR poster_url IS NULL
         ORDER BY rating DESC NULLS LAST
         LIMIT 3000`
    );
    const ids = needsR.rows.map((r) => r.id);

    const BATCH = 15;
    for (let i = 0; i < ids.length; i += BATCH) {
        await Promise.allSettled(
            ids.slice(i, i + BATCH).map(async (id) => {
                try {
                    const raw = await omdbJson({ i: id, plot: 'full' });
                    const full = omdbToImdb(raw);
                    if (isAdultContent(full)) return;
                    if (!full.primaryImage?.url) full.primaryImage = { url: omdbPosterUrl(id) };
                    cacheTitles([full]);
                    await pgSaveMovie(full, true);
                    stats.enriched++;
                    stats.lastId = id;
                    if (full.plot) stats.withSynopsis++;
                    if (full.primaryImage?.url) stats.withPoster++;
                } catch (e) {
                    const msg = e.message || '';
                    if (msg.includes('rate_limit') || msg.startsWith('omdb_4')) {
                        stats.errors.push(`${id}: ${msg}`);
                    } else {
                        stats.notFound++;
                    }
                }
            })
        );
        await sleep(200);
    }

    const afterR = await pgQuery('SELECT COUNT(*)::int AS n FROM media WHERE has_details = TRUE');
    stats.totalAfter = afterR.rows[0].n;
    stats.errors = stats.errors.slice(0, 20);
    return stats;
}

// POST /movies/enrich-only — enrich stubs with OMDB (no scan, no API discovery).
router.post('/enrich-only', (req, res) => {
    if (_enrichJob?.status === 'running') {
        return res.json({ status: 'running', stats: _enrichJob.stats });
    }
    const liveStats = { enriched: 0, withSynopsis: 0, withPoster: 0, notFound: 0, errors: [], totalBefore: 0, totalAfter: 0, lastId: null };
    _enrichJob = { status: 'running', stats: liveStats, error: null };
    runEnrichOnly(liveStats)
        .then((stats) => { _enrichJob = { status: 'done', stats, error: null }; })
        .catch((err)  => { _enrichJob = { status: 'error', stats: liveStats, error: err.message }; });
    res.json({ status: 'started' });
});

// GET /movies/enrich-only/status
router.get('/enrich-only/status', (req, res) => {
    if (!_enrichJob) return res.json({ status: 'idle' });
    res.json(_enrichJob);
});

// GET /movies/:id
// Fallback chain: TMDB -> OMDB -> SQLite cache -> PG catalog
router.get('/:id', async (req, res) => {
    const { id } = req.params;

    try {
        const data = stripTmdbId(await fetchTmdbByImdbId(id));
        stmts.saveMovie.run(id, data.primaryTitle || '', JSON.stringify(data), Date.now());
        pgSaveMovie(data, true).catch(() => {});
        return res.json(data);
    } catch (_) {}

    try {
        const raw = await omdbJson({ i: id, plot: 'full' });
        const normalized = omdbToImdb(raw);
        stmts.saveMovie.run(
            id,
            normalized.primaryTitle || '',
            JSON.stringify(normalized),
            Date.now()
        );
        pgSaveMovie(normalized, true).catch(() => {});
        return res.json(normalized);
    } catch (_) {}

    const hit = stmts.getMovie.get(id);
    if (hit) return res.json(JSON.parse(hit.raw_json));

    try {
        const movie = await pgGetMovie(id);
        if (movie) return res.json(movie);
    } catch (_) {}

    return res.status(503).json({ error: 'unavailable', id });
});

// POST /movies/backfill
router.post('/backfill', async (req, res) => {
    const limit = Math.min(parseInt(req.query.limit) || 50, 200);
    try {
        const r = await pgQuery('SELECT id FROM media WHERE has_details = FALSE LIMIT $1', [limit]);
        const ids = r.rows.map((row) => row.id);
        res.json({ queued: ids.length, ids });
        enrichStubs(ids).catch(() => {}); // fire and forget
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// GET /movies/catalog/stats
router.get('/catalog/stats', async (req, res) => {
    try {
        const [catalogR, activeR] = await Promise.all([
            pgQuery(
                `SELECT
                   COUNT(*)                                        AS total,
                   COUNT(*) FILTER (WHERE has_details)            AS full_detail,
                   COUNT(*) FILTER (WHERE NOT has_details)        AS stubs,
                   COUNT(*) FILTER (WHERE media_type = 'movie')   AS movies,
                   COUNT(*) FILTER (WHERE media_type = 'series')  AS series,
                   COUNT(*) FILTER (WHERE media_type = 'short')   AS shorts
                 FROM media`
            ),
            pgQuery(
                `SELECT COUNT(DISTINCT id) AS in_watchlists FROM movies`
            ),
        ]);
        res.json({ ...catalogR.rows[0], in_watchlists: parseInt(activeR.rows[0].in_watchlists) });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

module.exports = router;
