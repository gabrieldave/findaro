import { createHash, randomBytes } from "crypto";
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

export async function consumeDownloadToken(token: string) {
  const { rows } = await query<{
    id: string;
    order_id: string | null;
    license_id: string | null;
    used_count: number;
    max_uses: number;
    expires_at: Date;
    order_status: string | null;
    license_revoked: boolean | null;
    license_plan: string | null;
    license_expires: Date | null;
  }>(
    `SELECT t.id, t.order_id, t.license_id, t.used_count, t.max_uses, t.expires_at,
            o.status AS order_status,
            l.revoked AS license_revoked,
            l.plan AS license_plan,
            l.expires_at AS license_expires
     FROM download_tokens t
     LEFT JOIN orders o ON o.id = t.order_id
     LEFT JOIN licenses l ON l.id = t.license_id
     WHERE t.token = $1`,
    [token],
  );
  const row = rows[0];
  if (!row) return null;
  const orderOk = row.order_id != null && row.order_status === "paid";
  const licenseOk =
    row.license_id != null &&
    row.license_revoked === false &&
    (row.license_plan === "pro" ||
      (row.license_plan === "trial" &&
        row.license_expires != null &&
        new Date(row.license_expires).getTime() > Date.now()));
  if (!orderOk && !licenseOk) return null;
  if (new Date(row.expires_at).getTime() < Date.now()) return null;
  if (row.used_count >= row.max_uses) return null;
  await query(
    `UPDATE download_tokens SET used_count = used_count + 1 WHERE id = $1`,
    [row.id],
  );
  return row;
}

export function adminSessionSecret(): string {
  const s = process.env.ADMIN_SESSION_SECRET;
  if (!s || s.length < 24) throw new Error("ADMIN_SESSION_SECRET inválido");
  return s;
}

export function signAdminCookie(email: string): string {
  const exp = Date.now() + 7 * 24 * 60 * 60 * 1000;
  const payload = `${email}|${exp}`;
  const sig = createHash("sha256")
    .update(`${payload}|${adminSessionSecret()}`)
    .digest("base64url");
  return Buffer.from(`${payload}|${sig}`).toString("base64url");
}

export function verifyAdminCookie(raw: string | undefined): string | null {
  if (!raw) return null;
  try {
    const decoded = Buffer.from(raw, "base64url").toString("utf8");
    const [email, expStr, sig] = decoded.split("|");
    if (!email || !expStr || !sig) return null;
    if (Number(expStr) < Date.now()) return null;
    const expect = createHash("sha256")
      .update(`${email}|${expStr}|${adminSessionSecret()}`)
      .digest("base64url");
    if (expect !== sig) return null;
    const allowed = (process.env.ADMIN_EMAIL || "").toLowerCase();
    if (allowed && email.toLowerCase() !== allowed) return null;
    return email;
  } catch {
    return null;
  }
}
