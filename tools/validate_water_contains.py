#!/usr/bin/env python3
"""Validation hors-moteur de contains_point : mer ≠ immersion."""

from __future__ import annotations

import math
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
PASS = 0
FAIL = 0

VOXEL = 0.7
SEA = 100.0
OCEAN_TERRAIN = 90.0
LAND_TERRAIN = 110.0


def check(name: str, ok: bool, detail: str = "") -> None:
	global PASS, FAIL
	if ok:
		PASS += 1
		print(f"PASS  {name}" + (f" — {detail}" if detail else ""))
	else:
		FAIL += 1
		print(f"FAIL  {name}" + (f" — {detail}" if detail else ""))


def voxel_of(pos: tuple[float, float, float]) -> tuple[int, int, int]:
	return (
		math.floor(pos[0] / VOXEL),
		math.floor(pos[1] / VOXEL),
		math.floor(pos[2] / VOXEL),
	)


def center(cell: tuple[int, int, int]) -> tuple[float, float, float]:
	return (
		(cell[0] + 0.5) * VOXEL,
		(cell[1] + 0.5) * VOXEL,
		(cell[2] + 0.5) * VOXEL,
	)


def length(v: tuple[float, float, float]) -> float:
	return math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])


def scale(axis: tuple[float, float, float], radius: float) -> tuple[float, float, float]:
	n = length(axis)
	return (axis[0] / n * radius, axis[1] / n * radius, axis[2] / n * radius)


def terrain_height(dir_v: tuple[float, float, float]) -> float:
	n = length(dir_v)
	x, y, z = dir_v[0] / n, dir_v[1] / n, dir_v[2] / n
	if x + y + z >= 0.0:
		return OCEAN_TERRAIN
	return LAND_TERRAIN


def is_ocean_cell(cell: tuple[int, int, int], solid: set[tuple[int, int, int]]) -> bool:
	if cell in solid:
		return False
	c = center(cell)
	dist = length(c)
	if SEA <= 1.0 or dist <= 0.001 or dist > SEA + VOXEL:
		return False
	terrain = terrain_height(c)
	return terrain < SEA and dist + VOXEL * 0.45 >= terrain


def contains_point(
	pos: tuple[float, float, float],
	levels: dict[tuple[int, int, int], int],
	solid: set[tuple[int, int, int]],
) -> bool:
	"""Miroir de WaterVolume.contains_point (après correctif)."""
	if length(pos) ** 2 < 1.0:
		return False
	cell = voxel_of(pos)
	level = levels.get(cell, 0)
	if level > 0:
		if level >= 7:
			return True
		# surface partielle : rayon cellule approx (centre ± demi voxel)
		surface = length(center(cell)) + VOXEL * (level / 7.0 - 0.5)
		if length(pos) <= surface + 0.04:
			return True
	if not is_ocean_cell(cell, solid):
		return False
	return length(pos) <= SEA + 0.04


def legacy_below_sea(pos: tuple[float, float, float]) -> bool:
	"""Ancien fallback fautif : sea_level + bassin océanique."""
	dist = length(pos)
	if SEA <= 1.0 or dist >= SEA or dist < 0.001:
		return False
	return terrain_height(pos) < SEA


def main() -> int:
	solid: set[tuple[int, int, int]] = set()
	levels: dict[tuple[int, int, int], int] = {}
	axes = [(1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0)]

	for axis in axes:
		wet = scale(axis, 95.0)
		check(f"ocean wet {axis}", contains_point(wet, levels, solid))
		# Ancien bug : sous fond océanique aussi « wet ».
		under = scale(axis, 80.0)
		check(
			f"under floor dry {axis}",
			not contains_point(under, levels, solid)
			and legacy_below_sea(under),
			"legacy would be wet",
		)
		land = scale((-axis[0], -axis[1], -axis[2]), 95.0)
		check(f"land cave dry {axis}", not contains_point(land, levels, solid))
		above = scale(axis, 105.0)
		check(f"above sea dry {axis}", not contains_point(above, levels, solid))

	# Lac hors colonne océan (rayon > mer) pour isoler le niveau voxel.
	lake_cell = (200, 0, 0)
	levels[lake_cell] = 7
	lake_pos = center(lake_cell)
	check("lake voxel wet", contains_point(lake_pos, levels, solid))
	levels[lake_cell] = 0
	check("drained lake dry", not contains_point(lake_pos, levels, solid))

	# Cellule solide dans colonne océan → pas d'eau.
	ocean_cell = voxel_of(scale((1.0, 0.0, 0.0), 95.0))
	solid.add(ocean_cell)
	check(
		"solid ocean cell dry",
		not contains_point(scale((1.0, 0.0, 0.0), 95.0), levels, solid),
	)

	print(f"\n{PASS} passed, {FAIL} failed")
	return 1 if FAIL else 0


if __name__ == "__main__":
	sys.exit(main())
