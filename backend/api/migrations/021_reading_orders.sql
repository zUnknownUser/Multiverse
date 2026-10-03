-- Editorial journeys, not imported demo engagement or a claimed complete chronology.
CREATE TABLE reading_orders (
 id varchar(80) PRIMARY KEY CHECK(id ~ '^[a-z0-9-]+$'),
 universe_id varchar(80) NOT NULL REFERENCES catalog_universes(id),
 status text NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','published','archived')),
 sort_order integer NOT NULL DEFAULT 0
);
CREATE TABLE reading_order_translations (
 order_id varchar(80) NOT NULL REFERENCES reading_orders(id) ON DELETE CASCADE,
 locale text NOT NULL CHECK(locale IN ('pt-BR','en')),
 title text NOT NULL CHECK(char_length(title) BETWEEN 1 AND 120),
 description text NOT NULL CHECK(char_length(description) BETWEEN 1 AND 1500),
 PRIMARY KEY(order_id,locale)
);
CREATE TABLE reading_order_steps (
 order_id varchar(80) NOT NULL REFERENCES reading_orders(id) ON DELETE CASCADE,
 position integer NOT NULL CHECK(position BETWEEN 1 AND 200),
 item_id varchar(80) NOT NULL REFERENCES catalog_items(id),
 PRIMARY KEY(order_id,position), UNIQUE(order_id,item_id)
);
CREATE TABLE reading_order_state (
 firebase_uid varchar(128) PRIMARY KEY REFERENCES profiles(firebase_uid) ON DELETE CASCADE,
 version integer NOT NULL DEFAULT 0 CHECK(version>=0)
);
CREATE TABLE reading_order_marks (
 firebase_uid varchar(128) NOT NULL REFERENCES profiles(firebase_uid) ON DELETE CASCADE,
 order_id varchar(80) NOT NULL REFERENCES reading_orders(id) ON DELETE CASCADE,
 following boolean NOT NULL DEFAULT false,
 voted boolean NOT NULL DEFAULT false,
 PRIMARY KEY(firebase_uid,order_id)
);
CREATE INDEX reading_order_marks_counts ON reading_order_marks(order_id);
CREATE TABLE reading_order_mutations (
 firebase_uid varchar(128) NOT NULL REFERENCES profiles(firebase_uid) ON DELETE CASCADE,
 id uuid NOT NULL,
 request jsonb NOT NULL,
 applied_version integer NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(firebase_uid,id)
);
CREATE INDEX reading_order_mutations_budget ON reading_order_mutations(firebase_uid,created_at);
INSERT INTO reading_orders(id,universe_id,status,sort_order) VALUES
 ('marvel-event-highlights','marvel','published',1),
 ('dc-crises-and-restarts','dc','published',2),
 ('dc-hero-perspectives','dc','published',3);
INSERT INTO reading_order_translations(order_id,locale,title,description) VALUES
 ('marvel-event-highlights','pt-BR','Marvel: três grandes histórias','Percurso editorial por três HQs do catálogo, na ordem de publicação: A Saga da Fênix Negra, Guerra Civil e Guerras Secretas (2015). Leia a história principal de cada etapa. É uma seleção de obras, não a cronologia completa da Marvel nem uma lista de todos os capítulos e especiais.'),
 ('marvel-event-highlights','en','Marvel: three major stories','An editorial journey through three comics in the catalog, in publication order: The Dark Phoenix Saga, Civil War and Secret Wars (2015). Read the main story at each step. This is a selection of works, not the complete Marvel chronology or every issue and tie-in.'),
 ('dc-crises-and-restarts','pt-BR','DC: crises e recomeços','Comece pela história principal de Crise nas Infinitas Terras e depois leia Flashpoint. Este recorte editorial segue a ordem de publicação de dois eventos do catálogo. Há outras histórias entre eles; este percurso não apresenta Flashpoint como continuação direta nem inclui todos os especiais.'),
 ('dc-crises-and-restarts','en','DC: crises and fresh starts','Start with the main story of Crisis on Infinite Earths, then read Flashpoint. This editorial selection follows the publication order of two events in the catalog. Other stories occur between them; this journey does not present Flashpoint as a direct sequel or include every tie-in.'),
 ('dc-hero-perspectives','pt-BR','DC: outras visões dos heróis','Leia Watchmen e depois Reino do Amanhã para conhecer duas abordagens diferentes dos super-heróis. São histórias independentes, em realidades distintas. A sequência é uma sugestão editorial, não uma cronologia compartilhada.'),
 ('dc-hero-perspectives','en','DC: different views of heroes','Read Watchmen, then Kingdom Come to explore two different approaches to superheroes. These are independent stories in different realities. The sequence is an editorial suggestion, not a shared chronology.');
INSERT INTO reading_order_steps(order_id,position,item_id) VALUES
 ('marvel-event-highlights',1,'m-fenix'),('marvel-event-highlights',2,'m-civil'),('marvel-event-highlights',3,'m-secret'),
 ('dc-crises-and-restarts',1,'d-crise'),('dc-crises-and-restarts',2,'d-flash'),
 ('dc-hero-perspectives',1,'d-watchmen'),('dc-hero-perspectives',2,'d-reino');
