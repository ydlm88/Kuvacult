const fs   = require('fs');
const path = require('path');

const POSTERS_DIR = path.join(__dirname, '..', 'posters');

if (!fs.existsSync(POSTERS_DIR)) fs.mkdirSync(POSTERS_DIR, { recursive: true });

function posterLocalPath(imdbId) {
    return path.join(POSTERS_DIR, `${imdbId}.jpg`);
}

function posterPublicUrl(imdbId) {
    return `${process.env.APP_URL}/posters/${imdbId}.jpg`;
}

function isLocalPosterUrl(url) {
    return typeof url === 'string' && url.includes('/posters/tt');
}

function hasLocalPoster(imdbId) {
    return fs.existsSync(posterLocalPath(imdbId));
}

async function downloadPoster(imdbId, sourceUrl) {
    if (!imdbId || !sourceUrl) return false;
    try {
        const r = await fetch(sourceUrl, { signal: AbortSignal.timeout(15000) });
        if (!r.ok) return false;
        const buffer = Buffer.from(await r.arrayBuffer());
        fs.writeFileSync(posterLocalPath(imdbId), buffer);
        return true;
    } catch (_) {
        return false;
    }
}

// Fire-and-forget: download poster to disk and update media.poster_url in DB.
// Safe to call on every movie save — skips if already local.
async function cachePosterBackground(imdbId, sourceUrl, pgQuery) {
    if (!imdbId || !sourceUrl || isLocalPosterUrl(sourceUrl)) return;

    if (hasLocalPoster(imdbId)) {
        // Already on disk — just make sure DB points to local URL
        pgQuery(
            `UPDATE media SET poster_url = $1 WHERE id = $2 AND (poster_url NOT LIKE '%/posters/tt%' OR poster_url IS NULL)`,
            [posterPublicUrl(imdbId), imdbId]
        ).catch(() => {});
        return;
    }

    const ok = await downloadPoster(imdbId, sourceUrl);
    if (ok) {
        pgQuery(
            'UPDATE media SET poster_url = $1 WHERE id = $2',
            [posterPublicUrl(imdbId), imdbId]
        ).catch(() => {});
    }
}

module.exports = { posterPublicUrl, isLocalPosterUrl, hasLocalPoster, cachePosterBackground };
