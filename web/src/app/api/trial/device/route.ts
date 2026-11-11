import { fail, handle, ok } from "@/lib/api";
import { getOrStartDeviceTrial, signLicensePayload, TRIAL_DAYS } from "@/lib/license";
import { limitByIp } from "@/lib/ratelimit";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/**
 * La app pide aquí su prueba de TRIAL_DAYS al primer arranque (y en cada arranque mientras no sea Pro).
 * El servidor guarda la fecha de inicio por equipo (hash con sal) y devuelve un token firmado
 * con plan "trial", el machineId y la caducidad. Reinstalar o borrar el Llavero no la reinicia.
 */
export const POST = handle(async (req) => {
  // Límite de peticiones. Primer arranque de la app: 20 por hora por IP.
  const limited = limitByIp(req, "trial-device", 20, 60 * 60_000);
  if (limited) return limited;

  const body = (await req.json().catch(() => null)) as { machineId?: string } | null;
  const machineId = (body?.machineId || "").trim();
  // IOPlatformUUID: 36 caracteres. Rechazar basura para no llenar la tabla.
  if (!/^[0-9A-Fa-f-]{16,64}$/.test(machineId)) return fail("machineId inválido", 400);

  const { startedAt, expiresAt } = await getOrStartDeviceTrial(machineId);

  const token = signLicensePayload(
    {
      v: 2,
      plan: "trial",
      tier: "trial",
      key: "DEVICE-TRIAL",
      seats: 1,
      machineId,
      exp: Math.floor(expiresAt.getTime() / 1000),
    },
    "F2",
  );

  return ok({
    plan: "trial",
    trialDays: TRIAL_DAYS,
    startedAt,
    expiresAt,
    expired: expiresAt.getTime() <= Date.now(),
    signed: token,
  });
});
