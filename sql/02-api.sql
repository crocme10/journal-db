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
    id                        UUID
  , title                     VARCHAR(256)
  , abstract                  TEXT
  , document_author_id        VARCHAR(256)
  , document_author_fullname  VARCHAR(256)
  , document_author_resource  VARCHAR(256)
  , content                   TEXT
  , tags                      TEXT[]
  , image_id                  UUID
  , image_title               VARCHAR(256)
  , image_author_id           UUID
  , image_author_fullname     VARCHAR(256)
  , image_author_resource     VARCHAR(256)
  , image_resource            VARCHAR(256)
  , kind                      main.KIND
  , genre                     main.GENRE
  , created_at                TIMESTAMPTZ
  , updated_at                TIMESTAMPTZ
);

-- This is the same as return_document_type, except it does not
-- have the content of the document. This is more suitable for
-- listing documents.
CREATE TYPE return_short_document_type AS (
    id                        UUID
  , title                     VARCHAR(256)
  , abstract                  TEXT
  , document_author_id        UUID
  , document_author_fullname  VARCHAR(256)
  , document_author_resource  VARCHAR(256)
  , tags                      TEXT[]
  , image_id                  UUID
  , image_title               VARCHAR(256)
  , image_author_id           UUID
  , image_author_fullname     VARCHAR(256)
  , image_author_resource     VARCHAR(256)
  , image_resource            VARCHAR(256)
  , kind                      main.KIND
  , genre                     main.GENRE
  , created_at                TIMESTAMPTZ
  , updated_at                TIMESTAMPTZ
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

CREATE OR REPLACE FUNCTION main.list_documents(
  main.KIND  -- kind  (1)
) RETURNS SETOF return_short_document_type
AS $$
BEGIN
  RETURN QUERY
  SELECT d.id, d.title, d.abstract, da.id, da.fullname, da.resource, d.tags,
         ia.id, ia.fullname, ia.resource, i.resource, d.kind, d.genre,
         d.created_at, d.updated_at
  FROM main.documents AS d
  INNER JOIN main.authors AS da ON da.id = d.author
  INNER JOIN main.images AS i ON i.id = d.image
  INNER JOIN main.authors AS ia ON ia.id = i.author
  WHERE kind = $1;
END;
$$
LANGUAGE plpgsql;

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

-- BEGIN
--   RETURN QUERY
--   SELECT d.id, d.title, d.abstract, a.fullname, d.tags, d.image, d.kind, d.genre, d.updated_at, ''
--   FROM documents AS d
--   INNER JOIN authors AS a ON a.id = d.author
--   WHERE d.kind = $1
--   ORDER BY d.updated_at DESC;
-- END;
-- $$
-- LANGUAGE plpgsql;
-- 
-- -- DROP FUNCTION document_details(uuid);
-- CREATE OR REPLACE FUNCTION document_details(
--     INOUT _id UUID
--   , OUT _title TEXT
--   , OUT _abstract TEXT
--   , OUT _author TEXT
--   , OUT _tags TEXT[]
--   , OUT _image TEXT
--   , OUT _kind kind
--   , OUT _genre genre
--   , OUT _updated_at TIMESTAMPTZ
--   , OUT _content TEXT)
-- AS $$
-- BEGIN
--   SELECT title,  abstract,  author,  tags,  image,  kind,  genre,  updated_at, content
--   INTO  _title, _abstract, _author, _tags, _image, _kind, _genre, _updated_at, _content
--   FROM documents WHERE id = _id;
-- END;
-- $$
-- LANGUAGE plpgsql;
-- -- This function returns a bit of information about each document, suitable
-- -- to be printed in a list. Basically, everything, but the content.
-- -- So that the calling function does not create a separate type, we actually
-- -- return an empty content
-- -- This function returns a bit of information about each document,
-- -- using a string to filter documents based on full text search.
-- CREATE OR REPLACE FUNCTION document_search(
--   TEXT -- query
-- )
-- RETURNS TABLE (_id UUID,
--   _title VARCHAR(256),
--   _abstract TEXT,
--   _author VARCHAR(256),
--   _tags TEXT[],
--   _image VARCHAR(256),
--   _kind kind,
--   _genre genre,
--   _updated_at TIMESTAMPTZ)
-- AS $$
-- BEGIN
--   RETURN QUERY
--   SELECT k.id, k.title, k.abstract, a.fullname, k.tags, k.image, k.kind, k.genre, k.updated_at
--   FROM authors AS a
--   INNER JOIN (
--     SELECT d.id, d.title, d.author, d.abstract, d.tags, d.image, d.kind, d.genre, d.updated_at
--     FROM documents AS d, websearch_to_tsquery($1) AS query
--     WHERE query @@ d.search
--     ORDER BY ts_rank(d.search, query) DESC
--   ) k ON a.id = k.author;
-- END;
-- $$
-- LANGUAGE plpgsql;
-- -- Search by tag
-- -- This function returns a bit of information about each document, suitable
-- -- to be printed in a list.
-- -- DROP FUNCTION document_list(kind);
-- CREATE OR REPLACE FUNCTION document_tag(kind, text)
-- RETURNS TABLE (_id UUID,
--   _title VARCHAR(256),
--   _abstract TEXT,
--   _author VARCHAR(256),
--   _tags TEXT[],
--   _image VARCHAR(256),
--   _kind kind,
--   _genre genre,
--   _updated_at TIMESTAMPTZ)
-- AS $$
-- BEGIN
--   RETURN QUERY
--   SELECT d.id, d.title, d.abstract, a.fullname, d.tags, d.image, d.kind, d.genre, d.updated_at
--   FROM documents AS d
--   INNER JOIN authors AS a ON a.id = d.author
--   WHERE d.kind = $1
--     AND d.tags @> array[$2]
--   ORDER BY d.updated_at DESC;
-- END;
-- $$
-- LANGUAGE plpgsql;
