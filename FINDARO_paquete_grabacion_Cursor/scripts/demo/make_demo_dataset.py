#!/usr/bin/env python3
"""Crea el set de prueba ficticio de FINDARO para capturas y videos de marketing.

Solo usa la biblioteca estándar de Python 3. En macOS convierte las imágenes a JPEG con `sips`.

    python3 scripts/demo/make_demo_dataset.py            # crea ~/Documents/FINDARO-Demo
    python3 scripts/demo/make_demo_dataset.py --reset    # borra y recrea (solo si es un set de prueba)
    python3 scripts/demo/make_demo_dataset.py --video-mb 2000   # videos más pesados = barra de progreso más larga

Historia: «Estudio Aurora», un estudio de fotografía ficticio.
- ORIGEN  = Estudio Aurora (proyectos de trabajo)
- DESTINO = Respaldo Estudio (copia anterior, desactualizada)

Escenas que deja preparadas:
- Smart Merge: ORIGEN/Campaña-Otoño-2026/Documentos → DESTINO/Campaña-Otoño-2026/Documentos
  = 6 nuevos, 3 iguales, 2 distintos.
- Búsqueda «contrato» desde ORIGEN = 8 resultados en subcarpetas distintas.
- Transferencia con barra de progreso: ORIGEN/Campaña-Otoño-2026/Video (archivos grandes reales).
- Archivos ocultos (⌘⇧.), ZIP y TAR para descomprimir, imágenes para la vista Galería.

Todos los nombres, empresas y datos son inventados.
"""
from __future__ import annotations

import argparse
import colorsys
import os
import random
import shutil
import struct
import subprocess
import sys
import tarfile
import time
import zipfile
import zlib
from pathlib import Path

MARKER = ".findaro-demo"
SEED = 20261107


# ---------------------------------------------------------------- archivos de contenido

def write_png(path: Path, w: int, h: int, hue: float, rng: random.Random) -> None:
    """Imagen abstracta: degradado diagonal entre dos tonos y un «sol» suave."""
    h2 = (hue + rng.uniform(0.08, 0.22)) % 1.0
    c1 = colorsys.hsv_to_rgb(hue, rng.uniform(0.45, 0.75), rng.uniform(0.55, 0.85))
    c2 = colorsys.hsv_to_rgb(h2, rng.uniform(0.55, 0.9), rng.uniform(0.18, 0.4))
    sx, sy, sr = rng.uniform(0.2, 0.8) * w, rng.uniform(0.15, 0.55) * h, rng.uniform(0.12, 0.25) * w
    rows = []
    for y in range(h):
        row = bytearray([0])
        for x in range(w):
            t = (x / w * 0.4 + y / h * 0.6)
            r, g, b = (c1[i] * (1 - t) + c2[i] * t for i in range(3))
            d = ((x - sx) ** 2 + (y - sy) ** 2) ** 0.5
            glow = max(0.0, 1 - d / sr) ** 2 * 0.55
            row += bytes(min(255, int((v + glow) * 255)) for v in (r, g, b))
        rows.append(bytes(row))
    raw = b"".join(rows)

    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b"")
    path.write_bytes(png)


def write_image(path_jpg: Path, hue: float, rng: random.Random, size=(720, 480)) -> None:
    png = path_jpg.with_suffix(".png")
    write_png(png, size[0], size[1], hue, rng)
    if shutil.which("sips"):
        subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", "82", str(png), "--out", str(path_jpg)],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        png.unlink()
    else:  # fuera de macOS se queda en PNG
        png.rename(path_jpg.with_suffix(".png"))


def write_pdf(path: Path, title: str, lines: list[str]) -> None:
    """PDF mínimo válido con texto, para que Quick Look muestre algo legible."""
    def esc(s: str) -> str:
        return s.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")
    text = ["BT", "/F1 20 Tf", "72 760 Td", f"({esc(title)}) Tj", "/F1 12 Tf"]
    for ln in lines:
        text += ["0 -22 Td", f"({esc(ln)}) Tj"]
    text.append("ET")
    stream = "\n".join(text).encode("latin-1", "replace")
    objs = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
        b"<< /Length " + str(len(stream)).encode() + b" >>\nstream\n" + stream + b"\nendstream",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
    ]
    out = bytearray(b"%PDF-1.4\n")
    offsets = []
    for i, o in enumerate(objs, 1):
        offsets.append(len(out))
        out += f"{i} 0 obj\n".encode() + o + b"\nendobj\n"
    xref = len(out)
    out += f"xref\n0 {len(objs) + 1}\n0000000000 65535 f \n".encode()
    for off in offsets:
        out += f"{off:010d} 00000 n \n".encode()
    out += f"trailer\n<< /Size {len(objs) + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
    path.write_bytes(bytes(out))


def write_big(path: Path, mb: int) -> None:
    """Archivo grande con bytes reales (no disperso), para que copiar y verificar lleve unos segundos."""
    chunk = os.urandom(4 * 1024 * 1024)
    with path.open("wb") as f:
        for i in range(max(1, mb // 4)):
            f.write(chunk if i % 8 else os.urandom(len(chunk)))


def touch_past(path: Path, days_ago: float) -> None:
    t = time.time() - days_ago * 86400
    os.utime(path, (t, t))


# ---------------------------------------------------------------- el set

def build(root: Path, video_mb: int) -> dict[str, int]:
    rng = random.Random(SEED)
    o = root / "ORIGEN" / "Estudio Aurora"
    d = root / "DESTINO" / "Respaldo Estudio"
    stats = {"archivos": 0}

    def mk(p: Path) -> Path:
        p.mkdir(parents=True, exist_ok=True)
        return p

    def text(p: Path, body: str, days: float = 0) -> None:
        p.write_text(body, encoding="utf-8")
        touch_past(p, days)
        stats["archivos"] += 1

    def pdf(p: Path, title: str, lines: list[str], days: float = 0) -> None:
        write_pdf(p, title, lines)
        touch_past(p, days)
        stats["archivos"] += 1

    def img(p: Path, hue: float, days: float = 0, size=(720, 480)) -> None:
        write_image(p, hue, rng, size)
        final = p if p.exists() else p.with_suffix(".png")
        touch_past(final, days)
        stats["archivos"] += 1

    camp = mk(o / "Campaña-Otoño-2026")

    # Fotos para galería / iconos (tonos otoñales)
    raw = mk(camp / "Fotos")
    for i in range(1, 25):
        img(raw / f"AUR-{100 + i:04d}.jpg", rng.choice([0.02, 0.05, 0.08, 0.11, 0.58, 0.62]) + rng.uniform(-0.02, 0.02), days=rng.uniform(3, 9))
    sel = mk(camp / "Selección")
    for i in (103, 107, 111, 114, 118, 122, 124, 130):
        img(sel / f"AUR-{i:04d}-final.jpg", rng.choice([0.03, 0.07, 0.6]), days=rng.uniform(1, 3))

    # Videos grandes reales: la barra de progreso y la verificación SHA-256 se ven
    vid = mk(camp / "Video")
    write_big(vid / "teaser-otoño-4K.mov", video_mb)
    write_big(vid / "making-of.mov", max(200, video_mb // 3))
    stats["archivos"] += 2

    # Smart Merge: Documentos (ORIGEN 11 archivos, DESTINO 5: 3 iguales + 2 distintos)
    od = mk(camp / "Documentos")
    dd = mk(d / "Campaña-Otoño-2026" / "Documentos")
    same = {
        "brief-campaña.pdf": ("Brief Campaña Otoño 2026", ["Cliente: Estudio Aurora", "Entrega: 24 fotos + teaser 30 s"]),
        "presupuesto-v3.pdf": ("Presupuesto v3", ["Producción, edición y entrega", "Vigencia: 30 días"]),
        "lista-de-tomas.pdf": ("Lista de tomas", ["Exterior parque, luz de tarde", "Retrato, interior estudio"]),
    }
    for name, (t, lines) in same.items():
        pdf(od / name, t, lines, days=6)
        shutil.copy2(od / name, dd / name)
        stats["archivos"] += 1
    pdf(od / "contrato-aurora-firmado.pdf", "Contrato Estudio Aurora", ["Versión firmada por ambas partes", "Fecha: 4 nov 2026"], days=2)
    pdf(dd / "contrato-aurora-firmado.pdf", "Contrato Estudio Aurora", ["Borrador sin firmar", "Fecha: 28 oct 2026"], days=10)
    text(od / "notas-del-equipo.txt", "Notas del equipo\n- Confirmar locación del parque\n- Llevar reflector dorado\n- Revisar permisos de dron\n", days=1)
    text(dd / "notas-del-equipo.txt", "Notas del equipo\n- Confirmar locación\n", days=12)
    pdf(od / "calendario-rodaje.pdf", "Calendario de rodaje", ["Día 1: exteriores", "Día 2: estudio"], days=3)
    pdf(od / "permisos-locación.pdf", "Permisos de locación", ["Parque Central, 8:00-18:00"], days=3)
    text(od / "resumen-proyecto.md", "# Campaña Otoño 2026\n\n24 fotos seleccionadas y un teaser de 30 segundos.\n", days=1)
    pdf(od / "moodboard.pdf", "Moodboard", ["Paleta cálida, hojas, contraluz"], days=5)
    text(od / "guion-teaser.txt", "Teaser 30 s\n0-5 s hojas cayendo\n5-20 s retratos\n20-30 s logo\n", days=2)
    pdf(od / "derechos-de-imagen.pdf", "Derechos de imagen", ["Modelos: autorización firmada"], days=4)

    # Clientes (búsqueda «contrato»)
    cl = mk(o / "Clientes")
    lumen = mk(cl / "Lumen-Café")
    pdf(lumen / "contrato-lumen-2026.pdf", "Contrato Lumen Café", ["Sesión de menú de temporada"], days=20)
    pdf(lumen / "propuesta-lumen.pdf", "Propuesta Lumen Café", ["12 fotos de producto"], days=22)
    img(lumen / "referencia-lumen.jpg", 0.09, days=21)
    marea = mk(cl / "Hotel-Marea")
    pdf(marea / "contrato-marea-temporada.pdf", "Contrato Hotel Marea", ["Temporada alta 2026"], days=15)
    pdf(marea / "anexo-contrato-marea.pdf", "Anexo al contrato", ["Fotos de habitaciones nuevas"], days=14)
    fm = mk(marea / "Fotos-habitaciones")
    for i in range(1, 7):
        img(fm / f"marea-hab-{i:02d}.jpg", 0.52 + rng.uniform(-0.03, 0.03), days=13)
    bodega = mk(cl / "Bodega-Norte")
    pdf(bodega / "contrato-bodega-norte.pdf", "Contrato Bodega Norte", ["Catálogo de vinos 2027"], days=30)
    text(bodega / "notas-reunión.txt", "Reunión Bodega Norte\n- Fondo oscuro\n- 40 botellas\n", days=29)

    fac = mk(o / "Facturas")
    for i in range(31, 39):
        pdf(fac / f"factura-2026-{i:03d}.pdf", f"Factura 2026-{i:03d}", ["Estudio Aurora", "Servicios de fotografía"], days=60 - i)
    pdf(fac / "contrato-marco-servicios.pdf", "Contrato marco de servicios", ["Condiciones generales"], days=90)

    pla = mk(o / "Plantillas")
    text(pla / "contrato-plantilla.rtf", "{\\rtf1\\ansi Plantilla de contrato de servicios fotogr\\'e1ficos.}", days=120)
    text(pla / "presupuesto-plantilla.txt", "Concepto | Cantidad | Precio\n", days=120)

    ent = mk(o / "Entregas")
    pdf(ent / "contrato-entrega-aurora.pdf", "Acta de entrega", ["Entrega v1 Campaña Otoño"], days=1)
    with zipfile.ZipFile(ent / "Entrega-Aurora-v1.zip", "w", zipfile.ZIP_DEFLATED) as z:
        for p in sorted(sel.iterdir())[:4]:
            z.write(p, f"Entrega-Aurora-v1/{p.name}")
    with tarfile.open(ent / "Selección-Lumen.tar.gz", "w:gz") as t:
        t.add(lumen, arcname="Selección-Lumen")
    stats["archivos"] += 2

    # Ocultos (⌘⇧.)
    text(o / ".presets-color.xmp", "<x:xmpmeta>preset ficticio</x:xmpmeta>\n", days=40)
    text(o / ".cache-miniaturas", "cache\n", days=1)

    # DESTINO: respaldo anterior con algo de estructura
    for name in ("Clientes-2025", "Entregas-anteriores", "Facturas-2025"):
        mk(d / name)
    for i in range(1, 9):
        pdf(d / "Facturas-2025" / f"factura-2025-{i:03d}.pdf", f"Factura 2025-{i:03d}", ["Estudio Aurora"], days=300 - i)
    for i in range(1, 7):
        img(d / "Entregas-anteriores" / f"verano-2025-{i:02d}.jpg", 0.12 + rng.uniform(-0.04, 0.04), days=120)
    sel_d = mk(d / "Campaña-Otoño-2026" / "Selección")
    for p in sorted(sel.iterdir())[:2]:
        shutil.copy2(p, sel_d / p.name)
        stats["archivos"] += 1

    (root / MARKER).write_text("Set de prueba de FINDARO. Se puede borrar.\n", encoding="utf-8")
    return stats


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", default=str(Path.home() / "Documents" / "FINDARO-Demo"))
    ap.add_argument("--reset", action="store_true", help="borra el set existente (solo si tiene el marcador) y lo recrea")
    ap.add_argument("--video-mb", type=int, default=1200, help="tamaño del video principal en MB (por defecto 1200)")
    a = ap.parse_args()
    root = Path(a.root).expanduser()
    if root.exists() and any(root.iterdir()):
        if not a.reset:
            print(f"Ya existe {root}. Usa --reset para recrearlo.", file=sys.stderr)
            return 1
        if not (root / MARKER).exists():
            print(f"{root} no tiene el marcador {MARKER}: no lo borro.", file=sys.stderr)
            return 2
        shutil.rmtree(root)
    root.mkdir(parents=True, exist_ok=True)
    t0 = time.time()
    stats = build(root, a.video_mb)
    print(f"Set creado en {root} ({stats['archivos']} archivos, {time.time() - t0:.0f} s)")
    print("  ORIGEN : ORIGEN/Estudio Aurora")
    print("  DESTINO: DESTINO/Respaldo Estudio")
    print("  Smart Merge: Campaña-Otoño-2026/Documentos → 6 nuevos, 3 iguales, 2 distintos")
    print("  Búsqueda: «contrato» desde ORIGEN/Estudio Aurora → 8 resultados")
    return 0


if __name__ == "__main__":
    sys.exit(main())
