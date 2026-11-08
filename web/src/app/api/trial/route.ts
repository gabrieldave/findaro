import { fail, handle, ok } from "@/lib/api";
import { query } from "@/lib/db";
import { issueDownloadToken } from "@/lib/download";
import { issueTrialLicense, TRIAL_DAYS } from "@/lib/license";
import { PUBLIC_APP_URL } from "@/lib/site";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = handle(async (req) => {
  const body = (await req.json().catch(() => null)) as {
    email?: string;
    name?: string;
  } | null;

  const email = (body?.email || "").trim().toLowerCase();
  const name = (body?.name || "").trim() || "Prueba";
  if (!email || !email.includes("@")) return fail("Correo inválido", 400);

  const customer = await query<{ id: string }>(
    `INSERT INTO customers (email, name)
     VALUES ($1, $2)
     ON CONFLICT (email) DO UPDATE SET name = COALESCE(NULLIF(EXCLUDED.name,''), customers.name), updated_at = now()
     RETURNING id`,
    [email, name],
  );
  const customerId = customer.rows[0]?.id;
  if (!customerId) return fail("No se pudo registrar", 500);

  // Si ya tiene Pro, no dar trial: mandarlo a descargar Pro
  const pro = await query<{ license_key: string; id: string }>(
    `SELECT id, license_key FROM licenses
     WHERE customer_id = $1 AND plan = 'pro' AND revoked = false
     LIMIT 1`,
    [customerId],
  );
  if (pro.rows[0]) {
    const token = await issueDownloadToken(null, 30, pro.rows[0].id);
    return ok({
      plan: "pro",
      licenseKey: pro.rows[0].license_key,
      downloadUrl: `${PUBLIC_APP_URL}/api/download?token=${token}`,
      message: "Ya tienes licencia Pro. Aquí tienes tu descarga.",
    });
  }

  const trial = await issueTrialLicense(customerId, email);
  const lic = await query<{ id: string }>(
    `SELECT id FROM licenses WHERE license_key = $1`,
    [trial.licenseKey],
  );
  const licenseId = lic.rows[0]?.id;
  const token = await issueDownloadToken(null, TRIAL_DAYS + 2, licenseId);

  return ok({
    plan: "trial",
    trialDays: TRIAL_DAYS,
    licenseKey: trial.licenseKey,
    signed: "signed" in trial ? trial.signed : undefined,
    expiresAt: trial.expiresAt,
    reused: trial.reused,
    downloadUrl: `${PUBLIC_APP_URL}/api/download?token=${token}`,
    seats: 1,
    message: trial.reused
      ? "Ya pediste la prueba: reutilizamos tu licencia trial (1 Mac)."
      : `Prueba de ${TRIAL_DAYS} días lista (1 Mac). Activa la clave en Findaro.`,
  });
});
