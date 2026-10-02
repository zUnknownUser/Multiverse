import { setTimeout } from 'node:timers/promises';
import { metronMarvelRegistry } from './metron-registry.js';
import { fetchMetronMarvelIssues } from './metron.js';
import type { CatalogCandidate } from './candidate.js';

// The complete reviewed catalog is fetched before any database transaction.
// Private ad-hoc previews keep their 10-issue limit; publication uses paced chunks.
export async function fetchMetronPublication(
  token: string | undefined,
  transport: typeof fetch = fetch,
  wait: (ms: number) => Promise<unknown> = setTimeout,
) {
  const result: CatalogCandidate[] = [];
  for (let offset = 0; offset < metronMarvelRegistry.length; offset += 10) {
    if (offset) await wait(3100);
    result.push(
      ...(await fetchMetronMarvelIssues(
        metronMarvelRegistry.slice(offset, offset + 10).map((m) => m.id),
        token,
        transport,
        wait,
      )),
    );
  }
  return result;
}
