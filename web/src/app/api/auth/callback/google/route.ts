import { createHmac, timingSafeEqual } from "crypto";
import { NextRequest, NextResponse } from "next/server";
import {
  adminSessionSecret,
  isAllowedAdminEmail,
  signAdminCookie,
} from "@/lib/download";
import { PUBLIC_APP_URL } from "@/lib/site";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const DEFAULT_GOOGLE_CLIENT_ID =
  "1091222021847-ph8k6rbvkpkk9gf1j41v6hiiqje6vnlc.apps.googleusercontent.com";

type OAuthStatePayload = {
  state: string;
  verifier: string;
  exp: number;
};

function verifyStateCookie(
  cookieVal: string | undefined,
  providedState: string,
): OAuthStatePayload | null {
  if (!cookieVal || !providedState) return null;
  const dot = cookieVal.indexOf(".");
  if (dot <= 0) return null;
  const payload = cookieVal.slice(0, dot);
  const sig = cookieVal.slice(dot + 1);
  if (!payload || !sig) return null;

  try {
    const expectedSig = createHmac("sha256", adminSessionSecret())
      .update(payload)
      .digest();
    const providedSig = Buffer.from(sig, "base64url");
    if (expectedSig.length !== providedSig.length) return null;
    if (!timingSafeEqual(expectedSig, providedSig)) return null;

    const parsed = JSON.parse(
      Buffer.from(payload, "base64url").toString("utf8"),
    ) as Partial<OAuthStatePayload>;
    if (
      typeof parsed.state !== "string" ||
      typeof parsed.verifier !== "string" ||
      typeof parsed.exp !== "number"
    ) {
      return null;
    }
    if (Date.now() > parsed.exp) return null;

    const a = Buffer.from(parsed.state, "utf8");
    const b = Buffer.from(providedState, "utf8");
    if (a.length !== b.length || !timingSafeEqual(a, b)) return null;

    return {
      state: parsed.state,
      verifier: parsed.verifier,
      exp: parsed.exp,
    };
  } catch {
    return null;
  }
}

function redirectWithError(baseUrl: string, code: string): NextResponse {
  const res = NextResponse.redirect(
    `${baseUrl}/admin?error=${encodeURIComponent(code)}`,
    { status: 302 },
  );
  res.cookies.set("findaro_oauth_state", "", {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    path: "/",
    maxAge: 0,
  });
  return res;
}

export async function GET(req: NextRequest) {
  const baseUrl = PUBLIC_APP_URL.replace(/\/$/, "");
  const oauthError = req.nextUrl.searchParams.get("error");
  if (oauthError) {
    return redirectWithError(baseUrl, "oauth_state");
  }

  const code = (req.nextUrl.searchParams.get("code") || "").trim();
  const state = (req.nextUrl.searchParams.get("state") || "").trim();
  const cookieVal = req.cookies.get("findaro_oauth_state")?.value;

  const verifiedState = verifyStateCookie(cookieVal, state);
  if (!code || !verifiedState) {
    return redirectWithError(baseUrl, "oauth_state");
  }

  const clientId = (process.env.GOOGLE_CLIENT_ID || DEFAULT_GOOGLE_CLIENT_ID).trim();
  const clientSecret = (process.env.GOOGLE_CLIENT_SECRET || "").trim();
  if (!clientSecret) {
    return redirectWithError(baseUrl, "oauth_not_configured");
  }

  const redirectUri = (
    process.env.GOOGLE_REDIRECT_URI || `${baseUrl}/api/auth/callback/google`
  ).trim();

  const tokenParams = new URLSearchParams({
    code,
    client_id: clientId,
    client_secret: clientSecret,
    redirect_uri: redirectUri,
    grant_type: "authorization_code",
    code_verifier: verifiedState.verifier,
  });

  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: tokenParams.toString(),
    cache: "no-store",
  });

  if (!tokenRes.ok) {
    return redirectWithError(baseUrl, "oauth_token");
  }

  const tokenData = (await tokenRes.json().catch(() => null)) as {
    access_token?: string;
  } | null;
  if (!tokenData?.access_token) {
    return redirectWithError(baseUrl, "oauth_token");
  }

  const userRes = await fetch("https://openidconnect.googleapis.com/v1/userinfo", {
    headers: { Authorization: `Bearer ${tokenData.access_token}` },
    cache: "no-store",
  });
  if (!userRes.ok) {
    return redirectWithError(baseUrl, "oauth_userinfo");
  }

  const userInfo = (await userRes.json().catch(() => null)) as {
    email?: string;
    email_verified?: boolean;
  } | null;

  const userEmail = (userInfo?.email || "").trim().toLowerCase();
  if (!userInfo?.email_verified || !userEmail || !isAllowedAdminEmail(userEmail)) {
    return redirectWithError(baseUrl, "unauthorized_email");
  }

  const sessionCookie = signAdminCookie(userEmail);
  const res = NextResponse.redirect(`${baseUrl}/admin`, { status: 302 });
  res.cookies.set("findaro_oauth_state", "", {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    path: "/",
    maxAge: 0,
  });
  res.cookies.set("findaro_admin", sessionCookie, {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    path: "/",
    maxAge: 7 * 24 * 60 * 60,
  });
  return res;
}
