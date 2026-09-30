import { randomInt, randomUUID } from "node:crypto";
import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { defineSecret, defineString } from "firebase-functions/params";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { Challenge, createChallenge, confirmChallenge, VerificationError } from "./verificationPolicy";

initializeApp();
const db = getFirestore();
const mailKey = defineSecret("RESEND_API_KEY");
const codeSecret = defineSecret("VERIFICATION_CODE_SECRET");
const mailFrom = defineString("VERIFICATION_EMAIL_FROM");
const options = {
  region: "us-central1", maxInstances: 5, timeoutSeconds: 30,
  enforceAppCheck: true,
  secrets: [mailKey, codeSecret],
};

async function account(uid: string | undefined) {
  if (!uid) throw new HttpsError("unauthenticated", "Entre novamente.");
  const user = await getAuth().getUser(uid);
  if (user.disabled || !user.email || !user.providerData.some(p => p.providerId === "password")) {
    throw new HttpsError("failed-precondition", "Conta indisponível para confirmação.");
  }
  return user;
}

function fail(error: unknown): never {
  if (error instanceof HttpsError) throw error;
  if (error instanceof VerificationError) {
    throw new HttpsError(error.code, "Não foi possível confirmar. Confira o código ou solicite outro.");
  }
  // Never expose provider responses, codes, email addresses, or secrets to logs/clients.
  throw new HttpsError("unavailable", "Serviço de confirmação indisponível. Tente novamente mais tarde.");
}

export const requestEmailVerificationCode = onCall(options, async request => {
  try {
    const user = await account(request.auth?.uid);
    if (user.emailVerified) return { verified: true };
    const uid = user.uid;
    const email = user.email!;
    const code = randomInt(0, 1_000_000).toString().padStart(6, "0");
    const generation = randomUUID();
    const ref = db.collection("emailVerificationChallenges").doc(uid);
    const challenge = await db.runTransaction(async tx => {
      const previous = (await tx.get(ref)).data() as Challenge | undefined;
      const next = createChallenge(previous, { uid, email, code, generation, secret: codeSecret.value(), now: Date.now() });
      // Keep rate-limit metadata beyond the code's lifetime.
      tx.set(ref, { ...next, purgeAt: Timestamp.fromMillis(next.createdAt + 86_400_000) });
      return next;
    });
    try {
      const response = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${mailKey.value()}`,
          "Content-Type": "application/json",
          "Idempotency-Key": `email-verification/${generation}`,
        },
        body: JSON.stringify({
          from: mailFrom.value(), to: [email], subject: "Seu código Multiverse",
          text: `Seu código de confirmação é ${code}. Ele vale por 10 minutos. Se você não solicitou, ignore este e-mail.`,
        }),
        signal: AbortSignal.timeout(10_000),
      });
      if (!response.ok) throw new Error("delivery-failed");
      await db.runTransaction(async tx => {
        const current = (await tx.get(ref)).data() as Challenge | undefined;
        if (current?.generation === generation) tx.update(ref, { status: "active" });
      });
    } catch {
      await db.runTransaction(async tx => {
        const current = (await tx.get(ref)).data() as Challenge | undefined;
        if (current?.generation === generation) tx.update(ref, { status: "failed" });
      });
      throw new HttpsError("unavailable", "Não foi possível enviar o código. Tente novamente mais tarde.");
    }
    return { expiresIn: (challenge.expiresAt - challenge.createdAt) / 1000, retryAfter: 60 };
  } catch (error) { return fail(error); }
});

export const confirmEmailVerificationCode = onCall(options, async request => {
  try {
    const code = request.data?.code;
    if (typeof code !== "string" || !/^[0-9]{6}$/.test(code)) {
      throw new HttpsError("invalid-argument", "Informe os seis dígitos.");
    }
    const user = await account(request.auth?.uid);
    if (user.emailVerified) return { verified: true };
    const uid = user.uid;
    const email = user.email!;
    const ref = db.collection("emailVerificationChallenges").doc(uid);
    const result = await db.runTransaction(async tx => {
      const current = (await tx.get(ref)).data() as Challenge | undefined;
      const decision = confirmChallenge(current, { uid, email, code, secret: codeSecret.value(), now: Date.now() });
      tx.update(ref, { attempts: decision.challenge.attempts, status: decision.challenge.status });
      return decision;
    });
    // Throw AFTER committing so failed attempts cannot be rolled back.
    if (!result.accepted) throw new HttpsError("invalid-argument", "Código incorreto. Confira e tente novamente.");
    const latest = await getAuth().getUser(uid);
    if (latest.email !== email || latest.disabled) throw new HttpsError("failed-precondition", "A conta mudou. Solicite outro código.");
    await getAuth().updateUser(uid, { emailVerified: true });
    await db.runTransaction(async tx => {
      const current = (await tx.get(ref)).data() as Challenge | undefined;
      if (current?.generation === result.challenge.generation) tx.update(ref, { status: "verified", hash: "" });
    });
    return { verified: true };
  } catch (error) { return fail(error); }
});
