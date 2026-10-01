// Editorial titles/canon remain authoritative. Only a published Marvel TMDB
// source can enrich the synopsis, with an editorial fallback for missing locales.
export const descriptionSourceJoin = `LEFT JOIN catalog_sources tm ON tm.item_id=i.id
  AND tm.provider='tmdb' AND i.universe_id='marvel' AND i.type IN ('Filme','Série')`;

export function catalogDescription(locale: '$1' | '$2') {
  return `coalesce(nullif(tm.metadata->'descriptions'->>${locale},''),t.description,p.description)`;
}
