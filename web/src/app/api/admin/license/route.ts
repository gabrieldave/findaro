import { randomUUID } from "crypto";
import { fail, handle, ok, verifySameOrigin } from "@/lib/api";
import { query } from "@/lib/db";
import { issueDownloadToken, verifyAdminCookie } from "@/lib/download";
import {
  sendPurchaseConfirmationEmail,
  sendTrialConfirmationEmail,
} from "@/lib/email";
import {
  issueProLicense,
  mintReferralCode,
  TRIAL_DAYS,
} from "@/lib/license";
import type { LicenseTier } from "@/lib/pricing";
import { PUBLIC_APP_URL } from "@/lib/site";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

type AdminLicenseAction =
  | "revoke"
  | "restore"
  | "reset_activations"
  | "resend_email"
  | "issue_manual";

function normalizeTier(raw: unknown): LicenseTier {
  if (raw === "solo" || raw === "family" || raw === "personal") return raw;
  return "personal";
}

/** Acción administrativa sobre licencias: revocar, restaurar, limpiar Macs, reenviar correo o emitir manual. */
export const POST = handle(async (req) => {
  if (!verifySameOrigin(req)) return fail("Origen no permitido", 403);
  const cookie = req.headers.get("cookie") || "";
  const match = cookie.match(/(?:^|;\s*)findaro_admin=([^;]+)/);
  const adminEmail = verifyAdminCookie(match?.[1]);
  if (!adminEmail) return fail("No autorizado", 401);

  const body = (await req.json().catch(() => null)) as {
    licenseKey?: string;
    action?: AdminLicenseAction;
    email?: string;
    name?: string;
    tier?: LicenseTier;
    sendEmail?: boolean;
    lang?: "en" | "es";
  } | null;

  const action = body?.action;
  const baseUrl = PUBLIC_APP_URL.replace(/\/$/, "");
  const lang: "en" | "es" = body?.lang === "en" ? "en" : "es";

  if (action === "issue_manual") {
    const targetEmail = (body?.email || "").trim().toLowerCase();
    const targetName = (body?.name || "").trim();
    if (!targetEmail || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(targetEmail)) {
      return fail("Email de cliente inválido", 400);
    }

    const tier = normalizeTier(body?.tier);
    const upsertRes = await query<{
      id: string;
      email: string;
      name: string;
      referral_code: string | null;
    }>(
      `INSERT INTO customers (email, name, updated_at)
       VALUES ($1, $2, now())
       ON CONFLICT (email) DO UPDATE SET
         name = COALESCE(NULLIF(EXCLUDED.name, ''), customers.name),
         updated_at = now()
       RETURNING id, email, name, referral_code`,
      [targetEmail, targetName],
    );
    const customer = upsertRes.rows[0];
    if (!customer) return fail("No se pudo registrar el cliente", 500);

    let refCode = customer.referral_code;
    if (!refCode) {
      refCode = mintReferralCode(customer.name || customer.email);
      await query(`UPDATE customers SET referral_code = $1 WHERE id = $2`, [
        refCode,
        customer.id,
      ]);
    }

    const orderRes = await query<{ id: string }>(
      `INSERT INTO orders (customer_id, amount_usd, currency, status, stripe_session_id, promo_slot, tier, paid_at)
       VALUES ($1, 0.00, 'usd', 'paid', $2, false, $3, now())
       RETURNING id`,
      [customer.id, `manual_${randomUUID()}`, tier],
    );
    const orderId = orderRes.rows[0]?.id;
    if (!orderId) return fail("No se pudo crear orden manual", 500);

    const pro = await issueProLicense({
      customerId: customer.id,
      orderId,
      email: customer.email,
      tier,
    });

    const licRow = await query<{ id: string }>(
      `SELECT id FROM licenses WHERE license_key = $1`,
      [pro.licenseKey],
    );
    const token = await issueDownloadToken(orderId, 30, licRow.rows[0]?.id ?? null);
    const downloadUrl = `${baseUrl}/api/download?token=${token}`;
    const referralLink = `${baseUrl}/?ref=${refCode}`;

    let emailSent = false;
    if (body?.sendEmail !== false) {
      const emailRes = await sendPurchaseConfirmationEmail({
        to: customer.email,
        name: customer.name,
        licenseKey: pro.licenseKey,
        downloadUrl,
        referralLink,
        seats: pro.seats,
        tier: pro.tier,
        lang,
      });
      emailSent = emailRes.success;
      if (emailSent) {
        await query(`UPDATE orders SET email_sent_at = now() WHERE id = $1`, [orderId]);
      }
    }

    return ok({
      licenseKey: pro.licenseKey,
      tier: pro.tier,
      seats: pro.seats,
      emailSent,
      message: `Licencia ${pro.licenseKey} (${pro.tier} · ${pro.seats} Macs) emitida para ${customer.email}${emailSent ? " y enviada por correo." : "."}`,
    });
  }

  const licenseKey = (body?.licenseKey || "").trim().toUpperCase();
  if (!licenseKey) return fail("licenseKey requerido", 400);

  if (action === "resend_email") {
    const res = await query<{
      id: string;
      license_key: string;
      plan: "trial" | "pro";
      tier: string;
      seats: number;
      revoked: boolean;
      order_id: string | null;
      customer_id: string;
      email: string;
      name: string;
      referral_code: string | null;
    }>(
      `SELECT l.id, l.license_key, l.plan, COALESCE(l.tier, 'personal') AS tier, l.seats,
              l.revoked, l.order_id, l.customer_id, c.email, c.name, c.referral_code
       FROM licenses l
       JOIN customers c ON c.id = l.customer_id
       WHERE l.license_key = $1`,
      [licenseKey],
    );
    const lic = res.rows[0];
    if (!lic) return fail("Licencia no encontrada", 404);
    if (lic.revoked) {
      return fail("La licencia está revocada; reactívala antes de reenviar.", 400);
    }

    if (lic.plan === "pro") {
      let refCode = lic.referral_code;
      if (!refCode) {
        refCode = mintReferralCode(lic.name || lic.email);
        await query(`UPDATE customers SET referral_code = $1 WHERE id = $2`, [
          refCode,
          lic.customer_id,
        ]);
      }
      const token = await issueDownloadToken(lic.order_id, 30, lic.id);
      const downloadUrl = `${baseUrl}/api/download?token=${token}`;
      const referralLink = `${baseUrl}/?ref=${refCode}`;
      const emailRes = await sendPurchaseConfirmationEmail({
        to: lic.email,
        name: lic.name,
        licenseKey: lic.license_key,
        downloadUrl,
        referralLink,
        seats: lic.seats,
        tier: lic.tier,
        lang,
      });
      if (!emailRes.success) {
        return fail("No se pudo enviar el correo de licencia Pro.", 502);
      }
      if (lic.order_id) {
        await query(`UPDATE orders SET email_sent_at = now() WHERE id = $1`, [
          lic.order_id,
        ]);
      }
      return ok({
        licenseKey: lic.license_key,
        emailSent: true,
        message: `Correo Pro reenviado a ${lic.email}.`,
      });
    }

    const token = await issueDownloadToken(null, TRIAL_DAYS + 2, lic.id);
    const downloadUrl = `${baseUrl}/api/download?token=${token}`;
    const emailRes = await sendTrialConfirmationEmail({
      to: lic.email,
      name: lic.name,
      licenseKey: lic.license_key,
      downloadUrl,
      trialDays: TRIAL_DAYS,
      lang,
    });
    if (!emailRes.success) {
      return fail("No se pudo enviar el correo de prueba.", 502);
    }
    return ok({
      licenseKey: lic.license_key,
      emailSent: true,
      message: `Correo Trial reenviado a ${lic.email}.`,
    });
  }

  const lic = await query<{ id: string; revoked: boolean }>(
    `SELECT id, revoked FROM licenses WHERE license_key = $1`,
    [licenseKey],
  );
  if (!lic.rows[0]) return fail("Licencia no encontrada", 404);

  const licenseId = lic.rows[0].id;

  if (action === "revoke") {
    await query(`UPDATE licenses SET revoked = true WHERE id = $1`, [licenseId]);
    return ok({ licenseKey, status: "revoked", message: "Licencia revocada (Kill-switch activado)." });
  }

  if (action === "restore") {
    await query(`UPDATE licenses SET revoked = false WHERE id = $1`, [licenseId]);
    return ok({ licenseKey, status: "active", message: "Licencia restaurada." });
  }

  if (action === "reset_activations") {
    await query(`DELETE FROM license_activations WHERE license_id = $1`, [licenseId]);
    return ok({ licenseKey, message: "Todas las activaciones de equipos fueron liberadas." });
  }

  return fail("Acción no válida", 400);
});
