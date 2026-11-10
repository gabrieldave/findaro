import { fail, handle, ok } from "@/lib/api";
import { query } from "@/lib/db";
import { limitByIp } from "@/lib/ratelimit";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const GET = handle(async (req) => {
  const limited = limitByIp(req, "promo-validate", 20, 10 * 60_000);
  if (limited) return limited;

  const url = new URL(req.url);
  const code = (url.searchParams.get("code") || "").trim().toUpperCase();

  if (!code || code.length > 32 || !/^[A-Z0-9-]+$/.test(code)) {
    return fail("Código inválido", 400);
  }

  const res = await query<{ id: string; referral_code: string }>(
    `SELECT id, referral_code FROM customers WHERE UPPER(referral_code) = $1 LIMIT 1`,
    [code],
  );

  return ok({
    code,
    valid: Boolean(res.rows[0]),
  });
});
