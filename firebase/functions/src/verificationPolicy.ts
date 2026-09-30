import { createHmac, timingSafeEqual } from "node:crypto";

export const TTL_MS = 10 * 60_000;
export const RESEND_MS = 60_000;
export const MAX_ATTEMPTS = 5;
export const MAX_SENDS_PER_HOUR = 5;

export interface Challenge {
  uid: string;
  email: string;
  generation: string;
  hash: string;
  createdAt: number;
  expiresAt: number;
  attempts: number;
  hourlyStart: number;
  hourlySends: number;
  status: "sending" | "active" | "failed" | "accepted" | "verified";
}

export class VerificationError extends Error {
  constructor(public code: "resource-exhausted" | "invalid-argument" | "deadline-exceeded" | "failed-precondition") {
    super(code);
  }
}

export function hashCode(secret: string, uid: string, email: string, generation: string, code: string): string {
  return createHmac("sha256", secret).update(JSON.stringify([uid, email, generation, code])).digest("hex");
}

export function createChallenge(previous: Challenge | undefined, values: {
  uid: string; email: string; generation: string; code: string; secret: string; now: number;
}): Challenge {
  const { uid, email, generation, code, secret, now } = values;
  if (previous && now - previous.createdAt < RESEND_MS) throw new VerificationError("resource-exhausted");
  const sameWindow = previous && now - previous.hourlyStart < 3_600_000;
  if (sameWindow && previous.hourlySends >= MAX_SENDS_PER_HOUR) throw new VerificationError("resource-exhausted");
  return {
    uid, email, generation, hash: hashCode(secret, uid, email, generation, code),
    createdAt: now, expiresAt: now + TTL_MS, attempts: 0,
    hourlyStart: sameWindow ? previous.hourlyStart : now,
    hourlySends: sameWindow ? previous.hourlySends + 1 : 1,
    status: "sending",
  };
}

export function confirmChallenge(challenge: Challenge | undefined, values: {
  uid: string; email: string; code: string; secret: string; now: number;
}): { accepted: boolean; challenge: Challenge } {
  if (!challenge || challenge.expiresAt <= values.now) throw new VerificationError("deadline-exceeded");
  if (challenge.uid !== values.uid || challenge.email !== values.email ||
      !["active", "accepted"].includes(challenge.status)) throw new VerificationError("failed-precondition");
  if (challenge.attempts >= MAX_ATTEMPTS) throw new VerificationError("resource-exhausted");
  const expected = Buffer.from(challenge.hash, "hex");
  const received = Buffer.from(hashCode(values.secret, values.uid, values.email, challenge.generation, values.code), "hex");
  const accepted = expected.length === received.length && timingSafeEqual(expected, received);
  return {
    accepted,
    challenge: { ...challenge, attempts: challenge.attempts + (accepted ? 0 : 1), status: accepted ? "accepted" : challenge.status },
  };
}
