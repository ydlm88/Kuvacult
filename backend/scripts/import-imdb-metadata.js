// import-imdb-metadata.js — Bulk-imports IMDB metadata TSV files into the media table.
// Only inserts IDs not already in the catalog. Run with: node scripts/import-imdb-metadata.js
require('dotenv').config({ path: require('path').join(__dirname, '../.env') });
const fs       = require('fs');
const path     = require('path');
const readline = require('readline');
const { query: pgQuery, pool } = require('../db');

const IMDB_DIR   = 'C:/Users/JustJ/Downloads/imdb metadata/imdb metadata';
const BATCH_SIZE = 500;
const LOG_EVERY  = 50000;

const FILES = {
    ratings : path.join(IMDB_DIR, 'title.ratings.tsv'),
    crew    : path.join(IMDB_DIR, 'title.crew.tsv'),
    names   : path.join(IMDB_DIR, 'name.basics.tsv'),
    basics  : path.join(IMDB_DIR, 'title.basics.tsv'),
};

function streamLines(filePath) {
    return readline.createInterface({
        input: fs.createReadStream(filePath, { encoding: 'utf8' }),
        crlfDelay: Infinity,
    });
}

function mapMediaType(titleType) {
    if (titleType === 'tvSeries' || titleType === 'tvMiniSeries') return 'series';
    if (titleType === 'short'    || titleType === 'tvShort')      return 'short';
    return 'movie';
}

// Phase 1: Load ratings into Map<tconst, rating>
async function loadRatings() {
    console.log('Phase 1: Loading title.ratings.tsv...');
    const map = new Map();
    let n = 0;
    await new Promise((resolve, reject) => {
        const rl = streamLines(FILES.ratings);
        rl.on('line', (line) => {
            if (n++ === 0) return;
            const [tconst, avgRating] = line.split('\t');
            if (tconst && avgRating) map.set(tconst, parseFloat(avgRating) || 0);
        });
        rl.on('close', resolve);
        rl.on('error', reject);
    });
    console.log(`  → ${map.size.toLocaleString()} rated titles`);
    return map;
}

// Phase 2: Load first director nconst per title into Map<tconst, nconst>
async function loadDirectorNconsts() {
    console.log('Phase 2: Loading title.crew.tsv (first director only)...');
    const map = new Map();
    let n = 0;
    await new Promise((resolve, reject) => {
        const rl = streamLines(FILES.crew);
        rl.on('line', (line) => {
            if (n++ === 0) return;
            const [tconst, directors] = line.split('\t');
            if (!tconst || !directors || directors === '\\N') return;
            const first = directors.split(',')[0].trim();
            if (first) map.set(tconst, first);
        });
        rl.on('close', resolve);
        rl.on('error', reject);
    });
    console.log(`  → ${map.size.toLocaleString()} titles have a director nconst`);
    return map;
}

// Phase 3: Load names only for nconsts that appear as directors
async function loadDirectorNames(crewMap) {
    console.log('Phase 3: Loading name.basics.tsv (directors only)...');
    const needed = new Set(crewMap.values());
    const map = new Map();
    let n = 0;
    await new Promise((resolve, reject) => {
        const rl = streamLines(FILES.names);
        rl.on('line', (line) => {
            if (n++ === 0) return;
            const [nconst, primaryName] = line.split('\t');
            if (nconst && needed.has(nconst) && primaryName && primaryName !== '\\N') {
                map.set(nconst, primaryName);
            }
        });
        rl.on('close', resolve);
        rl.on('error', reject);
    });
    console.log(`  → ${map.size.toLocaleString()} director names`);
    return map;
}

// Phase 3.5: Load existing catalog IDs to skip
async function loadExistingIds() {
    console.log('Phase 3.5: Loading existing catalog IDs...');
    const r = await pgQuery('SELECT id FROM media');
    const set = new Set(r.rows.map((row) => row.id));
    console.log(`  → ${set.size.toLocaleString()} IDs already in catalog (will skip)`);
    return set;
}

// Bulk INSERT a batch of rows — new entries only, conflict is a no-op
async function bulkInsert(rows) {
    if (!rows.length) return;
    const vals   = [];
    const params = [];
    let p = 1;
    for (const r of rows) {
        vals.push(`($${p++},$${p++},$${p++},$${p++},$${p++},$${p++}::jsonb,$${p++},$${p++},$${p++},$${p++})`);
        params.push(
            r.id, r.title, r.year, r.runtime, r.rating,
            JSON.stringify(r.genres), r.director, '', null, r.mediaType
        );
    }
    await pgQuery(
        `INSERT INTO media
           (id, title, year, runtime, rating, genres, director, synopsis, poster_url, media_type)
         VALUES ${vals.join(',')}
         ON CONFLICT (id) DO NOTHING`,
        params
    );
}

async function run() {
    console.log('\n=== IMDB Metadata Import ===\n');

    const ratingsMap  = await loadRatings();
    const crewMap     = await loadDirectorNconsts();
    const namesMap    = await loadDirectorNames(crewMap);
    const existingIds = await loadExistingIds();

    // Phase 4: Stream title.basics synchronously — collect into array, no async in handler
    console.log('\nPhase 4: Streaming title.basics.tsv (collecting rows)...');

    const SKIP_TYPES = new Set(['tvEpisode', 'videoGame']);
    const pendingRows = [];
    let lineNum = 0;
    let skipped = 0;

    await new Promise((resolve, reject) => {
        const rl = streamLines(FILES.basics);

        // Synchronous handler — no await, no async, no race conditions
        rl.on('line', (line) => {
            lineNum++;
            if (lineNum === 1) return; // header

            const cols = line.split('\t');
            const tconst        = cols[0];
            const titleType     = cols[1];
            const primaryTitle  = cols[2];
            const isAdult       = cols[4];
            const startYear     = cols[5];
            const runtimeMins   = cols[7];
            const genres        = cols[8];

            if (SKIP_TYPES.has(titleType))                   { skipped++; return; }
            if (isAdult === '1')                             { skipped++; return; }
            if (!primaryTitle || primaryTitle === '\\N')     { skipped++; return; }
            if (existingIds.has(tconst))                     { skipped++; return; }

            const dirNconst = crewMap.get(tconst) ?? '';
            pendingRows.push({
                id        : tconst,
                title     : primaryTitle,
                year      : parseInt(startYear) || 0,
                runtime   : parseInt(runtimeMins) || 0,
                rating    : ratingsMap.get(tconst) ?? 0,
                genres    : (!genres || genres === '\\N') ? [] : genres.split(','),
                director  : dirNconst ? (namesMap.get(dirNconst) ?? '') : '',
                mediaType : mapMediaType(titleType),
            });

            if (lineNum % LOG_EVERY === 0) {
                process.stdout.write(
                    `\r  line ${lineNum.toLocaleString()}  |  queued: ${pendingRows.length.toLocaleString()}  |  skipped: ${skipped.toLocaleString()}   `
                );
            }
        });

        rl.on('close', resolve);
        rl.on('error', reject);
    });

    console.log(`\n  Done. ${pendingRows.length.toLocaleString()} rows to insert, ${skipped.toLocaleString()} skipped.\n`);

    // Phase 5: Insert collected rows in batches — fully sequential, no concurrency issues
    console.log('Phase 5: Inserting rows...');
    let inserted = 0;

    for (let i = 0; i < pendingRows.length; i += BATCH_SIZE) {
        const batch = pendingRows.slice(i, i + BATCH_SIZE);
        await bulkInsert(batch);
        inserted += batch.length;

        if (inserted % LOG_EVERY < BATCH_SIZE) {
            console.log(`  ${inserted.toLocaleString()} / ${pendingRows.length.toLocaleString()} inserted`);
        }
    }

    const countR = await pgQuery('SELECT COUNT(*)::int AS n FROM media');

    console.log(`\n=== Done ===`);
    console.log(`  Lines processed : ${lineNum.toLocaleString()}`);
    console.log(`  Rows inserted   : ${inserted.toLocaleString()}`);
    console.log(`  Rows skipped    : ${skipped.toLocaleString()}`);
    console.log(`  Total in catalog: ${countR.rows[0].n.toLocaleString()}`);

    await pool.end();
}

run().catch((err) => {
    console.error('\nFatal:', err.message);
    process.exit(1);
});
