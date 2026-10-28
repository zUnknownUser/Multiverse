import { catalogCoverField } from './catalog-cover.js';
import { catalogSeriesJoin, catalogSeriesField } from './catalog-series.js';
import {
  catalogDescription,
  descriptionSourceJoin,
} from './catalog-description.js';
// Fixed SQL shared by all public catalog reads. Values always use parameters.
export const publishedItemRelations = `catalog_items i
  JOIN catalog_universes u ON u.id=i.universe_id AND u.status='active'
  JOIN catalog_universe_translations up ON up.universe_id=u.id AND up.locale='pt-BR'
  JOIN catalog_item_translations p ON p.item_id=i.id AND p.locale='pt-BR'
  LEFT JOIN catalog_item_translations t ON t.item_id=i.id AND t.locale=$1
  ${descriptionSourceJoin} ${catalogSeriesJoin('$1')}`;
export const itemFields = `i.id,i.universe_id AS uni,i.type,coalesce(t.title,p.title) AS title,
  coalesce(t.year,p.year) AS year,s.average AS avg,s.log_count AS "logCount",s.review_count AS "reviewCount",
  s.rating_histogram AS "ratingHistogram",
  coalesce(t.canon,p.canon) AS canon,${catalogDescription('$1')} AS "desc",${catalogSeriesField},${catalogCoverField}`;
export const normalizedTitle = `lower(regexp_replace(normalize(coalesce(t.title,p.title),NFD),'[\u0300-\u036f]','','g'))`;
