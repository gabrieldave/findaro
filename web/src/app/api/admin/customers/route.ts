import { fail, handle, ok } from "@/lib/api";
import { query } from "@/lib/db";
import { verifyAdminCookie } from "@/lib/download";
import { currentOffer } from "@/lib/pricing";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const GET = handle(async (req) => {
  const cookie = req.headers.get("cookie") || "";
  const match = cookie.match(/(?:^|;\s*)findaro_admin=([^;]+)/);
  const email = verifyAdminCookie(match?.[1]);
  if (!email) return fail("No autorizado", 401);

  const offer = await currentOffer();
  const { rows } = await query<{
    id: string;
    email: string;
    name: string;
    referral_code: string | null;
    created_at: Date;
    order_id: string | null;
    amount_usd: string | null;
    status: string | null;
    paid_at: Date | null;
    promo_slot: boolean | null;
    stripe_session_id: string | null;
    license_key: string | null;
    license_plan: string | null;
    license_seats: number | null;
    license_revoked: boolean | null;
    active_macs: number;
    referred_count: number;
  }>(
    `SELECT c.id, c.email, c.name, c.referral_code, c.created_at,
            o.id AS order_id, o.amount_usd, o.status, o.paid_at, o.promo_slot,
            o.stripe_session_id,
            l.license_key, l.plan AS license_plan, l.seats AS license_seats, l.revoked AS license_revoked,
            COALESCE(act.cnt, 0)::int AS active_macs,
            COALESCE(ref.cnt, 0)::int AS referred_count
     FROM customers c
     LEFT JOIN LATERAL (
       SELECT * FROM orders WHERE customer_id = c.id
       ORDER BY created_at DESC LIMIT 1
     ) o ON true
     LEFT JOIN LATERAL (
       SELECT * FROM licenses WHERE customer_id = c.id
       ORDER BY created_at DESC LIMIT 1
     ) l ON true
     LEFT JOIN LATERAL (
       SELECT COUNT(*) AS cnt FROM license_activations WHERE license_id = l.id
     ) act ON true
     LEFT JOIN LATERAL (
       SELECT COUNT(*) AS cnt FROM referrals WHERE referrer_customer_id = c.id
     ) ref ON true
     ORDER BY c.created_at DESC
     LIMIT 500`,
  );

  return ok({ admin: email, offer, customers: rows });
});
