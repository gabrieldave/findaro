import { fail, handle, ok } from "@/lib/api";
import { lookupLicense, registerActivation, signLicensePayload } from "@/lib/license";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/** La app Mac verifica / activa una clave. Soporte multi-asiento (2 Macs personal / 5 Macs familiar). */
export const POST = handle(async (req) => {
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

  if (row.plan === "trial" && row.expires_at && new Date(row.expires_at).getTime() < Date.now()) {
    return fail("El período de prueba de 5 días ha finalizado. Compra tu licencia Pro para continuar.", 402);
  }

  const activation = await registerActivation(row.id, machineId, machineName, row.seats);
  if (!activation.success) {
    return fail(activation.error || "No se pudo activar en esta Mac", 403);
  }

  const signed = signLicensePayload({
    v: 1,
    plan: row.plan,
    tier: row.tier || "personal",
    email: row.email,
    key: row.license_key,
    seats: row.seats,
    machineId,
    exp: row.expires_at ? Math.floor(new Date(row.expires_at).getTime() / 1000) : null,
  });

  return ok({
    plan: row.plan,
    tier: row.tier || "personal",
    email: row.email,
    seats: row.seats,
    activeCount: activation.activeCount,
    expiresAt: row.expires_at,
    signed,
    licenseKey: row.license_key,
  });
});
