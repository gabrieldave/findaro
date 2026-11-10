import { fail, handle, ok, verifySameOrigin } from "@/lib/api";
import { query } from "@/lib/db";
import { verifyAdminCookie } from "@/lib/download";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/** Acción administrativa sobre una licencia: revocar (kill-switch), restaurar o limpiar asientos */
export const POST = handle(async (req) => {
  if (!verifySameOrigin(req)) return fail("Origen no permitido", 403);
  const cookie = req.headers.get("cookie") || "";
  const match = cookie.match(/(?:^|;\s*)findaro_admin=([^;]+)/);
  const email = verifyAdminCookie(match?.[1]);
  if (!email) return fail("No autorizado", 401);

  const body = (await req.json().catch(() => null)) as {
    licenseKey?: string;
    action?: "revoke" | "restore" | "reset_activations";
  } | null;

  const licenseKey = (body?.licenseKey || "").trim().toUpperCase();
  const action = body?.action;

  if (!licenseKey) return fail("licenseKey requerido", 400);

  const lic = await query<{ id: string; revoked: boolean }>(
    `SELECT id, revoked FROM licenses WHERE license_key = $1`,
    [licenseKey],
  );
  if (!lic.rows[0]) return fail("Licencia no encontrada", 404);

  const licenseId = lic.rows[0].id;

  if (action === "revoke") {
    await query(`UPDATE licenses SET revoked = true WHERE id = $1`, [licenseId]);
    return ok({ licenseKey, status: "revoked", message: "Licencia revocada (Kill-switch activado)." });
  }

  if (action === "restore") {
    await query(`UPDATE licenses SET revoked = false WHERE id = $1`, [licenseId]);
    return ok({ licenseKey, status: "active", message: "Licencia restaurada." });
  }

  if (action === "reset_activations") {
    await query(`DELETE FROM license_activations WHERE license_id = $1`, [licenseId]);
    return ok({ licenseKey, message: "Todas las activaciones de equipos fueron liberadas." });
  }

  return fail("Acción no válida", 400);
});
