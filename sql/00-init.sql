DO $$
BEGIN
  CREATE ROLE guthenberg WITH LOGIN PASSWORD 'secret';
  EXCEPTION WHEN DUPLICATE_OBJECT THEN
  RAISE NOTICE 'Not creating role ''guthenberg'' -- it already exists';
END
$$;

-- CREATE DATABASE documents OWNER guthenberg;
