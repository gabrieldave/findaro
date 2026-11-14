import { NextResponse } from "next/server";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export function GET() {
  return NextResponse.json(
    { ok: true, app: "findaro", version: "0.1.165", status: "healthy" },
    { status: 200 },
  );
}
