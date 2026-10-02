// One membership per item; shared by catalog, diary and feed reads so refreshes
// cannot erase the series metadata already held by the mobile client.
export function catalogSeriesJoin(locale: '$1' | '$2') {
  return `LEFT JOIN catalog_series_items csi ON csi.item_id=i.id
    LEFT JOIN catalog_series cs ON cs.id=csi.series_id AND cs.universe_id=i.universe_id
    LEFT JOIN catalog_series_translations csp ON csp.series_id=cs.id AND csp.locale='pt-BR'
    LEFT JOIN catalog_series_translations cst ON cst.series_id=cs.id AND cst.locale=${locale}`;
}
export const catalogSeriesField = `CASE WHEN cs.id IS NULL THEN NULL ELSE json_build_object(
  'id',cs.id,'title',coalesce(cst.title,csp.title),'year',cs.year,
  'number',csi.issue_number,'position',csi.position) END AS series`;
