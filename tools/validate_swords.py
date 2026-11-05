#!/usr/bin/env python3
"""Validation hors-moteur : épées craftables."""

from __future__ import annotations

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
PASS = 0
FAIL = 0

SWORDS = ("wooden_sword", "stone_sword", "iron_sword")
MODELS = {
	"wooden_sword": "wooden_sword.glb",
	"stone_sword": "stone_sword.glb",
	"iron_sword": "iron_sword.glb",
}
COSTS = {
	"wooden_sword": ('"sticks": 5', '"wood": 5'),
	"stone_sword": ('"sticks": 5', '"stone": 5'),
	"iron_sword": ('"sticks": 5', '"iron_ore": 3'),
}


def check(name: str, ok: bool, detail: str = "") -> None:
	global PASS, FAIL
	if ok:
		PASS += 1
		print(f"PASS  {name}" + (f" — {detail}" if detail else ""))
	else:
		FAIL += 1
		print(f"FAIL  {name}" + (f" — {detail}" if detail else ""))


def main() -> int:
	recipes = (ROOT / "scripts/resources/recipe_catalog.gd").read_text(encoding="utf-8")
	tools = (ROOT / "scripts/items/tool_scenes.gd").read_text(encoding="utf-8")
	dur = (ROOT / "scripts/items/tool_durability.gd").read_text(encoding="utf-8")
	previews = (ROOT / "scripts/ui/item_preview_scenes.gd").read_text(encoding="utf-8")
	icons = (ROOT / "scripts/ui/item_icons.gd").read_text(encoding="utf-8")
	locale = (ROOT / "locale/game.csv").read_text(encoding="utf-8")

	check("sword preview scene", (ROOT / "scenes/ui/item_previews/sword.tscn").is_file())
	for sid in SWORDS:
		model = ROOT / "assets/models" / MODELS[sid]
		held = ROOT / "scenes/items" / f"{sid}.tscn"
		check(f"{sid} model", model.is_file(), f"{model.stat().st_size} bytes" if model.is_file() else "")
		check(f"{sid} held scene", held.is_file())
		check(f"{sid} in NAMES", f'"{sid}"' in recipes)
		check(f"{sid} use tool", f'"{sid}": "tool"' in recipes)
		check(f"{sid} recipe", f'"result_id": "{sid}"' in recipes)
		for bit in COSTS[sid]:
			check(f"{sid} cost {bit}", bit in recipes)
		check(f"{sid} tool_scenes", f'"{sid}"' in tools and f"{sid}.tscn" in tools)
		check(f"{sid} durability", f'"{sid}"' in dur)
		check(f"{sid} preview SHARED/MODELS", f'"{sid}": "sword"' in previews and MODELS[sid] in previews)
		check(f"{sid} icon", f'"{sid}"' in icons and "_draw_sword" in icons)
		check(f"{sid} locale", f"ITEM_{sid.upper()}" in locale)

	print()
	print(f"Result: {PASS} passed, {FAIL} failed")
	return 1 if FAIL else 0


if __name__ == "__main__":
	sys.exit(main())
