extends Control
class_name LosePanel

signal restart_pressed

@export var restartbtn: TextureButton

func _ready() -> void:
	restartbtn.pressed.connect(_on_restartbtn_pressed)

func _on_restartbtn_pressed() -> void:
	restart_pressed.emit()