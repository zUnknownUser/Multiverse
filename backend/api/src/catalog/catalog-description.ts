// Editorial titles/canon remain authoritative. Only a published hero
// source can enrich the synopsis, with an editorial fallback for missing locales.
export const descriptionSourceJoin = `LEFT JOIN catalog_sources tm ON tm.item_id=i.id
  AND i.universe_id IN ('marvel','dc')
  AND ((tm.provider='tmdb' AND i.type IN ('Filme','Série'))
    OR (tm.provider='metron' AND i.type='HQ'))`;

export function catalogDescription(locale: '$1' | '$2') {
  return `coalesce(CASE WHEN tm.metadata->>'artworkOnly' IS DISTINCT FROM 'true' THEN nullif(tm.metadata->'descriptions'->>${locale},'') END,t.description,p.description)`;
}
