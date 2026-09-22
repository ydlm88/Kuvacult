-- Kuvacult PostgreSQL schema
-- Run once via: psql -U postgres -d kuvacult -f schema.sql
-- Or auto-run on startup via migrate.js

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Users
CREATE TABLE IF NOT EXISTS users (
  id             TEXT PRIMARY KEY,
  username       TEXT UNIQUE NOT NULL,
  email          TEXT UNIQUE NOT NULL,
  password_hash  TEXT NOT NULL,
  display_name   TEXT NOT NULL DEFAULT '',
  avatar_url     TEXT,
  avatar_bg      BIGINT NOT NULL DEFAULT 4294952019,
  room_key       TEXT UNIQUE,
  friend_ids     JSONB NOT NULL DEFAULT '[]',
  watchlist_ids  JSONB NOT NULL DEFAULT '[]',
  following_ids  JSONB NOT NULL DEFAULT '[]',
  follower_count INTEGER NOT NULL DEFAULT 0,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Email verification 
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name='users' AND column_name='email_verified') THEN
    ALTER TABLE users ADD COLUMN email_verified BOOLEAN NOT NULL DEFAULT FALSE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name='users' AND column_name='verification_token') THEN
    ALTER TABLE users ADD COLUMN verification_token TEXT;
  END IF;
END $$;

-- Password reset tokens
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name='users' AND column_name='reset_token_hash') THEN
    ALTER TABLE users ADD COLUMN reset_token_hash TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name='users' AND column_name='reset_token_expires') THEN
    ALTER TABLE users ADD COLUMN reset_token_expires TIMESTAMPTZ;
  END IF;
END $$;

-- Watched movies
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name='users' AND column_name='watched_movies') THEN
    ALTER TABLE users ADD COLUMN watched_movies JSONB NOT NULL DEFAULT '[]'::jsonb;
  END IF;
END $$;

-- Refresh tokens
CREATE TABLE IF NOT EXISTS refresh_tokens (
  id         TEXT PRIMARY KEY,
  user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user ON refresh_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_hash ON refresh_tokens(token_hash);

-- Watchlists 
CREATE TABLE IF NOT EXISTS watchlists (
  id         TEXT PRIMARY KEY,
  name       TEXT NOT NULL,
  list_key   TEXT UNIQUE,
  member_ids JSONB NOT NULL DEFAULT '[]',
  likes      INTEGER NOT NULL DEFAULT 0,
  liked_by   JSONB NOT NULL DEFAULT '[]',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_watchlists_list_key ON watchlists(list_key);

-- Movies
CREATE TABLE IF NOT EXISTS movies (
  id           TEXT NOT NULL,
  watchlist_id TEXT NOT NULL REFERENCES watchlists(id) ON DELETE CASCADE,
  title        TEXT NOT NULL,
  year         INTEGER NOT NULL DEFAULT 0,
  runtime      INTEGER NOT NULL DEFAULT 0,
  rating       REAL NOT NULL DEFAULT 0,
  genres       JSONB NOT NULL DEFAULT '[]',
  director     TEXT NOT NULL DEFAULT '',
  stream_id    TEXT NOT NULL DEFAULT '',
  added_by     TEXT NOT NULL,
  section      TEXT NOT NULL DEFAULT 'want',
  synopsis     TEXT NOT NULL DEFAULT '',
  image_url    TEXT,
  stars        JSONB NOT NULL DEFAULT '{}',
  notes        JSONB NOT NULL DEFAULT '[]',
  added_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (id, watchlist_id)
);
CREATE INDEX IF NOT EXISTS idx_movies_watchlist ON movies(watchlist_id);

-- watched_by
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name='movies' AND column_name='watched_by') THEN
    ALTER TABLE movies ADD COLUMN watched_by JSONB NOT NULL DEFAULT '[]'::jsonb;
  END IF;
END $$;

-- Activity
CREATE TABLE IF NOT EXISTS activity (
  id           TEXT PRIMARY KEY,
  watchlist_id TEXT NOT NULL REFERENCES watchlists(id) ON DELETE CASCADE,
  kind         TEXT NOT NULL,
  who          TEXT NOT NULL,
  movie_id     TEXT,
  stars        REAL,
  to_section   TEXT,
  picks        JSONB,
  text         TEXT,
  at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_activity_watchlist ON activity(watchlist_id);

-- Reviews 
CREATE TABLE IF NOT EXISTS reviews (
  id               TEXT PRIMARY KEY,
  by_id            TEXT NOT NULL,
  by_name          TEXT NOT NULL DEFAULT '',
  by_handle        TEXT NOT NULL DEFAULT '',
  by_avatar_url    TEXT,
  movie_id         TEXT NOT NULL,
  movie_title      TEXT NOT NULL,
  movie_year       INTEGER NOT NULL DEFAULT 0,
  movie_director   TEXT NOT NULL DEFAULT '',
  movie_poster_url TEXT,
  stars            REAL NOT NULL,
  text             TEXT NOT NULL,
  rewatch          BOOLEAN NOT NULL DEFAULT FALSE,
  likes            INTEGER NOT NULL DEFAULT 0,
  liked_by         JSONB NOT NULL DEFAULT '[]',
  comment_count    INTEGER NOT NULL DEFAULT 0,
  at               TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_reviews_movie  ON reviews(movie_id);
CREATE INDEX IF NOT EXISTS idx_reviews_by_id  ON reviews(by_id);
CREATE INDEX IF NOT EXISTS idx_reviews_at     ON reviews(at DESC);

-- One review per user per movie (enables upsert)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'reviews_by_id_movie_id_key'
  ) THEN
    ALTER TABLE reviews ADD CONSTRAINT reviews_by_id_movie_id_key UNIQUE (by_id, movie_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'review_comments') THEN
    CREATE TABLE review_comments (
      id            TEXT PRIMARY KEY,
      review_id     TEXT NOT NULL REFERENCES reviews(id) ON DELETE CASCADE,
      by_id         TEXT NOT NULL,
      by_name       TEXT NOT NULL DEFAULT '',
      by_handle     TEXT NOT NULL DEFAULT '',
      by_avatar_url TEXT,
      text          TEXT NOT NULL,
      likes         INTEGER NOT NULL DEFAULT 0,
      liked_by      JSONB NOT NULL DEFAULT '[]',
      at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    CREATE INDEX idx_review_comments_review ON review_comments(review_id, at ASC);
  END IF;
END $$;

-- Watchlist invites 
CREATE TABLE IF NOT EXISTS watchlist_invites (
  id           TEXT PRIMARY KEY,
  watchlist_id TEXT NOT NULL REFERENCES watchlists(id) ON DELETE CASCADE,
  inviter_id   TEXT NOT NULL,
  invitee_id   TEXT NOT NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(watchlist_id, invitee_id)
);
CREATE INDEX IF NOT EXISTS idx_invites_invitee ON watchlist_invites(invitee_id);

-- Friend requests 
CREATE TABLE IF NOT EXISTS friend_requests (
  id         TEXT PRIMARY KEY,
  from_id    TEXT NOT NULL,
  to_id      TEXT NOT NULL,
  status     TEXT NOT NULL DEFAULT 'pending',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_fr_to_id ON friend_requests(to_id, status);

-- Veto sessions 
CREATE TABLE IF NOT EXISTS veto_sessions (
  watchlist_id TEXT PRIMARY KEY,
  data         JSONB NOT NULL,
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- PG catalog
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE TABLE IF NOT EXISTS media (
  id          TEXT PRIMARY KEY,
  title       TEXT NOT NULL,
  year        INTEGER NOT NULL DEFAULT 0,
  runtime     INTEGER NOT NULL DEFAULT 0, -- minutes
  rating      REAL    NOT NULL DEFAULT 0,
  genres      JSONB   NOT NULL DEFAULT '[]',
  director    TEXT    NOT NULL DEFAULT '',
  synopsis    TEXT    NOT NULL DEFAULT '',
  poster_url  TEXT,
  media_type  TEXT    NOT NULL DEFAULT 'movie',
  has_details BOOLEAN NOT NULL DEFAULT FALSE,
  cached_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name='media' AND column_name='media_type') THEN
    ALTER TABLE media ADD COLUMN media_type TEXT NOT NULL DEFAULT 'movie';
  END IF;
END $$;
CREATE INDEX IF NOT EXISTS idx_media_title_trgm ON media USING gin(title gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_media_genres     ON media USING gin(genres);
CREATE INDEX IF NOT EXISTS idx_media_stubs      ON media(has_details) WHERE has_details = FALSE;

-- Banner URLs per user
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name='users' AND column_name='banner_urls') THEN
    ALTER TABLE users ADD COLUMN banner_urls JSONB NOT NULL DEFAULT '[]'::jsonb;
  END IF;
END $$;

-- Migrate
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'movie_catalog') AND
     NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'media') THEN
    ALTER TABLE movie_catalog RENAME TO media;
    ALTER INDEX IF EXISTS idx_catalog_title_trgm RENAME TO idx_media_title_trgm;
    ALTER INDEX IF EXISTS idx_catalog_genres     RENAME TO idx_media_genres;
    ALTER INDEX IF EXISTS idx_catalog_stubs      RENAME TO idx_media_stubs;
  END IF;
END $$;

-- One-time cleanup: remove pornographic content from catalog
-- Instant no-op on subsequent runs once rows are deleted
DELETE FROM media
WHERE EXISTS (
    SELECT 1 FROM jsonb_array_elements_text(genres) g
    WHERE lower(g) = 'adult'
);


-- Séance: one active session per watchlist
CREATE TABLE IF NOT EXISTS seance_sessions (
  watchlist_id   TEXT PRIMARY KEY REFERENCES watchlists(id) ON DELETE CASCADE,
  host_id        TEXT NOT NULL,
  host_name      TEXT NOT NULL DEFAULT '',
  host_avatar_url TEXT,
  livekit_room   TEXT NOT NULL,
  started_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
