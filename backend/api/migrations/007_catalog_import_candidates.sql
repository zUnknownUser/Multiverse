-- Private review inbox. Public catalog queries never join this table.
-- An individual issue must not replace a story arc, series or collected edition.
CREATE TABLE catalog_import_candidates (
  provider text NOT NULL CHECK (provider IN ('tmdb','metron')),
  external_id varchar(80) NOT NULL,
  universe_id varchar(80) NOT NULL REFERENCES catalog_universes(id) CHECK (universe_id='marvel'),
  suggested_item_id varchar(80) NOT NULL,
  kind text NOT NULL CHECK (kind IN ('movie','tv','issue')),
  source_url text NOT NULL,
  attribution jsonb NOT NULL CHECK (jsonb_typeof(attribution)='object'),
  metadata jsonb NOT NULL CHECK (jsonb_typeof(metadata)='object'),
  fetched_at timestamptz NOT NULL,
  PRIMARY KEY(provider,external_id),
  CHECK ((provider='metron' AND kind='issue') OR (provider='tmdb' AND kind IN ('movie','tv')))
);
