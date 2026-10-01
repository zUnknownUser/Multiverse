// Bound decompressed bytes while reading; Content-Length alone is not a limit.
export async function readProviderJSON(
  response: Response,
  provider: string,
): Promise<unknown> {
  const maxBytes = 2_000_000;
  const reader = response.body?.getReader();
  if (!reader) throw new Error(`${provider}_INVALID_ENTITY`);
  const chunks: Uint8Array[] = [];
  let bytes = 0;
  let complete = false;
  try {
    if (Number(response.headers.get('content-length') ?? 0) > maxBytes)
      throw new Error(`${provider}_RESPONSE_TOO_LARGE`);
    while (true) {
      const { value, done } = await reader.read();
      if (done) {
        complete = true;
        break;
      }
      bytes += value.byteLength;
      if (bytes > maxBytes) throw new Error(`${provider}_RESPONSE_TOO_LARGE`);
      chunks.push(value);
    }
    try {
      return JSON.parse(Buffer.concat(chunks, bytes).toString('utf8'));
    } catch {
      throw new Error(`${provider}_INVALID_JSON`);
    }
  } finally {
    if (!complete) await reader.cancel().catch(() => {});
    reader.releaseLock();
  }
}

export async function fetchProviderJSON(
  provider: 'tmdb' | 'metron',
  path: string,
  token: string | undefined,
  transport: typeof fetch = fetch,
): Promise<unknown> {
  const prefix = provider.toUpperCase();
  if (!token?.trim()) throw new Error(`${prefix}_NOT_CONFIGURED`);
  if (!/^[\x21-\x7e]{1,4096}$/.test(token.trim()))
    throw new Error(`${prefix}_INVALID_TOKEN`);
  const allowed =
    provider === 'tmdb' ? /^\/(movie|tv)\/[1-9]\d*$/ : /^\/issue\/[1-9]\d*\/$/;
  if (!allowed.test(path)) throw new Error(`${prefix}_INVALID_PATH`);
  const url = new URL(
    (provider === 'tmdb'
      ? 'https://api.themoviedb.org/3'
      : 'https://metron.cloud/api') + path,
  );
  if (provider === 'tmdb') {
    url.searchParams.set('language', 'en-US');
    url.searchParams.set('append_to_response', 'translations,credits');
  }
  let response: Response;
  try {
    response = await transport(url.toString(), {
      headers: {
        Authorization: `Bearer ${token.trim()}`,
        Accept: 'application/json',
        'User-Agent':
          'Multiverse/0.1 (https://somosmultiverse.com.br; catalog integration)',
      },
      signal: AbortSignal.timeout(15_000),
      redirect: 'error',
    });
  } catch {
    throw new Error(`${prefix}_UNAVAILABLE`);
  }
  if (!response.ok) {
    await response.body?.cancel().catch(() => {});
    // No upstream bodies, URLs, headers or credentials in operational errors.
    throw new Error(`${prefix}_HTTP_${response.status}`);
  }
  try {
    return await readProviderJSON(response, prefix);
  } catch (error) {
    if (
      error instanceof Error &&
      [
        `${prefix}_INVALID_ENTITY`,
        `${prefix}_INVALID_JSON`,
        `${prefix}_RESPONSE_TOO_LARGE`,
      ].includes(error.message)
    )
      throw error;
    throw new Error(`${prefix}_UNAVAILABLE`);
  }
}
