extends RefCounted
class_name BootProfile

## Chronométrage déterministe du démarrage monde (pas de coût/frame hors enregistrement).

var marks: Dictionary = {}
var order: PackedStringArray = PackedStringArray()
var t0_ms := 0
var playable_ms := -1
var ready_ms := -1


func begin() -> void:
	marks.clear()
	order = PackedStringArray()
	t0_ms = Time.get_ticks_msec()
	playable_ms = -1
	ready_ms = -1
	mark("begin")


func mark(label: String) -> void:
	var now := Time.get_ticks_msec()
	marks[label] = now - t0_ms
	order.append(label)


func span(from_label: String, to_label: String) -> int:
	if not marks.has(from_label) or not marks.has(to_label):
		return -1
	return int(marks[to_label]) - int(marks[from_label])


func mark_playable() -> void:
	playable_ms = Time.get_ticks_msec() - t0_ms
	mark("playable")


func mark_ready_done() -> void:
	ready_ms = Time.get_ticks_msec() - t0_ms
	mark("ready_done")


func report() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("boot_profile total_ready=%dms playable=%dms" % [ready_ms, playable_ms])
	var prev := 0
	for label in order:
		var abs_t: int = int(marks[label])
		var dt := abs_t - prev
		lines.append("  +%4dms  @%4dms  %s" % [dt, abs_t, label])
		prev = abs_t
	return "\n".join(lines)


func as_dict() -> Dictionary:
	return {
		"marks": marks.duplicate(),
		"ready_ms": ready_ms,
		"playable_ms": playable_ms,
		"report": report(),
	}
