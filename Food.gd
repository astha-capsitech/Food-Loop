# Food.gd
# Represents a food item that can wait in queue, circulate on a track, or exit off-screen.
extends PathFollow2D
class_name Food

signal food_exited(food: Food)

enum State { WAITING, CIRCULATING, EXITING }

@export var speed: float = 60.0
@export var target_size: float = 42.0

var state: State = State.WAITING
var is_player: bool = false
var has_exited: bool = false
var total_travel: float = 0.0
var entry_index: int = 0
var fruit_index: int = 0
var assigned_exit_index: int = -1

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	rotates = false # Keep fruit upright
	loop = true
	set_process(false)

func setup_fruit(tex: AtlasTexture, p_is_player: bool = false, p_speed: float = 60.0, p_fruit_index: int = 0) -> void:
	if not is_node_ready():
		await ready
	is_player = p_is_player
	speed = p_speed
	fruit_index = p_fruit_index
	
	if sprite:
		sprite.texture = tex
		var max_dim: float = maxf(tex.region.size.x, tex.region.size.y)
		if max_dim > 0.0:
			var s: float = target_size / max_dim
			sprite.scale = Vector2(s, s)
	
	queue_redraw()

func _draw() -> void:
	# Subtle indicator circle around player fruits once they enter the track
	if is_player and state != State.WAITING:
		draw_circle(Vector2.ZERO, target_size * 0.58, Color(0.15, 0.75, 1.0, 0.22))
		draw_arc(Vector2.ZERO, target_size * 0.58, 0.0, TAU, 32, Color(0.25, 0.85, 1.0, 0.85), 2.0)

func play_bump_animation() -> void:
	if not sprite:
		return
	var orig_scale: Vector2 = sprite.scale
	var tw := create_tween()
	tw.tween_property(sprite, "scale", orig_scale * 1.4, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(sprite, "modulate", Color(1.6, 0.4, 0.4, 1.0), 0.08)
	tw.parallel().tween_property(sprite, "rotation", deg_to_rad(randf_range(-20.0, 20.0)), 0.08)
	tw.tween_property(sprite, "scale", orig_scale * 0.85, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(sprite, "scale", orig_scale, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(sprite, "modulate", Color.WHITE, 0.15)
	tw.parallel().tween_property(sprite, "rotation", 0.0, 0.12)

func start_circulating(entry_progress: float = 0.0) -> void:
	state = State.CIRCULATING
	progress = entry_progress
	total_travel = 0.0
	loop = true
	set_process(true)
	queue_redraw()

func start_exiting(exit_path: Path2D) -> void:
	state = State.EXITING
	loop = false
	reparent(exit_path, false)
	progress = 0.0
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	match state:
		State.CIRCULATING:
			var step: float = speed * delta
			progress += step
			total_travel += step
		State.EXITING:
			progress += speed * delta
			# Only for exit path: queue_free when food has left the screen (viewport)
			var screen_rect: Rect2 = get_viewport_rect().grow(target_size)
			var is_off_screen: bool = not screen_rect.has_point(global_position)
			var parent_path: Path2D = get_parent() as Path2D
			var is_curve_end: bool = false
			if parent_path and parent_path.curve:
				var baked_len: float = parent_path.curve.get_baked_length()
				if baked_len > 1.0 and progress >= baked_len:
					is_curve_end = true

			if (is_off_screen or is_curve_end) and not has_exited:
				has_exited = true
				set_process(false)
				food_exited.emit(self)
				queue_free()