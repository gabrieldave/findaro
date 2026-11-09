import { createHash, createPrivateKey, createPublicKey, randomBytes, sign, verify } from "crypto";
import { query } from "./db";
import { LicenseTier, TIERS } from "./pricing";

const TRIAL_DAYS = 5;

/** Genera un hash con sal del identificador de hardware (no se guarda el UUID en claro) */
export function hashHardwareId(machineId: string): string {
  const salt = process.env.HARDWARE_SALT || "findaro-hardware-salt-2026";
  return createHash("sha256").update(`${salt}:${machineId.trim().toUpperCase()}`).digest("hex");
}

// Clave pública canónica Ed25519 embebida en la app Findaro (32 bytes raw hex).
// ROTADA el 2026-11-09: la clave anterior (6dd87779…) quedó comprometida porque su clave
// privada estaba escrita en este repositorio. Debe coincidir con
// FindaroLicenseVerifier.embeddedPublicKeyHex en Sources/OrdenCore/LicenseStore.swift.
export const FINDARO_ED25519_PUBLIC_KEY_HEX =
  "c86b663a1d94a3f69bee0b189b00c541c0c8e55b71c4ffdc166052ff57feb5dd";

/**
 * Días de validez del token Pro firmado ("lease"). La app lo renueva sola al abrir y cada 24 h;
 * si una Mac pasa más de estos días sin conectarse, se le pide conectarse para revalidar.
 * Esto hace efectivas las revocaciones (reembolsos, claves filtradas).
 */
export const PRO_LEASE_DAYS = Math.max(7, Number(process.env.LICENSE_LEASE_DAYS || 30));

/**
 * La clave privada SOLO vive en la variable de entorno LICENSE_SIGNING_PRIVATE_KEY del servidor.
 * Nunca en el repositorio. Si falta, se falla en cerrado (no se emiten licencias).
 */
function getSigningPrivateKey() {
  const raw = (process.env.LICENSE_SIGNING_PRIVATE_KEY || "").trim();
  if (!raw) {
    throw new Error("LICENSE_SIGNING_PRIVATE_KEY no configurada: no se pueden firmar licencias");
  }
  if (raw.includes("BEGIN PRIVATE KEY")) {
    return createPrivateKey(raw.replace(/\\n/g, "\n"));
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

/** Firma asimétrica Ed25519 de licencias para Findaro (F1 y F2 / ADR-01) */
export function signLicensePayload(payload: Record<string, unknown>, version: "F1" | "F2" = "F2"): string {
  const body = Buffer.from(JSON.stringify(payload)).toString("base64url");
  const privateKey = getSigningPrivateKey();
  // Comprobación de coherencia: la privada configurada debe corresponder a la pública que lleva la app.
  const derived = createPublicKey(privateKey).export({ type: "spki", format: "der" }).subarray(12).toString("hex");
  const expected = (process.env.LICENSE_SIGNING_PUBLIC_KEY || FINDARO_ED25519_PUBLIC_KEY_HEX).trim().toLowerCase();
  if (expected.length === 64 && derived !== expected) {
    throw new Error("LICENSE_SIGNING_PRIVATE_KEY no corresponde a la clave pública embebida en la app");
  }
  const sig = sign(null, Buffer.from(body), privateKey);
  return `${version}.${body}.${sig.toString("base64url")}`;
}

/** Verificación asimétrica Ed25519 del token de licencia */
export function verifySignedLicense(token: string): Record<string, unknown> | null {
  const parts = token.split(".");
  if (parts.length !== 3 || (parts[0] !== "F1" && parts[0] !== "F2")) return null;
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

/**
 * Prueba por equipo (sin correo): el reloj de 5 días vive en el SERVIDOR, ligado al hash del
 * hardware. Borrar el Llavero o reinstalar ya no reinicia la prueba (si la Mac tiene internet).
 */
export async function getOrStartDeviceTrial(machineId: string): Promise<{ startedAt: Date; expiresAt: Date }> {
  const hwHash = hashHardwareId(machineId);
  const trialMs = TRIAL_DAYS * 24 * 60 * 60 * 1000;
  await query(
    `INSERT INTO trial_devices (hardware_hash, license_id, first_seen_at, expires_at)
     VALUES ($1, NULL, now(), now() + make_interval(days => $2))
     ON CONFLICT (hardware_hash) DO NOTHING`,
    [hwHash, TRIAL_DAYS],
  );
  const { rows } = await query<{ first_seen_at: Date; expires_at: Date | null; license_expires_at: Date | null }>(
    `SELECT d.first_seen_at, d.expires_at, l.expires_at AS license_expires_at
     FROM trial_devices d
     LEFT JOIN licenses l ON l.id = d.license_id
     WHERE d.hardware_hash = $1`,
    [hwHash],
  );
  const row = rows[0];
  const startedAt = row ? new Date(row.first_seen_at) : new Date();
  const candidates = [
    row?.expires_at ? new Date(row.expires_at).getTime() : null,
    row?.license_expires_at ? new Date(row.license_expires_at).getTime() : null,
    startedAt.getTime() + trialMs,
  ].filter((v): v is number => typeof v === "number");
  return { startedAt, expiresAt: new Date(Math.min(...candidates)) };
}

export { TRIAL_DAYS };
