# Food.gd
# Represents a food item that can wait in queue, circulate on a track, or exit off-screen.
extends PathFollow2D
class_name Food

signal food_exited(food: Food)

enum State { WAITING, CIRCULATING, EXITING }

# ─── Trail Configuration ─────────────────────────────────────────────────────
@export_group("Trail Effect")
## Custom trail color override. Pick any color here in Inspector to override default fruit colors.
@export var custom_trail_color: Color = Color(0.0, 0.0, 0.0, 0.0)

## Trail width multiplier relative to fruit size (1.1 = slightly wider than fruit for rich motion blur).
@export var trail_width_scale: float = 1.1

## Palette of vibrant trail colors for each fruit variety (editable directly in Inspector).
@export var trail_colors: Array[Color] = [
	Color(1.0, 0.15, 0.15),   # 0: Apple (Deep Red)
	Color(1.0, 0.45, 0.0),    # 1: Orange (Deep Orange)
	Color(0.7, 0.18, 1.0),    # 2: Plum (Deep Purple)
	Color(1.0, 0.4, 0.65),    # 3: Peach (Deep Pink)
	Color(1.0, 0.82, 0.0),    # 4: Pineapple (Golden Yellow)
	Color(0.25, 0.9, 0.2),    # 5: Pear (Deep Lime Green)
	Color(1.0, 0.88, 0.05),   # 6: Banana (Vibrant Yellow)
	Color(0.75, 0.12, 0.95),  # 7: Grape (Deep Violet)
	Color(1.0, 0.95, 0.15),   # 8: Lemon (Bright Yellow)
	Color(0.12, 0.88, 0.38),  # 9: Watermelon (Vibrant Green)
]

const MAX_TRAIL_POINTS: int = 36

@export var speed: float = 60.0
@export var target_size: float = 42.0

var state: State = State.WAITING
var is_player: bool = false
var has_exited: bool = false
var total_travel: float = 0.0
var entry_index: int = 0
var fruit_index: int = 0
var assigned_exit_index: int = -1

var trail: Line2D = null
var trail_active: bool = false

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	rotates = false # Keep fruit upright
	loop = true
	set_process(false)

## Public method to set or override the trail color from outside (e.g. from code)
func set_trail_color(col: Color) -> void:
	custom_trail_color = col
	if is_instance_valid(trail):
		_apply_trail_color(col)

func setup_fruit(tex: AtlasTexture, p_is_player: bool = false, p_speed: float = 60.0, p_fruit_index: int = 0, p_size: float = 42.0) -> void:
	is_player = p_is_player
	speed = p_speed
	fruit_index = p_fruit_index
	target_size = p_size

	if not is_node_ready():
		await ready
	
	if sprite:
		sprite.texture = tex
		var max_dim: float = maxf(tex.region.size.x, tex.region.size.y)
		if max_dim > 0.0:
			var s: float = target_size / max_dim
			sprite.scale = Vector2(s, s)
	
	if is_player:
		var col: Color = _get_active_trail_color()
		_create_trail(col)
	
	queue_redraw()

func _get_active_trail_color() -> Color:
	if custom_trail_color.a > 0.0:
		return custom_trail_color
	if not trail_colors.is_empty():
		return trail_colors[fruit_index % trail_colors.size()]
	return Color(0.2, 0.85, 1.0) # Fallback cyan

func _create_trail(fruit_col: Color) -> void:
	if trail != null:
		return
	trail = Line2D.new()
	trail.name = "Trail"
	trail.top_level = true
	trail.z_as_relative = false
	trail.z_index = 4  # Absolute z-index: above road (0) and below fruits (5)
	trail.width = target_size * trail_width_scale
	trail.default_color = Color.WHITE
	trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
	trail.end_cap_mode = Line2D.LINE_CAP_ROUND
	trail.joint_mode = Line2D.LINE_JOINT_ROUND
	trail.antialiased = true

	# Width Curve: thick solid body with smooth aerodynamic taper at tail
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.2))   # Tail tip: rounded solid end
	curve.add_point(Vector2(0.45, 0.78)) # Mid: thick dense body
	curve.add_point(Vector2(1.0, 1.0))   # Fruit head: full width
	trail.width_curve = curve

	_apply_trail_color(fruit_col)

	add_child(trail)
	trail.visible = false

func _apply_trail_color(fruit_col: Color) -> void:
	if not is_instance_valid(trail):
		return
	# 3-Stop Gradient: deep, vibrant, dense color along the body, fading at tail
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	grad.colors = PackedColorArray([
		Color(fruit_col.r, fruit_col.g, fruit_col.b, 0.0),   # Tail tip (fade out)
		Color(fruit_col.r, fruit_col.g, fruit_col.b, 0.78),  # Mid tail (deep & rich)
		Color(fruit_col.r, fruit_col.g, fruit_col.b, 0.95)   # Near fruit (dense & vibrant)
	])
	trail.gradient = grad

func _draw() -> void:
	# Subtle indicator circle around player fruits once they enter the track
	if is_player and state != State.WAITING:
		draw_circle(Vector2.ZERO, target_size * 0.58, Color(0.15, 0.75, 1.0, 0.22))
		draw_arc(Vector2.ZERO, target_size * 0.58, 0.0, TAU, 32, Color(0.25, 0.85, 1.0, 0.85), 2.0)

func play_bump_animation() -> void:
	trail_active = false
	if is_instance_valid(trail):
		trail.visible = false
		trail.clear_points()
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

	if is_player:
		var col: Color = _get_active_trail_color()
		if trail == null:
			_create_trail(col)
		else:
			_apply_trail_color(col)
		if is_instance_valid(trail):
			trail.global_position = Vector2.ZERO
			trail.global_rotation = 0.0
			trail.global_scale = Vector2.ONE
			trail.clear_points()
			trail.visible = true
			trail_active = true

func start_exiting(exit_path: Path2D) -> void:
	state = State.EXITING
	loop = false
	# Keep trail active and visible along the exit path
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
				return

	# Update trail ribbon (both while circulating in loop and while exiting along exit path)
	if trail_active and is_instance_valid(trail):
		var pt: Vector2 = trail.to_local(global_position)
		if trail.points.size() < 2:
			trail.clear_points()
			trail.add_point(pt)
			trail.add_point(pt)
		else:
			# Keep the newest point glued to current fruit position
			trail.set_point_position(trail.points.size() - 1, pt)
			# When moved at least 2.5px away from previous anchor point, record a new point
			var prev_pt: Vector2 = trail.points[trail.points.size() - 2]
			if prev_pt.distance_squared_to(pt) >= 6.25:
				trail.add_point(pt)
				if trail.points.size() > MAX_TRAIL_POINTS:
					trail.remove_point(0)