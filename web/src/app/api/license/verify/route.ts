import { fail, handle, ok } from "@/lib/api";
import { query } from "@/lib/db";
import { lookupLicense, signLicensePayload } from "@/lib/license";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/** La app Mac verifica / activa una clave. 1 asiento = 1 machine_id. */
export const POST = handle(async (req) => {
  const body = (await req.json().catch(() => null)) as {
    licenseKey?: string;
    machineId?: string;
  } | null;

  const licenseKey = (body?.licenseKey || "").trim().toUpperCase();
  const machineId = (body?.machineId || "").trim();
  if (!licenseKey) return fail("licenseKey requerido", 400);
  if (!machineId) return fail("machineId requerido", 400);

  const row = await lookupLicense(licenseKey);
  if (!row || row.revoked) return fail("Licencia inválida", 404);

  if (row.plan === "trial" && row.expires_at && new Date(row.expires_at).getTime() < Date.now()) {
    return fail("La prueba de 5 días terminó. Compra Pro para seguir.", 402);
  }

  if (row.machine_id && row.machine_id !== machineId) {
    return fail("Esta licencia ya está activa en otra Mac (1 equipo).", 403);
  }

  if (!row.machine_id) {
    await query(
      `UPDATE licenses SET machine_id = $1, activated_at = now() WHERE license_key = $2`,
      [machineId, licenseKey],
    );
  }

  const signed = signLicensePayload({
    v: 1,
    plan: row.plan,
    email: row.email,
    key: row.license_key,
    seats: row.seats,
    machineId,
    exp: row.expires_at ? Math.floor(new Date(row.expires_at).getTime() / 1000) : null,
  });

  return ok({
    plan: row.plan,
    email: row.email,
    seats: row.seats,
    expiresAt: row.expires_at,
    signed,
    licenseKey: row.license_key,
  });
});
