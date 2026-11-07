#!/usr/bin/env python3
"""Produce a production Findaro master PNG: no white frame, full-bleed canvas."""
from __future__ import annotations

import sys
from pathlib import Path

try:
    from PIL import Image, ImageFilter
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "--user", "pillow", "-q"])
    from PIL import Image, ImageFilter


def is_near_white(rgb: tuple[int, int, int], thr: int = 240) -> bool:
    r, g, b = rgb[:3]
    return r >= thr and g >= thr and b >= thr and abs(r - g) < 12 and abs(g - b) < 12


def flood_white_exterior(img: Image.Image, thr: int = 240) -> Image.Image:
    """Make exterior near-white background transparent via corner flood fill."""
    rgba = img.convert("RGBA")
    w, h = rgba.size
    px = rgba.load()
    visited = [[False] * w for _ in range(h)]
    stack = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1), (w // 2, 0), (w // 2, h - 1), (0, h // 2), (w - 1, h // 2)]

    while stack:
        x, y = stack.pop()
        if x < 0 or y < 0 or x >= w or y >= h or visited[y][x]:
            continue
        visited[y][x] = True
        r, g, b, a = px[x, y]
        if not is_near_white((r, g, b), thr):
            continue
        px[x, y] = (0, 0, 0, 0)
        stack.extend(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))
    return rgba


def content_bbox(img: Image.Image, alpha_thr: int = 8) -> tuple[int, int, int, int]:
    rgba = img.convert("RGBA")
    w, h = rgba.size
    px = rgba.load()
    minx, miny, maxx, maxy = w, h, -1, -1
    for y in range(h):
        for x in range(w):
            if px[x, y][3] > alpha_thr:
                minx = min(minx, x)
                miny = min(miny, y)
                maxx = max(maxx, x)
                maxy = max(maxy, y)
    if maxx < 0:
        raise SystemExit("No visible content after removing white frame")
    return minx, miny, maxx + 1, maxy + 1


def cover_scale(img: Image.Image, size: int = 1024) -> Image.Image:
    """Scale cropped artwork to fill the square canvas (cover), then center-crop."""
    src = img.convert("RGBA")
    w, h = src.size
    scale = max(size / w, size / h)
    nw, nh = max(1, int(round(w * scale))), max(1, int(round(h * scale)))
    scaled = src.resize((nw, nh), Image.Resampling.LANCZOS)
    left = (nw - size) // 2
    top = (nh - size) // 2
    return scaled.crop((left, top, left + size, top + size))


def fill_remaining_transparency(img: Image.Image, sample_inset: int = 24) -> Image.Image:
    """Replace leftover transparent pixels with dark night-blue sampled from artwork."""
    rgba = img.convert("RGBA")
    w, h = rgba.size
    px = rgba.load()
    samples = []
    for y in range(sample_inset, h - sample_inset, 32):
        for x in range(sample_inset, w - sample_inset, 32):
            r, g, b, a = px[x, y]
            if a > 200 and (r + g + b) < 220:
                samples.append((r, g, b))
    if samples:
        fill = tuple(sum(c[i] for c in samples) // len(samples) for i in range(3))
    else:
        fill = (12, 28, 72)
    out = Image.new("RGBA", (w, h), (*fill, 255))
    out.alpha_composite(rgba)
    return out


def is_blown_highlight(rgb: tuple[int, int, int]) -> bool:
    """Near-white / overbright cyan glow that reads as a frame on Dock."""
    r, g, b = rgb[:3]
    luma = (r + g + b) / 3.0
    if luma >= 228:
        return True
    if is_near_white((r, g, b), 225):
        return True
    # Pale cyan rim (high G/B, still very bright)
    if luma >= 210 and b >= 220 and g >= 210 and r >= 180:
        return True
    return False


def edge_white_cleanup(img: Image.Image) -> Image.Image:
    """Kill residual frame/glow pixels near canvas edges after cover crop."""
    rgba = img.convert("RGBA")
    w, h = rgba.size
    px = rgba.load()
    band = max(12, w // 32)
    night = (14, 30, 68, 255)
    for y in range(h):
        for x in range(w):
            if x < band or y < band or x >= w - band or y >= h - band:
                r, g, b, a = px[x, y]
                if is_blown_highlight((r, g, b)):
                    ix = min(max(x, band + 8), w - band - 9)
                    iy = min(max(y, band + 8), h - band - 9)
                    ir, ig, ib, ia = px[ix, iy]
                    if ia > 0 and not is_blown_highlight((ir, ig, ib)) and (ir + ig + ib) < 280:
                        px[x, y] = (ir, ig, ib, 255)
                    else:
                        px[x, y] = night
    return rgba


def process(source: Path, dest: Path) -> dict:
    original = Image.open(source)
    cleaned = flood_white_exterior(original)
    box = content_bbox(cleaned)
    cropped = cleaned.crop(box)
    # Slight unsharp for Dock clarity at small sizes
    cropped = cropped.filter(ImageFilter.UnsharpMask(radius=1.2, percent=110, threshold=2))
    filled = cover_scale(cropped, 1024)
    filled = fill_remaining_transparency(filled)
    filled = edge_white_cleanup(filled)
    filled = filled.convert("RGBA")
    dest.parent.mkdir(parents=True, exist_ok=True)
    filled.save(dest, "PNG", optimize=True)

    # Verify no white corners
    px = filled.load()
    corners = [(0, 0), (1023, 0), (0, 1023), (1023, 1023), (8, 8), (1015, 8)]
    corner_rgb = [px[x, y][:3] for x, y in corners]
    white_corners = sum(1 for c in corner_rgb if is_near_white(c, 230))
    return {
        "source": str(source),
        "dest": str(dest),
        "crop_box": box,
        "corner_rgb": corner_rgb,
        "white_corners": white_corners,
        "size": filled.size,
    }


def main() -> None:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("Resources")
    source = None
    for name in (
        "findaro-icon-source.jpg",
        "findaro-icon-source.jpeg",
        "findaro-icon-source.png",
        "findaro-icon-master.png",
    ):
        candidate = root / name
        if candidate.exists() and name != "findaro-icon-master.png":
            source = candidate
            break
        if candidate.exists() and source is None:
            source = candidate
    if source is None:
        raise SystemExit(f"No Findaro icon source in {root}")
    dest = root / "findaro-icon-master.png"
    info = process(source, dest)
    print(
        f"processed source={info['source']} dest={info['dest']} "
        f"crop={info['crop_box']} white_corners={info['white_corners']} "
        f"corners={info['corner_rgb']}"
    )
    if info["white_corners"] > 0:
        raise SystemExit("FAIL: white corners still present after processing")


if __name__ == "__main__":
    main()
