#!/usr/bin/env python3
"""Enriquece motionsites-gratis.json con tags, blocks y app-fit desde apps.registry.json."""
from __future__ import annotations

import json
import os
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SRC = Path(os.environ.get("MOTIONSITES_SRC", ""))
REGISTRY = ROOT / "apps.registry.json"
OUT = ROOT / "catalog.json"

BLOCK_FROM_SECTION = {
    "heroes": "hero",
    "templates": "template-full",
    "backgrounds": "background",
}

CATEGORY_BLOCK = {
    "pricing": "pricing",
    "footer": "footer",
    "footer section": "footer",
    "cta": "cta",
    "cta section": "cta",
    "testimonials": "testimonials",
    "testimonial": "testimonials",
    "faq": "faq",
    "features": "features",
    "features section": "features",
    "benefits": "features",
    "component": "features",
    "404": "utility",
    "form": "contact",
    "blog": "gallery",
    "stats": "social-proof",
    "about": "about",
    "process": "process",
    "dashboard": "product-demo",
}


def load_apps() -> dict:
    with open(REGISTRY, encoding="utf-8") as f:
        data = json.load(f)
    return {k: v for k, v in data.get("apps", {}).items() if not k.startswith("_")}


def infer_tags(name: str, category: str, section: str) -> set[str]:
    text = f"{name} {category} {section}".lower()
    tags: set[str] = set()
    rules = [
        (r"\bai\b|automation|neural|sentinel|stellar|workflow|builder", "saas-ai"),
        (r"academy|learn|course|education|designpro|codenest|mindloop", "edtech"),
        (r"agency|studio|creative|portfolio|prisma", "agency"),
        (r"3d|collectible", "portfolio-3d"),
        (r"crypto|web3|nft|defi|rivr|orbis nft", "crypto"),
        (r"jet|yacht|luxury|elite", "luxury"),
        (r"wellness|yoga|health portal|organic", "wellness-only"),
        (r"security|cyber|securify|guardnet|akor", "security"),
        (r"finance|fintech|payment|wealth", "fintech"),
        (r"dark|neon|cyber|noir", "dark"),
        (r"email|marketing", "marketing"),
    ]
    for pattern, tag in rules:
        if re.search(pattern, text):
            tags.add(tag)
    if section == "backgrounds":
        tags.add("background")
    if section == "templates":
        tags.add("template-full")
    return tags


def infer_block(section: str, category: str) -> str:
    if section in BLOCK_FROM_SECTION:
        return BLOCK_FROM_SECTION[section]
    return CATEGORY_BLOCK.get(category.lower().strip(), "section")


def score_for_app(item: dict, app_id: str, app: dict) -> int:
    tags = set(item.get("tags", []))
    score = 10
    for t in app.get("tags", []):
        if t in tags:
            score += 15
    for t in app.get("avoid", []):
        if t in tags:
            score -= 40

    block = item.get("block", "")
    picks = app.get("curated_picks", {}).get(block, [])
    if item["name"] in picks:
        score += 50

    if block in ("hero", "features", "pricing", "template-full"):
        if "saas-ai" in tags or "edtech" in tags:
            score += 5
        if "crypto" in tags or "luxury" in tags:
            score -= 25

    return max(0, min(100, score))


def main() -> None:
    apps = load_apps()
    src = SRC if SRC.exists() else ROOT / "motionsites-gratis.json"
    if not src.exists():
        src = Path.home() / "Documents/Negocio/presentaciones/cursos-visuales/tools/motionsites-gratis.json"
    if not src.exists():
        raise SystemExit(f"No se encontró fuente: {src}")

    with open(src, encoding="utf-8") as f:
        raw = json.load(f)

    items = []
    for it in raw.get("items", []):
        tags = sorted(infer_tags(it.get("name", ""), it.get("category", ""), it.get("section", "")))
        block = infer_block(it.get("section", ""), it.get("category", ""))
        base = {**it, "tags": tags, "block": block}
        enriched = {
            **it,
            "id": re.sub(r"[^a-z0-9]+", "-", it.get("name", "").lower()).strip("-"),
            "block": block,
            "tags": tags,
            "app_scores": {app_id: score_for_app(base, app_id, app) for app_id, app in apps.items()},
        }
        items.append(enriched)

    catalog_apps = {}
    for app_id, app in apps.items():
        catalog_apps[app_id] = {
            "label": app.get("label", app_id),
            "theme": app.get("theme", {}),
            "repo_hint": app.get("repo_hint", ""),
            "landing_css": app.get("landing_css", ""),
            "app_profile": app.get("app_profile", {}),
            "curated_picks": app.get("curated_picks", {}),
            "applied_styles": app.get("applied_styles", {}),
        }

    catalog = {
        "version": 2,
        "source": raw.get("source", "https://motionsites.ai"),
        "registry": str(REGISTRY),
        "workflow": {
            "step1": "Identificar app_id en apps.registry.json",
            "step2": "Filtrar catalog.json por block y app_scores[app_id] >= 50",
            "step3": "Priorizar curated_picks del app_id",
            "step4": "Usuario copia prompt en MotionSites (botón Copy)",
            "step5": "Cursor adapta al theme y copy del producto",
        },
        "apps": catalog_apps,
        "blocks": sorted({i["block"] for i in items}),
        "total": len(items),
        "items": items,
    }

    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(catalog, f, ensure_ascii=False, indent=2)

    print(f"✓ {len(items)} items · {len(apps)} apps → {OUT}")


if __name__ == "__main__":
    main()
