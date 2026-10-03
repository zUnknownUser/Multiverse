-- Artwork URLs fetched from the existing reviewed provider mappings on 2026-10-03.
-- Only enrich already-linked sources; never attach an issue cover to an aggregate arc.
-- No external API call at deployment. Future operational imports refresh posterURL.
WITH covers(provider, external_id, item_id, url) AS (VALUES
  ('tmdb', 'movie:299534', 'm-ultimato', 'https://image.tmdb.org/t/p/w500/ulzhLuWrPK07P1YkdWQLZnQh1JL.jpg'),
  ('tmdb', 'movie:569094', 'm-aranha', 'https://image.tmdb.org/t/p/w500/8Vt6mWEReuy4Of61Lnj5Xj704m8.jpg'),
  ('tmdb', 'tv:84958', 'm-loki', 'https://image.tmdb.org/t/p/w500/kEl2t3OhXc3Zb9FBh1AuYzRTgZp.jpg'),
  ('metron', 'issue:3726', 'm-metron-issue-3726', 'https://static.metron.cloud/media/issue/2019/07/14/civil-war-v1-1.jpg'),
  ('metron', 'issue:3727', 'm-metron-issue-3727', 'https://static.metron.cloud/media/issue/2019/07/14/civil-war-v1-2.jpg'),
  ('metron', 'issue:3728', 'm-metron-issue-3728', 'https://static.metron.cloud/media/issue/2019/07/14/civil-war-v1-3.jpg'),
  ('metron', 'issue:3729', 'm-metron-issue-3729', 'https://static.metron.cloud/media/issue/2019/07/14/civil-war-v1-4.jpg'),
  ('metron', 'issue:3730', 'm-metron-issue-3730', 'https://static.metron.cloud/media/issue/2019/07/14/civil-war-v1-5.jpg'),
  ('metron', 'issue:3731', 'm-metron-issue-3731', 'https://static.metron.cloud/media/issue/2019/07/14/civil-war-v1-6.jpg'),
  ('metron', 'issue:3732', 'm-metron-issue-3732', 'https://static.metron.cloud/media/issue/2019/07/15/civil-war-v1-7.jpg'),
  ('metron', 'issue:21884', 'm-metron-issue-21884', 'https://static.metron.cloud/media/issue/2020/12/28/house-m-1.jpg'),
  ('metron', 'issue:21885', 'm-metron-issue-21885', 'https://static.metron.cloud/media/issue/2020/12/28/house-m-2.jpg'),
  ('metron', 'issue:21886', 'm-metron-issue-21886', 'https://static.metron.cloud/media/issue/2020/12/28/house-m-3.jpg'),
  ('metron', 'issue:21887', 'm-metron-issue-21887', 'https://static.metron.cloud/media/issue/2020/12/28/house-m-4.jpg'),
  ('metron', 'issue:21888', 'm-metron-issue-21888', 'https://static.metron.cloud/media/issue/2020/12/28/house-m-5.jpg'),
  ('metron', 'issue:21889', 'm-metron-issue-21889', 'https://static.metron.cloud/media/issue/2020/12/28/house-m-6.jpg'),
  ('metron', 'issue:21890', 'm-metron-issue-21890', 'https://static.metron.cloud/media/issue/2020/12/28/house-m-7.jpg'),
  ('metron', 'issue:21891', 'm-metron-issue-21891', 'https://static.metron.cloud/media/issue/2020/12/28/house-m-8.jpg'),
  ('metron', 'issue:27065', 'm-metron-issue-27065', 'https://static.metron.cloud/media/issue/2021/03/11/secret-wars-1.jpg'),
  ('metron', 'issue:27066', 'm-metron-issue-27066', 'https://static.metron.cloud/media/issue/2021/03/11/secret-wars-2.jpg'),
  ('metron', 'issue:27067', 'm-metron-issue-27067', 'https://static.metron.cloud/media/issue/2021/03/11/secret-wars-3.jpg'),
  ('metron', 'issue:27068', 'm-metron-issue-27068', 'https://static.metron.cloud/media/issue/2021/03/11/secret-wars-4.jpg'),
  ('metron', 'issue:27069', 'm-metron-issue-27069', 'https://static.metron.cloud/media/issue/2021/03/11/secret-wars-5.jpg'),
  ('metron', 'issue:27070', 'm-metron-issue-27070', 'https://static.metron.cloud/media/issue/2021/03/11/secret-wars-6.jpg'),
  ('metron', 'issue:27071', 'm-metron-issue-27071', 'https://static.metron.cloud/media/issue/2021/03/11/secret-wars-7.jpg'),
  ('metron', 'issue:27072', 'm-metron-issue-27072', 'https://static.metron.cloud/media/issue/2021/03/11/secret-wars-8.jpg'),
  ('metron', 'issue:27073', 'm-metron-issue-27073', 'https://static.metron.cloud/media/issue/2021/03/11/secret-wars-9.jpg'),
  ('metron', 'issue:42511', 'm-metron-issue-42511', 'https://static.metron.cloud/media/issue/2021/12/28/the-infinity-gauntlet-1.jpg'),
  ('metron', 'issue:42512', 'm-metron-issue-42512', 'https://static.metron.cloud/media/issue/2021/12/28/the-infinity-gauntlet-2.jpg'),
  ('metron', 'issue:42513', 'm-metron-issue-42513', 'https://static.metron.cloud/media/issue/2021/12/28/the-infinity-gauntlet-3.jpg'),
  ('metron', 'issue:42514', 'm-metron-issue-42514', 'https://static.metron.cloud/media/issue/2021/12/28/the-infinity-gauntlet-4.jpg'),
  ('metron', 'issue:42515', 'm-metron-issue-42515', 'https://static.metron.cloud/media/issue/2021/12/28/the-infinity-gauntlet-5.jpg'),
  ('metron', 'issue:42516', 'm-metron-issue-42516', 'https://static.metron.cloud/media/issue/2021/12/28/the-infinity-gauntlet-6.jpg')
)
UPDATE catalog_sources s
SET metadata=jsonb_set(s.metadata,'{posterURL}',to_jsonb(c.url))
FROM covers c, catalog_items i
WHERE s.provider=c.provider AND s.external_id=c.external_id AND s.item_id=c.item_id
  AND i.id=s.item_id AND i.universe_id='marvel'
  AND ((c.provider='metron' AND i.type='HQ')
    OR (c.provider='tmdb' AND i.type IN ('Filme','Série')));
