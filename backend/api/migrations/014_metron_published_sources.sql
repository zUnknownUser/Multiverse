ALTER TABLE catalog_sources DROP CONSTRAINT catalog_sources_provider_check;
ALTER TABLE catalog_sources ADD CONSTRAINT catalog_sources_provider_check
  CHECK (provider IN ('wikidata','tmdb','metron'));
