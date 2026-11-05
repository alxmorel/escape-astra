#!/usr/bin/env python3
"""Validation : recettes outils / épées uniformes + drop fer = 1."""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
PASS = 0
FAIL = 0

WOODEN = ("wooden_pickaxe", "wooden_axe", "wooden_sword", "wooden_shovel", "wooden_hoe")
STONE = ("stone_pickaxe", "stone_axe", "stone_sword", "stone_shovel", "stone_hoe")
IRON = ("iron_pickaxe", "iron_axe", "iron_sword", "iron_shovel", "iron_hoe")


def check(name: str, ok: bool, detail: str = "") -> None:
	global PASS, FAIL
	if ok:
		PASS += 1
		print(f"PASS  {name}" + (f" — {detail}" if detail else ""))
	else:
		FAIL += 1
		print(f"FAIL  {name}" + (f" — {detail}" if detail else ""))


def recipe_block(text: str, result_id: str) -> str:
	m = re.search(
		rf'\{{\s*"result_id": "{result_id}".*?"ingredients": \{{[^}}]+\}}',
		text,
		re.S,
	)
	return m.group(0) if m else ""


def main() -> int:
	recipes = (ROOT / "scripts/resources/recipe_catalog.gd").read_text(encoding="utf-8")
	rocks = (ROOT / "scripts/world/planet_rocks.gd").read_text(encoding="utf-8")

	for rid in WOODEN:
		block = recipe_block(recipes, rid)
		check(f"{rid} cost", '"sticks": 5' in block and '"wood": 5' in block and "wood_planks" not in block)
	for rid in STONE:
		block = recipe_block(recipes, rid)
		check(f"{rid} cost", '"sticks": 5' in block and '"stone": 5' in block)
	for rid in IRON:
		block = recipe_block(recipes, rid)
		check(
			f"{rid} cost",
			'"sticks": 5' in block and '"iron_ore": 3' in block and "wood_planks" not in block,
		)

	# Machines inchangées
	check("fermentation still iron_ore 10", '"fermentation_tank"' in recipes and '"iron_ore": 10' in recipes)
	check("distillery still iron_ore 50", '"distillery"' in recipes and '"iron_ore": 50' in recipes)

	# Drop fer : 1 unité par drop
	iron_spawn = rocks[rocks.find("func spawn_iron_deposit") : rocks.find("func spawn_coal_deposit")]
	check("iron drop_quantity 1", "drop_quantity = 1" in iron_spawn)
	check("iron resource_id iron_ore", 'resource_id = "iron_ore"' in iron_spawn)
	check("iron hits_per_drop 1", "hits_per_drop = 1" in iron_spawn)

	print()
	print(f"Result: {PASS} passed, {FAIL} failed")
	return 1 if FAIL else 0


if __name__ == "__main__":
	sys.exit(main())
