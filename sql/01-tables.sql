CREATE EXTENSION pg_trgm;
CREATE EXTENSION pgcrypto;
-- For aggregating tags
-- See https://stackoverflow.com/questions/31210790/indexing-an-array-for-full-text-search
--
CREATE OR REPLACE FUNCTION textarr2text(TEXT[])
  RETURNS TEXT LANGUAGE SQL IMMUTABLE AS $$SELECT array_to_string($1, ',')$$;

SET CLIENT_MIN_MESSAGES TO INFO;
SET CLIENT_ENCODING = 'UTF8';

DROP SCHEMA IF EXISTS main CASCADE;
CREATE SCHEMA main AUTHORIZATION guthenberg;
GRANT ALL ON SCHEMA main to guthenberg;
SET SEARCH_PATH = main;

CREATE TABLE main.authors (
  id UUID PRIMARY KEY DEFAULT public.gen_random_uuid(),
  fullname VARCHAR(256) NOT NULL UNIQUE,
  resource VARCHAR(256)
);

ALTER TABLE main.authors OWNER TO guthenberg;

CREATE TABLE main.images (
  id UUID PRIMARY KEY DEFAULT public.gen_random_uuid(),
  title VARCHAR(256) NOT NULL UNIQUE,
  author UUID REFERENCES main.authors(id),
  resource VARCHAR(256)
);

ALTER TABLE main.images OWNER TO guthenberg;

CREATE TYPE main.kind AS ENUM ('doc', 'post');

CREATE TYPE main.genre AS ENUM ('tutorial', 'howto', 'background', 'reference');

CREATE TABLE main.documents (
  id UUID PRIMARY KEY DEFAULT public.gen_random_uuid(),
  title VARCHAR(256) NOT NULL,
  abstract TEXT NOT NULL,
  author UUID REFERENCES main.authors(id),
  content TEXT NOT NULL,
  tags TEXT[] DEFAULT '{}',
  image UUID REFERENCES main.images(id),
  kind kind,
  genre genre,
  search TSVECTOR GENERATED ALWAYS AS (
    (
      setweight(to_tsvector('english', public.textarr2text(tags)), 'A') || ' ' ||
      setweight(to_tsvector('english', title), 'B') || ' ' ||
      setweight(to_tsvector('english', abstract), 'C') || ' ' ||
      setweight(to_tsvector('english', content), 'D')
    )::tsvector
  ) STORED,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE main.documents OWNER TO guthenberg;

CREATE INDEX doctags on main.documents USING GIN(tags);
