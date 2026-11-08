import { NextResponse } from "next/server";

export function ok<T>(data: T, init?: ResponseInit) {
  return NextResponse.json({ ok: true, data }, init);
}

export function fail(message: string, status = 400) {
  return NextResponse.json({ ok: false, error: message }, { status });
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
