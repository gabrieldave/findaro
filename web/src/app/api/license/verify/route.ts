import { fail, handle, ok } from "@/lib/api";
import { query } from "@/lib/db";
import { recordEvent } from "@/lib/events";
import {
  hashHardwareId,
  lookupLicense,
  registerActivation,
  PRO_LEASE_DAYS,
  signLicensePayload,
  TRIAL_DAYS,
} from "@/lib/license";
import { limitByIp } from "@/lib/ratelimit";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/** La app Mac verifica / activa una clave. Soporte multi-asiento (1/2/5 Macs) y prueba de TRIAL_DAYS. */
export const POST = handle(async (req) => {
  // Límite de peticiones. Activación/revalidación: 30 cada 10 min por IP.
  const limited = limitByIp(req, "license-verify", 30, 10 * 60_000);
  if (limited) return limited;

  const body = (await req.json().catch(() => null)) as {
    licenseKey?: string;
    machineId?: string;
    machineName?: string;
  } | null;

  const licenseKey = (body?.licenseKey || "").trim().toUpperCase();
  const machineId = (body?.machineId || "").trim();
  const machineName = (body?.machineName || "").trim();

  if (!licenseKey) return fail("licenseKey requerido", 400);
  if (!machineId) return fail("machineId requerido", 400);

  const row = await lookupLicense(licenseKey);
  if (!row || row.revoked) return fail("Licencia no encontrada o revocada.", 404);

  let effectiveExpiresAt = row.expires_at ? new Date(row.expires_at) : null;

  // Lógica específica para licencias trial: reloj único e impedir múltiples trials por equipo
  if (row.plan === "trial") {
    const hwHash = hashHardwareId(machineId);

    // Verificar si este equipo ya usó una prueba anterior
    const devCheck = await query<{ id: string; license_id: string }>(
      `SELECT id, license_id FROM trial_devices WHERE hardware_hash = $1 LIMIT 1`,
      [hwHash],
    );
    if (devCheck.rows[0] && devCheck.rows[0].license_id !== row.id) {
      return fail(
        "Este equipo ya utilizó un período de prueba de Findaro. Adquiere una licencia Pro para continuar.",
        403,
      );
    }

    // Reloj único: si expires_at es null, es la primera activación en una Mac
    if (!effectiveExpiresAt) {
      effectiveExpiresAt = new Date(Date.now() + TRIAL_DAYS * 24 * 60 * 60 * 1000);
      await query(
        `UPDATE licenses SET activated_at = now(), expires_at = $1 WHERE id = $2`,
        [effectiveExpiresAt.toISOString(), row.id],
      );
      await query(
        `INSERT INTO trial_devices (hardware_hash, license_id) VALUES ($1, $2)
         ON CONFLICT (hardware_hash) DO NOTHING`,
        [hwHash, row.id],
      );

      // Evento trial_started (T-04 y T-06 / ADR-05)
      await recordEvent({
        name: "trial_started",
        subjectType: "license",
        subjectId: row.id,
        occurrenceKey: "once",
        props: {
          tier: "trial",
          machineName: machineName || "Mac",
        },
      });
    } else if (effectiveExpiresAt.getTime() < Date.now()) {
      return fail(
        `El período de prueba de ${TRIAL_DAYS} días ha finalizado. Compra tu licencia Pro para continuar.`,
        402,
      );
    }
  }

  const activation = await registerActivation(row.id, machineId, machineName, row.seats);
  if (!activation.success) {
    return fail(activation.error || "No se pudo activar en esta Mac", 403);
  }

  // Pro: el token firmado caduca a los PRO_LEASE_DAYS y la app lo renueva sola (cada 24 h).
  // Así una licencia revocada/reembolsada deja de funcionar aunque bloqueen la red.
  const tokenExpiry = row.plan === "pro"
    ? new Date(Date.now() + PRO_LEASE_DAYS * 24 * 60 * 60 * 1000)
    : effectiveExpiresAt;

  const tokenPayload = {
    v: 2,
    plan: row.plan,
    tier: row.tier || "personal",
    key: row.license_key,
    seats: row.seats,
    machineId,
    exp: tokenExpiry ? Math.floor(tokenExpiry.getTime() / 1000) : null,
  };

  const signed = signLicensePayload(tokenPayload, "F1");
  const token = signLicensePayload(tokenPayload, "F2");

  return ok({
    plan: row.plan,
    tier: row.tier || "personal",
    email: row.email,
    seats: row.seats,
    activeCount: activation.activeCount,
    expiresAt: effectiveExpiresAt,
    signed,
    token,
    licenseKey: row.license_key,
  });
});
