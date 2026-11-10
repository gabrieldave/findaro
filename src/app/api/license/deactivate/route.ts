import { fail, handle, ok } from "@/lib/api";
import { lookupLicense, removeActivation } from "@/lib/license";
import { limitByIp } from "@/lib/ratelimit";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/** Desactiva una Mac para liberar un asiento */
export const POST = handle(async (req) => {
  // Límite de peticiones. 10 por hora por IP.
  const limited = limitByIp(req, "license-deactivate", 10, 60 * 60_000);
  if (limited) return limited;

  const body = (await req.json().catch(() => null)) as {
    licenseKey?: string;
    machineId?: string;
  } | null;

  const licenseKey = (body?.licenseKey || "").trim().toUpperCase();
  const machineId = (body?.machineId || "").trim();

  if (!licenseKey) return fail("licenseKey requerido", 400);
  if (!machineId) return fail("machineId requerido", 400);

  const row = await lookupLicense(licenseKey);
  if (!row) return fail("Licencia no encontrada", 404);

  const result = await removeActivation(row.id, machineId);

  return ok({
    deactivated: result.deleted,
    activeCount: result.activeCount,
    seats: row.seats,
  });
});
