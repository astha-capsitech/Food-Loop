# level_builder_plugin.gd
# EditorPlugin entry point for the Level Builder.
# Registers the dock in the bottom panel so it is always accessible.
@tool
extends EditorPlugin

var _dock: Control

func _enter_tree() -> void:
	_dock = load("res://addons/level_builder/level_builder_dock.gd").new()
	_dock.name = "LevelBuilderDock"
	add_control_to_bottom_panel(_dock, "🍎 Level Builder")

func _exit_tree() -> void:
	if is_instance_valid(_dock):
		remove_control_from_bottom_panel(_dock)
		_dock.queue_free()
