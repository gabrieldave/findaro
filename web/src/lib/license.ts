import { createHmac, randomBytes } from "crypto";
import { query } from "./db";

const TRIAL_DAYS = 5;

function signingSecret(): string {
  const s = process.env.LICENSE_SIGNING_SECRET || process.env.ADMIN_SESSION_SECRET;
  if (!s || s.length < 16) throw new Error("LICENSE_SIGNING_SECRET no configurado");
  return s;
}

/** Clave legible: FINDARO-XXXX-XXXX-XXXX-XXXX */
export function mintLicenseKey(): string {
  const raw = randomBytes(8).toString("hex").toUpperCase();
  const parts = raw.match(/.{1,4}/g) || [raw];
  return `FINDARO-${parts.join("-")}`;
}

export function signLicensePayload(payload: Record<string, unknown>): string {
  const body = Buffer.from(JSON.stringify(payload)).toString("base64url");
  const sig = createHmac("sha256", signingSecret()).update(body).digest("base64url");
  return `F1.${body}.${sig}`;
}

export function verifySignedLicense(token: string): Record<string, unknown> | null {
  const parts = token.split(".");
  if (parts.length !== 3 || parts[0] !== "F1") return null;
  const [, body, sig] = parts;
  const expect = createHmac("sha256", signingSecret()).update(body).digest("base64url");
  if (expect !== sig) return null;
  try {
    return JSON.parse(Buffer.from(body, "base64url").toString("utf8"));
  } catch {
    return null;
  }
}

export async function issueTrialLicense(customerId: string, email: string) {
  // ¿Ya tuvo trial?
  const existing = await query<{ id: string; license_key: string; expires_at: Date }>(
    `SELECT id, license_key, expires_at FROM licenses
     WHERE customer_id = $1 AND plan = 'trial'
     ORDER BY created_at DESC LIMIT 1`,
    [customerId],
  );
  if (existing.rows[0]) {
    return {
      licenseKey: existing.rows[0].license_key,
      expiresAt: existing.rows[0].expires_at,
      reused: true as const,
    };
  }

  const licenseKey = mintLicenseKey();
  const expiresAt = new Date(Date.now() + TRIAL_DAYS * 24 * 60 * 60 * 1000);
  const signed = signLicensePayload({
    v: 1,
    plan: "trial",
    email,
    key: licenseKey,
    seats: 1,
    exp: Math.floor(expiresAt.getTime() / 1000),
  });

  await query(
    `INSERT INTO licenses (customer_id, license_key, plan, seats, expires_at)
     VALUES ($1, $2, 'trial', 1, $3)`,
    [customerId, licenseKey, expiresAt.toISOString()],
  );

  // Guardamos el blob firmado en metadata vía update del key display? Usamos license_key human + signed aparte en respuesta.
  return { licenseKey, signed, expiresAt, reused: false as const, trialDays: TRIAL_DAYS };
}

export async function issueProLicense(opts: {
  customerId: string;
  orderId: string;
  email: string;
}) {
  const existing = await query<{ license_key: string }>(
    `SELECT license_key FROM licenses
     WHERE customer_id = $1 AND plan = 'pro' AND revoked = false
     ORDER BY created_at DESC LIMIT 1`,
    [opts.customerId],
  );
  if (existing.rows[0]) {
    const signed = signLicensePayload({
      v: 1,
      plan: "pro",
      email: opts.email,
      key: existing.rows[0].license_key,
      seats: 1,
      exp: null,
    });
    return { licenseKey: existing.rows[0].license_key, signed, reused: true as const };
  }

  const licenseKey = mintLicenseKey();
  const signed = signLicensePayload({
    v: 1,
    plan: "pro",
    email: opts.email,
    key: licenseKey,
    seats: 1,
    exp: null,
  });

  await query(
    `INSERT INTO licenses (customer_id, order_id, license_key, plan, seats, expires_at)
     VALUES ($1, $2, $3, 'pro', 1, NULL)`,
    [opts.customerId, opts.orderId, licenseKey],
  );

  // Revocar trials del mismo cliente
  await query(
    `UPDATE licenses SET revoked = true
     WHERE customer_id = $1 AND plan = 'trial' AND revoked = false`,
    [opts.customerId],
  );

  return { licenseKey, signed, reused: false as const };
}

export async function lookupLicense(licenseKey: string) {
  const { rows } = await query<{
    license_key: string;
    plan: "trial" | "pro";
    seats: number;
    expires_at: Date | null;
    revoked: boolean;
    email: string;
    machine_id: string | null;
  }>(
    `SELECT l.license_key, l.plan, l.seats, l.expires_at, l.revoked, c.email, l.machine_id
     FROM licenses l
     JOIN customers c ON c.id = l.customer_id
     WHERE l.license_key = $1`,
    [licenseKey.trim().toUpperCase()],
  );
  return rows[0] || null;
}

export { TRIAL_DAYS };
