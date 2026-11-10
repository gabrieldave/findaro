import { createHmac, randomBytes, timingSafeEqual } from "crypto";
import { query } from "./db";

export function newDownloadToken(): string {
  return randomBytes(32).toString("base64url");
}

export async function issueDownloadToken(
  orderId: string | null,
  days = 30,
  licenseId?: string | null,
) {
  const token = newDownloadToken();
  const expires = new Date(Date.now() + days * 24 * 60 * 60 * 1000);
  await query(
    `INSERT INTO download_tokens (order_id, license_id, token, expires_at)
     VALUES ($1, $2, $3, $4)`,
    [orderId, licenseId ?? null, token, expires.toISOString()],
  );
  return token;
}

/**
 * Consumo atómico del token de descarga en una sola sentencia UPDATE ... RETURNING
 * para evitar condiciones de carrera (TOCTOU) sobre `used_count < max_uses`.
 */
export async function consumeDownloadToken(token: string) {
  const { rows } = await query<{
    id: string;
    order_id: string | null;
    license_id: string | null;
    used_count: number;
    max_uses: number;
    expires_at: Date;
  }>(
    `UPDATE download_tokens t
     SET used_count = t.used_count + 1
     FROM (
       SELECT dt.id,
              o.status AS order_status,
              l.revoked AS license_revoked,
              l.plan AS license_plan,
              l.expires_at AS license_expires
       FROM download_tokens dt
       LEFT JOIN orders o ON o.id = dt.order_id
       LEFT JOIN licenses l ON l.id = dt.license_id
       WHERE dt.token = $1
     ) s
     WHERE t.id = s.id
       AND t.used_count < t.max_uses
       AND t.expires_at > now()
       AND (
         (t.order_id IS NOT NULL AND s.order_status = 'paid')
         OR (
           t.license_id IS NOT NULL
           AND s.license_revoked = false
           AND (
             s.license_plan = 'pro'
             OR (s.license_plan = 'trial' AND s.license_expires IS NOT NULL AND s.license_expires > now())
           )
         )
       )
     RETURNING t.id, t.order_id, t.license_id, t.used_count, t.max_uses, t.expires_at`,
    [token],
  );
  return rows[0] || null;
}

export function adminSessionSecret(): string {
  const s = process.env.ADMIN_SESSION_SECRET;
  if (!s || s.length < 24) throw new Error("ADMIN_SESSION_SECRET inválido");
  return s;
}

export function signAdminCookie(email: string): string {
  const exp = Date.now() + 7 * 24 * 60 * 60 * 1000;
  const payload = `${email}|${exp}`;
  const sig = createHmac("sha256", adminSessionSecret())
    .update(payload)
    .digest("base64url");
  return Buffer.from(`${payload}|${sig}`).toString("base64url");
}

export function verifyAdminCookie(raw: string | undefined): string | null {
  if (!raw) return null;
  try {
    const decoded = Buffer.from(raw, "base64url").toString("utf8");
    const parts = decoded.split("|");
    if (parts.length !== 3) return null;
    const [email, expStr, sig] = parts;
    if (!email || !expStr || !sig) return null;
    const expNum = Number(expStr);
    if (!Number.isFinite(expNum) || expNum < Date.now()) return null;

    const expectedBuf = createHmac("sha256", adminSessionSecret())
      .update(`${email}|${expStr}`)
      .digest();
    const providedBuf = Buffer.from(sig, "base64url");
    if (expectedBuf.length !== providedBuf.length) return null;
    if (!timingSafeEqual(expectedBuf, providedBuf)) return null;

    const allowed = (process.env.ADMIN_EMAIL || "").toLowerCase();
    if (allowed && email.toLowerCase() !== allowed) return null;
    return email;
  } catch {
    return null;
  }
}
