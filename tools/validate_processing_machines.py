#!/usr/bin/env python3
"""Validation hors-moteur : moulin, cuve, distillerie craftables."""

from __future__ import annotations

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
PASS = 0
FAIL = 0

MACHINES = (
	{
		"id": "flour_grinder",
		"script": "flour_grinder.gd",
		"model": "FlourGrinder.glb",
		"cost_bits": ('"wood": 30',),
	},
	{
		"id": "fermentation_tank",
		"script": "fermentation_tank.gd",
		"model": "FermentationTank.glb",
		"cost_bits": ('"wood": 50', '"iron_ore": 10'),
	},
	{
		"id": "distillery",
		"script": "distillery.gd",
		"model": "Distillery.glb",
		"cost_bits": ('"wood": 100', '"iron_ore": 50'),
	},
)


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
	previews = (ROOT / "scripts/ui/item_preview_scenes.gd").read_text(encoding="utf-8")
	icons = (ROOT / "scripts/ui/item_icons.gd").read_text(encoding="utf-8")
	session = (ROOT / "scripts/core/world_session.gd").read_text(encoding="utf-8")
	locale = (ROOT / "locale/game.csv").read_text(encoding="utf-8")

	for machine in MACHINES:
		mid = machine["id"]
		script_path = ROOT / "scripts/machines" / machine["script"]
		model_path = ROOT / "assets/models" / machine["model"]
		preview_path = ROOT / "scenes/ui/item_previews" / f"{mid}.tscn"
		script_text = script_path.read_text(encoding="utf-8") if script_path.is_file() else ""

		check(f"{mid} model", model_path.is_file(), f"{model_path.stat().st_size} bytes" if model_path.is_file() else "")
		check(f"{mid} script", script_path.is_file())
		check(f"{mid} preview scene", preview_path.is_file())
		check(f"{mid} recipe", f'"result_id": "{mid}"' in recipes)
		for bit in machine["cost_bits"]:
			check(f"{mid} cost {bit}", bit in recipes)
		check(f"{mid} USES place", f'"{mid}": "place"' in recipes)
		check(f"{mid} placeable_script", f'resource_id == "{mid}"' in recipes)
		check(f"{mid} preview model", machine["model"] in previews and f'"{mid}"' in previews)
		check(f"{mid} icon", f'"{mid}"' in icons)
		check(f"{mid} save id", f'ends_with("{machine["script"]}")' in session)
		check(f"{mid} locale", f"ITEM_{mid.upper()}" in locale)
		check(f"{mid} machine group", 'add_to_group(&"machine")' in script_text)
		check(f"{mid} ghost glb", "_make_ghost" in script_text and machine["model"] in script_text)
		check(f"{mid} no usage UI", "interact" not in script_text.lower() and "panel" not in script_text.lower())

	print()
	print(f"Result: {PASS} passed, {FAIL} failed")
	return 1 if FAIL else 0


if __name__ == "__main__":
	sys.exit(main())
