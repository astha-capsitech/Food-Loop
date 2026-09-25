# Gameplay.gd
# Main gameplay controller for Food Circle Loop.
# Manages level lifecycle, player input, food circulation, exit routing,
# collision detection, win/lose conditions, and editor-preview mode.
extends Node2D

# ─── Editor preview support ───────────────────────────────────────────────────
const _PREVIEW_FLAG   := "res://._preview"
const _PREVIEW_CONFIG := "res://Levels/_preview.tres"

# ─── Exports ─────────────────────────────────────────────────────────────────
@export var food_scene: PackedScene

# ─── Runtime state ───────────────────────────────────────────────────────────
var current_level_index: int = 1
var active_config: LevelConfig

var queue:      Array[Food] = []
var circulating: Array[Food] = []
var player_foods_in_play: int = 0

var game_started: bool = false
var game_over:   bool = false
var level_won:   bool = false
var level_timer: float = 30.0
var is_timer_active: bool = false

## Round-robin index into active_config.entry_points.
var entry_round_robin: int = 0

## Input debounce to prevent dual touch/mouse events on mobile
const TAP_COOLDOWN: float = 0.15
var last_tap_time: float = -999.0

## Dynamically created Path2D nodes for each ExitConfig (parallel arrays).
var exit_path_nodes: Array[Path2D] = []
## Pre-computed progress offsets along loop_path for each exit trigger point.
var exit_progs: Array[float] = []

# ─── Scene nodes ─────────────────────────────────────────────────────────────
@onready var level_root:      Node2D    = $LevelRoot
@onready var route:           Node2D    = $LevelRoot/Route
@onready var oval_sprite:     Sprite2D  = $LevelRoot/Route/OvalSprite
@onready var entry_road:      Line2D    = $LevelRoot/Route/EntryRoad
@onready var exit_road:       Line2D    = $LevelRoot/Route/ExitRoad
@onready var entry_dashes:    Line2D    = $LevelRoot/Route/EntryDashes
@onready var exit_dashes:     Line2D    = $LevelRoot/Route/ExitDashes
@onready var loop_path:       Path2D    = $LevelRoot/Route/Path2D
@onready var exit_path:       Path2D    = $LevelRoot/Route/ExitPath2D
@onready var exit_indicator:  Polygon2D = $LevelRoot/Route/ExitIndicator
@onready var queue_container: Node2D   = $LevelRoot/Queue

@onready var canvas_layer: CanvasLayer = $CanvasLayer
@onready var gamepanel:   GamePanel   = $CanvasLayer/Gamepanel
@onready var win_panel:   WinPanel    = $CanvasLayer/WinPanel
@onready var lose_panel:  LosePanel   = $CanvasLayer/LosePanel
@onready var start_panel: StartPanel  = $CanvasLayer/StartPanel

# Design viewport size — all LevelConfig positions were authored at this resolution.
const DESIGN_W: float = 720.0
const DESIGN_H: float = 1280.0

## Runtime scale factors: design → actual viewport (set once in _apply_config).
var vp_scale_x: float = 1.0
var vp_scale_y: float = 1.0


# ─── Ready ───────────────────────────────────────────────────────────────────

func _ready() -> void:
	canvas_layer.show()

	# ── Editor preview mode ──────────────────────────────────────────────────
	if FileAccess.file_exists(_PREVIEW_FLAG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_PREVIEW_FLAG))
		if ResourceLoader.exists(_PREVIEW_CONFIG):
			active_config = load(_PREVIEW_CONFIG) as LevelConfig
		if active_config:
			_apply_config()
			gamepanel.hide()
			win_panel.hide()
			lose_panel.hide()
			start_panel.hide()
			gamepanel.show()
			gamepanel.set_level_title(active_config.title)
			game_started   = true
			is_timer_active = true
			spawn_initial_circulating()
			spawn_queue()
			update_counter()
			update_timer_display()
			return

	# ── Normal startup ───────────────────────────────────────────────────────
	gamepanel.hide()
	win_panel.hide()
	lose_panel.hide()
	start_panel.show()

	start_panel.start_pressed.connect(start_game)
	win_panel.next_pressed.connect(go_to_next_level)
	lose_panel.restart_pressed.connect(restart_level)
	get_viewport().size_changed.connect(_on_viewport_size_changed)

	load_level(current_level_index)


# ─── Level loading ────────────────────────────────────────────────────────────

func load_level(level_num: int) -> void:
	current_level_index = level_num
	active_config = LevelManager.get_level(level_num)
	if not active_config:
		push_error("Gameplay: No LevelConfig for level %d. Open the Level Builder and create or save levels first." % level_num)
		return
	_clear_level_state()
	_apply_config()
	gamepanel.set_level_title(active_config.title)
	update_counter()
	update_timer_display()


func _clear_level_state() -> void:
	for f: Food in circulating:
		if is_instance_valid(f): f.queue_free()
	circulating.clear()

	for f: Food in queue:
		if is_instance_valid(f): f.queue_free()
	queue.clear()

	# Clear any foods still attached to loop_path, exit_path or queue_container
	if is_instance_valid(loop_path):
		for c in loop_path.get_children():
			if c is Food and is_instance_valid(c):
				c.queue_free()

	if is_instance_valid(exit_path):
		for c in exit_path.get_children():
			if c is Food and is_instance_valid(c):
				c.queue_free()

	if is_instance_valid(queue_container):
		for c in queue_container.get_children():
			if c is Food and is_instance_valid(c):
				c.queue_free()

	# Destroy dynamically created extra exit paths (index > 0; index 0 = reused scene node)
	for i: int in range(1, exit_path_nodes.size()):
		var ep: Path2D = exit_path_nodes[i]
		if is_instance_valid(ep):
			for c in ep.get_children():
				if c is Food and is_instance_valid(c):
					c.queue_free()
			ep.queue_free()
	exit_path_nodes.clear()
	exit_progs.clear()

	player_foods_in_play  = 0
	game_over             = false
	level_won             = false
	level_timer           = 30.0
	is_timer_active       = false
	entry_round_robin     = 0
	last_tap_time         = -999.0


func _apply_config() -> void:
	level_timer = active_config.level_time

	# ── 1. Route transform in LevelRoot space (origin is always (0, 0)) ─────────
	route.position = Vector2.ZERO
	route.rotation = 0.0
	route.scale    = active_config.route_scale

	# ── 2. OvalSprite at origin of Route (same centre as the loop Path2D) ─────────
	if active_config.track_texture:
		oval_sprite.texture  = active_config.track_texture
		oval_sprite.position = Vector2.ZERO   # centred on Route
		oval_sprite.visible  = true
	else:
		oval_sprite.visible = false

	# ── 3. Build loop curve ──────────────────────────────────────────────────────
	loop_path.curve = active_config.get_loop_curve()

	# ── 4. Anchor queue to entry point (in LevelRoot space) ───────────────────
	if not active_config.entry_points.is_empty():
		queue_container.position = active_config.entry_points[0] * active_config.route_scale
	else:
		var q_rel: Vector2 = active_config.queue_base_position - active_config.route_position
		queue_container.position = q_rel
	queue_container.rotation = 0.0

	# ── 5. Auto-generate Entry Road visual along the queue direction ────────────
	_rebuild_entry_road()

	# ── 6. Setup exit paths ─────────────────────────────────────────────────────
	if active_config.has_exit and not active_config.exit_configs.is_empty():
		exit_indicator.show()
		for i: int in range(active_config.exit_configs.size()):
			var ecfg: ExitConfig = active_config.exit_configs[i]
			var ep_node: Path2D

			if i == 0:
				# Reuse the existing ExitPath2D for the first exit
				ep_node = exit_path
				ep_node.show()
			else:
				# Dynamically add extra exit paths as children of Route
				ep_node = Path2D.new()
				route.add_child(ep_node)

			var exit_curve := Curve2D.new()
			for p: Vector2 in ecfg.exit_points:
				exit_curve.add_point(p)
			ep_node.curve = exit_curve

			exit_path_nodes.append(ep_node)
			exit_progs.append(active_config.get_exit_progress(loop_path.curve, i))

		# Orient exit indicator toward first exit
		var first: ExitConfig = active_config.exit_configs[0]
		if not first.exit_points.is_empty():
			exit_indicator.position = first.exit_points[0]
			if first.exit_points.size() > 1:
				var dir: Vector2 = (first.exit_points[1] - first.exit_points[0]).normalized()
				exit_indicator.rotation = dir.angle() + PI / 2.0

		# Auto-generate Exit Road visual
		_rebuild_exit_road()
	else:
		exit_path.hide()
		exit_indicator.hide()
		_clear_exit_road()

	# ── 7. Responsive scaling and centering ───────────────────────────────────
	_apply_responsive_layout()


func _on_viewport_size_changed() -> void:
	if active_config:
		_apply_responsive_layout()


## Responsively scales LevelRoot as a single unit so the loop occupies ~75% of
## the available viewport width and is centered horizontally.
func _apply_responsive_layout() -> void:
	if not active_config or not is_instance_valid(level_root):
		return

	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		return

	vp_scale_x = vp_size.x / DESIGN_W
	vp_scale_y = vp_size.y / DESIGN_H

	# ── 1. Measure base authored width of the track/loop in design space ────────
	var base_width: float = 0.0

	var pts: PackedVector2Array = active_config.loop_points
	if pts.is_empty() and is_instance_valid(loop_path) and loop_path.curve:
		pts = loop_path.curve.get_baked_points()

	if pts.size() >= 3:
		var min_x := INF
		var max_x := -INF
		for p: Vector2 in pts:
			min_x = minf(min_x, p.x)
			max_x = maxf(max_x, p.x)
		base_width = (max_x - min_x) * absf(active_config.route_scale.x)
	elif active_config.track_texture:
		var tex_sz: Vector2 = active_config.track_texture.get_size()
		base_width = tex_sz.x * absf(active_config.route_scale.x)

	if base_width <= 10.0:
		base_width = DESIGN_W * 0.75 # Default fallback: 540.0 px

	# ── 2. Target width: exactly 75% of current viewport width ─────────────────
	var target_width: float = vp_size.x * 0.75

	# ── 3. Responsive scale factor ─────────────────────────────────────────────
	# On higher resolutions (e.g. 1080p, 1440p) scale_factor > 1.0 (scales UP)
	# On lower resolutions (e.g. 480p) scale_factor < 1.0 (scales DOWN)
	var scale_factor: float = target_width / base_width
	level_root.scale = Vector2(scale_factor, scale_factor)

	# ── 4. Horizontal centering ────────────────────────────────────────────────
	# Since route.position is Vector2.ZERO inside LevelRoot, placing LevelRoot at
	# vp_size.x * 0.5 GUARANTEES route/sprite is dead center on every resolution.
	level_root.position.x = vp_size.x * 0.5

	# ── 5. Vertical positioning ────────────────────────────────────────────────
	# Preserve the authored vertical proportion (default ~44% from top of screen)
	var authored_y: float = active_config.route_position.y if active_config.route_position.y > 0.0 else 560.0
	level_root.position.y = vp_size.y * (authored_y / DESIGN_H)


## Entry road extends from entry_local outward along the queue direction (matching queue_step).
func _rebuild_entry_road() -> void:
	entry_road.clear_points()
	entry_dashes.clear_points()
	if active_config.entry_points.is_empty():
		return

	var entry_local: Vector2 = active_config.entry_points[0]
	var far_local: Vector2 = entry_local + Vector2.DOWN * 3000.0

	entry_road.add_point(entry_local)
	entry_road.add_point(far_local)
	_add_dashes(entry_dashes, entry_local, far_local)


func _clear_exit_road() -> void:
	exit_road.clear_points()
	exit_dashes.clear_points()


## Exit road extends from exit_local in the direction of the exit path.
## Direction = exit_points[0] → exit_points[1] (the path the food takes after exiting).
func _rebuild_exit_road() -> void:
	exit_road.clear_points()
	exit_dashes.clear_points()
	if active_config.exit_configs.is_empty():
		return
	var first_exit: ExitConfig = active_config.exit_configs[0]
	if first_exit.exit_points.size() < 2:
		return

	var exit_local: Vector2 = first_exit.exit_points[0]
	# Direction from trigger point → next exit waypoint
	var dir: Vector2 = (first_exit.exit_points[1] - exit_local).normalized()
	var far_local: Vector2 = exit_local + dir * 3000.0

	exit_road.add_point(exit_local)
	exit_road.add_point(far_local)
	_add_dashes(exit_dashes, exit_local, far_local)


## Shared helper — draws dashed centre-line into [param line] from [param a] to [param b].
## Direction-agnostic: works for any Route rotation/scale/position.
func _add_dashes(line: Line2D, a: Vector2, b: Vector2) -> void:
	var delta: Vector2 = b - a
	var total: float   = delta.length()
	if total < 1.0:
		return
	var dir: Vector2 = delta / total
	var inv_s: float    = 1.0 / maxf(absf(route.scale.y), 0.01)
	var dash_len: float = 18.0 * inv_s
	var gap_len: float  = 14.0 * inv_s
	var t: float = 0.0
	var on: bool = true
	while t < total:
		var seg: float = dash_len if on else gap_len
		var t2: float  = minf(t + seg, total)
		if on:
			line.add_point(a + dir * t)
			line.add_point(a + dir * t2)
		t = t2
		on = not on


# ─── Game lifecycle ───────────────────────────────────────────────────────────

func start_game() -> void:
	if not active_config:
		push_error("Gameplay: Cannot start game because no LevelConfig is loaded.")
		return
	game_started    = true
	game_over       = false
	level_won       = false
	is_timer_active = true

	start_panel.hide()
	win_panel.hide()
	lose_panel.hide()
	gamepanel.show()

	spawn_initial_circulating()
	spawn_queue()
	update_counter()
	update_timer_display()


func spawn_initial_circulating() -> void:
	var indices := active_config.initial_fruit_indices
	var count: int = indices.size()
	if count <= 0:
		return
	var curve_len: float = loop_path.curve.get_baked_length()
	var gap: float = curve_len / float(count)
	for i: int in range(count):
		var f: Food = food_scene.instantiate() as Food
		loop_path.add_child(f)
		var tex: AtlasTexture = FoodTextures.get_fruit_texture(indices[i])
		f.setup_fruit(tex, false, active_config.speed, indices[i])
		f.start_circulating(i * gap)
		circulating.append(f)


func spawn_queue() -> void:
	var count: int   = active_config.queue_count
	var indices      := active_config.queue_fruit_indices
	for i: int in range(count):
		var f: Food = food_scene.instantiate() as Food
		queue_container.add_child(f)
		var f_idx: int = 0
		var tex: AtlasTexture
		if active_config.queue_random_fruit:
			f_idx = randi() % FoodTextures.get_total_fruit_types()
			tex = FoodTextures.get_fruit_texture(f_idx)
		elif indices.size() > 0:
			f_idx = indices[i % indices.size()]
			tex = FoodTextures.get_fruit_texture(f_idx)
		else:
			f_idx = 0
			tex = FoodTextures.get_fruit_texture(0)
		f.setup_fruit(tex, true, active_config.speed, f_idx)
		f.position = active_config.queue_step * float(i)
		queue.append(f)


# ─── Input ────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not game_started or game_over or level_won:
		return
	
	var is_valid_tap: bool = false
	if event is InputEventScreenTouch:
		var touch_ev := event as InputEventScreenTouch
		if touch_ev.pressed:
			is_valid_tap = true
	elif event is InputEventMouseButton:
		var mouse_ev := event as InputEventMouseButton
		if mouse_ev.pressed and mouse_ev.button_index == MOUSE_BUTTON_LEFT:
			is_valid_tap = true
	
	if is_valid_tap:
		var current_time: float = Time.get_ticks_msec() / 1000.0
		if current_time - last_tap_time < TAP_COOLDOWN:
			return
		last_tap_time = current_time
		get_viewport().set_input_as_handled()
		enter_next_food()


func enter_next_food() -> void:
	if queue.is_empty() or game_over or level_won:
		return

	var colliding_food: Food = get_colliding_food_at_entry()

	# Determine which entry point to use (round-robin)
	var current_entry_idx: int = entry_round_robin
	var entry_prog: float = active_config.get_entry_progress(
		loop_path.curve, current_entry_idx)
	entry_round_robin = (entry_round_robin + 1) % maxi(1, active_config.entry_points.size())

	var f: Food = queue.pop_front() as Food
	f.entry_index = current_entry_idx
	f.reparent(loop_path, false)
	f.start_circulating(entry_prog)
	circulating.append(f)
	player_foods_in_play += 1

	shift_queue()
	update_counter()

	# If there was a fruit at the entry point, play collision animation then game over
	if colliding_food != null:
		trigger_collision_game_over(f, colliding_food)
		return

	# No-exit levels win when the queue is fully sent
	if not active_config.has_exit and queue.is_empty():
		trigger_win()


func get_colliding_food_at_entry() -> Food:
	var curve_len: float  = loop_path.curve.get_baked_length()
	var entry_prog: float = active_config.get_entry_progress(
		loop_path.curve, entry_round_robin)
	for f: Food in circulating:
		if not is_instance_valid(f) or f.state != Food.State.CIRCULATING:
			continue
		# Protect newly entered queue fruits while they are still in the entry area
		if f.is_player and f.total_travel < active_config.min_gap:
			continue
		var diff: float = absf(fposmod(f.progress - entry_prog, curve_len))
		diff = minf(diff, curve_len - diff)
		if diff < active_config.min_gap:
			return f
	return null


func check_collision_at_entry() -> bool:
	return get_colliding_food_at_entry() != null


func shift_queue() -> void:
	for i: int in range(queue.size()):
		var target_pos: Vector2 = active_config.queue_step * float(i)
		var tw: Tween = create_tween()
		tw.tween_property(queue[i], "position", target_pos, 0.12) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# ─── Process / Exit logic ─────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if not game_started or game_over or level_won:
		return

	# Countdown timer
	if is_timer_active:
		level_timer -= delta
		if level_timer <= 0.0:
			level_timer = 0.0
			trigger_game_over()
		update_timer_display()

	if not active_config or not active_config.has_exit:
		return

	# Check each exit: route player foods that reach the exit trigger point
	var curve_len: float = loop_path.curve.get_baked_length()
	if curve_len <= 0.0:
		return

	for ei: int in range(exit_progs.size()):
		var ep: float = exit_progs[ei]
		if ep < 0.0:
			continue
		var ep_node: Path2D = exit_path_nodes[ei]
		for i: int in range(circulating.size() - 1, -1, -1):
			var f: Food = circulating[i] as Food
			if not is_instance_valid(f):
				circulating.remove_at(i)
				continue
			if f.is_player and f.state == Food.State.CIRCULATING and f.total_travel >= 12.0:
				if _can_food_use_exit(f, ei):
					var step: float = f.speed * delta
					var dist_to_ep: float = fposmod(ep - f.progress, curve_len)
					# Food reaches or crosses the exit trigger point
					if dist_to_ep <= step * 1.5 or dist_to_ep >= (curve_len - step * 0.5):
						circulating.remove_at(i)
						f.food_exited.connect(_on_food_exited)
						f.start_exiting(ep_node)


func _can_food_use_exit(f: Food, exit_idx: int) -> bool:
	if exit_idx >= active_config.exit_configs.size():
		return false
	var ecfg: ExitConfig = active_config.exit_configs[exit_idx]
	match ecfg.assign_rule:
		"any":
			return true
		"entry_match":
			return f.entry_index == exit_idx
		"fruit_type":
			return (f.fruit_index % active_config.exit_configs.size()) == exit_idx
		"random":
			if f.assigned_exit_index == -1:
				f.assigned_exit_index = randi() % active_config.exit_configs.size()
			return f.assigned_exit_index == exit_idx
	return true


func _on_food_exited(_food: Food) -> void:
	player_foods_in_play = maxi(0, player_foods_in_play - 1)
	update_counter()
	if active_config.has_exit and queue.is_empty() and player_foods_in_play == 0:
		trigger_win()


# ─── UI helpers ──────────────────────────────────────────────────────────────

func update_counter() -> void:
	var rem: int = queue.size()
	if active_config and active_config.has_exit:
		rem += player_foods_in_play
	gamepanel.set_counter(rem)

func update_timer_display() -> void:
	gamepanel.set_timer(level_timer)


# ─── Win / Lose ───────────────────────────────────────────────────────────────

func trigger_win() -> void:
	level_won       = true
	is_timer_active = false
	gamepanel.hide()
	win_panel.show()
	if current_level_index >= LevelManager.get_total_levels():
		win_panel.set_next_label_text("Finish!")
	else:
		win_panel.set_next_label_text("Next")


func trigger_collision_game_over(f: Food, hit_food: Food) -> void:
	game_over       = true
	is_timer_active = false

	# Stop all food movement so they freeze at the crash point
	for food: Food in circulating:
		if is_instance_valid(food):
			food.set_process(false)
	for ep_node: Path2D in exit_path_nodes:
		if is_instance_valid(ep_node):
			for c: Node in ep_node.get_children():
				if c is Food and is_instance_valid(c):
					c.set_process(false)

	# Play collision bump animation on both contacting fruits
	if is_instance_valid(f):
		f.play_bump_animation()
	if is_instance_valid(hit_food):
		hit_food.play_bump_animation()

	# Give player a brief moment to see the collision impact animation
	await get_tree().create_timer(0.45).timeout

	if is_instance_valid(gamepanel):
		gamepanel.hide()
	if is_instance_valid(lose_panel):
		lose_panel.show()


func trigger_game_over() -> void:
	game_over       = true
	is_timer_active = false
	for f: Food in circulating:
		if is_instance_valid(f): f.set_process(false)
	for ep_node: Path2D in exit_path_nodes:
		if is_instance_valid(ep_node):
			for c: Node in ep_node.get_children():
				if c is Food and is_instance_valid(c):
					c.set_process(false)
	gamepanel.hide()
	lose_panel.show()


func go_to_next_level() -> void:
	win_panel.hide()
	current_level_index += 1
	if current_level_index > LevelManager.get_total_levels():
		current_level_index = 1
	load_level(current_level_index)
	start_game()


func restart_level() -> void:
	lose_panel.hide()
	load_level(current_level_index)
	start_game()
