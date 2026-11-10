/**
 * Servicio de envío de correos transaccionales bilingües (ES / EN) para Findaro.
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
  lang?: "en" | "es";
}

export interface TrialEmailPayload {
  to: string;
  name: string;
  licenseKey: string;
  downloadUrl: string;
  trialDays: number;
  lang?: "en" | "es";
}

export async function sendTrialConfirmationEmail(
  payload: TrialEmailPayload,
): Promise<{ success: boolean; id?: string }> {
  const isEn = payload.lang === "en";
  const supportAddr = isEn ? "support@findaro.iareal.net" : "soporte@findaro.iareal.net";
  const emailSubject = isEn
    ? `Your Findaro free trial key (${payload.trialDays} days)`
    : `Tu clave de prueba de Findaro (${payload.trialDays} días)`;

  const html = `
<!DOCTYPE html>
<html lang="${isEn ? "en" : "es"}">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${escapeHtml(emailSubject)}</title>
</head>
<body style="margin:0;padding:0;background-color:#090d16;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#f1f5f9;">
  <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#090d16;padding:32px 16px;">
    <tr>
      <td align="center">
        <table width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:560px;background:#0f172a;border:1px solid #1e293b;border-radius:14px;overflow:hidden;box-shadow:0 12px 30px rgba(0,0,0,0.45);">
          <tr>
            <td style="padding:28px 28px 16px;text-align:center;border-bottom:1px solid rgba(255,255,255,0.06);background:linear-gradient(180deg, #131d35 0%, #0f172a 100%);">
              <div style="font-size:24px;font-weight:900;letter-spacing:2px;color:#38bdf8;">FINDARO</div>
              <div style="font-size:13px;color:#94a3b8;margin-top:4px;">${
                isEn ? "AI-Powered Dual-Pane File Manager for macOS" : "Explorador de archivos inteligente para macOS"
              }</div>
            </td>
          </tr>
          <tr>
            <td style="padding:32px 28px;">
              <h1 style="font-size:20px;font-weight:700;color:#ffffff;margin:0 0 12px;">${
                isEn
                  ? `Hi ${escapeHtml(payload.name || "there")}!`
                  : `¡Hola, ${escapeHtml(payload.name || "amigo")}!`
              }</h1>
              <p style="font-size:14px;line-height:1.6;color:#cbd5e1;margin:0 0 24px;">
                ${
                  isEn
                    ? `Here is your license key to activate your ${payload.trialDays}-day free trial on your Mac. The ${payload.trialDays}-day timer only starts once you activate the key inside the app.`
                    : `Aquí tienes tu clave para activar tu prueba gratuita de ${payload.trialDays} días en tu Mac. El contador de ${payload.trialDays} días comienza únicamente cuando actives la clave en tu aplicación.`
                }
              </p>

              <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#020617;border:1px solid #334155;border-radius:10px;margin-bottom:24px;">
                <tr>
                  <td style="padding:18px 20px;">
                    <div style="font-size:12px;color:#94a3b8;text-transform:uppercase;letter-spacing:1px;margin-bottom:6px;">
                      ${
                        isEn
                          ? `Your trial key (${payload.trialDays} days · 1 Mac):`
                          : `Tu clave de prueba (${payload.trialDays} días · 1 Mac):`
                      }
                    </div>
                    <div style="font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,monospace;font-size:17px;font-weight:700;color:#38bdf8;letter-spacing:1px;word-break:break-all;">
                      ${escapeHtml(payload.licenseKey)}
                    </div>
                    <div style="font-size:12px;color:#64748b;margin-top:10px;line-height:1.4;">
                      ${
                        isEn
                          ? `ℹ️ <strong>How to activate:</strong> Open Findaro → Top menu or ⌘, (Settings) → <strong>License</strong> tab → Paste your key.`
                          : `ℹ️ <strong>Cómo activar:</strong> Abre Findaro → Menú superior o ⌘, (Preferencias) → Pestaña <strong>Licencia</strong> → Pega tu clave.`
                      }
                    </div>
                  </td>
                </tr>
              </table>

              <table width="100%" cellpadding="0" cellspacing="0" border="0" style="margin-bottom:28px;">
                <tr>
                  <td align="center">
                    <a href="${escapeHtml(payload.downloadUrl)}" target="_blank" style="display:inline-block;background:#0284c7;color:#ffffff;font-size:15px;font-weight:700;text-decoration:none;padding:14px 28px;border-radius:8px;box-shadow:0 4px 14px rgba(2,132,199,0.35);">
                      ⬇️ ${isEn ? "Download Findaro for macOS" : "Descargar Findaro para macOS"}
                    </a>
                  </td>
                </tr>
              </table>

              <p style="font-size:12px;color:#64748b;margin:0;">
                ${
                  isEn
                    ? `Questions or feedback? Reply directly to this email or write to ${supportAddr}.`
                    : `¿Dudas o comentarios? Escríbenos directamente respondiendo a este correo o a ${supportAddr}.`
                }
              </p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;

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
  const isEn = payload.lang === "en";
  const langParam = isEn ? "en" : "es";
  const supportAddr = isEn ? "support@findaro.iareal.net" : ADMIN_EMAIL;

  const tierName =
    payload.tier === "family"
      ? isEn
        ? "Family Plan (5 Macs)"
        : "Plan Familiar (5 Macs)"
      : isEn
        ? "Personal Plan (2 Macs)"
        : "Plan Personal (2 Macs)";

  const emailSubject = isEn
    ? `Your Findaro Lifetime License for macOS ⚡ (${tierName})`
    : `Tu licencia de Findaro para macOS ⚡ (${tierName})`;

  const html = `
<!DOCTYPE html>
<html lang="${langParam}">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${escapeHtml(emailSubject)}</title>
</head>
<body style="margin:0;padding:0;background-color:#090d16;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#f1f5f9;">
  <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#090d16;padding:32px 16px;">
    <tr>
      <td align="center">
        <table width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:560px;background:#0f172a;border:1px solid #1e293b;border-radius:14px;overflow:hidden;box-shadow:0 12px 30px rgba(0,0,0,0.45);">
          <tr>
            <td style="padding:28px 28px 16px;text-align:center;border-bottom:1px solid rgba(255,255,255,0.06);background:linear-gradient(180deg, #131d35 0%, #0f172a 100%);">
              <div style="font-size:24px;font-weight:900;letter-spacing:2px;color:#38bdf8;">FINDARO</div>
              <div style="font-size:13px;color:#94a3b8;margin-top:4px;">${
                isEn ? "AI-Powered Dual-Pane File Manager for macOS" : "Explorador de archivos inteligente para macOS"
              }</div>
            </td>
          </tr>
          <tr>
            <td style="padding:32px 28px;">
              <h1 style="font-size:20px;font-weight:700;color:#ffffff;margin:0 0 12px;">${
                isEn
                  ? `Thank you for your purchase, ${escapeHtml(payload.name || "friend")}!`
                  : `¡Gracias por tu compra, ${escapeHtml(payload.name || "amigo")}!`
              }</h1>
              <p style="font-size:14px;line-height:1.6;color:#cbd5e1;margin:0 0 24px;">
                ${
                  isEn
                    ? "Your payment has been confirmed. You now have lifetime access to Findaro with all automatic updates included."
                    : "Tu pago ha sido confirmado. Ya tienes acceso de por vida a Findaro con todas las actualizaciones automáticas incluidas."
                }
              </p>

              <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#020617;border:1px solid #334155;border-radius:10px;margin-bottom:24px;">
                <tr>
                  <td style="padding:18px 20px;">
                    <div style="font-size:12px;color:#94a3b8;text-transform:uppercase;letter-spacing:1px;margin-bottom:6px;">
                      ${isEn ? `License Key (${escapeHtml(tierName)}):` : `Clave de Licencia (${escapeHtml(tierName)}):`}
                    </div>
                    <div style="font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,monospace;font-size:17px;font-weight:700;color:#38bdf8;letter-spacing:1px;word-break:break-all;">
                      ${escapeHtml(payload.licenseKey)}
                    </div>
                    <div style="font-size:12px;color:#64748b;margin-top:10px;line-height:1.4;">
                      ${
                        isEn
                          ? `ℹ️ <strong>How to activate:</strong> Open Findaro → Top menu or ⌘, (Settings) → <strong>License</strong> tab → Paste your key.`
                          : `ℹ️ <strong>Cómo activar:</strong> Abre Findaro → Menú superior o ⌘, (Preferencias) → Pestaña <strong>Licencia</strong> → Pega tu clave.`
                      }
                    </div>
                  </td>
                </tr>
              </table>

              <table width="100%" cellpadding="0" cellspacing="0" border="0" style="margin-bottom:28px;">
                <tr>
                  <td align="center">
                    <a href="${escapeHtml(payload.downloadUrl)}" target="_blank" style="display:inline-block;background:#0284c7;color:#ffffff;font-size:15px;font-weight:700;text-decoration:none;padding:14px 28px;border-radius:8px;box-shadow:0 4px 14px rgba(2,132,199,0.35);">
                      ⬇️ ${isEn ? "Download Findaro for macOS" : "Descargar Findaro para macOS"}
                    </a>
                  </td>
                </tr>
              </table>

              <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background:rgba(34,197,94,0.08);border:1px solid rgba(34,197,94,0.3);border-radius:10px;margin-bottom:24px;">
                <tr>
                  <td style="padding:18px 20px;">
                    <div style="font-size:14px;font-weight:700;color:#4ade80;margin-bottom:6px;">
                      🎁 ${isEn ? "Share Findaro with friends" : "Comparte Findaro con tus amigos"}
                    </div>
                    <p style="font-size:13px;line-height:1.5;color:#cbd5e1;margin:0 0 10px;">
                      ${
                        isEn
                          ? "Your friends get an <strong>instant discount</strong> on their purchase when using your referral link or code:"
                          : "Tus amigos reciben <strong>descuento directo</strong> en su compra al usar tu enlace o código de recomendación:"
                      }
                    </p>
                    <div style="background:#020617;padding:8px 12px;border-radius:6px;font-family:monospace;font-size:12px;color:#94a3b8;word-break:break-all;">
                      ${escapeHtml(payload.referralLink)}
                    </div>
                  </td>
                </tr>
              </table>

              <p style="font-size:13px;color:#94a3b8;line-height:1.5;margin:0;">
                ${
                  isEn
                    ? `Need help installing or activating? Reply directly to this email or contact us at <a href="mailto:${supportAddr}" style="color:#38bdf8;text-decoration:none;">${supportAddr}</a>.`
                    : `¿Tienes alguna pregunta o necesitas ayuda instalando? Responde directamente a este correo o escríbenos a <a href="mailto:${supportAddr}" style="color:#38bdf8;text-decoration:none;">${supportAddr}</a>.`
                }
              </p>
            </td>
          </tr>
          <tr>
            <td style="padding:20px 28px;background:#090d16;border-top:1px solid rgba(255,255,255,0.06);text-align:center;font-size:12px;color:#64748b;">
              ${isEn ? "Findaro for macOS · 14-day satisfaction guarantee" : "Findaro para macOS · Garantía de satisfacción de 14 días"}<br>
              <a href="https://findaro.iareal.net/terminos?lang=${langParam}" style="color:#64748b;text-decoration:underline;">${isEn ? "Terms of Service" : "Términos de Servicio"}</a> ·
              <a href="https://findaro.iareal.net/privacidad?lang=${langParam}" style="color:#64748b;text-decoration:underline;">${isEn ? "Privacy" : "Privacidad"}</a> ·
              <a href="https://findaro.iareal.net/reembolso?lang=${langParam}" style="color:#64748b;text-decoration:underline;">${isEn ? "Refund Policy" : "Política de Reembolso"}</a>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>
  `.trim();

  let buyerSent = false;
  let buyerId: string | undefined;

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
  }

  if (!buyerSent && EMAIL_GATEWAY_URL) {
    try {
      const fallbackRes = await fetch(EMAIL_GATEWAY_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          appId: "findaro",
          event: "purchase.confirmation",
          to: payload.to,
          subject: emailSubject,
          html,
          data: {
            name: payload.name,
            licenseKey: payload.licenseKey,
            downloadUrl: payload.downloadUrl,
            referralLink: payload.referralLink,
            seats: payload.seats,
            tier: payload.tier,
            lang: langParam,
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

  if (RESEND_API_KEY) {
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
              <p><strong>Plan:</strong> ${escapeHtml(tierName)} · Idioma: ${langParam.toUpperCase()}</p>
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
