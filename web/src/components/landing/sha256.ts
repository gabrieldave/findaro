/** SHA-256 real en el navegador (Web Crypto) con respaldo en JS puro para contextos no seguros. */
const encoder = new TextEncoder();

export async function sha256Hex(input: string): Promise<string> {
  const data = encoder.encode(input);
  if (typeof crypto !== "undefined" && crypto.subtle) {
    try {
      const digest = await crypto.subtle.digest("SHA-256", data);
      return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
    } catch {
      // continúa con el respaldo
    }
  }
  return sha256Fallback(data);
}

function sha256Fallback(msg: Uint8Array): string {
  const K: number[] = [];
  const H: number[] = [];
  const isPrime = (v: number) => {
    for (let d = 2; d * d <= v; d++) if (v % d === 0) return false;
    return true;
  };
  for (let n = 2, c = 0; c < 64; n++) {
    if (!isPrime(n)) continue;
    if (c < 8) H[c] = ((Math.pow(n, 1 / 2) % 1) * 4294967296) | 0;
    K[c] = ((Math.pow(n, 1 / 3) % 1) * 4294967296) | 0;
    c++;
  }
  const l = msg.length;
  const bl = ((l + 9 + 63) >> 6) << 6;
  const b = new Uint8Array(bl);
  b.set(msg);
  b[l] = 0x80;
  const dv = new DataView(b.buffer);
  dv.setUint32(bl - 4, l * 8);
  const w = new Int32Array(64);
  const r = (v: number, s: number) => (v >>> s) | (v << (32 - s));
  for (let o = 0; o < bl; o += 64) {
    for (let i = 0; i < 16; i++) w[i] = dv.getInt32(o + i * 4);
    for (let i = 16; i < 64; i++) {
      const a = w[i - 15];
      const d = w[i - 2];
      w[i] = (w[i - 16] + (r(a, 7) ^ r(a, 18) ^ (a >>> 3)) + w[i - 7] + (r(d, 17) ^ r(d, 19) ^ (d >>> 10))) | 0;
    }
    let [a, bb, cc, d, e, f, g, h] = H;
    for (let i = 0; i < 64; i++) {
      const t1 = (h + (r(e, 6) ^ r(e, 11) ^ r(e, 25)) + ((e & f) ^ (~e & g)) + K[i] + w[i]) | 0;
      const t2 = ((r(a, 2) ^ r(a, 13) ^ r(a, 22)) + ((a & bb) ^ (a & cc) ^ (bb & cc))) | 0;
      h = g;
      g = f;
      f = e;
      e = (d + t1) | 0;
      d = cc;
      cc = bb;
      bb = a;
      a = (t1 + t2) | 0;
    }
    H[0] = (H[0] + a) | 0;
    H[1] = (H[1] + bb) | 0;
    H[2] = (H[2] + cc) | 0;
    H[3] = (H[3] + d) | 0;
    H[4] = (H[4] + e) | 0;
    H[5] = (H[5] + f) | 0;
    H[6] = (H[6] + g) | 0;
    H[7] = (H[7] + h) | 0;
  }
  return H.map((v) => (v >>> 0).toString(16).padStart(8, "0")).join("");
}
