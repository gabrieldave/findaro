import { handle, ok } from "@/lib/api";
import { recordEvent } from "@/lib/events";
import { limitByIp } from "@/lib/ratelimit";
import crypto from "crypto";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

function cleanField(val: string | undefined, fallback: string, maxLen = 128): string {
  const trimmed = (val || "").trim().slice(0, maxLen);
  return trimmed || fallback;
}

export const POST = handle(async (req) => {
  const limited = limitByIp(req, "visit-event", 60, 10 * 60_000);
  if (limited) return limited;

  const body = (await req.json().catch(() => null)) as {
    visit_id?: string;
    utm_source?: string;
    utm_medium?: string;
    utm_campaign?: string;
    utm_content?: string;
    lang?: string;
  } | null;

  const rawVisitId = (body?.visit_id || "").trim();
  const visitId =
    rawVisitId && /^[A-Za-z0-9_-]{8,80}$/.test(rawVisitId)
      ? rawVisitId
      : crypto.randomUUID();
  const utmSource = cleanField(body?.utm_source, "unknown");
  const utmMedium = cleanField(body?.utm_medium, "unknown");
  const utmCampaign = cleanField(body?.utm_campaign, "unknown");
  const utmContent = cleanField(body?.utm_content, "unknown");
  const lang = body?.lang === "en" ? "en" : "es";

  await recordEvent({
    name: "visit",
    subjectType: "visit",
    subjectId: visitId,
    occurrenceKey: "once",
    props: {
      utm_source: utmSource,
      utm_medium: utmMedium,
      utm_campaign: utmCampaign,
      utm_content: utmContent,
      lang,
    },
  });

  return ok({ recorded: true, visitId });
});
