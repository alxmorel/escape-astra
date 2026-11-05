#!/usr/bin/env python3
"""Validation hors-moteur : four craftable (furnace)."""

from __future__ import annotations

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
PASS = 0
FAIL = 0


def check(name: str, ok: bool, detail: str = "") -> None:
	global PASS, FAIL
	if ok:
		PASS += 1
		print(f"PASS  {name}" + (f" — {detail}" if detail else ""))
	else:
		FAIL += 1
		print(f"FAIL  {name}" + (f" — {detail}" if detail else ""))


def main() -> int:
	model = ROOT / "assets/models/Four.glb"
	furnace = (ROOT / "scripts/machines/furnace.gd").read_text(encoding="utf-8")
	recipes = (ROOT / "scripts/resources/recipe_catalog.gd").read_text(encoding="utf-8")
	previews = (ROOT / "scripts/ui/item_preview_scenes.gd").read_text(encoding="utf-8")
	icons = (ROOT / "scripts/ui/item_icons.gd").read_text(encoding="utf-8")
	session = (ROOT / "scripts/core/world_session.gd").read_text(encoding="utf-8")
	locale = (ROOT / "locale/game.csv").read_text(encoding="utf-8")
	preview_scene = ROOT / "scenes/ui/item_previews/furnace.tscn"

	check("Four.glb exists", model.is_file(), f"{model.stat().st_size} bytes" if model.is_file() else "")
	check("furnace.gd exists", (ROOT / "scripts/machines/furnace.gd").is_file())
	check("preview scene exists", preview_scene.is_file())
	check("recipe furnace", '"result_id": "furnace"' in recipes)
	check("cost stone 10 dirt 10", '"stone": 10' in recipes and '"dirt": 10' in recipes)
	check("USES place", '"furnace": "place"' in recipes)
	check("placeable_script furnace", "FURNACE_SCRIPT" in recipes and 'resource_id == "furnace"' in recipes)
	check("preview model Four.glb", "Four.glb" in previews and '"furnace"' in previews)
	check("icon furnace", '"furnace"' in icons and "_draw_furnace" in icons)
	check("save machine id", 'ends_with("furnace.gd")' in session)
	check("locale ITEM_FURNACE", "ITEM_FURNACE" in locale)
	check("machine group", 'add_to_group(&"machine")' in furnace)
	check("cook wood to charcoal", "SMELT_RECIPES" in furnace and "_try_complete_cook" in furnace)
	check("ghost uses glb", "_make_ghost" in furnace and "_add_proxy" not in furnace)

	print()
	print(f"Result: {PASS} passed, {FAIL} failed")
	return 1 if FAIL else 0


if __name__ == "__main__":
	sys.exit(main())
