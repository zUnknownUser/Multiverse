// Public artwork is selected only from the source already mapped to this item.
// Metadata licensing does not transfer ownership of the cover illustrations.
export function providerCoverURL(
  provider: 'tmdb' | 'metron',
  value: unknown,
): string | undefined {
  if (typeof value !== 'string' || value.length > 1000) return;
  const pattern =
    provider === 'tmdb'
      ? /^https:\/\/image\.tmdb\.org\/t\/p\/w500\/[a-zA-Z0-9]+\.(jpg|png)$/
      : /^https:\/\/static\.metron\.cloud\/media\/issue\/[a-zA-Z0-9_/-]+(\.(jpg|jpeg|png))?\.(jpg|jpeg|png|webp)$/;
  return pattern.test(value) && !value.includes('//', 8) ? value : undefined;
}

export const catalogCoverField = `CASE
  WHEN tm.provider='tmdb' AND tm.external_id ~ '^(movie|tv):[1-9][0-9]*$'
    AND tm.metadata->>'posterURL' ~ '^https://image[.]tmdb[.]org/t/p/w500/[a-zA-Z0-9]+[.](jpg|png)$'
    THEN json_build_object('provider','tmdb','url',tm.metadata->>'posterURL',
      'sourceURL','https://www.themoviedb.org/' || replace(tm.external_id,':','/'))
  WHEN tm.provider='metron' AND tm.external_id ~ '^issue:[1-9][0-9]*$'
    AND tm.metadata->>'posterURL' ~ '^https://static[.]metron[.]cloud/media/issue/[a-zA-Z0-9_/-]+([.](jpg|jpeg|png))?[.](jpg|jpeg|png|webp)$'
    THEN json_build_object('provider','metron','url',tm.metadata->>'posterURL',
      'sourceURL','https://metron.cloud/issue/' || split_part(tm.external_id,':',2) || '/')
  ELSE NULL END AS cover`;
