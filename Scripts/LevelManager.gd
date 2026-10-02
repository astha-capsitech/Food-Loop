# LevelManager.gd
# Dynamically scans res://Levels/ for LevelConfig .tres files and returns them.
# ─────────────────────────────────────────────────────────────────────────────
# IMPORTANT: No per-level data is hardcoded here.
# All level data lives in .tres files authored via the Level Builder editor plugin.
# To add / edit / remove a level, open the "Level Builder" panel inside Godot editor.
# ─────────────────────────────────────────────────────────────────────────────
extends RefCounted
class_name LevelManager

const LEVELS_DIR := "res://Levels"

## Returns every LevelConfig found in res://Levels/, sorted by level_number.
## Files whose names begin with '_' (e.g. _preview.tres) are reserved for
## internal / temporary use and are excluded from the public list.
static func get_all_levels() -> Array[LevelConfig]:
	var list: Array[LevelConfig] = []
	var dir := DirAccess.open(LEVELS_DIR)
	if not dir:
		push_warning("LevelManager: Cannot open '%s'. Use the Level Builder plugin to create at least one level." % LEVELS_DIR)
		return list

	var loaded_paths := {}
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			var clean_name := file_name.trim_suffix(".remap").trim_suffix(".import")
			if clean_name.ends_with(".tres") and not clean_name.begins_with("_"):
				var path := "%s/%s" % [LEVELS_DIR, clean_name]
				if not loaded_paths.has(path):
					loaded_paths[path] = true
					var cfg := load(path) as LevelConfig
					if cfg:
						list.append(cfg)
		file_name = dir.get_next()
	dir.list_dir_end()

	list.sort_custom(func(a: LevelConfig, b: LevelConfig) -> bool:
		return a.level_number < b.level_number)
	return list


## Returns the LevelConfig for the given 1-based level_number.
## Clamps to the nearest valid level when level_number is out of range.
static func get_level(level_number: int) -> LevelConfig:
	var levels := get_all_levels()
	if levels.is_empty():
		return null
	var idx := clampi(level_number - 1, 0, levels.size() - 1)
	return levels[idx]


## Returns the total number of levels found on disk.
static func get_total_levels() -> int:
	return get_all_levels().size()
