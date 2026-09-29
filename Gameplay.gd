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

var queue:            Array[Food]  = []
var queues:           Array[Array] = [] # Array of Array[Food]
var queue_containers: Array[Node2D] = []
var circulating:      Array[Food]  = []
var player_foods_in_play: int = 0

var game_started: bool = false
var game_over:   bool = false
var level_won:   bool = false
var level_timer: float = 30.0
var is_timer_active: bool = false

## Round-robin index into active_config.entry_points (legacy fallback).
var entry_round_robin: int = 0

## Input debounce to prevent dual touch/mouse events on mobile
const TAP_COOLDOWN: float = 0.15
var last_tap_time: float = -999.0

## Dynamically created Line2D nodes for each EntryConfig (parallel arrays).
var entry_road_nodes: Array[Line2D] = []
var entry_dash_nodes: Array[Line2D] = []
var entry_progs:      Array[float]  = []

## Dynamically created Path2D nodes for each ExitConfig (parallel arrays).
var exit_path_nodes:      Array[Path2D]     = []
## Pre-computed progress offsets along loop_path for each exit trigger point.
var exit_progs:           Array[float]      = []
## Dynamically created Line2D and Polygon2D nodes for each ExitConfig (parallel arrays).
var exit_road_nodes:      Array[Line2D]     = []
var exit_dash_nodes:      Array[Line2D]     = []
var exit_indicator_nodes: Array[Polygon2D]  = []

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

	for q: Array in queues:
		for f: Food in q:
			if is_instance_valid(f): f.queue_free()
	queues.clear()
	queue.clear()

	# Clear any foods still attached to loop_path, exit_path or queue_containers
	if is_instance_valid(loop_path):
		for c in loop_path.get_children():
			if c is Food and is_instance_valid(c):
				c.queue_free()

	if is_instance_valid(exit_path):
		for c in exit_path.get_children():
			if c is Food and is_instance_valid(c):
				c.queue_free()

	for qc in queue_containers:
		if is_instance_valid(qc):
			for c in qc.get_children():
				if c is Food and is_instance_valid(c):
					c.queue_free()

	# Destroy dynamically created extra queue containers (index > 0; index 0 = reused scene node)
	for i: int in range(1, queue_containers.size()):
		var qc: Node2D = queue_containers[i]
		if is_instance_valid(qc):
			qc.queue_free()
	queue_containers.clear()

	# Destroy dynamically created extra entry roads and dashes (index > 0)
	for i: int in range(1, entry_road_nodes.size()):
		var er: Line2D = entry_road_nodes[i]
		if is_instance_valid(er):
			er.queue_free()
	entry_road_nodes.clear()

	for i: int in range(1, entry_dash_nodes.size()):
		var ed: Line2D = entry_dash_nodes[i]
		if is_instance_valid(ed):
			ed.queue_free()
	entry_dash_nodes.clear()

	entry_progs.clear()

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

	for i: int in range(1, exit_road_nodes.size()):
		var er: Line2D = exit_road_nodes[i]
		if is_instance_valid(er): er.queue_free()
	exit_road_nodes.clear()

	for i: int in range(1, exit_dash_nodes.size()):
		var ed: Line2D = exit_dash_nodes[i]
		if is_instance_valid(ed): ed.queue_free()
	exit_dash_nodes.clear()

	for i: int in range(1, exit_indicator_nodes.size()):
		var ind: Polygon2D = exit_indicator_nodes[i]
		if is_instance_valid(ind): ind.queue_free()
	exit_indicator_nodes.clear()

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
	loop_path.z_index = 5

	# ── 4. Setup entry points, entry roads, and queue containers ──────────────
	_setup_entries_and_queues()

	# ── 6. Setup exit paths ─────────────────────────────────────────────────────
	if active_config.has_exit and not active_config.exit_configs.is_empty():
		for i: int in range(active_config.exit_configs.size()):
			var ecfg: ExitConfig = active_config.exit_configs[i]
			var ep_node: Path2D
			var road_node: Line2D
			var dash_node: Line2D
			var ind_node: Polygon2D

			if i == 0:
				ep_node = exit_path
				ep_node.show()
				road_node = exit_road
				dash_node = exit_dashes
				ind_node = exit_indicator
			else:
				# 1. Road Line2D added first (rendered at base)
				road_node = Line2D.new()
				road_node.width = exit_road.width
				road_node.default_color = exit_road.default_color
				road_node.joint_mode = exit_road.joint_mode
				route.add_child(road_node)

				# 2. Dashes Line2D added second
				dash_node = Line2D.new()
				dash_node.width = exit_dashes.width
				dash_node.default_color = exit_dashes.default_color
				dash_node.joint_mode = exit_dashes.joint_mode
				route.add_child(dash_node)

				# 3. Indicator Polygon2D added third
				ind_node = Polygon2D.new()
				ind_node.polygon = exit_indicator.polygon
				route.add_child(ind_node)

				# 4. Exit Path2D added last (so fruits are rendered above roads)
				ep_node = Path2D.new()
				route.add_child(ep_node)

			road_node.z_index = 0
			dash_node.z_index = 1
			ind_node.z_index = 2
			ep_node.z_index = 5

			var exit_curve := Curve2D.new()
			for p: Vector2 in ecfg.exit_points:
				exit_curve.add_point(p)
			# Extend exit path straight off-screen so exiting food can travel past the viewport boundary
			if ecfg.exit_points.size() >= 2:
				var last_pt: Vector2 = ecfg.exit_points[-1]
				var prev_pt: Vector2 = ecfg.exit_points[-2]
				var exit_dir: Vector2 = (last_pt - prev_pt).normalized()
				exit_curve.add_point(last_pt + exit_dir * 3000.0)
			ep_node.curve = exit_curve

			exit_path_nodes.append(ep_node)
			exit_road_nodes.append(road_node)
			exit_dash_nodes.append(dash_node)
			exit_indicator_nodes.append(ind_node)
			exit_progs.append(active_config.get_exit_progress(loop_path.curve, i))

			# Position, orient, and color each exit indicator based on target fruit type
			if not ecfg.exit_points.is_empty():
				ind_node.position = ecfg.exit_points[0]
				if ecfg.exit_points.size() > 1:
					var dir: Vector2 = (ecfg.exit_points[1] - ecfg.exit_points[0]).normalized()
					ind_node.rotation = dir.angle() + PI / 2.0
				ind_node.color = FoodTextures.get_fruit_color(ecfg.target_fruit_type)
				ind_node.show()

		# Auto-generate Exit Road visual for all exits
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


# ─── Entry points & Queues setup ─────────────────────────────────────────────

func _setup_entries_and_queues() -> void:
	entry_progs.clear()
	var e_configs := active_config.get_entry_configs()
	var count: int = e_configs.size()

	for i: int in range(count):
		var ec: EntryConfig = e_configs[i]
		entry_progs.append(active_config.get_entry_progress(loop_path.curve, i))

		# Queue Container Node
		var qc_node: Node2D
		if i == 0:
			qc_node = queue_container
		else:
			qc_node = Node2D.new()
			qc_node.name = "Queue_%d" % i
			level_root.add_child(qc_node)

		qc_node.position = ec.entry_point * active_config.route_scale
		qc_node.rotation = 0.0
		qc_node.z_index = 5
		queue_containers.append(qc_node)

		# Entry Road Visuals (Line2D)
		var road_node: Line2D
		var dash_node: Line2D
		if i == 0:
			road_node = entry_road
			dash_node = entry_dashes
		else:
			road_node = Line2D.new()
			road_node.width = entry_road.width
			road_node.default_color = entry_road.default_color
			road_node.joint_mode = entry_road.joint_mode
			route.add_child(road_node)

			dash_node = Line2D.new()
			dash_node.width = entry_dashes.width
			dash_node.default_color = entry_dashes.default_color
			dash_node.joint_mode = entry_dashes.joint_mode
			route.add_child(dash_node)

		road_node.z_index = 0
		dash_node.z_index = 0

		entry_road_nodes.append(road_node)
		entry_dash_nodes.append(dash_node)

		_build_single_entry_road(road_node, dash_node, ec)


func _build_single_entry_road(road: Line2D, dashes: Line2D, ec: EntryConfig) -> void:
	road.clear_points()
	dashes.clear_points()
	var entry_local: Vector2 = ec.entry_point
	var step_dir: Vector2 = ec.queue_step.normalized()
	if step_dir.length_squared() < 0.01:
		step_dir = Vector2.DOWN
	var far_local: Vector2 = entry_local + step_dir * 3000.0

	road.add_point(entry_local)
	road.add_point(far_local)
	_add_dashes(dashes, entry_local, far_local)


## Rebuilds all entry roads according to current active_config entry configs.
func _rebuild_entry_road() -> void:
	if not active_config:
		return
	var e_configs := active_config.get_entry_configs()
	for i in range(mini(e_configs.size(), entry_road_nodes.size())):
		_build_single_entry_road(entry_road_nodes[i], entry_dash_nodes[i], e_configs[i])


func _clear_exit_road() -> void:
	for r in exit_road_nodes:
		if is_instance_valid(r): r.clear_points()
	for d in exit_dash_nodes:
		if is_instance_valid(d): d.clear_points()
	for ind in exit_indicator_nodes:
		if is_instance_valid(ind): ind.hide()
	exit_road.clear_points()
	exit_dashes.clear_points()
	exit_indicator.hide()


## Exit road extends from exit_local in the direction of the exit path for all exits.
func _rebuild_exit_road() -> void:
	_clear_exit_road()
	if active_config.exit_configs.is_empty():
		return
	for i: int in range(mini(active_config.exit_configs.size(), exit_road_nodes.size())):
		var ecfg: ExitConfig = active_config.exit_configs[i]
		if ecfg.exit_points.size() < 2:
			continue
		var road_node: Line2D = exit_road_nodes[i]
		var dash_node: Line2D = exit_dash_nodes[i]
		var exit_local: Vector2 = ecfg.exit_points[0]
		var dir: Vector2 = (ecfg.exit_points[1] - exit_local).normalized()
		var far_local: Vector2 = exit_local + dir * 3000.0

		road_node.add_point(exit_local)
		road_node.add_point(far_local)
		_add_dashes(dash_node, exit_local, far_local)
		if i < exit_indicator_nodes.size() and is_instance_valid(exit_indicator_nodes[i]):
			exit_indicator_nodes[i].show()


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
		var f_sz: float = active_config.get_fruit_size(indices[i])
		f.setup_fruit(tex, false, active_config.speed, indices[i], f_sz)
		f.start_circulating(i * gap)
		circulating.append(f)


func spawn_queue() -> void:
	queues.clear()
	var e_configs := active_config.get_entry_configs()
	for qi: int in range(e_configs.size()):
		var ec: EntryConfig = e_configs[qi]
		if qi >= queue_containers.size():
			continue
		var qc_node: Node2D = queue_containers[qi]
		var q_list: Array[Food] = []

		var count: int = ec.queue_count
		var indices := ec.queue_fruit_indices
		for slot: int in range(count):
			var f: Food = food_scene.instantiate() as Food
			qc_node.add_child(f)
			var f_idx: int = 0
			var tex: AtlasTexture
			if ec.queue_random_fruit:
				f_idx = randi() % FoodTextures.get_total_fruit_types()
				tex = FoodTextures.get_fruit_texture(f_idx)
			elif indices.size() > 0:
				f_idx = indices[slot % indices.size()]
				tex = FoodTextures.get_fruit_texture(f_idx)
			else:
				f_idx = 0
				tex = FoodTextures.get_fruit_texture(0)
			var f_sz: float = active_config.get_fruit_size(f_idx)
			f.setup_fruit(tex, true, active_config.speed, f_idx, f_sz)
			f.position = ec.queue_step * float(slot)
			q_list.append(f)
		queues.append(q_list)

	queue = queues[0] if not queues.is_empty() else []


# ─── Input ────────────────────────────────────────────────────────────────────

## Identifies which Entry / Queue was clicked by checking distance from tap_pos
## to each Entry Point, its active queue foods, and its entry road.
## Returns -1 if tap is outside all valid interaction areas.
func _find_clicked_queue(tap_pos: Vector2) -> int:
	var e_configs := active_config.get_entry_configs()
	var best_idx: int = -1
	var min_distance: float = INF

	# Scale touch radius with screen size
	var hit_threshold: float = 65.0 * maxf(level_root.scale.x, 0.7)

	for i: int in range(queues.size()):
		if i >= e_configs.size() or i >= queue_containers.size():
			continue

		# If this queue is completely empty, it does not respond to clicks
		if queues[i].is_empty():
			continue

		var ec: EntryConfig = e_configs[i]

		# 1. Distance to entry point on track
		var ep_global: Vector2 = route.to_global(ec.entry_point)
		var queue_dist: float = tap_pos.distance_to(ep_global)

		# 2. Distance to each active food in this queue
		for f: Food in queues[i]:
			if is_instance_valid(f):
				var f_dist: float = tap_pos.distance_to(f.global_position)
				if f_dist < queue_dist:
					queue_dist = f_dist

		# 3. Distance to the entry road line segment
		var step_dir := ec.queue_step
		if step_dir.length_squared() < 0.01:
			step_dir = Vector2(0, 44)
		var tail_local: Vector2 = ec.entry_point + step_dir * float(maxi(1, ec.queue_count))
		var tail_global: Vector2 = route.to_global(tail_local)
		var closest_pt: Vector2 = Geometry2D.get_closest_point_to_segment(tap_pos, ep_global, tail_global)
		var dist_to_segment: float = tap_pos.distance_to(closest_pt)
		if dist_to_segment < queue_dist:
			queue_dist = dist_to_segment

		if queue_dist < hit_threshold and queue_dist < min_distance:
			min_distance = queue_dist
			best_idx = i

	return best_idx


func _unhandled_input(event: InputEvent) -> void:
	if not game_started or game_over or level_won:
		return

	var is_valid_tap: bool = false
	var tap_pos: Vector2 = Vector2.ZERO
	if event is InputEventScreenTouch:
		var touch_ev := event as InputEventScreenTouch
		if touch_ev.pressed:
			is_valid_tap = true
			tap_pos = touch_ev.position
	elif event is InputEventMouseButton:
		var mouse_ev := event as InputEventMouseButton
		if mouse_ev.pressed and mouse_ev.button_index == MOUSE_BUTTON_LEFT:
			is_valid_tap = true
			tap_pos = mouse_ev.position

	if is_valid_tap:
		var current_time: float = Time.get_ticks_msec() / 1000.0
		if current_time - last_tap_time < TAP_COOLDOWN:
			return

		var target_queue_idx: int = _find_clicked_queue(tap_pos)
		if target_queue_idx < 0:
			# Clicked outside of any entry path, queue, or entry point -> ignore tap
			return

		last_tap_time = current_time
		get_viewport().set_input_as_handled()
		enter_food_from_queue(target_queue_idx)


func enter_food_from_queue(queue_idx: int) -> void:
	if queue_idx < 0 or queue_idx >= queues.size():
		return
	if queues[queue_idx].is_empty() or game_over or level_won:
		return

	var colliding_food: Food = get_colliding_food_at_entry(queue_idx)
	var entry_prog: float = entry_progs[queue_idx] if queue_idx < entry_progs.size() else 0.0

	var f: Food = queues[queue_idx].pop_front() as Food
	queue = queues[0] if not queues.is_empty() else []
	f.entry_index = queue_idx
	f.reparent(loop_path, false)
	f.start_circulating(entry_prog)
	circulating.append(f)
	player_foods_in_play += 1

	shift_queue(queue_idx)
	update_counter()

	# If there was a fruit at this entry point, play collision animation then game over
	if colliding_food != null:
		trigger_collision_game_over(f, colliding_food)
		return

	# No-exit levels win when all queues are fully sent
	if not active_config.has_exit and are_all_queues_empty():
		trigger_win()


func enter_next_food() -> void:
	for i in range(queues.size()):
		if not queues[i].is_empty():
			enter_food_from_queue(i)
			return


func get_colliding_food_at_entry(entry_idx: int = 0) -> Food:
	var curve_len: float  = loop_path.curve.get_baked_length()
	var entry_prog: float = entry_progs[entry_idx] if entry_idx < entry_progs.size() else active_config.get_entry_progress(loop_path.curve, entry_idx)

	# Determine the entering fruit's target size
	var entering_size: float = 42.0
	if entry_idx < queues.size() and not queues[entry_idx].is_empty():
		var first_in_q: Food = queues[entry_idx][0]
		if is_instance_valid(first_in_q):
			entering_size = first_in_q.target_size

	for f: Food in circulating:
		if not is_instance_valid(f) or f.state != Food.State.CIRCULATING:
			continue

		var circ_size: float = f.target_size
		# Dynamic touch distance = (entering_size + circ_size) / 2
		var touch_dist: float = (entering_size + circ_size) * 0.5
		# Respect any custom min_gap scaling (default min_gap = 44.0 means ~1:1 with touch_dist)
		var gap_ratio: float = active_config.min_gap / 44.0 if active_config.min_gap > 0.0 else 1.0
		var required_gap: float = maxf(touch_dist, touch_dist * gap_ratio)

		# Protect newly entered queue fruits while they are still in the entry area
		if f.is_player and f.total_travel < required_gap:
			continue
		var diff: float = absf(fposmod(f.progress - entry_prog, curve_len))
		diff = minf(diff, curve_len - diff)
		if diff < required_gap:
			return f
	return null


func check_collision_at_entry(entry_idx: int = 0) -> bool:
	return get_colliding_food_at_entry(entry_idx) != null


func shift_queue(queue_idx: int = 0) -> void:
	if queue_idx < 0 or queue_idx >= queues.size():
		return
	var e_configs := active_config.get_entry_configs()
	var step: Vector2 = e_configs[queue_idx].queue_step if queue_idx < e_configs.size() else active_config.queue_step
	var q: Array = queues[queue_idx]
	for i: int in range(q.size()):
		var target_pos: Vector2 = step * float(i)
		var tw: Tween = create_tween()
		tw.tween_property(q[i], "position", target_pos, 0.12) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func are_all_queues_empty() -> bool:
	if queues.is_empty():
		return queue.is_empty()
	for q: Array in queues:
		if not q.is_empty():
			return false
	return true


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
			if f.state == Food.State.CIRCULATING and f.total_travel >= 12.0:
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

	# 1. Target fruit type matching:
	if ecfg.target_fruit_type != -1:
		# Both circulating and player foods matching this fruit type take this exit
		return f.fruit_index == ecfg.target_fruit_type

	# 2. Legacy / Any Fruit exit (target_fruit_type == -1):
	# Only player foods use generic exit, preserving balance of existing levels
	if not f.is_player:
		return false

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


func _on_food_exited(food: Food) -> void:
	if is_instance_valid(food) and food.is_player:
		player_foods_in_play = maxi(0, player_foods_in_play - 1)
	update_counter()
	if active_config.has_exit and are_all_queues_empty() and player_foods_in_play == 0:
		trigger_win()


# ─── UI helpers ──────────────────────────────────────────────────────────────

func update_counter() -> void:
	var rem: int = 0
	if not queues.is_empty():
		for q: Array in queues:
			rem += q.size()
	else:
		rem = queue.size()
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
