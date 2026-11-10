import { NextResponse } from "next/server";
import { PUBLIC_APP_URL } from "./site";

export function ok<T>(data: T, init?: ResponseInit) {
  return NextResponse.json({ ok: true, data }, init);
}

export function fail(message: string, status = 400) {
  return NextResponse.json({ ok: false, error: message }, { status });
}

/** Verifica que mutaciones administrativas provengan del mismo origen esperado. */
export function verifySameOrigin(req: Request): boolean {
  const origin = req.headers.get("origin");
  if (!origin) {
    // En producción los navegadores siempre envían Origin en POST fetch()
    return process.env.NODE_ENV !== "production";
  }
  try {
    const reqOrigin = new URL(origin).origin;
    const reqUrlOrigin = new URL(req.url).origin;
    const publicOrigin = new URL(PUBLIC_APP_URL).origin;
    return reqOrigin === publicOrigin || reqOrigin === reqUrlOrigin;
  } catch {
    return false;
  }
}

export function handle(
  fn: (req: Request) => Promise<Response> | Response,
) {
  return async (req: Request): Promise<Response> => {
    try {
      return await fn(req);
    } catch (err) {
      console.error("[api]", err instanceof Error ? err.message : "error");
      return fail("Error interno", 500);
    }
  };
}
