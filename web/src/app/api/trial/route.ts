import { fail, handle, ok } from "@/lib/api";
import { query } from "@/lib/db";
import { issueDownloadToken } from "@/lib/download";
import { sendTrialConfirmationEmail } from "@/lib/email";
import { issueTrialLicense, TRIAL_DAYS } from "@/lib/license";
import { PUBLIC_APP_URL } from "@/lib/site";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = handle(async (req) => {
  const body = (await req.json().catch(() => null)) as {
    email?: string;
    name?: string;
    utm_source?: string;
    utm_medium?: string;
    utm_campaign?: string;
    utm_content?: string;
  } | null;

  const email = (body?.email || "").trim().toLowerCase();
  const name = (body?.name || "").trim() || "Prueba";
  if (!email || !email.includes("@")) return fail("Correo inválido", 400);

  const utmSource = (body?.utm_source || "").trim() || null;
  const utmMedium = (body?.utm_medium || "").trim() || null;
  const utmCampaign = (body?.utm_campaign || "").trim() || null;
  const utmContent = (body?.utm_content || "").trim() || null;

  const customer = await query<{ id: string }>(
    `INSERT INTO customers (email, name, utm_source, utm_medium, utm_campaign, utm_content, first_seen_at)
     VALUES ($1, $2, $3, $4, $5, $6, now())
     ON CONFLICT (email) DO UPDATE SET 
       name = COALESCE(NULLIF(EXCLUDED.name,''), customers.name),
       utm_source = COALESCE(customers.utm_source, EXCLUDED.utm_source),
       utm_medium = COALESCE(customers.utm_medium, EXCLUDED.utm_medium),
       utm_campaign = COALESCE(customers.utm_campaign, EXCLUDED.utm_campaign),
       utm_content = COALESCE(customers.utm_content, EXCLUDED.utm_content),
       updated_at = now()
     RETURNING id`,
    [email, name, utmSource, utmMedium, utmCampaign, utmContent],
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
    // Nunca devolver la clave Pro aquí: este endpoint no tiene autenticación y bastaría
    // con conocer el correo de un cliente para robar su licencia. La clave va solo por correo.
    return ok({
      plan: "pro",
      licenseKey: "",
      downloadUrl: "",
      message: "Este correo ya tiene licencia Pro. Revisa tu correo de compra o escríbenos para reenviarte la clave.",
    });
  }

  const trial = await issueTrialLicense(customerId, email);
  const lic = await query<{ id: string }>(
    `SELECT id FROM licenses WHERE license_key = $1`,
    [trial.licenseKey],
  );
  const licenseId = lic.rows[0]?.id;
  const token = await issueDownloadToken(null, TRIAL_DAYS + 2, licenseId);
  const downloadUrl = `${PUBLIC_APP_URL}/api/download?token=${token}`;

  // Enviar correo con la clave y enlace de descarga (F-08)
  try {
    await sendTrialConfirmationEmail({
      to: email,
      name,
      licenseKey: trial.licenseKey,
      downloadUrl,
      trialDays: TRIAL_DAYS,
    });
  } catch (emailErr) {
    console.error("[trial] Error enviando correo con clave de prueba:", emailErr);
  }

  return ok({
    plan: "trial",
    trialDays: TRIAL_DAYS,
    licenseKey: trial.licenseKey,
    expiresAt: trial.expiresAt,
    reused: trial.reused,
    downloadUrl,
    seats: 1,
    message: trial.reused
      ? "Ya pediste la prueba: reutilizamos tu licencia trial (1 Mac)."
      : `Prueba de ${TRIAL_DAYS} días emitida (1 Mac). Hemos enviado tu clave por correo. Actívala en Findaro para iniciar tus ${TRIAL_DAYS} días.`,
  });
});
