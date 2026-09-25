extends Control
class_name GamePanel

@export var timer_label: Label
@export var level_label: Label
@export var counter_label: Label

func set_timer(seconds: float) -> void:
	if timer_label:
		var mins: int = int(seconds) / 60
		var secs: int = int(seconds) % 60
		timer_label.text = "%02d:%02d" % [mins, secs]

func set_level_title(title: String) -> void:
	if level_label:
		level_label.text = title.to_upper()

func set_counter(count: int) -> void:
	if counter_label:
		counter_label.text = str(count)