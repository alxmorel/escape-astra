#!/usr/bin/env python3
"""Validation hors-moteur pour gisements de charbon."""

from __future__ import annotations

import math
import pathlib
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


def coal_key(direction: tuple[float, float, float]) -> str:
	return "coal_%s" % rock_key(direction)


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
		ROOT / "assets/models/coal_rock_01.glb",
		ROOT / "assets/models/coal_rock_02.glb",
	]
	for path in models:
		check(f"model exists {path.name}", path.is_file(), f"{path.stat().st_size} bytes")
		check(f"{path.name} has mesh", glb_has_mesh(path))
	item_model = ROOT / "assets/models/Coal.glb"
	check("Coal.glb item model", item_model.is_file(), f"{item_model.stat().st_size} bytes" if item_model.is_file() else "")
	check("Coal.glb has mesh", item_model.is_file() and glb_has_mesh(item_model))
	preview = (ROOT / "scenes/ui/item_previews/coal.tscn").read_text(encoding="utf-8")
	previews_gd = (ROOT / "scripts/ui/item_preview_scenes.gd").read_text(encoding="utf-8")
	check("coal preview uses Coal.glb", "Coal.glb" in preview and "coal_rock" not in preview)
	check("MODELS coal uses Coal.glb", '"coal": preload("res://assets/models/Coal.glb")' in previews_gd)

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
	icons = files["item_icons.gd"].read_text(encoding="utf-8")

	check("COAL_SCENES declared", "COAL_SCENES" in rocks)
	check("coal_rock_01/02 preloaded", "coal_rock_01.glb" in rocks and "coal_rock_02.glb" in rocks)
	check("spawn_coal_deposit present", "func spawn_coal_deposit" in rocks)
	check("instantiate_coal present", "func instantiate_coal" in rocks)
	check("coal resource_id", 'resource_id = "coal"' in rocks)
	check("coal_key prefix", 'return "coal_%s"' in rocks or "coal_%s" in rocks)
	check("_spawn_coal_deposits present", "func _spawn_coal_deposits" in planet)
	check("dedicated coal RNG seed", "_coal_spawn_seed" in planet)
	check("coal uses RandomNumberGenerator", "rng.seed = _coal_spawn_seed()" in planet)
	check("coal denser than iron (target)", "coal_target := 44" in planet and "iron_target := 22" in planet)
	check("coal denser than iron (density)", "coal_density: float = 1.35" in planet and "iron_density: float = 1.15" in planet)
	check("coal higher rarity", "coal_rarity: float = 0.72" in planet and "iron_rarity: float = 0.48" in planet)
	check("coal shallow surface chance", "coal_shallow_chance" in planet)
	check("skip_terrain_snap on coal", "skip_terrain_snap" in rocks)
	check("exposure gate", "is_exposed" in harvest and "is_point_air" in planet)
	check("coal in catalog", '"coal"' in recipes)
	check("ITEM_COAL locale", "ITEM_COAL" in locale)
	check("coal icon", '"coal"' in icons)

	dirs = fibonacci_directions(64)
	keys = [coal_key(d) for d in dirs]
	check("coal keys unique on sample", len(keys) == len(set(keys)), f"{len(set(keys))} unique")
	check("coal keys prefixed", all(k.startswith("coal_") for k in keys))
	iron_keys = [iron_key(d) for d in dirs]
	stone_keys = [rock_key(d) for d in dirs]
	check("coal keys distinct from iron", set(keys).isdisjoint(set(iron_keys)))
	check("coal keys distinct from stone", set(keys).isdisjoint(set(stone_keys)))
	check("key determinism", coal_key(dirs[7]) == coal_key(dirs[7]))

	print()
	print(f"Result: {PASS} passed, {FAIL} failed")
	return 1 if FAIL else 0


if __name__ == "__main__":
	sys.exit(main())
