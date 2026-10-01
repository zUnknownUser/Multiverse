-- Provider metadata is separate from editorial copy and user activity.
CREATE TABLE catalog_sources (
  provider text NOT NULL CHECK (provider IN ('wikidata')),
  external_id varchar(80) NOT NULL,
  item_id varchar(80) NOT NULL REFERENCES catalog_items(id),
  source_url text NOT NULL,
  revision bigint NOT NULL,
  metadata jsonb NOT NULL,
  fetched_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(provider,external_id),
  UNIQUE(provider,item_id)
);
CREATE INDEX catalog_sources_item_idx ON catalog_sources(item_id);
