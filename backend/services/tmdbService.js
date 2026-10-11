const TMDB_BASE = 'https://api.themoviedb.org/3';
const TMDB_IMG  = 'https://image.tmdb.org/t/p/w500';

const TMDB_GENRE_IDS = {
    Action: 28, Adventure: 12, Animation: 16, Comedy: 35, Crime: 80,
    Documentary: 99, Drama: 18, Family: 10751, Fantasy: 14, History: 36,
    Horror: 27, Music: 10402, Mystery: 9648, Romance: 10749,
    'Science Fiction': 878, 'Science-Fiction': 878, Thriller: 53, War: 10752, Western: 37,
};

function tmdbHeaders() {
    return {
        Authorization: `Bearer ${process.env.TMDB_API_KEY}`,
        'Content-Type': 'application/json',
    };
}

async function tmdbJson(path) {
    const r = await fetch(`${TMDB_BASE}${path}`, {
        headers: tmdbHeaders(),
        signal: AbortSignal.timeout(10000),
    });
    if (r.status === 429) throw Object.assign(new Error('tmdb_rate_limited'), { code: 429 });
    if (!r.ok) throw new Error(`tmdb_${r.status}`);
    return r.json();
}

function tmdbPosterUrl(posterPath) {
    if (!posterPath) return null;
    return `${TMDB_IMG}${posterPath}`;
}

// Normalize TMDB movie object (stub or full detail) to the canonical IMDb shape.
// Stubs (from search/trending/discover) have id=null and carry tmdbId for enrichment.
// Full detail objects (from /movie/{id}?append_to_response=credits,external_ids) have id=imdb_id.
function tmdbToImdb(movie) {
    const imdbId = movie.imdb_id || movie.external_ids?.imdb_id || null;
    const primaryTitle = movie.title || movie.original_title || '';
    const originalTitle = movie.original_title || primaryTitle;
    const startYear = movie.release_date
        ? parseInt(movie.release_date.slice(0, 4), 10) || 0
        : 0;
    const runtimeSeconds = (movie.runtime || 0) * 60;
    const voteAvg = movie.vote_average ?? 0;
    const rating = voteAvg > 0 ? { aggregateRating: parseFloat(voteAvg.toFixed(1)) } : null;

    let genres = [];
    if (Array.isArray(movie.genres) && movie.genres.length) {
        genres = movie.genres.map((g) => g.name).filter(Boolean);
    }

    let directors = [];
    if (Array.isArray(movie.credits?.crew)) {
        directors = movie.credits.crew
            .filter((c) => c.job === 'Director')
            .map((c) => ({ primaryName: c.name }));
    }

    const plot = movie.overview || '';
    const posterPath = movie.poster_path || null;
    const primaryImage = posterPath ? { url: tmdbPosterUrl(posterPath) } : null;
    const mediaType = movie.media_type === 'tv' ? 'series' : 'movie';

    return {
        id: imdbId,
        tmdbId: movie.id,
        primaryTitle,
        originalTitle,
        startYear,
        runtimeSeconds,
        rating,
        genres,
        directors,
        plot,
        primaryImage,
        mediaType,
    };
}

// Strip the carry-through tmdbId before persistence or API response.
function stripTmdbId(m) {
    const { tmdbId, ...rest } = m;
    return rest;
}

function isSafeMovie(r) {
    if (!r.release_date) return false;
    if (r.adult === true) return false;
    return new Date(r.release_date) <= new Date();
}

const ENRICH_CONCURRENCY = 10;

// Fetch full detail for each stub (which has tmdbId but id=null).
// Resolves imdb_id via external_ids. Drops entries where imdb_id cannot be found.
async function enrichTmdbStubs(stubs) {
    if (!stubs.length) return [];
    const results = new Array(stubs.length).fill(null);
    let idx = 0;

    async function worker() {
        while (idx < stubs.length) {
            const i = idx++;
            const stub = stubs[i];
            if (!stub.tmdbId) { results[i] = stub; continue; }
            try {
                const detail = await tmdbJson(
                    `/movie/${stub.tmdbId}?append_to_response=credits,external_ids`
                );
                const full = tmdbToImdb(detail);
                if (!full.id) continue;
                results[i] = full;
            } catch (_) {
                // drop on error — OMDB fallback in caller handles remaining gaps
            }
        }
    }

    const workers = Array.from(
        { length: Math.min(ENRICH_CONCURRENCY, stubs.length) },
        worker
    );
    await Promise.all(workers);
    return results.filter(Boolean);
}

// Search movies by title string.
// Returns { titles: [stub with tmdbId, id=null], nextPageToken: string|null }
async function searchTmdb(query, page = 1) {
    const data = await tmdbJson(
        `/search/movie?query=${encodeURIComponent(query)}&page=${page}&include_adult=false`
    );
    const stubs = (data.results || []).filter(isSafeMovie).map(tmdbToImdb);
    const nextPageToken = data.page < data.total_pages ? String(data.page + 1) : null;
    return { titles: stubs, nextPageToken };
}

// Fetch full detail for a known IMDb ID via /find (imdb_id → tmdb_id → full detail).
async function fetchTmdbByImdbId(imdbId) {
    const findData = await tmdbJson(`/find/${imdbId}?external_source=imdb_id`);
    const movie = (findData.movie_results || [])[0];
    if (!movie) throw new Error(`tmdb_not_found:${imdbId}`);
    const detail = await tmdbJson(
        `/movie/${movie.id}?append_to_response=credits,external_ids`
    );
    const normalized = tmdbToImdb(detail);
    // Prefer the confirmed imdb_id from external_ids; fall back to the ID we looked up with
    normalized.id = detail.external_ids?.imdb_id || imdbId;
    return normalized;
}

async function fetchTmdbTrending(page = 1) {
    const data = await tmdbJson(`/trending/movie/week?page=${page}&include_adult=false`);
    const stubs = (data.results || []).filter(isSafeMovie).map(tmdbToImdb);
    const nextPageToken = data.page < data.total_pages ? String(data.page + 1) : null;
    return { titles: stubs, nextPageToken };
}

async function fetchTmdbGenre(genreName, page = 1) {
    const genreId = TMDB_GENRE_IDS[genreName];
    if (!genreId) throw new Error(`tmdb_unknown_genre:${genreName}`);
    const data = await tmdbJson(
        `/discover/movie?with_genres=${genreId}&sort_by=popularity.desc&page=${page}&include_adult=false`
    );
    const stubs = (data.results || []).filter(isSafeMovie).map(tmdbToImdb);
    const nextPageToken = data.page < data.total_pages ? String(data.page + 1) : null;
    return { titles: stubs, nextPageToken };
}

async function fetchTmdbPopular(page = 1) {
    const data = await tmdbJson(`/movie/popular?page=${page}&include_adult=false`);
    const stubs = (data.results || []).filter(isSafeMovie).map(tmdbToImdb);
    const nextPageToken = data.page < data.total_pages ? String(data.page + 1) : null;
    return { titles: stubs, nextPageToken };
}

module.exports = {
    tmdbToImdb,
    stripTmdbId,
    enrichTmdbStubs,
    searchTmdb,
    fetchTmdbByImdbId,
    fetchTmdbTrending,
    fetchTmdbGenre,
    fetchTmdbPopular,
    TMDB_GENRE_IDS,
};
