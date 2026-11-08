import { ok } from "@/lib/api";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export function GET() {
  return ok({ status: "healthy", app: "findaro", ts: Date.now() });
}
