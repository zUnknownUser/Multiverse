// Editorial titles/canon remain authoritative. Only a published Marvel
// source can enrich the synopsis, with an editorial fallback for missing locales.
export const descriptionSourceJoin = `LEFT JOIN catalog_sources tm ON tm.item_id=i.id
  AND i.universe_id='marvel'
  AND ((tm.provider='tmdb' AND i.type IN ('Filme','Série'))
    OR (tm.provider='metron' AND i.type='HQ'))`;

export function catalogDescription(locale: '$1' | '$2') {
  return `coalesce(nullif(tm.metadata->'descriptions'->>${locale},''),t.description,p.description)`;
}
