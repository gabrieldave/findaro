/**
 * Servicio de envío de correos transaccionales para Findaro.
 * Utiliza Resend API directamente con fallback al Email Gateway de n8n.
 */

const RESEND_API_KEY = process.env.RESEND_API_KEY?.trim() || "";
const EMAIL_FROM =
  process.env.EMAIL_FROM?.trim() || "Findaro <soporte@findaro.iareal.net>";
const ADMIN_EMAIL =
  process.env.SUPPORT_EMAIL?.trim() || process.env.ADMIN_EMAIL?.trim() || "soporte@findaro.iareal.net";
const EMAIL_GATEWAY_URL =
  process.env.EMAIL_GATEWAY_URL?.trim() || "https://n8n.vibesystems.tech/webhook/email/send";

export interface PurchaseEmailPayload {
  to: string;
  name: string;
  licenseKey: string;
  downloadUrl: string;
  referralLink: string;
  seats: number;
  tier: string;
}

export interface TrialEmailPayload {
  to: string;
  name: string;
  licenseKey: string;
  downloadUrl: string;
  trialDays: number;
}

export async function sendTrialConfirmationEmail(
  payload: TrialEmailPayload,
): Promise<{ success: boolean; id?: string }> {
  const html = `
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Tu clave de prueba de Findaro</title>
</head>
<body style="margin:0;padding:0;background-color:#090d16;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#f1f5f9;">
  <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#090d16;padding:32px 16px;">
    <tr>
      <td align="center">
        <table width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:560px;background:#0f172a;border:1px solid #1e293b;border-radius:14px;overflow:hidden;box-shadow:0 12px 30px rgba(0,0,0,0.45);">
          <!-- Header -->
          <tr>
            <td style="padding:28px 28px 16px;text-align:center;border-bottom:1px solid rgba(255,255,255,0.06);background:linear-gradient(180deg, #131d35 0%, #0f172a 100%);">
              <div style="font-size:24px;font-weight:900;letter-spacing:2px;color:#38bdf8;">FINDARO</div>
              <div style="font-size:13px;color:#94a3b8;margin-top:4px;">Explorador de archivos inteligente para macOS</div>
            </td>
          </tr>

          <!-- Body Content -->
          <tr>
            <td style="padding:32px 28px;">
              <h1 style="font-size:20px;font-weight:700;color:#ffffff;margin:0 0 12px;">¡Hola, ${escapeHtml(payload.name || "amigo")}!</h1>
              <p style="font-size:14px;line-height:1.6;color:#cbd5e1;margin:0 0 24px;">
                Aquí tienes tu clave para activar tu prueba gratuita de ${payload.trialDays} días en tu Mac. El contador de 5 días comienza únicamente cuando actives la clave en tu aplicación.
              </p>

              <!-- License Card -->
              <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#020617;border:1px solid #334155;border-radius:10px;margin-bottom:24px;">
                <tr>
                  <td style="padding:18px 20px;">
                    <div style="font-size:12px;color:#94a3b8;text-transform:uppercase;letter-spacing:1px;margin-bottom:6px;">
                      Tu clave de prueba (${payload.trialDays} días · 1 Mac):
                    </div>
                    <div style="font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,monospace;font-size:17px;font-weight:700;color:#38bdf8;letter-spacing:1px;word-break:break-all;">
                      ${escapeHtml(payload.licenseKey)}
                    </div>
                    <div style="font-size:12px;color:#64748b;margin-top:10px;line-height:1.4;">
                      ℹ️ <strong>Cómo activar:</strong> Abre Findaro → Menú superior o ⌘, (Preferencias) → Pestaña <strong>Licencia</strong> → Pega tu clave.
                    </div>
                  </td>
                </tr>
              </table>

              <!-- CTA Download Button -->
              <table width="100%" cellpadding="0" cellspacing="0" border="0" style="margin-bottom:28px;">
                <tr>
                  <td align="center">
                    <a href="${escapeHtml(payload.downloadUrl)}" target="_blank" style="display:inline-block;background:#0284c7;color:#ffffff;font-size:15px;font-weight:700;text-decoration:none;padding:14px 28px;border-radius:8px;box-shadow:0 4px 14px rgba(2,132,199,0.35);">
                      ⬇️ Descargar Findaro para macOS
                    </a>
                  </td>
                </tr>
              </table>

              <p style="font-size:12px;color:#64748b;margin:0;">
                ¿Dudas o comentarios? Escríbenos directamente respondiendo a este correo o a soporte@findaro.iareal.net.
              </p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;

  const emailSubject = `Tu clave de prueba de Findaro (${payload.trialDays} días)`;

  if (RESEND_API_KEY) {
    try {
      const res = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${RESEND_API_KEY}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          from: EMAIL_FROM,
          to: [payload.to],
          subject: emailSubject,
          html,
        }),
      });
      const data = (await res.json().catch(() => null)) as { id?: string } | null;
      if (res.ok && data?.id) {
        return { success: true, id: data.id };
      }
    } catch (e) {
      console.warn("[Email] Resend falló para trial, probando gateway:", e);
    }
  }

  try {
    const gwRes = await fetch(EMAIL_GATEWAY_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        to: payload.to,
        from: EMAIL_FROM,
        subject: emailSubject,
        html,
      }),
    });
    const gwData = (await gwRes.json().catch(() => null)) as { success?: boolean; id?: string } | null;
    return { success: Boolean(gwRes.ok && gwData?.success), id: gwData?.id };
  } catch (gwErr) {
    console.error("[Email] Ambos envíos fallaron para trial:", gwErr);
    return { success: false };
  }
}

export async function sendPurchaseConfirmationEmail(
  payload: PurchaseEmailPayload,
): Promise<{ success: boolean; id?: string }> {
  const tierName =
    payload.tier === "family"
      ? "Plan Familiar (5 Macs)"
      : "Plan Personal (2 Macs)";

  const html = `
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Tu licencia de Findaro</title>
</head>
<body style="margin:0;padding:0;background-color:#090d16;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#f1f5f9;">
  <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#090d16;padding:32px 16px;">
    <tr>
      <td align="center">
        <table width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:560px;background:#0f172a;border:1px solid #1e293b;border-radius:14px;overflow:hidden;box-shadow:0 12px 30px rgba(0,0,0,0.45);">
          <!-- Header -->
          <tr>
            <td style="padding:28px 28px 16px;text-align:center;border-bottom:1px solid rgba(255,255,255,0.06);background:linear-gradient(180deg, #131d35 0%, #0f172a 100%);">
              <div style="font-size:24px;font-weight:900;letter-spacing:2px;color:#38bdf8;">FINDARO</div>
              <div style="font-size:13px;color:#94a3b8;margin-top:4px;">Explorador de archivos inteligente para macOS</div>
            </td>
          </tr>

          <!-- Body Content -->
          <tr>
            <td style="padding:32px 28px;">
              <h1 style="font-size:20px;font-weight:700;color:#ffffff;margin:0 0 12px;">¡Gracias por tu compra, ${escapeHtml(payload.name || "amigo")}!</h1>
              <p style="font-size:14px;line-height:1.6;color:#cbd5e1;margin:0 0 24px;">
                Tu pago ha sido confirmado. Ya tienes acceso de por vida a Findaro con todas las actualizaciones automáticas incluidas.
              </p>

              <!-- License Card -->
              <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#020617;border:1px solid #334155;border-radius:10px;margin-bottom:24px;">
                <tr>
                  <td style="padding:18px 20px;">
                    <div style="font-size:12px;color:#94a3b8;text-transform:uppercase;letter-spacing:1px;margin-bottom:6px;">
                      Clave de Licencia (${escapeHtml(tierName)}):
                    </div>
                    <div style="font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,monospace;font-size:17px;font-weight:700;color:#38bdf8;letter-spacing:1px;word-break:break-all;">
                      ${escapeHtml(payload.licenseKey)}
                    </div>
                    <div style="font-size:12px;color:#64748b;margin-top:10px;line-height:1.4;">
                      ℹ️ <strong>Cómo activar:</strong> Abre Findaro → Menú superior o ⌘, (Preferencias) → Pestaña <strong>Licencia</strong> → Pega tu clave.
                    </div>
                  </td>
                </tr>
              </table>

              <!-- CTA Download Button -->
              <table width="100%" cellpadding="0" cellspacing="0" border="0" style="margin-bottom:28px;">
                <tr>
                  <td align="center">
                    <a href="${escapeHtml(payload.downloadUrl)}" target="_blank" style="display:inline-block;background:#0284c7;color:#ffffff;font-size:15px;font-weight:700;text-decoration:none;padding:14px 28px;border-radius:8px;box-shadow:0 4px 14px rgba(2,132,199,0.35);">
                      ⬇️ Descargar Findaro para macOS
                    </a>
                  </td>
                </tr>
              </table>

              <!-- Referral / Cashback Box -->
              <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background:rgba(34,197,94,0.08);border:1px solid rgba(34,197,94,0.3);border-radius:10px;margin-bottom:24px;">
                <tr>
                  <td style="padding:18px 20px;">
                    <div style="font-size:14px;font-weight:700;color:#4ade80;margin-bottom:6px;">
                      🎁 Comparte Findaro con tus amigos
                    </div>
                    <p style="font-size:13px;line-height:1.5;color:#cbd5e1;margin:0 0 10px;">
                      Tus amigos reciben <strong>descuento directo</strong> en su compra al usar tu enlace o código de recomendación:
                    </p>
                    <div style="background:#020617;padding:8px 12px;border-radius:6px;font-family:monospace;font-size:12px;color:#94a3b8;word-break:break-all;">
                      ${escapeHtml(payload.referralLink)}
                    </div>
                  </td>
                </tr>
              </table>

              <p style="font-size:13px;color:#94a3b8;line-height:1.5;margin:0;">
                ¿Tienes alguna pregunta o necesitas ayuda instalando? Responde directamente a este correo o escríbenos a <a href="mailto:${ADMIN_EMAIL}" style="color:#38bdf8;text-decoration:none;">${ADMIN_EMAIL}</a>.
              </p>
            </td>
          </tr>

          <!-- Footer -->
          <tr>
            <td style="padding:20px 28px;background:#090d16;border-top:1px solid rgba(255,255,255,0.06);text-align:center;font-size:12px;color:#64748b;">
              Findaro para macOS · Garantía de satisfacción de 14 días<br>
              <a href="https://findaro.iareal.net/terminos" style="color:#64748b;text-decoration:underline;">Términos de Servicio</a> · 
              <a href="https://findaro.iareal.net/privacidad" style="color:#64748b;text-decoration:underline;">Privacidad</a> · 
              <a href="https://findaro.iareal.net/reembolso" style="color:#64748b;text-decoration:underline;">Política de Reembolso</a>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>
  `.trim();

  // 1. Envío principal al comprador vía Resend API
  let buyerSent = false;
  let buyerId: string | undefined;

  try {
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${RESEND_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: EMAIL_FROM,
        to: [payload.to],
        subject: `Tu licencia de Findaro para macOS ⚡ (${tierName})`,
        html,
      }),
      cache: "no-store",
    });

    if (res.ok) {
      const json = (await res.json().catch(() => null)) as { id?: string } | null;
      buyerSent = true;
      buyerId = json?.id;
    } else {
      console.error("[Email] Error Resend comprador:", await res.text().catch(() => ""));
    }
  } catch (err) {
    console.error("[Email] Falló conexión con Resend:", err);
  }

  // Fallback secundario a través de n8n si Resend falló
  if (!buyerSent && EMAIL_GATEWAY_URL) {
    try {
      const fallbackRes = await fetch(EMAIL_GATEWAY_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          appId: "findaro",
          event: "purchase.confirmation",
          to: payload.to,
          data: {
            name: payload.name,
            licenseKey: payload.licenseKey,
            downloadUrl: payload.downloadUrl,
            referralLink: payload.referralLink,
            seats: payload.seats,
            tier: payload.tier,
          },
        }),
      });
      if (fallbackRes.ok) {
        buyerSent = true;
      }
    } catch (fbErr) {
      console.error("[Email] Fallback n8n falló:", fbErr);
    }
  }

  // 2. Notificación al Administrador (David) de la venta
  try {
    await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${RESEND_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: EMAIL_FROM,
        to: [ADMIN_EMAIL],
        subject: `🎉 [Nueva Venta Findaro] ${payload.name} (${tierName})`,
        html: `
          <div style="font-family:sans-serif;padding:20px;background:#0f172a;color:#f8fafc;border-radius:8px;">
            <h2 style="color:#4ade80;">¡Nueva venta registrada en Findaro!</h2>
            <p><strong>Cliente:</strong> ${escapeHtml(payload.name)} (&lt;${escapeHtml(payload.to)}&gt;)</p>
            <p><strong>Plan:</strong> ${escapeHtml(tierName)}</p>
            <p><strong>Clave emitida:</strong> <code>${escapeHtml(payload.licenseKey)}</code></p>
            <p><strong>Enlace de referido del cliente:</strong> ${escapeHtml(payload.referralLink)}</p>
          </div>
        `,
      }),
      cache: "no-store",
    });
  } catch (adminErr) {
    console.error("[Email] Notificación admin falló:", adminErr);
  }

  return { success: buyerSent, id: buyerId };
}

function escapeHtml(str: string): string {
  return str
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}
