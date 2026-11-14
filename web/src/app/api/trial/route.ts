import { fail, handle, ok } from "@/lib/api";
import { query } from "@/lib/db";
import { issueDownloadToken } from "@/lib/download";
import { sendTrialConfirmationEmail } from "@/lib/email";
import { detectLanguageFromHeaders } from "@/lib/geo";
import { issueTrialLicense, TRIAL_DAYS } from "@/lib/license";
import { PUBLIC_APP_URL } from "@/lib/site";
import { hit, limitByIp, tooMany } from "@/lib/ratelimit";
import { langFromCookieHeader } from "@/lib/lang";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = handle(async (req) => {
  const limited = limitByIp(req, "trial", 5, 60 * 60_000);
  if (limited) return limited;

  const body = (await req.json().catch(() => null)) as {
    email?: string;
    name?: string;
    lang?: string;
    utm_source?: string;
    utm_medium?: string;
    utm_campaign?: string;
    utm_content?: string;
  } | null;

  const cookieHeader = req.headers.get("cookie") || "";
  const lang = detectLanguageFromHeaders(req.headers, langFromCookieHeader(cookieHeader), body?.lang);
  const isEn = lang === "en";

  const email = (body?.email || "").trim().toLowerCase();
  const name = (body?.name || "").trim() || (isEn ? "Trial User" : "Prueba");
  if (!email || !email.includes("@")) {
    return fail(isEn ? "Invalid email address" : "Correo inválido", 400);
  }
  if (!hit(`trial:email:${email}`, 3, 24 * 60 * 60_000)) return tooMany();

  const utmSource = (body?.utm_source || "").trim().slice(0, 128) || null;
  const utmMedium = (body?.utm_medium || "").trim().slice(0, 128) || null;
  const utmCampaign = (body?.utm_campaign || "").trim().slice(0, 128) || null;
  const utmContent = (body?.utm_content || "").trim().slice(0, 128) || null;

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
  if (!customerId) return fail(isEn ? "Could not register trial" : "No se pudo registrar", 500);

  const pro = await query<{ license_key: string; id: string }>(
    `SELECT id, license_key FROM licenses
     WHERE customer_id = $1 AND plan = 'pro' AND revoked = false
     LIMIT 1`,
    [customerId],
  );
  if (pro.rows[0]) {
    return ok({
      plan: "pro",
      licenseKey: "",
      downloadUrl: "",
      message: isEn
        ? "This email already holds an active Pro license. Check your purchase email or contact support to resend your key."
        : "Este correo ya tiene licencia Pro. Revisa tu correo de compra o escríbenos para reenviarte la clave.",
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

  try {
    await sendTrialConfirmationEmail({
      to: email,
      name,
      licenseKey: trial.licenseKey,
      downloadUrl,
      trialDays: TRIAL_DAYS,
      lang,
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
      ? isEn
        ? "You already requested a trial: we reused your trial license key (1 Mac)."
        : "Ya pediste la prueba: reutilizamos tu licencia trial (1 Mac)."
      : isEn
        ? `${TRIAL_DAYS}-day free trial issued (1 Mac). We also emailed your key. Activate it inside Findaro to start your ${TRIAL_DAYS} days.`
        : `Prueba de ${TRIAL_DAYS} días emitida (1 Mac). Hemos enviado tu clave por correo. Actívala en Findaro para iniciar tus ${TRIAL_DAYS} días.`,
  });
});
