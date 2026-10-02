extends Control
class_name StartPanel

signal start_pressed

@export var startBtn: TextureButton

func _ready() -> void:
	startBtn.pressed.connect(_on_startBtn_pressed)

func _on_startBtn_pressed() -> void:
	start_pressed.emit()