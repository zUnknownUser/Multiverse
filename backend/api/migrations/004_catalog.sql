-- Initial editorial catalog copied from the existing PT/EN resources.
-- Stable IDs preserve existing onboarding. Demo engagement numbers are not imported.
CREATE TABLE catalog_universes (
  id varchar(80) PRIMARY KEY CHECK (id ~ '^[a-z0-9-]+$'),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','coming_soon','archived')),
  color char(7) NOT NULL CHECK (color ~ '^#[0-9A-Fa-f]{6}$'),
  dark_color char(7) NOT NULL CHECK (dark_color ~ '^#[0-9A-Fa-f]{6}$'),
  ink_color char(7) NOT NULL CHECK (ink_color ~ '^#[0-9A-Fa-f]{6}$'),
  track text NOT NULL,
  sort_order integer NOT NULL DEFAULT 0
);
CREATE TABLE catalog_universe_translations (
  universe_id varchar(80) NOT NULL REFERENCES catalog_universes(id) ON DELETE CASCADE,
  locale text NOT NULL CHECK (locale IN ('pt-BR','en')),
  name text NOT NULL CHECK (length(btrim(name)) > 0),
  canon text NOT NULL DEFAULT '',
  tagline text NOT NULL DEFAULT '',
  PRIMARY KEY (universe_id,locale)
);
CREATE TABLE catalog_items (
  id varchar(80) PRIMARY KEY CHECK (id ~ '^[a-z0-9-]+$'),
  universe_id varchar(80) NOT NULL REFERENCES catalog_universes(id),
  type text NOT NULL CHECK (type IN ('HQ','Filme','Série','Jogo','Livro','Personagem','Evento')),
  status text NOT NULL DEFAULT 'published' CHECK (status IN ('published','archived')),
  sort_order integer NOT NULL DEFAULT 0
);
CREATE INDEX catalog_items_universe_idx ON catalog_items(universe_id,status,sort_order);
CREATE TABLE catalog_item_translations (
  item_id varchar(80) NOT NULL REFERENCES catalog_items(id) ON DELETE CASCADE,
  locale text NOT NULL CHECK (locale IN ('pt-BR','en')),
  title text NOT NULL CHECK (length(btrim(title)) > 0),
  year text NOT NULL,
  canon text NOT NULL DEFAULT '',
  description text NOT NULL DEFAULT '',
  PRIMARY KEY (item_id,locale)
);
INSERT INTO catalog_universes (id,color,dark_color,ink_color,track,sort_order) VALUES ('marvel','#E4412F','#C9362A','#FFFDF8','rgba(255,253,248,.35)','0');
INSERT INTO catalog_universes (id,color,dark_color,ink_color,track,sort_order) VALUES ('dc','#2E5BE8','#2349C4','#FFFDF8','rgba(255,253,248,.35)','1');
INSERT INTO catalog_universes (id,color,dark_color,ink_color,track,sort_order) VALUES ('wow','#F4A814','#D99210','#16130F','rgba(22,19,15,.2)','2');
INSERT INTO catalog_universes (id,status,color,dark_color,ink_color,track,sort_order) VALUES ('star-wars','coming_soon','#16130F','#16130F','#FFFDF8','rgba(255,253,248,.35)','3');
INSERT INTO catalog_universe_translations (universe_id,locale,name) VALUES ('star-wars','pt-BR','Star Wars');
INSERT INTO catalog_universe_translations (universe_id,locale,name) VALUES ('star-wars','en','Star Wars');
INSERT INTO catalog_universes (id,status,color,dark_color,ink_color,track,sort_order) VALUES ('league-of-legends','coming_soon','#16130F','#16130F','#FFFDF8','rgba(255,253,248,.35)','4');
INSERT INTO catalog_universe_translations (universe_id,locale,name) VALUES ('league-of-legends','pt-BR','League of Legends');
INSERT INTO catalog_universe_translations (universe_id,locale,name) VALUES ('league-of-legends','en','League of Legends');
INSERT INTO catalog_universes (id,status,color,dark_color,ink_color,track,sort_order) VALUES ('tolkien','coming_soon','#16130F','#16130F','#FFFDF8','rgba(255,253,248,.35)','5');
INSERT INTO catalog_universe_translations (universe_id,locale,name) VALUES ('tolkien','pt-BR','Tolkien');
INSERT INTO catalog_universe_translations (universe_id,locale,name) VALUES ('tolkien','en','Tolkien');
INSERT INTO catalog_items (id,universe_id,type,sort_order) VALUES ('m-civil','marvel','HQ','0');
INSERT INTO catalog_items (id,universe_id,type,sort_order) VALUES ('m-ultimato','marvel','Filme','1');
INSERT INTO catalog_items (id,universe_id,type,sort_order) VALUES ('m-secret','marvel','HQ','2');
INSERT INTO catalog_items (id,universe_id,type,sort_order) VALUES ('m-fenix','marvel','HQ','3');
INSERT INTO catalog_items (id,universe_id,type,sort_order) VALUES ('m-aranha','marvel','Filme','4');
INSERT INTO catalog_items (id,universe_id,type,sort_order) VALUES ('m-loki','marvel','Série','5');
INSERT INTO catalog_items (id,universe_id,type,sort_order) VALUES ('d-crise','dc','HQ','6');
INSERT INTO catalog_items (id,universe_id,type,sort_order) VALUES ('d-watchmen','dc','HQ','7');
INSERT INTO catalog_items (id,universe_id,type,sort_order) VALUES ('d-tdk','dc','Filme','8');
INSERT INTO catalog_items (id,universe_id,type,sort_order) VALUES ('d-reino','dc','HQ','9');
INSERT INTO catalog_items (id,universe_id,type,sort_order) VALUES ('d-flash','dc','HQ','10');
INSERT INTO catalog_items (id,universe_id,type,sort_order) VALUES ('d-injustice','dc','Jogo','11');
INSERT INTO catalog_items (id,universe_id,type,sort_order) VALUES ('w-wc3','wow','Jogo','12');
INSERT INTO catalog_items (id,universe_id,type,sort_order) VALUES ('w-wotlk','wow','Jogo','13');
INSERT INTO catalog_items (id,universe_id,type,sort_order) VALUES ('w-cata','wow','Jogo','14');
INSERT INTO catalog_items (id,universe_id,type,sort_order) VALUES ('w-arthas','wow','Livro','15');
INSERT INTO catalog_items (id,universe_id,type,sort_order) VALUES ('w-wcfilme','wow','Filme','16');
INSERT INTO catalog_items (id,universe_id,type,sort_order) VALUES ('w-crimes','wow','Livro','17');
INSERT INTO catalog_items (id,universe_id,type,sort_order) VALUES ('c-arthas','wow','Personagem','18');
INSERT INTO catalog_items (id,universe_id,type,sort_order) VALUES ('c-thrall','wow','Personagem','19');
INSERT INTO catalog_items (id,universe_id,type,sort_order) VALUES ('c-sylvanas','wow','Personagem','20');
INSERT INTO catalog_items (id,universe_id,type,sort_order) VALUES ('c-wanda','marvel','Personagem','21');
INSERT INTO catalog_items (id,universe_id,type,sort_order) VALUES ('c-thanos','marvel','Personagem','22');
INSERT INTO catalog_items (id,universe_id,type,sort_order) VALUES ('c-loki','marvel','Personagem','23');
INSERT INTO catalog_items (id,universe_id,type,sort_order) VALUES ('c-batman','dc','Personagem','24');
INSERT INTO catalog_items (id,universe_id,type,sort_order) VALUES ('c-coringa','dc','Personagem','25');
INSERT INTO catalog_items (id,universe_id,type,sort_order) VALUES ('c-barry','dc','Personagem','26');
INSERT INTO catalog_items (id,universe_id,type,sort_order) VALUES ('e-estalo','marvel','Evento','27');
INSERT INTO catalog_items (id,universe_id,type,sort_order) VALUES ('e-lordaeron','wow','Evento','28');
INSERT INTO catalog_items (id,universe_id,type,sort_order) VALUES ('e-cataclismo','wow','Evento','29');
INSERT INTO catalog_items (id,universe_id,type,sort_order) VALUES ('e-superman','dc','Evento','30');
INSERT INTO catalog_universe_translations (universe_id,locale,name,canon,tagline) VALUES ('marvel','pt-BR','Marvel','Terra-616 + MCU','Seis décadas de HQs, um multiverso cinematográfico e variantes o suficiente pra enlouquecer a TVA.');
INSERT INTO catalog_universe_translations (universe_id,locale,name,canon,tagline) VALUES ('dc','pt-BR','DC','Pré e pós-Crise','Infinitas Terras, algumas Crises e um Batman pra cada geração.');
INSERT INTO catalog_universe_translations (universe_id,locale,name,canon,tagline) VALUES ('wow','pt-BR','Warcraft','Azeroth','Três décadas de guerras, expansões, livros e retcons. Pela Horda ou pela Aliança.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('m-civil','pt-BR','Guerra Civil','2006','Terra-616','A Lei de Registro de Super-Humanos divide os heróis entre Capitão América e Homem de Ferro.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('m-ultimato','pt-BR','Vingadores: Ultimato','2019','MCU','Cinco anos após o Estalo, os Vingadores restantes arriscam tudo num assalto através do tempo.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('m-secret','pt-BR','Guerras Secretas','2015','Multiverso','O multiverso colapsa e Doom remonta os destroços no Mundo Bélico.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('m-fenix','pt-BR','A Saga da Fênix Negra','1980','Terra-616','Jean Grey sucumbe à Força Fênix. A tragédia que ensinou os quadrinhos a ter consequência.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('m-aranha','pt-BR','Através do Aranhaverso','2023','Aranhaverso','Miles Morales atravessa o multiverso e descobre que eventos canônicos cobram um preço.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('m-loki','pt-BR','Loki','2021','MCU','Uma variante de Loki é capturada pela TVA, a burocracia que poda linhas do tempo.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('d-crise','pt-BR','Crise nas Infinitas Terras','1985','Pré-Crise','O Antimonitor devora universos. No fim sobra uma Terra, e o cânone da DC nunca mais foi o mesmo.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('d-watchmen','pt-BR','Watchmen','1986','Terra-Watchmen','Quem vigia os vigilantes? Um mistério de assassinato que desmonta o gênero de super-herói.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('d-tdk','pt-BR','O Cavaleiro das Trevas','2008','Trilogia Nolan','O Coringa leva Gotham ao limite e força Batman a escolher entre ser herói e ser necessário.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('d-reino','pt-BR','Reino do Amanhã','1996','Terra-22','Num futuro de heróis sem limites, Superman volta do exílio.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('d-flash','pt-BR','Flashpoint','2011','Pós-Crise → Novos 52','Barry Allen salva a mãe e acorda num mundo em guerra. O evento que reiniciou a DC.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('d-injustice','pt-BR','Injustice','2013','Terra-Injustice','Depois de perder Lois, Superman instala um regime.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('w-wc3','pt-BR','Warcraft III: Reign of Chaos','2002','Azeroth','O Flagelo se espalha, Arthas cai e a Legião Ardente chega. A base de quase tudo.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('w-wotlk','pt-BR','Wrath of the Lich King','2008','Azeroth','Horda e Aliança marcham até Nortúndria para enfrentar Arthas no Trono de Gelo.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('w-cata','pt-BR','Cataclysm','2010','Azeroth','Deathwing emerge e redesenha o mapa de Azeroth. O mundo antigo nunca mais volta.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('w-arthas','pt-BR','Arthas: A Ascensão do Lich King','2009','Azeroth','De príncipe de Lordaeron a Lich King: a queda contada de dentro.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('w-wcfilme','pt-BR','Warcraft: O Primeiro Encontro','2016','Adaptação','Orcs atravessam o Portal Negro e o primeiro contato vira guerra.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('w-crimes','pt-BR','Crimes de Guerra','2014','Azeroth','Garrosh Grito Infernal vai a julgamento. Todas as facções têm sangue nas mãos.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('c-arthas','pt-BR','Arthas Menethil','1ª ap. 2002','Azeroth','Príncipe paladino que empunhou Gélido Lamento e virou o Lich King.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('c-thrall','pt-BR','Thrall','1ª ap. 2002','Azeroth','Ex-escravo, xamã e fundador da Nova Horda.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('c-sylvanas','pt-BR','Sylvanas Correventos','1ª ap. 2002','Azeroth','Patrulheira, Rainha Banshee, Chefe Guerreira. A mais debatida da lore.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('c-wanda','pt-BR','Wanda Maximoff','1ª ap. 1964','Terra-616 + MCU','A Feiticeira Escarlate. Reescreveu a realidade mais de uma vez.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('c-thanos','pt-BR','Thanos','1ª ap. 1973','Terra-616 + MCU','O Titã Louco e sua obsessão pelo equilíbrio.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('c-loki','pt-BR','Loki','1ª ap. 1949','Terra-616 + MCU','Deus da trapaça, com mais variantes que qualquer outro personagem.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('c-batman','pt-BR','Batman','1ª ap. 1939','Todas as Terras','Bruce Wayne. Existe em praticamente todas as Terras do multiverso.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('c-coringa','pt-BR','Coringa','1ª ap. 1940','Todas as Terras','Nenhuma origem oficial. É assim que ele prefere.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('c-barry','pt-BR','Barry Allen','1ª ap. 1956','Pré e pós-Crise','O Flash que morreu na Crise, voltou e quebrou a linha do tempo.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('e-estalo','pt-BR','O Estalo','MCU · 2018','MCU','Thanos estala os dedos e metade da vida no universo desaparece.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('e-lordaeron','pt-BR','Queda de Lordaeron','Ano 21','Azeroth','Arthas mata o próprio pai e entrega o reino ao Flagelo.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('e-cataclismo','pt-BR','O Cataclismo','Ano 30','Azeroth','Deathwing rompe Azeroth. Terras afundam e regiões inteiras mudam pra sempre.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('e-superman','pt-BR','A Morte do Superman','Pós-Crise · 1992','Pós-Crise','Doomsday chega e o Superman cai em Metrópolis. Não por muito tempo.');
INSERT INTO catalog_universe_translations (universe_id,locale,name,canon,tagline) VALUES ('marvel','en','Marvel','Earth-616 + MCU','Six decades of comics, a cinematic multiverse, and enough variants to drive the TVA mad.');
INSERT INTO catalog_universe_translations (universe_id,locale,name,canon,tagline) VALUES ('dc','en','DC','Pre- and post-Crisis','Infinite Earths, a few Crises, and a Batman for every generation.');
INSERT INTO catalog_universe_translations (universe_id,locale,name,canon,tagline) VALUES ('wow','en','Warcraft','Azeroth','Three decades of wars, expansions, books, and retcons. For the Horde or the Alliance.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('m-civil','en','Civil War','2006','Earth-616','The Superhuman Registration Act divides heroes between Captain America and Iron Man.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('m-ultimato','en','Avengers: Endgame','2019','MCU','Five years after the Snap, the remaining Avengers risk everything on a heist through time.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('m-secret','en','Secret Wars','2015','Multiverse','The multiverse collapses, and Doom rebuilds the wreckage into Battleworld.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('m-fenix','en','The Dark Phoenix Saga','1980','Earth-616','Jean Grey succumbs to the Phoenix Force. The tragedy that taught comics about consequences.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('m-aranha','en','Spider-Man: Across the Spider-Verse','2023','Spider-Verse','Miles Morales travels across the multiverse and discovers that canon events come at a cost.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('m-loki','en','Loki','2021','MCU','A variant of Loki is captured by the TVA, the bureaucracy that prunes timelines.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('d-crise','en','Crisis on Infinite Earths','1985','Pre-Crisis','The Anti-Monitor devours universes. One Earth remains, and DC canon is never the same.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('d-watchmen','en','Watchmen','1986','Earth-Watchmen','Who watches the watchmen? A murder mystery that deconstructs the superhero genre.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('d-tdk','en','The Dark Knight','2008','Nolan trilogy','The Joker pushes Gotham to the brink and forces Batman to choose between being a hero and being necessary.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('d-reino','en','Kingdom Come','1996','Earth-22','In a future of heroes without limits, Superman returns from exile.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('d-flash','en','Flashpoint','2011','Post-Crisis → New 52','Barry Allen saves his mother and wakes up in a world at war. The event that rebooted DC.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('d-injustice','en','Injustice','2013','Earth-Injustice','After losing Lois, Superman establishes a regime.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('w-wc3','en','Warcraft III: Reign of Chaos','2002','Azeroth','The Scourge spreads, Arthas falls, and the Burning Legion arrives. The foundation of almost everything.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('w-wotlk','en','Wrath of the Lich King','2008','Azeroth','The Horde and Alliance march to Northrend to face Arthas on the Frozen Throne.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('w-cata','en','Cataclysm','2010','Azeroth','Deathwing emerges and redraws the map of Azeroth. The old world never returns.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('w-arthas','en','Arthas: Rise of the Lich King','2009','Azeroth','From prince of Lordaeron to Lich King: an inside view of the fall.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('w-wcfilme','en','Warcraft','2016','Adaptation','Orcs cross the Dark Portal, and first contact becomes war.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('w-crimes','en','War Crimes','2014','Azeroth','Garrosh Hellscream stands trial. Every faction has blood on its hands.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('c-arthas','en','Arthas Menethil','First app. 2002','Azeroth','The paladin prince who wielded Frostmourne and became the Lich King.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('c-thrall','en','Thrall','First app. 2002','Azeroth','Former slave, shaman, and founder of the New Horde.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('c-sylvanas','en','Sylvanas Windrunner','First app. 2002','Azeroth','Ranger, Banshee Queen, Warchief. The most debated figure in the lore.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('c-wanda','en','Wanda Maximoff','First app. 1964','Earth-616 + MCU','The Scarlet Witch. She''s rewritten reality more than once.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('c-thanos','en','Thanos','First app. 1973','Earth-616 + MCU','The Mad Titan and his obsession with balance.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('c-loki','en','Loki','First app. 1949','Earth-616 + MCU','The god of mischief, with more variants than any other character.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('c-batman','en','Batman','First app. 1939','All Earths','Bruce Wayne. He exists on almost every Earth in the multiverse.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('c-coringa','en','Joker','First app. 1940','All Earths','No official origin. That''s how he likes it.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('c-barry','en','Barry Allen','First app. 1956','Pre- and post-Crisis','The Flash who died in Crisis, returned, and broke the timeline.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('e-estalo','en','The Snap','MCU · 2018','MCU','Thanos snaps his fingers, and half of all life in the universe disappears.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('e-lordaeron','en','Fall of Lordaeron','Year 21','Azeroth','Arthas kills his own father and delivers the kingdom to the Scourge.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('e-cataclismo','en','The Cataclysm','Year 30','Azeroth','Deathwing shatters Azeroth. Lands sink, and entire regions change forever.');
INSERT INTO catalog_item_translations (item_id,locale,title,year,canon,description) VALUES ('e-superman','en','The Death of Superman','Post-Crisis · 1992','Post-Crisis','Doomsday arrives, and Superman falls in Metropolis. Not for long.');
