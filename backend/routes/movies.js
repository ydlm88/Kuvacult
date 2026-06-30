const express = require('express');
const Database = require('better-sqlite3');
const path = require('path');
const { query: pgQuery } = require('../db');

const router = express.Router();

const IMDB_BASE = 'https://api.imdbapi.dev';
const OMDB_BASE = 'https://www.omdbapi.com';

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

async function imdbJson(urlPath) {
    const r = await fetch(`${IMDB_BASE}${urlPath}`, { signal: AbortSignal.timeout(10000) });
    if (r.status === 429) throw new Error('imdb_rate_limited');
    if (!r.ok) throw new Error(`imdb_${r.status}`);
    const data = await r.json();
    if (data.code) throw new Error(data.message || 'imdb_api_error');
    return data;
}

async function omdbJson(params) {
    const url = new URL(OMDB_BASE);
    url.searchParams.set('apikey', process.env.OMDB_API_KEY);
    for (const [k, v] of Object.entries(params)) url.searchParams.set(k, v);
    const r = await fetch(url.toString(), { signal: AbortSignal.timeout(10000) });
    if (!r.ok) throw new Error(`omdb_${r.status}`);
    const data = await r.json();
    if (data.Response === 'False') throw new Error(data.Error || 'omdb_no_results');
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
        primaryImage: row.poster_url ? { url: row.poster_url } : null,
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

    await pgQuery(
        `INSERT INTO media
       (id, title, year, runtime, rating, genres, director, synopsis, poster_url, has_details)
     VALUES ($1,$2,$3,$4,$5,$6::jsonb,$7,$8,$9,$10)
     ON CONFLICT (id) DO UPDATE SET
       title       = EXCLUDED.title,
       year        = EXCLUDED.year,
       runtime     = CASE WHEN EXCLUDED.runtime  > 0           THEN EXCLUDED.runtime  ELSE media.runtime  END,
       rating      = CASE WHEN EXCLUDED.rating   > 0           THEN EXCLUDED.rating   ELSE media.rating   END,
       genres      = CASE WHEN EXCLUDED.genres  != '[]'::jsonb THEN EXCLUDED.genres   ELSE media.genres   END,
       director    = CASE WHEN EXCLUDED.director != ''          THEN EXCLUDED.director ELSE media.director END,
       synopsis    = CASE WHEN EXCLUDED.synopsis != ''          THEN EXCLUDED.synopsis ELSE media.synopsis END,
       poster_url  = COALESCE(EXCLUDED.poster_url, media.poster_url),
       has_details = EXCLUDED.has_details OR media.has_details,
       updated_at  = NOW()`,
        [id, title, year, runtime, rating, genres, director, synopsis, posterUrl, hasDetails]
    );
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

// Single round-trip to fetch detail-level data for multiple IDs. imdbapi.dev search
// results are stubs, so this gives us a second shot at plot/director before falling
// back to OMDB. Handles all known response shapes defensively.
async function imdbBatchGet(ids) {
    if (!ids.length) return [];
    try {
        const data = await imdbJson(`/titles/batchGet?ids=${ids.join(',')}`);
        if (Array.isArray(data)) return data;
        if (Array.isArray(data.titles)) return data.titles;
        // Some batch APIs return an object keyed by ID: { tt123: {…}, tt456: {…} }
        const vals = Object.values(data);
        if (vals.length && typeof vals[0] === 'object' && vals[0] !== null) return vals;
        return [];
    } catch (_) {
        return []; // endpoint absent or rate-limited — fall through to OMDB
    }
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
            primaryImage: db.poster_url ? { url: db.poster_url } : t.primaryImage,
        };
    });

    const afterPg = list
        .map((t, i) => ({ t, i }))
        .filter(({ t }) => !t.plot || !t.directors?.length);

    if (afterPg.length) {
        const batchIds = afterPg.map(({ t }) => t.id).filter(Boolean);
        const batchResults = await imdbBatchGet(batchIds);

        if (batchResults.length) {
            const batchMap = {};
            for (const r of batchResults) {
                const id = r.id || r.imdbID;
                if (id) batchMap[id] = r;
            }

            const batchSaved = [];
            afterPg.forEach(({ t, i }) => {
                const full = batchMap[t.id];
                if (!full) return;
                list[i] = {
                    ...t,
                    directors: mergeField(t.directors, full.directors),
                    plot: mergeField(t.plot, full.plot),
                    runtimeSeconds: mergeField(t.runtimeSeconds, full.runtimeSeconds),
                    rating: mergeField(t.rating, full.rating),
                    genres: mergeField(t.genres, full.genres),
                    primaryImage: mergeField(t.primaryImage, full.primaryImage),
                };
                if (full.plot || full.directors?.length) batchSaved.push(full);
            });

            if (batchSaved.length) {
                cacheTitles(batchSaved);
                pgSaveMovies(batchSaved, true).catch(() => {});
            }
        }
    }

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
                const data = await imdbJson(`/titles/${id}`);
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
        let urlPath = `/search/titles?query=${encodeURIComponent(q)}`;
        if (pageToken) urlPath += `&pageToken=${encodeURIComponent(pageToken)}`;
        const data = await imdbJson(urlPath);
        if ((data.titles || []).length) {
            titles = data.titles;
            nextToken = data.nextPageToken || null;
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
// Fallback chain: IMDb -> SQLite cache -> PG catalog
router.get('/trending', async (req, res) => {
    try {
        const data = await imdbJson('/titles?titleType=movie&sort=POPULARITY&order=DESC');
        const titles = data.titles || [];
        cacheTitles(titles);
        stmts.saveSearch.run('trending', JSON.stringify(data), Date.now());
        pgSaveMovies(titles, true).catch(() => {});
        return res.json(data);
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
// Fallback chain: IMDb -> SQLite cache -> PG catalog
router.get('/genre', async (req, res) => {
    const genre = (req.query.g || '').trim();
    const pageToken = req.query.pageToken;
    const cacheKey = `genre:${genre.toLowerCase()}`;

    try {
        let urlPath = `/titles?titleType=movie&genres=${encodeURIComponent(genre)}&sort=POPULARITY&order=DESC`;
        if (pageToken) urlPath += `&pageToken=${encodeURIComponent(pageToken)}`;
        const data = await imdbJson(urlPath);
        const titles = data.titles || [];
        cacheTitles(titles);
        if (!pageToken) stmts.saveSearch.run(cacheKey, JSON.stringify(data), Date.now());
        pgSaveMovies(titles, true).catch(() => {});
        return res.json(data);
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
        const limit = Math.min(parseInt(req.query.limit) || 20, 100);
        const offset = Math.max(parseInt(req.query.offset) || 0, 0);
        const q = (req.query.q || '').trim();

        const entriesR = q
            ? await pgQuery(
                  `SELECT id, title, year, runtime, rating, genres, director, synopsis, poster_url, has_details
           FROM media WHERE title ILIKE $1 ORDER BY rating DESC, has_details DESC LIMIT $2 OFFSET $3`,
                  [`%${q}%`, limit, offset]
              )
            : await pgQuery(
                  `SELECT id, title, year, runtime, rating, genres, director, synopsis, poster_url, has_details
           FROM media ORDER BY updated_at DESC NULLS LAST, cached_at DESC NULLS LAST LIMIT $1 OFFSET $2`,
                  [limit, offset]
              );

        const totalR = await pgQuery(
            q ? `SELECT COUNT(*) FROM media WHERE title ILIKE $1` : `SELECT COUNT(*) FROM media`,
            q ? [`%${q}%`] : []
        );

        res.json({
            entries: entriesR.rows.map(pgRowToImdb),
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

// POST /movies/bulk-pull
router.post('/bulk-pull', async (req, res) => {
    const genres = [
        'Action',
        'Drama',
        'Thriller',
        'Comedy',
        'Horror',
        'Romance',
        'Animation',
        'Crime',
        'Adventure',
        'Science-Fiction',
        'Documentary',
        'Biography',
        'Fantasy',
        'Mystery',
        'History',
        'War',
        'Sport',
        'Western',
        'Family',
        'Music',
    ];

    const stats = {
        imdbTrending: 0,
        imdbGenre: 0,
        imdbAdded: 0,
        imdbErrors: [],
        omdbById: 0,
        omdbByName: 0,
        omdbErrors: [],
        totalBefore: 0,
        totalAfter: 0,
    };

    try {
        const beforeR = await pgQuery('SELECT COUNT(*) FROM media');
        stats.totalBefore = parseInt(beforeR.rows[0].count);

        const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

        let nextTrendToken = null;
        for (let page = 0; page < 2; page++) {
            try {
                let urlPath = '/titles?titleType=movie&sort=POPULARITY&order=DESC';
                if (nextTrendToken) urlPath += `&pageToken=${encodeURIComponent(nextTrendToken)}`;
                const data = await imdbJson(urlPath);
                const titles = data.titles || [];
                if (!titles.length) break;
                cacheTitles(titles);
                await pgSaveMovies(titles, true);
                stats.imdbTrending += titles.length;
                nextTrendToken = data.nextPageToken || null;
                if (!nextTrendToken) break;
                await sleep(350);
            } catch (e) {
                stats.imdbErrors.push(`trending p${page + 1}: ${e.message}`);
                break;
            }
        }

        const failedGenres = new Set();
        for (const genre of genres) {
            let nextGenreToken = null;
            for (let page = 0; page < 2; page++) {
                try {
                    let urlPath = `/titles?titleType=movie&genres=${encodeURIComponent(genre)}&sort=POPULARITY&order=DESC`;
                    if (nextGenreToken)
                        urlPath += `&pageToken=${encodeURIComponent(nextGenreToken)}`;
                    const data = await imdbJson(urlPath);
                    const titles = data.titles || [];
                    if (!titles.length) break;
                    cacheTitles(titles);
                    await pgSaveMovies(titles, true);
                    stats.imdbGenre += titles.length;
                    nextGenreToken = data.nextPageToken || null;
                    if (!nextGenreToken) break;
                    await sleep(350);
                } catch (e) {
                    stats.imdbErrors.push(`${genre} p${page + 1}: ${e.message}`);
                    failedGenres.add(genre);
                    break;
                }
            }
        }

        const omdbGenres =
            failedGenres.size > 0
                ? [...failedGenres]
                : stats.imdbTrending === 0 && stats.imdbGenre === 0
                  ? genres.slice(0, 10)
                  : [];

        for (const genre of omdbGenres) {
            try {
                const raw = await omdbJson({ s: genre, type: 'movie' });
                const stubs = (raw.Search || []).map(omdbSearchItemToImdb);
                if (!stubs.length) continue;
                cacheTitles(stubs);
                await pgSaveMovies(stubs, false);
                stats.omdbByName += stubs.length;
            } catch (e) {
                stats.omdbErrors.push(`omdb-search ${genre}: ${e.message}`);
            }
        }

        const needsEnrichR = await pgQuery(
            `SELECT id FROM media
       WHERE NOT has_details OR director = '' OR synopsis = ''
       ORDER BY updated_at DESC NULLS LAST
       LIMIT 200`
        );
        const enrichIds = needsEnrichR.rows.map((r) => r.id);
        const BATCH = 10;
        for (let i = 0; i < enrichIds.length; i += BATCH) {
            await Promise.all(
                enrichIds.slice(i, i + BATCH).map(async (id) => {
                    try {
                        const raw = await omdbJson({ i: id, plot: 'full' });
                        const full = omdbToImdb(raw);
                        stmts.saveMovie.run(id, full.primaryTitle || '', JSON.stringify(full), Date.now());
                        await pgSaveMovie(full, true);
                        stats.omdbById++;
                    } catch (e) {
                        stats.omdbErrors.push(`omdb-id ${id}: ${e.message}`);
                    }
                })
            );
        }

        const finalR = await pgQuery('SELECT COUNT(*) FROM media');
        stats.totalAfter = parseInt(finalR.rows[0].count);

        stats.imdbErrors = stats.imdbErrors.slice(0, 20);
        stats.omdbErrors = stats.omdbErrors.slice(0, 20);

        res.json(stats);
    } catch (err) {
        res.status(500).json({ error: err.message, stats });
    }
});

// GET /movies/:id
// Fallback chain: IMDb -> OMDB -> SQLite cache -> PG catalog
router.get('/:id', async (req, res) => {
    const { id } = req.params;

    try {
        const data = await imdbJson(`/titles/${id}`);
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
        const r = await pgQuery(
            `SELECT
         COUNT(*)                          AS total,
         COUNT(*) FILTER (WHERE has_details)      AS full_detail,
         COUNT(*) FILTER (WHERE NOT has_details)  AS stubs
       FROM media`
        );
        res.json(r.rows[0]);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

module.exports = router;
