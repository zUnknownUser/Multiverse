CREATE TABLE catalog_series (
  id varchar(80) PRIMARY KEY,
  universe_id varchar(80) NOT NULL REFERENCES catalog_universes(id),
  year integer NOT NULL CHECK(year BETWEEN 1900 AND 2100)
);
CREATE TABLE catalog_series_translations (
  series_id varchar(80) NOT NULL REFERENCES catalog_series(id) ON DELETE CASCADE,
  locale text NOT NULL CHECK(locale IN ('pt-BR','en')),
  title text NOT NULL CHECK(length(btrim(title)) BETWEEN 1 AND 300),
  PRIMARY KEY(series_id,locale)
);
CREATE TABLE catalog_series_items (
  item_id varchar(80) PRIMARY KEY REFERENCES catalog_items(id),
  series_id varchar(80) NOT NULL REFERENCES catalog_series(id),
  issue_number text NOT NULL CHECK(length(issue_number) BETWEEN 1 AND 30),
  position integer NOT NULL CHECK(position>0),
  UNIQUE(series_id,issue_number),
  UNIQUE(series_id,position)
);
