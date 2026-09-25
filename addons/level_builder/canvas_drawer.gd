# canvas_drawer.gd
# Thin Control subclass that delegates _draw() and _gui_input() back to the
# parent LevelBuilderDock. This lets the dock own all drawing and input logic
# while still using Godot's native Control rendering pipeline.
@tool
extends Control

## Must be set to the LevelBuilderDock instance before adding to the tree.
var dock: Object

func _draw() -> void:
	if is_instance_valid(dock):
		dock.on_canvas_draw(self)

func _gui_input(event: InputEvent) -> void:
	if is_instance_valid(dock):
		dock.on_canvas_input(event, self)
