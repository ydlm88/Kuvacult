// Letterboxd import route — accepts a .zip or .csv export file, parses watched/
// watchlist/review CSVs, resolves each film against IMDb and OMDB, then writes
// watchlists, watched history, and reviews to PostgreSQL.
const express = require('express');
const multer = require('multer');
const AdmZip = require('adm-zip');
const { query: pgQuery } = require('../db');
const { requireAuth } = require('../middleware/auth');

const router = express.Router();
const upload = multer({
    storage: multer.memoryStorage(),
    limits: { fileSize: 20 * 1024 * 1024 },
});

const IMDB_BASE = 'https://api.imdbapi.dev';
const OMDB_BASE = 'https://www.omdbapi.com';
const MAX_MOVIES = 500;
const CONCURRENCY = 6;

async function imdbJson(urlPath) {
    const r = await fetch(`${IMDB_BASE}${urlPath}`, { signal: AbortSignal.timeout(8000) });
    if (r.status === 429) throw Object.assign(new Error('rate_limited'), { code: 429 });
    if (!r.ok) throw new Error(`imdb_${r.status}`);
    const data = await r.json();
    if (data.code) throw new Error(data.message || 'imdb_api_error');
    return data;
}

async function omdbJson(params) {
    const url = new URL(OMDB_BASE);
    url.searchParams.set('apikey', process.env.OMDB_API_KEY);
    for (const [k, v] of Object.entries(params)) url.searchParams.set(k, v);
    const r = await fetch(url.toString(), { signal: AbortSignal.timeout(8000) });
    if (!r.ok) throw new Error(`omdb_${r.status}`);
    const data = await r.json();
    if (data.Response === 'False') throw new Error(data.Error || 'omdb_no_results');
    return data;
}

function omdbToImdb(o) {
    return {
        id: o.imdbID,
        primaryTitle: o.Title,
        startYear: parseInt(o.Year) || 0,
        runtimeSeconds: (parseInt(o.Runtime) || 0) * 60,
        rating:
            o.imdbRating && o.imdbRating !== 'N/A'
                ? { aggregateRating: parseFloat(o.imdbRating) }
                : null,
        genres: o.Genre && o.Genre !== 'N/A' ? o.Genre.split(', ') : [],
        directors:
            o.Director && o.Director !== 'N/A'
                ? o.Director.split(', ').map((n) => ({ primaryName: n }))
                : [],
        plot: o.Plot && o.Plot !== 'N/A' ? o.Plot : '',
        primaryImage: o.Poster && o.Poster !== 'N/A' ? { url: o.Poster } : null,
    };
}

async function pgSaveMovie(m, hasDetails = true) {
    const id = m.id;
    const title = m.primaryTitle || m.title || '';
    if (!id || !title) return;
    await pgQuery(
        `INSERT INTO media
       (id, title, year, runtime, rating, genres, director, synopsis, poster_url, has_details)
     VALUES ($1,$2,$3,$4,$5,$6::jsonb,$7,$8,$9,$10)
     ON CONFLICT (id) DO UPDATE SET
       title      = EXCLUDED.title,
       runtime    = CASE WHEN EXCLUDED.runtime   > 0           THEN EXCLUDED.runtime   ELSE media.runtime   END,
       rating     = CASE WHEN EXCLUDED.rating    > 0           THEN EXCLUDED.rating    ELSE media.rating    END,
       genres     = CASE WHEN EXCLUDED.genres   != '[]'::jsonb THEN EXCLUDED.genres    ELSE media.genres    END,
       director   = CASE WHEN EXCLUDED.director != ''          THEN EXCLUDED.director  ELSE media.director  END,
       synopsis   = CASE WHEN EXCLUDED.synopsis != ''          THEN EXCLUDED.synopsis  ELSE media.synopsis  END,
       poster_url = COALESCE(EXCLUDED.poster_url, media.poster_url),
       has_details = EXCLUDED.has_details OR media.has_details,
       updated_at  = NOW()`,
        [
            id,
            title,
            m.startYear || 0,
            Math.round((m.runtimeSeconds || 0) / 60),
            m.rating?.aggregateRating ?? 0,
            JSON.stringify(m.genres || []),
            m.directors?.[0]?.primaryName ?? '',
            m.plot || '',
            m.primaryImage?.url ?? null,
            hasDetails,
        ]
    );
}

// Parses a single CSV line. Does NOT handle multi-line quoted fields.
function parseCsvLine(line) {
    const result = [];
    let current = '';
    let inQuotes = false;
    for (let i = 0; i < line.length; i++) {
        const c = line[i];
        if (c === '"') {
            if (inQuotes && line[i + 1] === '"') {
                current += '"';
                i++;
            } else inQuotes = !inQuotes;
        } else if (c === ',' && !inQuotes) {
            result.push(current.trim());
            current = '';
        } else {
            current += c;
        }
    }
    result.push(current.trim());
    return result;
}

// Handles multi-line quoted fields — Letterboxd review CSVs embed newlines inside quotes.
function parseCsv(text) {
    const raw = text.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
    const records = [];
    let current = '';
    let inQuotes = false;

    for (let i = 0; i < raw.length; i++) {
        const c = raw[i];
        if (c === '"') {
            if (inQuotes && raw[i + 1] === '"') {
                current += '""'; // escaped quote — preserve so parseCsvLine handles it
                i++;
            } else {
                inQuotes = !inQuotes;
                current += c;
            }
        } else if (c === '\n' && !inQuotes) {
            if (current.trim()) records.push(current);
            current = '';
        } else {
            current += c;
        }
    }
    if (current.trim()) records.push(current);

    if (records.length < 2) return { headers: [], rows: [] };
    const headers = parseCsvLine(records[0]).map((h) => h.toLowerCase().trim());
    const rows = records.slice(1).map((line) => {
        const vals = parseCsvLine(line);
        const obj = {};
        headers.forEach((h, i) => {
            obj[h] = vals[i] ?? '';
        });
        return obj;
    });
    return { headers, rows };
}

// Parses a Letterboxd custom-list CSV, example format:
//   Line 0:  "Letterboxd list export v7"
//   Line 1:  "Date,Name,Tags,URL,Description"  Metadata
//   Line 2:  <date>,<list name>,...            Metadata rows
//   Line 3:  (blank potentially)
//   Line 4:  "Position,Name,Year,URL,Description" data
//   Line 5+: movie rows
// Returns {rows, listName} where listName comes from the metadata row.
function parseLetterboxdListCsv(text) {
    const raw = text.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
    const lines = raw.split('\n');

    let listName = null;
    if (lines[0]?.trim().toLowerCase().startsWith('letterboxd list export')) {
        const metaHeaders = parseCsvLine(lines[1] || '').map((h) => h.toLowerCase().trim());
        const metaVals = parseCsvLine(lines[2] || '');
        const nameIdx = metaHeaders.indexOf('name');
        if (nameIdx !== -1) listName = metaVals[nameIdx]?.trim() || null;
    }

    const headerIdx = lines.findIndex((l) => /^position\s*,/i.test(l.trim()));
    if (headerIdx === -1) return { rows: parseCsv(text).rows, listName };

    const headers = parseCsvLine(lines[headerIdx]).map((h) => h.toLowerCase().trim());
    const rows = lines
        .slice(headerIdx + 1)
        .filter((l) => l.trim())
        .map((line) => {
            const vals = parseCsvLine(line);
            const obj = {};
            headers.forEach((h, i) => {
                obj[h] = vals[i] ?? '';
            });
            return obj;
        });

    return { rows, listName };
}

//Ex: "my-horror-picks.csv" to "My Horror Picks"
function filenameToListName(fname) {
    return (
        fname
            .replace(/\.csv$/i, '')
            .replace(/[-_]/g, ' ')
            .replace(/\b\w/g, (c) => c.toUpperCase())
            .trim() || 'Imported List'
    );
}

function decodeHtmlEntities(str) {
    return str
        .replace(/&amp;/g, '&')
        .replace(/&lt;/g, '<')
        .replace(/&gt;/g, '>')
        .replace(/&quot;/g, '"')
        .replace(/&#39;/g, "'")
        .replace(/&apos;/g, "'")
        .replace(/&hellip;/g, '…')
        .replace(/&mdash;/g, '—')
        .replace(/&ndash;/g, '–')
        .replace(/&rsquo;/g, '’')
        .replace(/&lsquo;/g, '‘')
        .replace(/&rdquo;/g, '”')
        .replace(/&ldquo;/g, '“')
        .replace(/&#(\d+);/g, (_, code) => String.fromCharCode(parseInt(code, 10)))
        .replace(/&#x([0-9a-f]+);/gi, (_, hex) => String.fromCharCode(parseInt(hex, 16)));
}

// Handles both numeric floats and Unicode star strings ("★★★½").
function parseLetterboxdRating(ratingStr) {
    if (!ratingStr || ratingStr.trim() === '') return 0;
    const num = parseFloat(ratingStr);
    if (!isNaN(num)) return Math.max(0, Math.min(5, num));
    const count = (ratingStr.match(/★/g) || []).length;
    const half = ratingStr.includes('½') ? 0.5 : 0;
    return count + half || 0;
}

const _norm = (s) => s.toLowerCase().replace(/[^a-z0-9]/g, '');
async function lookupMovie(name, year) {
    const normName = _norm(name);

    try {
        const data = await imdbJson(`/search/titles?query=${encodeURIComponent(name)}`);
        const titles = data.titles || [];
        const match =
            titles.find(
                (t) =>
                    (_norm(t.primaryTitle || '') === normName ||
                        _norm(t.originalTitle || '') === normName) &&
                    Math.abs((t.startYear || 0) - year) <= 2
            ) ||
            titles.find((t) => {
                const tn = _norm(t.primaryTitle || '');
                return (
                    Math.abs((t.startYear || 0) - year) <= 2 &&
                    (tn.includes(normName) || normName.includes(tn))
                );
            });

        if (match) {
            let resolved = null;

            try {
                const full = await imdbJson(`/titles/${match.id}`);
                await pgSaveMovie(full, true);
                resolved = full;
            } catch (_) {}

            try {
                const raw = await omdbJson({ i: match.id, plot: 'full' });
                const m = omdbToImdb(raw);
                await pgSaveMovie(m, true);
                if (!resolved || !resolved.primaryImage?.url) resolved = m;
            } catch (e) {
                console.error('[import] OMDB 1b failed for', match.id, e.message);
            }

            if (!resolved) {
                await pgSaveMovie(match, false);
                resolved = match;
            }

            return toEntry(
                resolved.id || match.id,
                resolved.primaryTitle || name,
                resolved.startYear || year,
                resolved.primaryImage?.url
            );
        }
    } catch (err) {
        if (err.code !== 429) console.error('[import] IMDb search failed for', name, err.message);
    }

    try {
        const raw = await omdbJson({ t: name, y: String(year), type: 'movie', plot: 'full' });
        const m = omdbToImdb(raw);
        await pgSaveMovie(m, true);
        return toEntry(m.id, m.primaryTitle || name, m.startYear || year, m.primaryImage?.url);
    } catch (e) {
        console.log('[import] OMDB t+y failed for', name, year, e.message);
    }

    try {
        const raw = await omdbJson({ t: name, type: 'movie', plot: 'full' });
        const m = omdbToImdb(raw);
        if (Math.abs((m.startYear || 0) - year) <= 3) {
            await pgSaveMovie(m, true);
            return toEntry(m.id, m.primaryTitle || name, m.startYear || year, m.primaryImage?.url);
        }
    } catch (e) {
        console.log('[import] OMDB t-only failed for', name, e.message);
    }

    // No type filter — catches films OMDB classifies as non-movie. Tight 1yr tolerance.
    try {
        const raw = await omdbJson({ t: name, plot: 'full' });
        const m = omdbToImdb(raw);
        if (Math.abs((m.startYear || 0) - year) <= 1) {
            await pgSaveMovie(m, true);
            return toEntry(m.id, m.primaryTitle || name, m.startYear || year, m.primaryImage?.url);
        }
    } catch (_) {}

    try {
        const raw = await omdbJson({ s: name, type: 'movie' });
        const results = raw.Search || [];
        const hit = results.find((r) => {
            const rNorm = _norm(r.Title || '');
            return (
                Math.abs((parseInt(r.Year) || 0) - year) <= 3 &&
                (rNorm.includes(normName) || normName.includes(rNorm))
            );
        });
        if (hit) {
            try {
                const detail = await omdbJson({ i: hit.imdbID, plot: 'full' });
                const m = omdbToImdb(detail);
                await pgSaveMovie(m, true);
                return toEntry(
                    m.id,
                    m.primaryTitle || name,
                    m.startYear || year,
                    m.primaryImage?.url
                );
            } catch (_) {
                //Return stub if detail fetch fails
                return toEntry(
                    hit.imdbID,
                    hit.Title || name,
                    parseInt(hit.Year) || year,
                    hit.Poster && hit.Poster !== 'N/A' ? hit.Poster : null
                );
            }
        }
    } catch (e) {
        console.log('[import] OMDB search failed for', name, e.message);
    }

    try {
        let r = await pgQuery(
            `SELECT id, title, year, poster_url FROM media
       WHERE title ILIKE $1 AND ABS(year - $2) <= 2
       ORDER BY has_details DESC, rating DESC LIMIT 1`,
            [name, year]
        );
        if (!r.rows[0]) {
            r = await pgQuery(
                `SELECT id, title, year, poster_url FROM media
         WHERE title ILIKE $1 AND ABS(year - $2) <= 2
         ORDER BY has_details DESC, rating DESC LIMIT 1`,
                [`%${name}%`, year]
            );
        }
        if (r.rows[0]) {
            const row = r.rows[0];
            return toEntry(row.id, row.title, row.year, row.poster_url);
        }
    } catch (_) {}

    return null;
}

function toEntry(movieId, title, year, posterUrl) {
    return { movieId, title, year: year || 0, posterUrl: posterUrl || null };
}

//Bounded concurrency
async function pMapLimit(arr, limit, fn) {
    const results = new Array(arr.length);
    let idx = 0;
    async function worker() {
        while (idx < arr.length) {
            const i = idx++;
            results[i] = await fn(arr[i], i);
        }
    }
    await Promise.all(Array.from({ length: Math.min(limit, arr.length) }, worker));
    return results;
}

//Watchlist creation
async function createWatchlist(userId, name, movies, section = 'want') {
    if (movies.length === 0) return 0;
    const watchlistId = `lb_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`;
    const listKey = Math.random().toString(36).slice(2, 8).toUpperCase();

    await pgQuery(
        `INSERT INTO watchlists (id, name, list_key, member_ids) VALUES ($1,$2,$3,$4::jsonb)`,
        [watchlistId, name, listKey, JSON.stringify([userId])]
    );
    await pgQuery(
        `UPDATE users SET watchlist_ids = watchlist_ids || $1::jsonb, updated_at = NOW() WHERE id = $2`,
        [JSON.stringify([watchlistId]), userId]
    );

    for (const m of movies) {
        await pgQuery(
            `INSERT INTO movies (id, watchlist_id, title, year, added_by, section, image_url)
       VALUES ($1,$2,$3,$4,$5,$6,$7)
       ON CONFLICT (id, watchlist_id) DO NOTHING`,
            [m.movieId, watchlistId, m.title, m.year, userId, section, m.posterUrl || null]
        );
    }
    return movies.length;
}

//POST /import/letterboxd
router.post('/letterboxd', requireAuth, upload.single('file'), async (req, res) => {
    const userId = req.user.sub;
    if (!req.file) return res.status(400).json({ error: 'No file uploaded' });

    const sources = [];
    let reviewRows = [];

    const ext = req.file.originalname.toLowerCase().split('.').pop();

    try {
        if (ext === 'zip') {
            const zip = new AdmZip(req.file.buffer);
            const listBuckets = {};

            const SKIP_PARENTS = new Set(['deleted', 'orphaned']);

            const SKIP_ROOT = new Set([
                'profile.csv',
                'diary.csv',
                'follows.csv',
                'followers.csv',
                'following.csv',
                'likes.csv',
                'comments.csv',
            ]);

            console.log('[import] ZIP entries:');
            for (const entry of zip.getEntries()) {
                if (entry.isDirectory) continue;
                const parts = entry.entryName.replace(/\\/g, '/').split('/');
                const fname = parts[parts.length - 1].toLowerCase();
                const parentDir = parts.length > 1 ? parts[parts.length - 2].toLowerCase() : '';
                if (!fname.endsWith('.csv')) continue;

                console.log(`  "${entry.entryName}" parent="${parentDir}"`);
                if (SKIP_PARENTS.has(parentDir)) continue;

                const text = entry.getData().toString('utf8');

                if (fname === 'watched.csv') {
                    const { rows } = parseCsv(text);
                    console.log(`  → watched.csv: ${rows.length} rows`);
                    sources.push({ dest: 'watched', rows });
                } else if (fname === 'ratings.csv') {
                    const { rows } = parseCsv(text);
                    console.log(`  → ratings.csv: ${rows.length} rows`);
                    sources.push({ dest: 'watched', rows });
                } else if (fname === 'watchlist.csv') {
                    const { rows } = parseCsv(text);
                    console.log(`  → watchlist.csv: ${rows.length} rows`);
                    sources.push({ dest: 'watchlist', rows });
                } else if (fname === 'reviews.csv' && parentDir === '') {
                    //Only the root-level reviews.csv
                    reviewRows = parseCsv(text).rows;
                    console.log(`  → reviews.csv: ${reviewRows.length} rows`);
                } else if (fname === 'films.csv' && parentDir === 'likes') {
                    const { rows } = parseCsv(text);
                    console.log(`  → likes/films.csv (Liked from Letterboxd): ${rows.length} rows`);
                    sources.push({ dest: 'Liked from Letterboxd', rows });
                } else if (parentDir === 'likes') {
                    // likes/lists.csv, skip likes/reviews.csv
                    console.log(`  → skipping likes subfolder file`);
                } else if (parentDir === 'lists') {
                    const { rows, listName } = parseLetterboxdListCsv(text);
                    const name = (listName && listName.trim()) || filenameToListName(fname);
                    console.log(`  → list "${name}": ${rows.length} rows`);
                    listBuckets[name] = (listBuckets[name] || []).concat(rows);
                } else if (!SKIP_ROOT.has(fname)) {
                    const { rows } = parseCsv(text);
                    const name = filenameToListName(fname);
                    console.log(`  → unknown file as custom list "${name}": ${rows.length} rows`);
                    listBuckets[name] = (listBuckets[name] || []).concat(rows);
                }
            }

            for (const [name, rows] of Object.entries(listBuckets)) {
                sources.push({ dest: name, rows });
            }
        } else if (ext === 'csv') {
            const { headers, rows } = parseCsv(req.file.buffer.toString('utf8'));
            const dest = headers.includes('rating') ? 'watched' : 'watchlist';
            sources.push({ dest, rows });
        } else {
            return res.status(400).json({ error: 'File must be a .zip or .csv' });
        }
    } catch (err) {
        console.error('[import] parse error:', err);
        return res.status(400).json({ error: `Could not parse file: ${err.message}` });
    }

    console.log(
        '[import] sources:',
        sources.map((s) => `${s.dest}(${s.rows.length})`)
    );
    console.log('[import] reviewRows:', reviewRows.length);

    if (sources.length === 0 || sources.every((s) => s.rows.length === 0)) {
        return res.status(400).json({
            error: "No movies found. Make sure you're uploading the correct Letterboxd export file.",
        });
    }

    //Resolve movies
    const allRows = sources.flatMap((s) =>
        s.rows.slice(0, MAX_MOVIES).map((r) => ({ ...r, _dest: s.dest }))
    );

    const seen = new Set();
    const uniqueRows = allRows.filter((r) => {
        const name = (r.name || r['film name'] || r['title'] || '').toLowerCase().trim();
        const key = `${name}|${r.year}|${r._dest}`;
        if (seen.has(key)) return false;
        seen.add(key);
        return true;
    });

    console.log(`[import] ${uniqueRows.length} unique movie rows to look up`);

    const lookupResults = await pMapLimit(uniqueRows, CONCURRENCY, async (row) => {
        const name = (row.name || row['film name'] || row['title'] || '').trim();
        const year = parseInt(row.year) || 0;
        if (!name || !year) return null;
        const found = await lookupMovie(name, year);
        return found ? { ...found, _dest: row._dest } : null;
    });

    const buckets = {};
    let notFound = 0;
    for (const r of lookupResults) {
        if (!r) {
            notFound++;
            continue;
        }
        if (!buckets[r._dest]) buckets[r._dest] = [];
        buckets[r._dest].push(r);
    }

    //Write watchlists
    const dateLabel = new Date().toLocaleDateString('en-GB', {
        day: '2-digit',
        month: 'short',
        year: 'numeric',
    });
    let totalAdded = 0;
    let watchedAdded = 0;
    let watchlistsCreated = 0;

    if (buckets['watched']?.length > 0) {
        const found = buckets['watched'];
        const existingR = await pgQuery('SELECT watched_movies FROM users WHERE id = $1', [userId]);
        const existIds = new Set((existingR.rows[0]?.watched_movies || []).map((m) => m.movieId));
        const newEntries = found
            .filter((m) => !existIds.has(m.movieId))
            .map((m) => ({
                movieId: m.movieId,
                posterUrl: m.posterUrl || null,
                title: m.title,
                year: m.year,
            }));

        if (newEntries.length > 0) {
            await pgQuery(
                'UPDATE users SET watched_movies = watched_movies || $1::jsonb, updated_at = NOW() WHERE id = $2',
                [JSON.stringify(newEntries), userId]
            );
            await createWatchlist(
                userId,
                `Letterboxd · Watched · ${dateLabel}`,
                newEntries,
                'watched'
            );
            watchedAdded = newEntries.length;
            totalAdded += newEntries.length;
            watchlistsCreated++;
        }
    }

    if (buckets['watchlist']?.length > 0) {
        const added = await createWatchlist(
            userId,
            `Letterboxd · Watchlist · ${dateLabel}`,
            buckets['watchlist'],
            'want'
        );
        totalAdded += added;
        watchlistsCreated++;
    }

    for (const [dest, movies] of Object.entries(buckets)) {
        if (dest === 'watched' || dest === 'watchlist') continue;
        const added = await createWatchlist(userId, `${dest} · ${dateLabel}`, movies, 'want');
        totalAdded += added;
        watchlistsCreated++;
    }

    //Import reviews
    let reviewsImported = 0;
    if (reviewRows.length > 0) {
        let byName = '',
            byHandle = '',
            byAvatarUrl = null;
        try {
            const uRow = await pgQuery(
                'SELECT display_name, username, avatar_url FROM users WHERE id = $1',
                [userId]
            );
            if (uRow.rows[0]) {
                byName = uRow.rows[0].display_name || '';
                byHandle = uRow.rows[0].username || '';
                byAvatarUrl = uRow.rows[0].avatar_url || null;
            }
        } catch (_) {}

        const withText = reviewRows.filter((r) => (r.review || '').trim().length > 0);
        console.log(`[import] ${withText.length} reviews with text`);

        for (const row of withText.slice(0, 300)) {
            const name = (row.name || row['film name'] || row['title'] || '').trim();
            const year = parseInt(row.year) || 0;
            if (!name || !year) continue;

            // Check catalog first — watched.csv and reviews.csv heavily overlap.
            // Falls back to substring match for subtitle variations (e.g. "The VVitch" vs full title).
            let movie = null;
            try {
                let r = await pgQuery(
                    `SELECT id, title, year, director, poster_url FROM media
           WHERE title ILIKE $1 AND ABS(year - $2) <= 2
           ORDER BY has_details DESC, rating DESC LIMIT 1`,
                    [name, year]
                );
                if (!r.rows[0]) {
                    r = await pgQuery(
                        `SELECT id, title, year, director, poster_url FROM media
             WHERE title ILIKE $1 AND ABS(year - $2) <= 2
             ORDER BY has_details DESC, rating DESC LIMIT 1`,
                        [`%${name}%`, year]
                    );
                }
                if (r.rows[0]) movie = r.rows[0];
            } catch (_) {}

            if (!movie) {
                const found = await lookupMovie(name, year);
                if (found) {
                    try {
                        const r = await pgQuery(
                            'SELECT id, title, year, director, poster_url FROM media WHERE id = $1',
                            [found.movieId]
                        );
                        movie = r.rows[0] || {
                            id: found.movieId,
                            title: found.title,
                            year: found.year,
                        };
                    } catch (_) {
                        movie = { id: found.movieId, title: found.title, year: found.year };
                    }
                }
            }

            if (!movie) continue;

            const stars = parseLetterboxdRating(row.rating);
            const text = decodeHtmlEntities((row.review || '').trim());
            const rewatch = (row.rewatch || '').toLowerCase() === 'yes';
            const reviewId = `lb_rev_${userId}_${movie.id}`;

            try {
                await pgQuery(
                    `INSERT INTO reviews
             (id, by_id, by_name, by_handle, by_avatar_url,
              movie_id, movie_title, movie_year, movie_director, movie_poster_url,
              stars, text, rewatch)
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)
           ON CONFLICT (id) DO NOTHING`,
                    [
                        reviewId,
                        userId,
                        byName,
                        byHandle,
                        byAvatarUrl,
                        movie.id,
                        movie.title || name,
                        movie.year || year,
                        movie.director || '',
                        movie.poster_url || null,
                        stars,
                        text,
                        rewatch,
                    ]
                );
                reviewsImported++;
            } catch (e) {
                console.error('[import] review insert failed:', e.message);
            }
        }
    }

    console.log(
        `[import] done: totalAdded=${totalAdded} watchlistsCreated=${watchlistsCreated} reviewsImported=${reviewsImported} notFound=${notFound}`
    );

    res.json({
        imported: totalAdded,
        watchedAdded,
        watchlistsCreated,
        reviewsImported,
        notFound,
        total: uniqueRows.length,
    });
});

module.exports = router;
