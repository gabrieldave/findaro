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
    license_id: string | null;
    license_key: string | null;
    license_plan: string | null;
    license_tier: string | null;
    license_seats: number | null;
    license_revoked: boolean | null;
    active_macs: number;
    referred_count: number;
  }>(
    `SELECT c.id, c.email, c.name, c.referral_code, c.created_at,
            o.id AS order_id, o.amount_usd, o.status, o.paid_at, o.promo_slot,
            o.stripe_session_id,
            l.id AS license_id, l.license_key, l.plan AS license_plan, COALESCE(l.tier, l.plan) AS license_tier, l.seats AS license_seats, l.revoked AS license_revoked,
            COALESCE(act.cnt, 0)::int AS active_macs,
            COALESCE(ref.cnt, 0)::int AS referred_count
     FROM customers c
     LEFT JOIN LATERAL (
       SELECT * FROM orders WHERE customer_id = c.id
       ORDER BY (status = 'paid') DESC, created_at DESC
       LIMIT 1
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

  const revenue = await query<{ revenue_usd: string }>(
    `SELECT COALESCE(SUM(amount_usd), 0)::text AS revenue_usd FROM orders WHERE status = 'paid'`,
  );

  const paidByTier = await query<{ tier: string; cnt: string }>(
    `SELECT COALESCE(tier, 'personal') AS tier, COUNT(*)::text AS cnt
     FROM orders WHERE status = 'paid'
     GROUP BY COALESCE(tier, 'personal')`,
  );

  const paidOrders = paidByTier.rows.reduce((acc, r) => acc + Number(r.cnt || 0), 0);
  const paidOrdersByTier = {
    solo: 0,
    personal: 0,
    family: 0,
  } as Record<string, number>;
  for (const r of paidByTier.rows) {
    paidOrdersByTier[r.tier] = Number(r.cnt || 0);
  }

  const trials = await query<{ active_trials: string }>(
    `SELECT (
        (SELECT COUNT(*) FROM licenses WHERE plan = 'trial' AND revoked = false)
        +
        (SELECT COUNT(*) FROM trial_devices WHERE expires_at > now())
      )::text AS active_trials`,
  );

  const traffic = await query<{
    utm_source: string;
    visits: string;
    customers: string;
    paid: string;
  }>(
    `WITH visit_src AS (
       SELECT LOWER(COALESCE(NULLIF(TRIM(props->>'utm_source'), ''), 'direct')) AS src, COUNT(*) AS visits
       FROM events WHERE name = 'visit'
       GROUP BY 1
     ),
     cust_src AS (
       SELECT LOWER(COALESCE(NULLIF(TRIM(c.utm_source), ''), 'direct')) AS src,
              COUNT(DISTINCT c.id) AS customers,
              COUNT(DISTINCT o.id) FILTER (WHERE o.status = 'paid') AS paid
       FROM customers c
       LEFT JOIN orders o ON o.customer_id = c.id
       GROUP BY 1
     )
     SELECT COALESCE(v.src, c.src) AS utm_source,
            COALESCE(v.visits, 0)::text AS visits,
            COALESCE(c.customers, 0)::text AS customers,
            COALESCE(c.paid, 0)::text AS paid
     FROM visit_src v
     FULL OUTER JOIN cust_src c ON c.src = v.src
     ORDER BY COALESCE(v.visits, 0) + COALESCE(c.paid, 0) DESC
     LIMIT 20`,
  );

  const proLicensesRes = await query<{ cnt: string }>(
    `SELECT COUNT(*)::text AS cnt FROM licenses WHERE plan = 'pro' AND revoked = false`,
  );

  const pendingRefs = await query<{ cnt: string; amount: string }>(
    `SELECT COUNT(*)::text AS cnt,
            COALESCE(SUM(commission_amount_usd), 0)::text AS amount
     FROM referrals WHERE status = 'pending'`,
  );

  const trafficBySource = traffic.rows.map((r) => ({
    utm_source: r.utm_source,
    visits: Number(r.visits || 0),
    customers: Number(r.customers || 0),
    paid: Number(r.paid || 0),
  }));

  const stats = {
    revenueUsd: Number(revenue.rows[0]?.revenue_usd || 0),
    paidOrders,
    paidOrdersByTier,
    proLicenses: Number(proLicensesRes.rows[0]?.cnt || 0),
    totalCustomers: rows.length,
    activeTrials: Number(trials.rows[0]?.active_trials || 0),
    trafficBySource,
    pendingReferrals: {
      count: Number(pendingRefs.rows[0]?.cnt || 0),
      amountUsd: Number(pendingRefs.rows[0]?.amount || 0),
    },
  };

  return ok({ admin: email, offer, customers: rows, stats });
});
