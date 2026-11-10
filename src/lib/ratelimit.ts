import { fail } from "./api";

/**
 * Límite de peticiones en memoria (ventana fija). La web corre en UN solo contenedor
 * (Coolify), así que un mapa en memoria es suficiente; se reinicia al redesplegar.
 * Protege el envío de correos de /api/trial, el login de admin y la API de licencias
 * contra abuso y fuerza bruta.
 */
type Bucket = { count: number; resetAt: number };
const buckets = new Map<string, Bucket>();
let lastSweep = 0;

function sweep(now: number) {
  if (now - lastSweep < 60_000) return;
  lastSweep = now;
  for (const [k, b] of buckets) if (b.resetAt <= now) buckets.delete(k);
}

/** IP real del cliente detrás de Cloudflare / proxy de Coolify. */
export function clientIp(req: Request): string {
  const h = req.headers;
  return (
    h.get("cf-connecting-ip") ||
    h.get("x-real-ip") ||
    (h.get("x-forwarded-for") || "").split(",")[0].trim() ||
    "unknown"
  );
}

/** Devuelve true si la petición está dentro del límite; false si lo excede. */
export function hit(key: string, limit: number, windowMs: number, now = Date.now()): boolean {
  sweep(now);
  const b = buckets.get(key);
  if (!b || b.resetAt <= now) {
    buckets.set(key, { count: 1, resetAt: now + windowMs });
    return true;
  }
  b.count += 1;
  return b.count <= limit;
}

/** Atajo: limita por IP y devuelve la respuesta 429 lista, o null si se permite. */
export function limitByIp(req: Request, scope: string, limit: number, windowMs: number): Response | null {
  if (hit(`${scope}:ip:${clientIp(req)}`, limit, windowMs)) return null;
  return tooMany();
}

export function tooMany(): Response {
  const res = fail("Demasiadas solicitudes. Espera unos minutos e inténtalo de nuevo.", 429);
  res.headers.set("Retry-After", "600");
  return res;
}

/** Solo para pruebas. */
export function _resetRateLimits() {
  buckets.clear();
}
