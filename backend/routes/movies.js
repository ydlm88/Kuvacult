const express = require('express');
const router = express.Router();
const Database = require('better-sqlite3');
const path = require('path');

const IMDB_BASE = 'https://api.imdbapi.dev';

// Opens (or creates) movie_cache.db alongside server.js
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
  saveMovie:   db.prepare('INSERT OR REPLACE INTO movies (id, title, raw_json, cached_at) VALUES (?, ?, ?, ?)'),
  saveSearch:  db.prepare('INSERT OR REPLACE INTO searches (cache_key, raw_json, cached_at) VALUES (?, ?, ?)'),
  getMovie:    db.prepare('SELECT raw_json FROM movies WHERE id = ?'),
  getSearch:   db.prepare('SELECT raw_json FROM searches WHERE cache_key = ?'),
  fuzzySearch: db.prepare('SELECT raw_json FROM movies WHERE title LIKE ? LIMIT 20'),
};

async function imdbFetch(urlPath) {
  const res = await fetch(`${IMDB_BASE}${urlPath}`, {
    signal: AbortSignal.timeout(10000),
  });
  return res;
}

function cacheTitles(titles) {
  const now = Date.now();
  const save = db.transaction((list) => {
    for (const t of list) {
      if (t.id) stmts.saveMovie.run(t.id, t.primaryTitle || t.title || '', JSON.stringify(t), now);
    }
  });
  save(titles);
}

// ── GET /movies/search?q=query[&pageToken=...] ────────────────────────────────
router.get('/search', async (req, res) => {
  const q = (req.query.q || '').trim();
  const pageToken = req.query.pageToken;

  let urlPath = `/search/titles?query=${encodeURIComponent(q)}`;
  if (pageToken) urlPath += `&pageToken=${encodeURIComponent(pageToken)}`;

  try {
    const r = await imdbFetch(urlPath);
    if (r.status === 429) throw new Error('rate_limited');
    if (!r.ok) throw new Error(`imdb_${r.status}`);

    const data = await r.json();
    if (data.code) throw new Error(data.message || 'api_error');

    cacheTitles(data.titles || []);
    if (!pageToken) stmts.saveSearch.run(`search:${q.toLowerCase()}`, JSON.stringify(data), Date.now());
    return res.json(data);
  } catch (_) {
    const hit = stmts.getSearch.get(`search:${q.toLowerCase()}`);
    if (hit) return res.json(JSON.parse(hit.raw_json));

    // Last resort: fuzzy match on accumulated movie titles
    const rows = stmts.fuzzySearch.all(`%${q}%`);
    return res.json({ titles: rows.map(r => JSON.parse(r.raw_json)), nextPageToken: null });
  }
});

// ── GET /movies/trending ──────────────────────────────────────────────────────
router.get('/trending', async (req, res) => {
  try {
    const r = await imdbFetch('/titles?titleType=movie&sort=POPULARITY&order=DESC');
    if (r.status === 429) throw new Error('rate_limited');
    if (!r.ok) throw new Error(`imdb_${r.status}`);

    const data = await r.json();
    if (data.code) throw new Error(data.message || 'api_error');

    cacheTitles(data.titles || []);
    stmts.saveSearch.run('trending', JSON.stringify(data), Date.now());
    return res.json(data);
  } catch (_) {
    const hit = stmts.getSearch.get('trending');
    if (hit) return res.json(JSON.parse(hit.raw_json));
    return res.status(503).json({ titles: [], error: 'rate_limited' });
  }
});

// ── GET /movies/genre?g=genre[&pageToken=...] ─────────────────────────────────
router.get('/genre', async (req, res) => {
  const genre = (req.query.g || '').trim();
  const pageToken = req.query.pageToken;

  let urlPath = `/titles?titleType=movie&genres=${encodeURIComponent(genre)}&sort=POPULARITY&order=DESC`;
  if (pageToken) urlPath += `&pageToken=${encodeURIComponent(pageToken)}`;

  try {
    const r = await imdbFetch(urlPath);
    if (r.status === 429) throw new Error('rate_limited');
    if (!r.ok) throw new Error(`imdb_${r.status}`);

    const data = await r.json();
    if (data.code) throw new Error(data.message || 'api_error');

    cacheTitles(data.titles || []);
    if (!pageToken) stmts.saveSearch.run(`genre:${genre.toLowerCase()}`, JSON.stringify(data), Date.now());
    return res.json(data);
  } catch (_) {
    const hit = stmts.getSearch.get(`genre:${genre.toLowerCase()}`);
    if (hit) return res.json(JSON.parse(hit.raw_json));
    return res.status(503).json({ titles: [], error: 'rate_limited' });
  }
});

// ── GET /movies/:id ───────────────────────────────────────────────────────────
router.get('/:id', async (req, res) => {
  const { id } = req.params;

  try {
    const r = await imdbFetch(`/titles/${id}`);
    if (r.status === 429) throw new Error('rate_limited');
    if (!r.ok) throw new Error(`imdb_${r.status}`);

    const data = await r.json();
    stmts.saveMovie.run(id, data.primaryTitle || data.title || '', JSON.stringify(data), Date.now());
    return res.json(data);
  } catch (_) {
    const hit = stmts.getMovie.get(id);
    if (hit) return res.json(JSON.parse(hit.raw_json));
    return res.status(503).json({ error: 'rate_limited', id });
  }
});

module.exports = router;
