#!/usr/bin/env python3
"""Recomienda estilos MotionSites gratis por bloque según app_id."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
MIN_SCORE = 50
TOP_N = 3


def load_json(name: str) -> dict:
    with open(ROOT / name, encoding="utf-8") as f:
        return json.load(f)


def main() -> None:
    app_id = sys.argv[1] if len(sys.argv) > 1 else "cursia"
    registry = load_json("apps.registry.json")
    catalog = load_json("catalog.json")

    apps = registry.get("apps", {})
    if app_id not in apps:
        print(f"App '{app_id}' no registrada. Disponibles: {', '.join(k for k in apps if not k.startswith('_'))}")
        sys.exit(1)

    app = apps[app_id]
    profile = app.get("app_profile", {})
    picks = app.get("curated_picks", {})
    items = catalog.get("items", [])

    print(f"# Recomendación Web Style — {app.get('label', app_id)}")
    print()
    if profile:
        print("## Perfil de la app")
        for key in ("product", "audience", "tone", "differentiator"):
            if profile.get(key):
                print(f"- **{key}**: {profile[key]}")
        print()

    blocks = sorted({i["block"] for i in items if i.get("app_scores", {}).get(app_id, 0) >= MIN_SCORE})
    priority = profile.get("landing_blocks", blocks)
    ordered = [b for b in priority if b in blocks] + [b for b in blocks if b not in priority]

    print("## Estilos MotionSites gratis recomendados")
    print()
    print("| Bloque | #1 (TOP) | #2 | #3 | MotionSites |")
    print("|--------|----------|----|----|-------------|")

    for block in ordered:
        ranked = [
            i
            for i in items
            if i.get("block") == block and i.get("app_scores", {}).get(app_id, 0) >= MIN_SCORE
        ]
        ranked.sort(key=lambda x: (-x["app_scores"][app_id], x["name"]))

        top_names = picks.get(block, [])
        rationale = (app.get("app_profile", {}).get("style_rationale") or {}).get(block)
        rationale_name = rationale.split("—")[0].strip() if rationale else None

        def sort_key(x: dict) -> tuple:
            name = x["name"]
            curated_rank = top_names.index(name) if name in top_names else 99
            is_rationale = 0 if rationale_name and name == rationale_name else 1
            return (is_rationale, curated_rank, -x["app_scores"][app_id])

        ranked.sort(key=sort_key)

        row = [block]
        for i in range(TOP_N):
            if i < len(ranked):
                it = ranked[i]
                mark = " ⭐" if it["name"] in top_names else ""
                row.append(f"{it['name']} ({it['app_scores'][app_id]}%){mark}")
            else:
                row.append("—")
        url = ranked[0]["page_url"] if ranked else "https://motionsites.ai"
        row.append(url)
        print("| " + " | ".join(row) + " |")

    print()
    print("⭐ = curated pick · Copiar prompt en MotionSites con botón **Copy**")
    if app.get("applied_styles", {}).get("blocks"):
        print()
        print("## Ya aplicado en este repo")
        for b, name in app["applied_styles"]["blocks"].items():
            print(f"- {b}: {name}")


if __name__ == "__main__":
    main()
