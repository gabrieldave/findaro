import { createHash, createPrivateKey, createPublicKey, randomBytes, sign, verify } from "crypto";
import { query } from "./db";
import { LicenseTier, TIERS } from "./pricing";

const TRIAL_DAYS = 5;

/** Genera un hash con sal del identificador de hardware (no se guarda el UUID en claro) */
export function hashHardwareId(machineId: string): string {
  const salt = process.env.HARDWARE_SALT || "findaro-hardware-salt-2026";
  return createHash("sha256").update(`${salt}:${machineId.trim().toUpperCase()}`).digest("hex");
}

// Clave pública canónica Ed25519 embebida en la app Findaro (32 bytes raw hex)
export const FINDARO_ED25519_PUBLIC_KEY_HEX =
  "6dd877795679418e21f4e19c116e5c02c68c7d58808cd3b330bc0c5b2e3c3bac";

// Clave privada canónica Ed25519 (DER PKCS#8) para desarrollo y respaldo si no se define LICENSE_SIGNING_PRIVATE_KEY
const DEFAULT_PRIVATE_KEY_PEM = `-----BEGIN PRIVATE KEY-----
MC4CAQAwBQYDK2VwBCIEIMHjWGCrFSk7cCF7Q2lXf2Ux840IBDI/0fdg/aCzzibo
-----END PRIVATE KEY-----`;

function getSigningPrivateKey() {
  const raw = process.env.LICENSE_SIGNING_PRIVATE_KEY;
  if (!raw) {
    return createPrivateKey(DEFAULT_PRIVATE_KEY_PEM);
  }
  if (raw.includes("BEGIN PRIVATE KEY")) {
    return createPrivateKey(raw);
  }
  let buf: Buffer;
  if (raw.length === 64 && /^[0-9a-fA-F]+$/.test(raw)) {
    buf = Buffer.from(raw, "hex");
  } else {
    buf = Buffer.from(raw, "base64url");
  }
  const prefix = Buffer.from("302e020100300506032b657004220420", "hex");
  return createPrivateKey({ key: Buffer.concat([prefix, buf]), format: "der", type: "pkcs8" });
}

function getSigningPublicKey() {
  const raw = process.env.LICENSE_SIGNING_PUBLIC_KEY;
  if (!raw) {
    const pubBuf = Buffer.from(FINDARO_ED25519_PUBLIC_KEY_HEX, "hex");
    const prefix = Buffer.from("302a300506032b6570032100", "hex");
    return createPublicKey({ key: Buffer.concat([prefix, pubBuf]), format: "der", type: "spki" });
  }
  if (raw.includes("BEGIN PUBLIC KEY")) {
    return createPublicKey(raw);
  }
  let buf: Buffer;
  if (raw.length === 64 && /^[0-9a-fA-F]+$/.test(raw)) {
    buf = Buffer.from(raw, "hex");
  } else {
    buf = Buffer.from(raw, "base64url");
  }
  const prefix = Buffer.from("302a300506032b6570032100", "hex");
  return createPublicKey({ key: Buffer.concat([prefix, buf]), format: "der", type: "spki" });
}

/** Clave legible: FINDARO-XXXX-XXXX-XXXX-XXXX */
export function mintLicenseKey(): string {
  const raw = randomBytes(8).toString("hex").toUpperCase();
  const parts = raw.match(/.{1,4}/g) || [raw];
  return `FINDARO-${parts.join("-")}`;
}

/** Código de referido único: e.g. DAVE-7X29 */
export function mintReferralCode(seed?: string): string {
  const prefix = (seed || "REF")
    .replace(/[^A-Za-z0-9]/g, "")
    .slice(0, 4)
    .toUpperCase() || "FIND";
  const suffix = randomBytes(2).toString("hex").toUpperCase();
  return `${prefix}-${suffix}`;
}

/** Firma asimétrica Ed25519 de licencias para Findaro */
export function signLicensePayload(payload: Record<string, unknown>): string {
  const body = Buffer.from(JSON.stringify(payload)).toString("base64url");
  const privateKey = getSigningPrivateKey();
  const sig = sign(null, Buffer.from(body), privateKey);
  return `F1.${body}.${sig.toString("base64url")}`;
}

/** Verificación asimétrica Ed25519 del token de licencia */
export function verifySignedLicense(token: string): Record<string, unknown> | null {
  const parts = token.split(".");
  if (parts.length !== 3 || parts[0] !== "F1") return null;
  const [, body, sigB64] = parts;
  try {
    const publicKey = getSigningPublicKey();
    const sig = Buffer.from(sigB64, "base64url");
    const valid = verify(null, Buffer.from(body), publicKey, sig);
    if (!valid) return null;
    return JSON.parse(Buffer.from(body, "base64url").toString("utf8"));
  } catch {
    return null;
  }
}

export async function issueTrialLicense(customerId: string, _email: string) {
  // ¿Ya tuvo trial?
  const existing = await query<{ id: string; license_key: string; expires_at: Date | null }>(
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
      trialDays: TRIAL_DAYS,
    };
  }

  const licenseKey = mintLicenseKey();
  // Reloj único: expires_at es NULL al emitir la clave; el servidor fija now() + 5 días en la primera activación en Mac
  await query(
    `INSERT INTO licenses (customer_id, license_key, plan, tier, seats, expires_at)
     VALUES ($1, $2, 'trial', 'trial', 1, NULL)`,
    [customerId, licenseKey],
  );

  return { licenseKey, expiresAt: null, reused: false as const, trialDays: TRIAL_DAYS };
}

export async function issueProLicense(opts: {
  customerId: string;
  orderId: string;
  email: string;
  tier?: LicenseTier;
}) {
  const tier = opts.tier || "personal";
  const seats = TIERS[tier]?.seats ?? 2;

  const existing = await query<{ id: string; license_key: string; seats: number; tier: string }>(
    `SELECT id, license_key, seats, tier FROM licenses
     WHERE customer_id = $1 AND plan = 'pro' AND revoked = false
     ORDER BY created_at DESC LIMIT 1`,
    [opts.customerId],
  );
  if (existing.rows[0]) {
    const existingTier = (existing.rows[0].tier as LicenseTier) || tier;
    const existingSeats = Math.max(existing.rows[0].seats, seats);

    // Asegurar que seats refleje el tier adecuado
    if (existingSeats > existing.rows[0].seats) {
      await query(`UPDATE licenses SET seats = $1, tier = $2 WHERE id = $3`, [
        existingSeats,
        existingTier,
        existing.rows[0].id,
      ]);
    }

    const signed = signLicensePayload({
      v: 1,
      plan: "pro",
      tier: existingTier,
      email: opts.email,
      key: existing.rows[0].license_key,
      seats: existingSeats,
      exp: null,
    });
    return {
      licenseKey: existing.rows[0].license_key,
      signed,
      seats: existingSeats,
      tier: existingTier,
      reused: true as const,
    };
  }

  const licenseKey = mintLicenseKey();
  const signed = signLicensePayload({
    v: 1,
    plan: "pro",
    tier,
    email: opts.email,
    key: licenseKey,
    seats,
    exp: null,
  });

  await query(
    `INSERT INTO licenses (customer_id, order_id, license_key, plan, tier, seats, expires_at)
     VALUES ($1, $2, $3, 'pro', $4, $5, NULL)`,
    [opts.customerId, opts.orderId, licenseKey, tier, seats],
  );

  // Revocar trials del mismo cliente
  await query(
    `UPDATE licenses SET revoked = true
     WHERE customer_id = $1 AND plan = 'trial' AND revoked = false`,
    [opts.customerId],
  );

  return { licenseKey, signed, seats, tier, reused: false as const };
}

export async function lookupLicense(licenseKey: string) {
  const { rows } = await query<{
    id: string;
    license_key: string;
    plan: "trial" | "pro";
    tier: string;
    seats: number;
    expires_at: Date | null;
    revoked: boolean;
    email: string;
    customer_id: string;
  }>(
    `SELECT l.id, l.license_key, l.plan, l.tier, l.seats, l.expires_at, l.revoked, c.email, l.customer_id
     FROM licenses l
     JOIN customers c ON c.id = l.customer_id
     WHERE l.license_key = $1`,
    [licenseKey.trim().toUpperCase()],
  );
  return rows[0] || null;
}

export async function getActivations(licenseId: string) {
  const { rows } = await query<{
    machine_id: string;
    machine_name: string;
    activated_at: Date;
    last_seen_at: Date;
  }>(
    `SELECT machine_id, machine_name, activated_at, last_seen_at
     FROM license_activations
     WHERE license_id = $1
     ORDER BY activated_at ASC`,
    [licenseId],
  );
  return rows;
}

export async function registerActivation(
  licenseId: string,
  machineId: string,
  machineName: string = "",
  maxSeats: number = 2,
): Promise<{ success: boolean; activeCount: number; maxSeats: number; error?: string }> {
  const trimmedMachine = machineId.trim();
  if (!trimmedMachine) return { success: false, activeCount: 0, maxSeats, error: "machineId vacío" };

  const current = await getActivations(licenseId);
  const existing = current.find((a) => a.machine_id === trimmedMachine);

  if (existing) {
    await query(
      `UPDATE license_activations SET last_seen_at = now(), machine_name = COALESCE(NULLIF($2,''), machine_name)
       WHERE license_id = $1 AND machine_id = $3`,
      [licenseId, machineName, trimmedMachine],
    );
    return { success: true, activeCount: current.length, maxSeats };
  }

  if (current.length >= maxSeats) {
    return {
      success: false,
      activeCount: current.length,
      maxSeats,
      error: `Límite de Macs alcanzado (${current.length}/${maxSeats}). Desactiva otra Mac en Preferencias > Licencia o actualiza a Plan Familiar.`,
    };
  }

  await query(
    `INSERT INTO license_activations (license_id, machine_id, machine_name)
     VALUES ($1, $2, $3)
     ON CONFLICT (license_id, machine_id) DO UPDATE SET last_seen_at = now()`,
    [licenseId, trimmedMachine, machineName || "Mac"],
  );

  return { success: true, activeCount: current.length + 1, maxSeats };
}

export async function removeActivation(licenseId: string, machineId: string) {
  const res = await query(
    `DELETE FROM license_activations WHERE license_id = $1 AND machine_id = $2 RETURNING id`,
    [licenseId, machineId.trim()],
  );
  const remaining = await getActivations(licenseId);
  return { deleted: res.rows.length > 0, activeCount: remaining.length };
}

export { TRIAL_DAYS };
