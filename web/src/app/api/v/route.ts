import { handle, ok } from "@/lib/api";
import { recordEvent } from "@/lib/events";
import crypto from "crypto";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = handle(async (req) => {
  const body = (await req.json().catch(() => null)) as {
    visit_id?: string;
    utm_source?: string;
    utm_medium?: string;
    utm_campaign?: string;
    utm_content?: string;
    lang?: string;
  } | null;

  const visitId = (body?.visit_id && body.visit_id.trim()) || crypto.randomUUID();
  const utmSource = (body?.utm_source || "unknown").trim();
  const utmMedium = (body?.utm_medium || "unknown").trim();
  const utmCampaign = (body?.utm_campaign || "unknown").trim();
  const utmContent = (body?.utm_content || "unknown").trim();
  const lang = (body?.lang || "es").trim();

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
