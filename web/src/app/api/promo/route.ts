import { handle, ok } from "@/lib/api";
import { currentOffer } from "@/lib/pricing";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const GET = handle(async () => {
  const offer = await currentOffer();
  return ok(offer);
});
