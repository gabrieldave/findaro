import { fail, handle, ok } from "@/lib/api";
import { query } from "@/lib/db";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const GET = handle(async (req) => {
  const url = new URL(req.url);
  const code = (url.searchParams.get("code") || "").trim().toUpperCase();

  if (!code) {
    return fail("Código requerido", 400);
  }

  const res = await query<{ id: string; referral_code: string }>(
    `SELECT id, referral_code FROM customers WHERE UPPER(referral_code) = $1 LIMIT 1`,
    [code],
  );

  const found = Boolean(res.rows[0]);

  return ok({
    code,
    valid: found,
  });
});
