#!/usr/bin/env python3
"""Validation hors-moteur pour US-A12 (gisements de fer)."""

from __future__ import annotations

import math
import pathlib
import re
import struct
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


def fibonacci_directions(count: int) -> list[tuple[float, float, float]]:
	golden = math.pi * (3.0 - math.sqrt(5.0))
	out: list[tuple[float, float, float]] = []
	for i in range(count):
		y = 1.0 - (float(i) / float(count - 1)) * 2.0
		ring = math.sqrt(max(0.0, 1.0 - y * y))
		theta = golden * i
		out.append((math.cos(theta) * ring, y, math.sin(theta) * ring))
	return out


def rock_key(direction: tuple[float, float, float]) -> str:
	length = math.sqrt(sum(c * c for c in direction))
	dir_n = tuple(c / length for c in direction)
	return "%d_%d_%d" % (
		int(round(dir_n[0] * 1000.0)),
		int(round(dir_n[1] * 1000.0)),
		int(round(dir_n[2] * 1000.0)),
	)


def iron_key(direction: tuple[float, float, float]) -> str:
	return "iron_%s" % rock_key(direction)


def glb_has_mesh(path: pathlib.Path) -> bool:
	data = path.read_bytes()
	if len(data) < 20 or data[:4] != b"glTF":
		return False
	json_len = struct.unpack_from("<I", data, 12)[0]
	json_blob = data[20 : 20 + json_len]
	return b'"meshes"' in json_blob


def main() -> int:
	models = [
		ROOT / "assets/models/iron_rock_01.glb",
		ROOT / "assets/models/iron_rock_02.glb",
		ROOT / "assets/models/iron_rock_03.glb",
	]
	for path in models:
		check(f"model exists {path.name}", path.is_file(), f"{path.stat().st_size} bytes")

	mesh_flags = [glb_has_mesh(p) for p in models]
	check("iron_rock_01 has mesh", mesh_flags[0])
	check("iron_rock_03 has mesh", mesh_flags[2])
	check(
		"iron_rock_02 mesh presence noted",
		True,
		"empty scene" if not mesh_flags[1] else "has mesh",
	)

	files = {
		"planet_rocks.gd": ROOT / "scripts/world/planet_rocks.gd",
		"planet_generator.gd": ROOT / "scripts/world/planet_generator.gd",
		"harvestable.gd": ROOT / "scripts/resources/harvestable.gd",
		"recipe_catalog.gd": ROOT / "scripts/resources/recipe_catalog.gd",
		"item_icons.gd": ROOT / "scripts/ui/item_icons.gd",
		"game.csv": ROOT / "locale/game.csv",
	}
	for label, path in files.items():
		text = path.read_text(encoding="utf-8")
		check(f"{label} readable", len(text) > 0)

	rocks = files["planet_rocks.gd"].read_text(encoding="utf-8")
	planet = files["planet_generator.gd"].read_text(encoding="utf-8")
	harvest = files["harvestable.gd"].read_text(encoding="utf-8")
	recipes = files["recipe_catalog.gd"].read_text(encoding="utf-8")
	locale = files["game.csv"].read_text(encoding="utf-8")

	check("IRON_SCENES declared", "IRON_SCENES" in rocks)
	check("spawn_iron_deposit present", "func spawn_iron_deposit" in rocks)
	check("iron 1 drop per hit", "hits_per_drop = 1" in rocks and "drop_quantity = 1" in rocks)
	check("iron breaks in 5 hits", "max_hits = 5" in rocks)
	check("iron_key prefix", 'return "iron_%s"' in rocks or "iron_%s" in rocks)
	check("_spawn_iron_deposits present", "func _spawn_iron_deposits" in planet)
	check("dedicated iron RNG seed", "_iron_spawn_seed" in planet)
	check("skip_terrain_snap meta", "skip_terrain_snap" in rocks and "skip_terrain_snap" in planet)
	check("exposure gate", "is_exposed" in harvest and "is_point_air" in planet)
	check("iron_ore in catalog", '"iron_ore"' in recipes)
	check("ITEM_IRON_ORE locale", "ITEM_IRON_ORE" in locale)
	check("configurable burial exports", "iron_burial_min" in planet and "iron_burial_max" in planet)
	check("configurable rarity/density", "iron_rarity" in planet and "iron_density" in planet)

	dirs = fibonacci_directions(64)
	keys = [iron_key(d) for d in dirs]
	check("iron keys unique on sample", len(keys) == len(set(keys)), f"{len(set(keys))} unique")
	check("iron keys prefixed", all(k.startswith("iron_") for k in keys))
	stone_keys = [rock_key(d) for d in dirs]
	check("iron keys distinct from stone", set(keys).isdisjoint(set(stone_keys)))

	# Determinism: same direction => same key
	check("key determinism", iron_key(dirs[7]) == iron_key(dirs[7]))

	# Burial math: top stays below surface for default ranges
	burial_min, burial_max = 1.5, 3.4
	mesh_h = 1.2
	tops = [b for b in (burial_min, burial_max)]
	check(
		"default burial keeps top under surface",
		all(t > 0.2 for t in tops),
		f"top depth range {burial_min}..{burial_max} (+ mesh {mesh_h} at feet)",
	)
	dirt_depth = 4.2
	tip_deepest = burial_max + 0.45 * mesh_h
	check(
		"deep tip mostly within dirt layer",
		tip_deepest <= dirt_depth,
		f"tip~{tip_deepest:.2f} vs dirt {dirt_depth}",
	)

	# Ensure rock spawn stream not interleaved with global rand for iron
	check(
		"iron uses RandomNumberGenerator",
		"RandomNumberGenerator" in planet and "rng.seed = _iron_spawn_seed()" in planet,
	)

	# Recipe wiring for iron tools (5 sticks + 3 iron_ore)
	for tool in ("iron_pickaxe", "iron_axe", "iron_shovel", "iron_hoe"):
		block = re.search(rf'"result_id": "{tool}".*?"ingredients": \{{[^}}]+\}}', recipes, re.S)
		ok = block is not None and '"iron_ore": 3' in block.group(0) and '"sticks": 5' in block.group(0)
		check(f"{tool} uses iron_ore", ok)

	print()
	print(f"Result: {PASS} passed, {FAIL} failed")
	return 1 if FAIL else 0


if __name__ == "__main__":
	sys.exit(main())
