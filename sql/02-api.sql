-- help from https://tapoueh.org/blog/2018/07/postgresql-listen/notify/
-- CREATE OR REPLACE FUNCTION tg_notify_documents()
--  RETURNS TRIGGER
-- AS $$
-- BEGIN
--   PERFORM pg_notify('documents', json_build_object('operation', TG_OP, 'record', row_to_json(NEW))::text);
--   RETURN NEW;
-- END;
-- $$ LANGUAGE plpgsql;

-- Trigger notification for messaging to PG Notify
CREATE FUNCTION notify_trigger() RETURNS trigger AS $trigger$
DECLARE
  rec RECORD;
  payload TEXT;
  column_name TEXT;
  column_value TEXT;
  payload_items TEXT[];
BEGIN
  -- Set record row depending on operation
  CASE TG_OP
  WHEN 'INSERT', 'UPDATE' THEN
     rec := NEW;
  WHEN 'DELETE' THEN
     rec := OLD;
  ELSE
     RAISE EXCEPTION 'Unknown TG_OP: "%". Should not occur!', TG_OP;
  END CASE;

  -- Get required fields
  FOREACH column_name IN ARRAY TG_ARGV LOOP
    EXECUTE format('SELECT $1.%I::TEXT', column_name)
    INTO column_value
    USING rec;
    payload_items := array_append(payload_items, '"' || replace(column_name, '"', '\"') || '":"' || replace(column_value, '"', '\"') || '"');
  END LOOP;

  -- Build the payload
  payload := ''
              || '{'
              || '"timestamp":"' || CURRENT_TIMESTAMP                    || '",'
              || '"operation":"' || TG_OP                                || '",'
              || '"schema":"'    || TG_TABLE_SCHEMA                      || '",'
              || '"table":"'     || TG_TABLE_NAME                        || '",'
              || '"data":{'      || array_to_string(payload_items, ',')  || '}'
              || '}';

  -- Notify the channel
  PERFORM pg_notify('documents', payload);

  RETURN rec;
END;
$trigger$ LANGUAGE plpgsql;

CREATE TRIGGER documents_notify
AFTER INSERT OR UPDATE ON main.documents
FOR EACH ROW
EXECUTE PROCEDURE notify_trigger('id', 'title');

CREATE TYPE return_author_type AS (
    id          UUID
  , fullname    VARCHAR(256)
  , resource    VARCHAR(256)
);

CREATE OR REPLACE FUNCTION main.create_author (
    TEXT -- fullname       (1)
  , TEXT -- resource       (2)
) RETURNS return_author_type
AS $$
DECLARE
  res return_author_type;
BEGIN

  INSERT INTO main.authors (fullname, resource) VALUES (
    $1, -- fullname
    $2  -- resource
  )
  ON CONFLICT ("fullname") DO
    UPDATE
    SET resource = EXCLUDED.resource
    RETURNING id, fullname, resource INTO res;
  RETURN res;
END;
$$
LANGUAGE PLPGSQL;

CREATE TYPE return_image_type AS (
    id               UUID
  , title            VARCHAR(256)
  , author_id        VARCHAR(256)
  , author_fullname  VARCHAR(256)
  , author_resource  VARCHAR(256)
  , resource         VARCHAR(256)
);

CREATE OR REPLACE FUNCTION main.create_image (
    TEXT -- title               (1)
  , TEXT -- author fullname     (2)
  , TEXT -- author resource     (3)
  , TEXT -- resource            (4)
) RETURNS return_image_type
AS $$
DECLARE
  author return_author_type;
  res return_image_type;
BEGIN

  SELECT * FROM main.create_author($2, $3) INTO author;
  INSERT INTO main.images (title, author, resource) VALUES (
      $1          -- title
    , author.id   -- author id
    , $4          -- resource
  )
  ON CONFLICT ("title") DO
    UPDATE
    SET author = EXCLUDED.author
      , resource = EXCLUDED.resource
    RETURNING id, title, author.id, author.fullname, author.resource, resource INTO res;
  RETURN res;
END;
$$
LANGUAGE PLPGSQL;

-- Note this return type implies, like the rest of the schema so far,
-- that there is only one author.
CREATE TYPE return_document_type AS (
    id                        UUID             -- (0)
  , title                     VARCHAR(256)     -- (1)
  , abstract                  TEXT             -- (2)
  , document_author_id        UUID             -- (3)
  , document_author_fullname  VARCHAR(256)     -- (4)
  , document_author_resource  VARCHAR(256)     -- (5)
  , content                   TEXT             -- (6)
  , tags                      TEXT[]           -- (7)
  , image_id                  UUID             -- (8)
  , image_title               VARCHAR(256)     -- (9)
  , image_author_id           UUID             -- (10)
  , image_author_fullname     VARCHAR(256)     -- (11)
  , image_author_resource     VARCHAR(256)     -- (12)
  , image_resource            VARCHAR(256)     -- (13)
  , kind                      main.KIND        -- (14)
  , genre                     main.GENRE       -- (15)
  , created_at                TIMESTAMPTZ      -- (16)
  , updated_at                TIMESTAMPTZ      -- (17)
);

-- This is the same as return_document_type, except it does not
-- have the content of the document. This is more suitable for
-- listing documents.
CREATE TYPE return_short_document_type AS (
    id                        UUID             -- (0)
  , title                     VARCHAR(256)     -- (1)
  , abstract                  TEXT             -- (2)
  , document_author_id        UUID             -- (3)
  , document_author_fullname  VARCHAR(256)     -- (4)
  , document_author_resource  VARCHAR(256)     -- (5)
  , tags                      TEXT[]           -- (6)
  , image_id                  UUID             -- (7)
  , image_title               VARCHAR(256)     -- (8)
  , image_author_id           UUID             -- (9)
  , image_author_fullname     VARCHAR(256)     -- (10)
  , image_author_resource     VARCHAR(256)     -- (11)
  , image_resource            VARCHAR(256)     -- (12)
  , kind                      main.KIND        -- (13)
  , genre                     main.GENRE       -- (14)
  , created_at                TIMESTAMPTZ      -- (15)
  , updated_at                TIMESTAMPTZ      -- (16)
);

CREATE OR REPLACE FUNCTION main.create_document_with_id(
    UUID       -- id                        (1)
  , TEXT       -- title                     (2)
  , TEXT       -- abstract                  (3)
  , TEXT       -- document_author_fullname  (4)
  , TEXT       -- document_author_resource  (5)
  , TEXT       -- content                   (6)
  , TEXT[]     -- tags                      (7)
  , TEXT       -- image_title               (8)
  , TEXT       -- image_author_fullname     (9)
  , TEXT       -- image_author_resource     (10)
  , TEXT       -- image_resource            (11)
  , main.KIND  -- kind                      (12)
  , main.GENRE -- genre                     (13)
) RETURNS return_document_type
AS $$
DECLARE
  image  return_image_type;
  author return_author_type;
  res return_document_type;
BEGIN

  SELECT * FROM main.create_author($4, $5) INTO author;
  SELECT * FROM main.create_image($8, $9, $10, $11) INTO image;
  INSERT INTO main.documents (id, title, abstract, author, content, tags, image, kind, genre) VALUES (
      $1
    , $2
    , $3
    , author.id
    , $6
    , $7
    , image.id
    , $12
    , $13
  )
  ON CONFLICT ("id") DO
    UPDATE
    SET title = EXCLUDED.title
      , abstract = EXCLUDED.abstract
      , author = EXCLUDED.author
      , content = EXCLUDED.content
      , tags = EXCLUDED.tags
      , image = EXCLUDED.image
      , kind = EXCLUDED.kind
      , genre = EXCLUDED.genre
    RETURNING id, title, abstract, author.id, author.fullname, author.resource , content, tags
    , image.id, image.title, image.author_id, image.author_fullname, image.author_resource, image.resource
    , kind, genre, created_at, updated_at INTO res;
  RETURN res;
END;
$$
LANGUAGE PLPGSQL;

-- This function returns a list of shorten documents (meaning no content), suitable
-- for printing in a list.
CREATE OR REPLACE FUNCTION main.list_documents(
  main.KIND  -- kind  (1)
) RETURNS SETOF return_short_document_type
AS $$
BEGIN
  RETURN QUERY
  SELECT d.id, d.title, d.abstract, da.id, da.fullname, da.resource, d.tags,
         i.id, i.title, ia.id, ia.fullname, ia.resource, i.resource, d.kind, d.genre,
         d.created_at, d.updated_at
  FROM main.documents AS d
  INNER JOIN main.authors AS da ON da.id = d.author
  INNER JOIN main.images AS i ON i.id = d.image
  INNER JOIN main.authors AS ia ON ia.id = i.author
  WHERE kind = $1;
END;
$$
LANGUAGE plpgsql;

-- Return the document and its content
CREATE OR REPLACE FUNCTION main.get_document_by_id(
  UUID       -- uuid  (1)
) RETURNS return_document_type
AS $$
DECLARE
  res return_document_type;
BEGIN
  SELECT d.id, d.title, d.abstract, da.id, da.fullname, da.resource, d.content, d.tags,
         i.id, i.title, ia.id, ia.fullname, ia.resource, i.resource, d.kind, d.genre,
         d.created_at, d.updated_at
  FROM main.documents AS d
  INNER JOIN main.authors AS da ON da.id = d.author
  INNER JOIN main.images AS i ON i.id = d.image
  INNER JOIN main.authors AS ia ON ia.id = i.author
  WHERE d.id = $1
  INTO res;
  RETURN res;
END;
$$
LANGUAGE plpgsql;

-- This function returns a list of shorten documents (meaning no content), suitable
-- for printing in a list.
CREATE OR REPLACE FUNCTION main.search_documents_by_query(
  TEXT  -- query  (1)
) RETURNS SETOF return_short_document_type
AS $$
BEGIN
  RETURN QUERY
  SELECT d.id, d.title, d.abstract, da.id, da.fullname, da.resource, d.tags,
         i.id, i.title, ia.id, ia.fullname, ia.resource, i.resource, d.kind, d.genre,
         d.created_at, d.updated_at
  FROM main.authors AS da
  INNER JOIN (
    SELECT d.id, d.title, d.abstract, d.author, d.image, d.tags,
           d.kind, d.genre, d.created_at, d.updated_at
    FROM main.documents AS d,
         websearch_to_tsquery($1) AS query
    WHERE query @@ d.search
    ORDER BY ts_rank(d.search, query) DESC
  ) d ON d.author = da.id
  INNER JOIN main.images AS i ON i.id = d.image
  INNER JOIN main.authors AS ia ON ia.id = i.author;
END;
$$
LANGUAGE plpgsql;

-- This function returns a list of shorten documents (meaning no content), suitable
-- for printing in a list.
CREATE OR REPLACE FUNCTION main.search_documents_by_tag(
  TEXT  -- tag  (1)
) RETURNS SETOF return_short_document_type
AS $$
BEGIN
  RETURN QUERY
  SELECT d.id, d.title, d.abstract, da.id, da.fullname, da.resource, d.tags,
         i.id, i.title, ia.id, ia.fullname, ia.resource, i.resource, d.kind, d.genre,
         d.created_at, d.updated_at
  FROM main.authors AS da
  INNER JOIN (
    SELECT d.id, d.title, d.abstract, d.author, d.image, d.tags,
           d.kind, d.genre, d.created_at, d.updated_at
    FROM main.documents AS d
    WHERE d.tags @> array[$1]
    ORDER BY d.updated_at DESC
  ) d ON d.author = da.id
  INNER JOIN main.images AS i ON i.id = d.image
  INNER JOIN main.authors AS ia ON ia.id = i.author;
END;
$$
LANGUAGE plpgsql;
