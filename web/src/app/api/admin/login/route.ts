import { fail, handle, ok } from "@/lib/api";
import { signAdminCookie } from "@/lib/download";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = handle(async (req) => {
  const body = (await req.json().catch(() => null)) as {
    email?: string;
    secret?: string;
  } | null;
  const email = (body?.email || "").trim().toLowerCase();
  const secret = body?.secret || "";
  const setup = process.env.ADMIN_SETUP_SECRET || "";
  const allowed = (process.env.ADMIN_EMAIL || "").toLowerCase();

  if (!setup || secret !== setup) return fail("No autorizado", 401);
  if (!email || (allowed && email !== allowed)) return fail("Email no autorizado", 403);

  const cookie = signAdminCookie(email);
  const res = ok({ email });
  res.cookies.set("findaro_admin", cookie, {
    httpOnly: true,
    secure: true,
    sameSite: "lax",
    path: "/",
    maxAge: 7 * 24 * 60 * 60,
  });
  return res;
});
