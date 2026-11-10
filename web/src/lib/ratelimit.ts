import { fail } from "./api";

/**
 * Límite de peticiones en memoria (ventana fija) con tope de cardinalidad.
 * Con el puerto del contenedor enlazado a 127.0.0.1, el tráfico público solo entra
 * por el reverse proxy / Cloudflare, evitando falsificación directa de cabeceras.
 */
type Bucket = { count: number; resetAt: number };
const buckets = new Map<string, Bucket>();
const MAX_BUCKETS = 50_000;
let lastSweep = 0;

function sweep(now: number) {
  if (now - lastSweep < 60_000 && buckets.size < MAX_BUCKETS) return;
  lastSweep = now;
  for (const [k, b] of buckets) {
    if (b.resetAt <= now) buckets.delete(k);
  }
  if (buckets.size >= MAX_BUCKETS) {
    const excess = buckets.size - MAX_BUCKETS + 1000;
    let removed = 0;
    for (const k of buckets.keys()) {
      buckets.delete(k);
      removed += 1;
      if (removed >= excess) break;
    }
  }
}

function sanitizeIp(raw: string | null | undefined): string | null {
  if (!raw) return null;
  const trimmed = raw.trim().slice(0, 64);
  if (!trimmed) return null;
  if (/^[0-9a-fA-F:.]+$/.test(trimmed)) {
    return trimmed.toLowerCase();
  }
  return null;
}

/**
 * IP real del cliente detrás de Cloudflare / proxy inverso de Coolify.
 * Solo confía en `cf-connecting-ip` cuando viene acompañada de `cf-ray`
 * (y no se ha desactivado explícitamente TRUST_CLOUDFLARE_HEADERS=false).
 */
export function clientIp(req: Request): string {
  const h = req.headers;
  const trustCf = process.env.TRUST_CLOUDFLARE_HEADERS !== "false";
  if (trustCf && h.get("cf-ray")) {
    const cfIp = sanitizeIp(h.get("cf-connecting-ip"));
    if (cfIp) return cfIp;
  }

  const xff = h.get("x-forwarded-for");
  if (xff) {
    const hops = xff
      .split(",")
      .map((part) => sanitizeIp(part))
      .filter((ip): ip is string => Boolean(ip));
    // Último salto añadido por el reverse proxy local confiable
    if (hops.length > 0) {
      return hops[hops.length - 1];
    }
  }

  return sanitizeIp(h.get("x-real-ip")) || "unknown";
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
