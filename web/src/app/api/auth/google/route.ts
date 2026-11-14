import { createHash, createHmac, randomBytes } from "crypto";
import { NextResponse } from "next/server";
import { adminSessionSecret } from "@/lib/download";
import { PUBLIC_APP_URL } from "@/lib/site";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const DEFAULT_GOOGLE_CLIENT_ID =
  "1091222021847-ph8k6rbvkpkk9gf1j41v6hiiqje6vnlc.apps.googleusercontent.com";

export function GET() {
  const clientId = (process.env.GOOGLE_CLIENT_ID || DEFAULT_GOOGLE_CLIENT_ID).trim();
  const baseUrl = PUBLIC_APP_URL.replace(/\/$/, "");
  const redirectUri = (
    process.env.GOOGLE_REDIRECT_URI || `${baseUrl}/api/auth/callback/google`
  ).trim();

  const state = randomBytes(32).toString("base64url");
  const verifier = randomBytes(32).toString("base64url");
  const challenge = createHash("sha256").update(verifier).digest("base64url");
  const exp = Date.now() + 10 * 60_000;

  const payload = Buffer.from(
    JSON.stringify({ state, verifier, exp }),
    "utf8",
  ).toString("base64url");
  const sig = createHmac("sha256", adminSessionSecret())
    .update(payload)
    .digest("base64url");
  const stateCookie = `${payload}.${sig}`;

  const authUrl = new URL("https://accounts.google.com/o/oauth2/v2/auth");
  authUrl.searchParams.set("client_id", clientId);
  authUrl.searchParams.set("redirect_uri", redirectUri);
  authUrl.searchParams.set("response_type", "code");
  authUrl.searchParams.set("scope", "openid email profile");
  authUrl.searchParams.set("state", state);
  authUrl.searchParams.set("code_challenge", challenge);
  authUrl.searchParams.set("code_challenge_method", "S256");
  authUrl.searchParams.set("prompt", "select_account");

  const res = NextResponse.redirect(authUrl.toString(), { status: 302 });
  res.cookies.set("findaro_oauth_state", stateCookie, {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    path: "/",
    maxAge: 600,
  });
  return res;
}
