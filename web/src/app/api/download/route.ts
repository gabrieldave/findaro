import { fail, handle } from "@/lib/api";
import { consumeDownloadToken } from "@/lib/download";
import { recordEvent } from "@/lib/events";
import { resolveDmgUpstreamUrl } from "@/lib/site";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const GET = handle(async (req) => {
  const url = new URL(req.url);
  const direct = url.searchParams.get("direct") === "1";
  const token = url.searchParams.get("token") || "";

  if (direct) {
    const ip =
      req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ||
      req.headers.get("x-real-ip") ||
      "anon";
    const day = new Date().toISOString().slice(0, 10);
    await recordEvent({
      name: "download_requested",
      subjectType: "direct_trial",
      subjectId: ip.slice(0, 64),
      occurrenceKey: day,
      props: { mode: "direct_trial" },
    });
  } else {
    if (!token) return fail("Token requerido", 401);

    const row = await consumeDownloadToken(token);
    if (!row) return fail("Enlace inválido o agotado", 403);

    // Registrar evento download_click deduplicado por token_id + día (T-06)
    await recordEvent({
      name: "download_requested",
      subjectType: "download_token",
      subjectId: row.id,
      occurrenceKey: String(row.used_count),
      props: { usedCount: row.used_count },
    });
  }

  const dmgUrl = await resolveDmgUpstreamUrl();
  const upstream = await fetch(dmgUrl, { redirect: "follow", cache: "no-store" });
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
    'attachment; filename="Findaro.dmg"',
  );
  const len = upstream.headers.get("content-length");
  if (len) headers.set("Content-Length", len);
  headers.set("Cache-Control", "no-store");

  return new Response(upstream.body, { status: 200, headers });
});
