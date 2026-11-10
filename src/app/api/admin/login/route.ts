import { createHash, timingSafeEqual } from "crypto";
import { fail, handle, ok } from "@/lib/api";
import { signAdminCookie } from "@/lib/download";
import { limitByIp } from "@/lib/ratelimit";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/** Comparación en tiempo constante (evita adivinar el secreto midiendo tiempos de respuesta). */
function safeEqual(a: string, b: string): boolean {
  const ha = createHash("sha256").update(a).digest();
  const hb = createHash("sha256").update(b).digest();
  return timingSafeEqual(ha, hb);
}

export const POST = handle(async (req) => {
  // Límite de peticiones. Fuerza bruta: 5 intentos cada 15 min por IP.
  const limited = limitByIp(req, "admin-login", 5, 15 * 60_000);
  if (limited) return limited;

  const body = (await req.json().catch(() => null)) as {
    email?: string;
    secret?: string;
  } | null;
  const email = (body?.email || "").trim().toLowerCase();
  const secret = body?.secret || "";
  const setup = process.env.ADMIN_SETUP_SECRET || "";
  const allowed = (process.env.ADMIN_EMAIL || "").toLowerCase();

  // Secreto corto = adivinable: exigir al menos 24 caracteres y un correo de admin configurado.
  if (setup.length < 24 || !allowed) return fail("Panel de administración no configurado", 503);
  if (!safeEqual(secret, setup)) {
    // Frenar fuerza bruta (no hay rate limit global en esta app).
    await new Promise((r) => setTimeout(r, 1500));
    return fail("No autorizado", 401);
  }
  if (!email || email !== allowed) return fail("Email no autorizado", 403);

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
