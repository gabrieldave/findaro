import { fail, handle } from "@/lib/api";
import { consumeDownloadToken } from "@/lib/download";
import { DMG_UPSTREAM_URL } from "@/lib/site";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const GET = handle(async (req) => {
  const url = new URL(req.url);
  const token = url.searchParams.get("token") || "";
  if (!token) return fail("Token requerido", 401);

  const row = await consumeDownloadToken(token);
  if (!row) return fail("Enlace inválido o agotado", 403);

  const upstream = await fetch(DMG_UPSTREAM_URL, { redirect: "follow" });
  if (!upstream.ok || !upstream.body) {
    return fail("Instalador no disponible temporalmente", 502);
  }

  const headers = new Headers();
  headers.set(
    "Content-Type",
    upstream.headers.get("content-type") || "application/octet-stream",
  );
  headers.set(
    "Content-Disposition",
    'attachment; filename="Findaro-latest.dmg"',
  );
  const len = upstream.headers.get("content-length");
  if (len) headers.set("Content-Length", len);
  headers.set("Cache-Control", "no-store");

  return new Response(upstream.body, { status: 200, headers });
});
