import { fail, handle, ok, verifySameOrigin } from "@/lib/api";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = handle(async (req) => {
  if (!verifySameOrigin(req)) return fail("Origen no permitido", 403);
  const res = ok({ loggedOut: true });
  res.cookies.set("findaro_admin", "", {
    httpOnly: true,
    secure: true,
    sameSite: "strict",
    path: "/",
    maxAge: 0,
  });
  return res;
});
