extends Control
class_name WinPanel

signal next_pressed

@export var nextlevelBtn: TextureButton
@export var next_label: Label

func _ready() -> void:
	nextlevelBtn.pressed.connect(_on_nextlevelBtn_pressed)

func _on_nextlevelBtn_pressed() -> void:
	next_pressed.emit()

func set_next_label_text(text: String) -> void:
	if next_label:
		next_label.text = text