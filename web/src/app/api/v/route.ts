import { handle, ok } from "@/lib/api";
import { recordEvent } from "@/lib/events";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = handle(async (req) => {
  const body = (await req.json().catch(() => null)) as {
    utm_source?: string;
    utm_medium?: string;
    utm_campaign?: string;
    utm_content?: string;
    lang?: string;
  } | null;

  const utmSource = (body?.utm_source || "unknown").trim();
  const utmMedium = (body?.utm_medium || "unknown").trim();
  const utmCampaign = (body?.utm_campaign || "unknown").trim();
  const utmContent = (body?.utm_content || "unknown").trim();
  const lang = (body?.lang || "es").trim();

  const today = new Date().toISOString().slice(0, 10);
  const dedupKey = `visit:${today}:${utmSource}:${utmMedium}:${utmCampaign}:${utmContent}:${lang}`;

  await recordEvent({
    name: "visit_attributed",
    dedupKey,
    props: {
      utm_source: utmSource,
      utm_medium: utmMedium,
      utm_campaign: utmCampaign,
      utm_content: utmContent,
      lang,
      day: today,
    },
  });

  return ok({ recorded: true });
});
