# level_builder_dock.gd
# Full Level Builder editor UI — built entirely in GDScript.
#
# Layout (matches the reference screenshot):
#   ┌ TOP BAR: title · Timer · Play · Save ──────────────────────────────────┐
#   │ LEFT panel   │ CENTER: sprite bar + mode tabs + canvas │ RIGHT panel   │
#   │  level list  │  + mode-settings strip below canvas     │ fruit picker  │
#   │  + New level │                                         │ queue / init  │
#   └──────────────┴─────────────────────────────────────────┴───────────────┘
@tool
extends Control

# ─── Internal constants ───────────────────────────────────────────────────────
const _LEVELS_DIR    := "res://Levels"
const _SPRITES_DIR   := "res://Assets/Sprites"
const _PREVIEW_TRES  := "res://Levels/_preview.tres"
const _PREVIEW_FLAG  := "res://._preview"
const _GAMEPLAY_SCENE := "res://Assets/Scenes/Gameplay.tscn"

# Fruit spritesheet data (mirrors FoodTextures.gd)
const _FRUIT_SHEET := "res://Assets/Sprites/sprite-vegetable-fruit-animation-sprite-removebg-preview.png"
const _FRUIT_NAMES := ["Apple", "Orange", "Plum", "Peach", "Pineapple",
                        "Pear", "Banana", "Grape", "Lemon", "Watermelon"]
const _FRUIT_REGIONS: Array = [
	Rect2(8,   0,   97,  112),
	Rect2(141, 11,  119, 104),
	Rect2(295, 7,   104, 104),
	Rect2(453, 3,   110, 111),
	Rect2(10,  120, 113, 167),
	Rect2(179, 139, 101, 145),
	Rect2(318, 155, 136, 109),
	Rect2(1,   293, 131, 149),
	Rect2(167, 333, 140, 82),
	Rect2(345, 309, 124, 127),
]

const _TILE_SHEET_PATH := "res://Assets/Sprites/tilesprite.png"
var _tile_sheet_tex: Texture2D = null

const TILE_BASE_SIZE: float = 99.0
const TILE_INFOS: Array[Dictionary] = [
	{"id": 0,  "name": "Cross (+)",  "rect": Rect2(15,  18,  99, 100), "offset": Vector2( 0.0,  0.0), "conns": [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]},
	{"id": 1,  "name": "T-Down",     "rect": Rect2(138, 30,  99, 88),  "offset": Vector2( 0.0,  5.5), "conns": [Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]},
	{"id": 2,  "name": "T-Left",     "rect": Rect2(260, 18,  88, 100), "offset": Vector2(-5.5,  0.0), "conns": [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT]},
	{"id": 3,  "name": "Turn BL",    "rect": Rect2(383, 30,  88, 88),  "offset": Vector2(-5.5,  5.5), "conns": [Vector2i.DOWN, Vector2i.LEFT]},
	{"id": 4,  "name": "T-Up",       "rect": Rect2(15,  141, 99, 88),  "offset": Vector2( 0.0, -5.5), "conns": [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT]},
	{"id": 5,  "name": "Straight H", "rect": Rect2(138, 153, 99, 76),  "offset": Vector2( 0.0,  0.0), "conns": [Vector2i.LEFT, Vector2i.RIGHT]},
	{"id": 6,  "name": "Turn TL",    "rect": Rect2(260, 141, 87, 88),  "offset": Vector2(-6.0, -5.5), "conns": [Vector2i.UP, Vector2i.LEFT]},
	{"id": 7,  "name": "Cap Right",  "rect": Rect2(383, 153, 88, 76),  "offset": Vector2(-5.5,  0.0), "conns": [Vector2i.LEFT]},
	{"id": 8,  "name": "T-Right",    "rect": Rect2(27,  264, 87, 100), "offset": Vector2( 6.0,  0.0), "conns": [Vector2i.UP, Vector2i.DOWN, Vector2i.RIGHT]},
	{"id": 9,  "name": "Turn BR",    "rect": Rect2(150, 276, 87, 88),  "offset": Vector2( 6.0,  5.5), "conns": [Vector2i.DOWN, Vector2i.RIGHT]},
	{"id": 10, "name": "Straight V", "rect": Rect2(273, 264, 74, 99),  "offset": Vector2( 0.0,  0.0), "conns": [Vector2i.UP, Vector2i.DOWN]},
	{"id": 11, "name": "Cap Top",    "rect": Rect2(395, 276, 76, 87),  "offset": Vector2( 0.0,  6.0), "conns": [Vector2i.DOWN]},
	{"id": 12, "name": "Turn TR",    "rect": Rect2(26,  386, 88, 89),  "offset": Vector2( 5.5, -5.0), "conns": [Vector2i.UP, Vector2i.RIGHT]},
	{"id": 13, "name": "Cap Left",   "rect": Rect2(150, 399, 87, 76),  "offset": Vector2( 6.0,  0.0), "conns": [Vector2i.RIGHT]},
	{"id": 14, "name": "Cap Bottom", "rect": Rect2(273, 386, 74, 88),  "offset": Vector2( 0.0, -5.5), "conns": [Vector2i.UP]},
]

enum EditMode { LOOP, TILES, ENTRY, EXIT }

# ─── State ────────────────────────────────────────────────────────────────────
var current_config: LevelConfig = null
var current_file_path: String   = ""
var is_dirty: bool              = false

var edit_mode: EditMode = EditMode.LOOP
var current_entry_idx: int = 0
var current_exit_idx: int = 0

# Canvas view
var canvas_zoom: float     = 0.5
var canvas_pan: Vector2    = Vector2.ZERO
var is_panning: bool       = false
var pan_start_mouse: Vector2
var pan_start_offset: Vector2

# Point editing
var selected_idx: int     = -1
var is_dragging: bool     = false
var drag_start_world: Vector2

# Fruit state
var fruit_target: String  = "queue"   # "queue" | "initial"
var _sheet_tex: Texture2D = null

# Device Frame / Mobile Viewport Guide
var show_device_frame: bool = true
var selected_device_idx: int = 0
const DEVICE_PRESETS: Array[Dictionary] = [
	{"name": "📱 720 × 1280 (HD 16:9 - Default)", "w": 720.0, "h": 1280.0},
	{"name": "📱 1080 × 1920 (FHD 16:9)", "w": 1080.0, "h": 1920.0},
	{"name": "📱 1080 × 2340 (Modern 19.5:9)", "w": 1080.0, "h": 2340.0},
	{"name": "📱 1080 × 2400 (Tall 20:9)", "w": 1080.0, "h": 2400.0},
	{"name": "📱 720 × 1600 (Tall Budget 20:9)", "w": 720.0, "h": 1600.0},
	{"name": "📟 768 × 1024 (Tablet 4:3)", "w": 768.0, "h": 1024.0},
	{"name": "📟 1200 × 1920 (Tablet 16:10)", "w": 1200.0, "h": 1920.0},
]
var device_frame_check: CheckBox
var device_res_select: OptionButton

# ─── UI references ────────────────────────────────────────────────────────────
var level_list_vbox: VBoxContainer
var level_btn_group: ButtonGroup
var canvas_ctrl: Control
var sprite_name_lbl: Label
var timer_spin: SpinBox
var loop_btn: Button
var entry_btn: Button
var exit_btn: Button
var fruit_grid: GridContainer
var queue_flow: HFlowContainer
var initial_flow: HFlowContainer
var randomize_check: CheckBox
var queue_count_spin: SpinBox
var has_exit_check: CheckBox
var speed_spin: SpinBox
var gap_spin: SpinBox
var entry_select: OptionButton
var entry_label_edit: LineEdit
var exit_select: OptionButton
var exit_label_edit: LineEdit
var rule_select: OptionButton
var exit_fruit_select: OptionButton
var route_pos_x: SpinBox
var route_pos_y: SpinBox
var route_scale_x: SpinBox
var route_scale_y: SpinBox
var loop_settings_box: VBoxContainer
var entry_settings_box: VBoxContainer
var exit_settings_box: VBoxContainer
var queue_target_btn: Button
var initial_target_btn: Button
var queue_pos_x: SpinBox
var queue_pos_y: SpinBox
var queue_step_x: SpinBox
var queue_step_y: SpinBox
var fruit_size_spins: Array[SpinBox] = []
var fruit_sizes_box: VBoxContainer
var fruit_sizes_toggle_btn: Button
var selected_is_queue: bool = false
var selected_queue_idx: int = -1
var file_dialog: EditorFileDialog
var confirm_dialog: ConfirmationDialog
var _pending_delete_path: String = ""

# Tile Mode variables
var tiles_btn: Button
var tile_settings_box: VBoxContainer
var use_tilemap_check: CheckBox
var tile_grid_spin: SpinBox
var tile_palette_btns: Array[Button] = []
var selected_tile_id: int = 5
var hover_grid_cell: Vector2i = Vector2i(9999, 9999)
var is_painting_tile: bool = false
var is_erasing_tile: bool = false


# ══════════════════════════════════════════════════════════════════════════════
# SECTION 1 — Setup
# ══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	set_clip_contents(true)
	custom_minimum_size = Vector2(0, 320)
	level_btn_group = ButtonGroup.new()
	_build_ui()
	_build_dialogs()
	_ensure_levels_dir()
	_refresh_level_list()
	_refresh_fruit_grid()
	_update_canvas()


# ══════════════════════════════════════════════════════════════════════════════
# SECTION 2 — UI Construction
# ══════════════════════════════════════════════════════════════════════════════

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 4)
	add_child(root)

	_build_top_bar(root)

	var hbox := HBoxContainer.new()
	hbox.set_v_size_flags(SIZE_EXPAND_FILL)
	hbox.add_theme_constant_override("separation", 0)
	root.add_child(hbox)

	_build_left_panel(hbox)
	_add_vsep(hbox)
	_build_center_panel(hbox)
	_add_vsep(hbox)
	_build_right_panel(hbox)


func _build_top_bar(parent: Control) -> void:
	var bar := PanelContainer.new()
	parent.add_child(bar)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	bar.add_child(hb)

	var title := Label.new()
	title.text = "🍎  Food Loop — Level Editor"
	title.set_h_size_flags(SIZE_EXPAND_FILL)
	hb.add_child(title)

	hb.add_child(_make_label("Timer:"))

	timer_spin = _make_spinbox(5.0, 600.0, 1.0, 30.0, 60.0)
	timer_spin.value_changed.connect(_on_timer_changed)
	hb.add_child(timer_spin)

	hb.add_child(_make_label("sec"))
	_add_vsep(hb)

	var play_btn := Button.new()
	play_btn.text = "▶  Play"
	play_btn.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
	play_btn.pressed.connect(_on_play)
	hb.add_child(play_btn)

	var save_btn := Button.new()
	save_btn.text = "💾  Save"
	save_btn.pressed.connect(_on_save)
	hb.add_child(save_btn)


func _build_left_panel(parent: Control) -> void:
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(155, 0)
	vb.add_theme_constant_override("separation", 4)
	parent.add_child(vb)

	var lbl := Label.new()
	lbl.text = "Levels"
	lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vb.add_child(lbl)

	var scroll := ScrollContainer.new()
	scroll.set_v_size_flags(SIZE_EXPAND_FILL)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)

	level_list_vbox = VBoxContainer.new()
	level_list_vbox.set_h_size_flags(SIZE_EXPAND_FILL)
	level_list_vbox.add_theme_constant_override("separation", 2)
	scroll.add_child(level_list_vbox)

	var new_btn := Button.new()
	new_btn.text = "+  New level"
	new_btn.pressed.connect(_on_new_level)
	vb.add_child(new_btn)

	# Create sample levels button (only shows when Levels/ is empty)
	var sample_btn := Button.new()
	sample_btn.name = "MigrateBtn"
	sample_btn.text = "Create sample levels"
	sample_btn.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	sample_btn.pressed.connect(_create_sample_levels)
	vb.add_child(sample_btn)


func _build_center_panel(parent: Control) -> void:
	var vb := VBoxContainer.new()
	vb.set_h_size_flags(SIZE_EXPAND_FILL)
	vb.set_v_size_flags(SIZE_EXPAND_FILL)
	vb.add_theme_constant_override("separation", 4)
	parent.add_child(vb)

	# ── Sprite bar ────────────────────────────────────────────────────────────
	var sprite_bar := HBoxContainer.new()
	vb.add_child(sprite_bar)

	var spr_btn := Button.new()
	spr_btn.text = "📷  Choose sprite"
	spr_btn.pressed.connect(_on_choose_sprite)
	sprite_bar.add_child(spr_btn)

	sprite_name_lbl = Label.new()
	sprite_name_lbl.text = "(none)"
	sprite_name_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	sprite_name_lbl.set_h_size_flags(SIZE_EXPAND_FILL)
	sprite_bar.add_child(sprite_name_lbl)

	# ── Mode tabs ─────────────────────────────────────────────────────────────
	var tab_bar := HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", 2)
	vb.add_child(tab_bar)

	loop_btn  = _make_tab_btn("Loop",  func(): _set_mode(EditMode.LOOP))
	tiles_btn = _make_tab_btn("🧩 Tiles", func(): _set_mode(EditMode.TILES))
	entry_btn = _make_tab_btn("Entry", func(): _set_mode(EditMode.ENTRY))
	exit_btn  = _make_tab_btn("Exit",  func(): _set_mode(EditMode.EXIT))
	tab_bar.add_child(loop_btn)
	tab_bar.add_child(tiles_btn)
	tab_bar.add_child(entry_btn)
	tab_bar.add_child(exit_btn)

	_add_vsep(tab_bar)

	device_frame_check = CheckBox.new()
	device_frame_check.text = "📱 Phone Frame"
	device_frame_check.button_pressed = show_device_frame
	device_frame_check.toggled.connect(func(v: bool):
		show_device_frame = v
		_update_canvas()
	)
	tab_bar.add_child(device_frame_check)

	device_res_select = OptionButton.new()
	device_res_select.custom_minimum_size = Vector2(175, 0)
	for i in range(DEVICE_PRESETS.size()):
		device_res_select.add_item(DEVICE_PRESETS[i]["name"])
	device_res_select.selected = selected_device_idx
	device_res_select.item_selected.connect(func(idx: int):
		selected_device_idx = idx
		_fit_canvas()
		_update_canvas()
	)
	tab_bar.add_child(device_res_select)

	var fit_frame_btn := Button.new()
	fit_frame_btn.text = "🔍 Fit"
	fit_frame_btn.tooltip_text = "Fit mobile screen frame inside canvas"
	fit_frame_btn.pressed.connect(func():
		_fit_canvas()
		_update_canvas()
	)
	tab_bar.add_child(fit_frame_btn)

	# ── Canvas ────────────────────────────────────────────────────────────────
	var canvas_script := load("res://addons/level_builder/canvas_drawer.gd")
	canvas_ctrl = canvas_script.new() as Control
	canvas_ctrl.dock = self
	canvas_ctrl.set_h_size_flags(SIZE_EXPAND_FILL)
	canvas_ctrl.set_v_size_flags(SIZE_EXPAND_FILL)
	canvas_ctrl.custom_minimum_size = Vector2(200, 200)
	canvas_ctrl.focus_mode = Control.FOCUS_CLICK
	canvas_ctrl.resized.connect(_on_canvas_resized)
	vb.add_child(canvas_ctrl)

	# ── Mode-specific settings strip ──────────────────────────────────────────
	_build_loop_settings(vb)
	_build_tile_settings(vb)
	_build_entry_settings(vb)
	_build_exit_settings(vb)
	_update_mode_settings_visibility()


func _build_loop_settings(parent: Control) -> void:
	loop_settings_box = VBoxContainer.new()
	loop_settings_box.add_theme_constant_override("separation", 4)
	parent.add_child(loop_settings_box)

	# Speed + Gap row
	var row1 := HBoxContainer.new()
	loop_settings_box.add_child(row1)
	row1.add_child(_make_label("Speed:"))
	speed_spin = _make_spinbox(10.0, 500.0, 1.0, 70.0, 70.0)
	speed_spin.value_changed.connect(func(v): if current_config: current_config.speed = v; _mark_dirty())
	row1.add_child(speed_spin)
	row1.add_child(_make_label("  Min Gap:"))
	gap_spin = _make_spinbox(5.0, 200.0, 1.0, 44.0, 44.0)
	gap_spin.value_changed.connect(func(v): if current_config: current_config.min_gap = v; _mark_dirty())
	row1.add_child(gap_spin)

	# Route transform row
	var row2 := HBoxContainer.new()
	loop_settings_box.add_child(row2)
	row2.add_child(_make_label("Pos:"))
	route_pos_x = _make_spinbox(-3000.0, 3000.0, 1.0, 360.0, 50.0)
	route_pos_x.value_changed.connect(func(v): if current_config: current_config.route_position.x = v; _mark_dirty(); _update_canvas())
	row2.add_child(route_pos_x)
	route_pos_y = _make_spinbox(-3000.0, 3000.0, 1.0, 640.0, 50.0)
	route_pos_y.value_changed.connect(func(v): if current_config: current_config.route_position.y = v; _mark_dirty(); _update_canvas())
	row2.add_child(route_pos_y)

	row2.add_child(_make_label("  Scale:"))
	route_scale_x = _make_spinbox(0.05, 10.0, 0.01, 1.0, 45.0)
	route_scale_x.value_changed.connect(func(v): if current_config: current_config.route_scale.x = v; _mark_dirty())
	row2.add_child(route_scale_x)
	route_scale_y = _make_spinbox(0.05, 10.0, 0.01, 1.0, 45.0)
	route_scale_y.value_changed.connect(func(v): if current_config: current_config.route_scale.y = v; _mark_dirty())
	row2.add_child(route_scale_y)

	# Row 3: Circle Generator (Smooth Canvas Road)
	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 6)
	loop_settings_box.add_child(row3)
	row3.add_child(_make_label("⭕ Circle: Radius"))
	var circle_radius_spin := _make_spinbox(20.0, 1000.0, 5.0, 140.0, 50.0)
	circle_radius_spin.tooltip_text = "Radius of the circular road loop"
	row3.add_child(circle_radius_spin)

	row3.add_child(_make_label(" Points:"))
	var circle_count_spin := _make_spinbox(12.0, 64.0, 2.0, 32.0, 45.0)
	circle_count_spin.tooltip_text = "Number of curve points in the circle (32 = very smooth)"
	row3.add_child(circle_count_spin)

	var make_circle_btn := Button.new()
	make_circle_btn.text = "✨ Generate Circle"
	make_circle_btn.tooltip_text = "Generate a smooth circular road loop with matching colors"
	make_circle_btn.add_theme_color_override("font_color", Color(0.3, 1.0, 0.7))
	make_circle_btn.pressed.connect(func() -> void:
		_generate_circle_loop(circle_radius_spin.value, int(circle_count_spin.value))
	)
	row3.add_child(make_circle_btn)

	_add_vsep(row3)

	var make_tile_loop_btn := Button.new()
	make_tile_loop_btn.text = "⚡ Auto-Generate from Tiles"
	make_tile_loop_btn.tooltip_text = "Generate loop Curve2D points from placed road tiles"
	make_tile_loop_btn.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
	make_tile_loop_btn.pressed.connect(_auto_generate_loop_from_tiles)
	row3.add_child(make_tile_loop_btn)

	# Row 4: Straight Oval / Stadium Track Generator (Smooth Canvas Road)
	var row4 := HBoxContainer.new()
	row4.add_theme_constant_override("separation", 6)
	loop_settings_box.add_child(row4)
	row4.add_child(_make_label("🏟️ Straight Oval: Straight"))
	var oval_straight_spin := _make_spinbox(0.0, 1500.0, 10.0, 240.0, 55.0)
	oval_straight_spin.tooltip_text = "Length of the straight road sections (0 = circle, >0 adds straight sections)"
	row4.add_child(oval_straight_spin)

	row4.add_child(_make_label(" Radius:"))
	var oval_radius_spin := _make_spinbox(20.0, 800.0, 5.0, 120.0, 50.0)
	oval_radius_spin.tooltip_text = "Radius of the curved rounded end caps"
	row4.add_child(oval_radius_spin)

	row4.add_child(_make_label(" Orient:"))
	var oval_orient_btn := OptionButton.new()
	oval_orient_btn.add_item("↔ Horizontal")
	oval_orient_btn.add_item("↕ Vertical")
	oval_orient_btn.selected = 0
	row4.add_child(oval_orient_btn)

	row4.add_child(_make_label(" Cap Pts:"))
	var oval_cap_spin := _make_spinbox(6.0, 32.0, 2.0, 16.0, 42.0)
	oval_cap_spin.tooltip_text = "Points per curved end cap (16 = very smooth)"
	row4.add_child(oval_cap_spin)

	var make_oval_btn := Button.new()
	make_oval_btn.text = "✨ Generate Straight Oval"
	make_oval_btn.tooltip_text = "Generate a smooth stadium track with straight sections and rounded ends"
	make_oval_btn.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0))
	make_oval_btn.pressed.connect(func() -> void:
		var is_horiz: bool = (oval_orient_btn.selected == 0)
		_generate_straight_oval_loop(oval_straight_spin.value, oval_radius_spin.value, is_horiz, int(oval_cap_spin.value))
	)
	row4.add_child(make_oval_btn)

	var make_ellipse_btn := Button.new()
	make_ellipse_btn.text = "🥚 Ellipse"
	make_ellipse_btn.tooltip_text = "Generate a smooth continuous ellipse"
	make_ellipse_btn.pressed.connect(func() -> void:
		var is_horiz: bool = (oval_orient_btn.selected == 0)
		var rx: float = (oval_straight_spin.value * 0.5 + oval_radius_spin.value) if is_horiz else oval_radius_spin.value
		var ry: float = oval_radius_spin.value if is_horiz else (oval_straight_spin.value * 0.5 + oval_radius_spin.value)
		_generate_ellipse_loop(rx, ry, int(oval_cap_spin.value) * 2)
	)
	row4.add_child(make_ellipse_btn)




func _generate_circle_loop(radius: float = 140.0, count: int = 32) -> void:
	if not current_config:
		return

	# Disable tilemap mode - smooth vector loop on canvas
	current_config.use_tilemap = false
	current_config.placed_tiles.clear()
	current_config.track_texture = null
	if is_instance_valid(use_tilemap_check):
		use_tilemap_check.button_pressed = false

	var pts := PackedVector2Array()
	var r: float = maxf(10.0, radius)
	var n: int = maxi(12, count)
	for i in range(n):
		var angle: float = (float(i) / float(n)) * TAU
		var x: float = -r * sin(angle)
		var y: float = r * cos(angle)
		pts.append(Vector2(snappedf(x, 0.01), snappedf(y, 0.01)))
	pts.append(pts[0])
	current_config.loop_points = pts

	# Auto-connect Entry Point at the bottom of the circle (y = +r)
	_ensure_entry_configs()
	if not current_config.entry_configs.is_empty():
		var ep_pos := Vector2(0.0, r)
		current_config.entry_configs[0].entry_point = ep_pos
		current_config.entry_configs[0].queue_step = Vector2(0.0, 44.0)
		current_config.entry_configs[0].queue_base_position = ep_pos + Vector2(0.0, 44.0)
		_sync_legacy_queue_fields()

	# Auto-connect Exit Point at the top of the circle (y = -r)
	var exit_pos := Vector2(0.0, -r)
	current_config.has_exit = true
	if current_config.exit_configs.is_empty():
		var new_exit := ExitConfig.new()
		new_exit.label = "Exit 1"
		new_exit.exit_points = PackedVector2Array([
			exit_pos,
			exit_pos + Vector2(0.0, -180.0),
			exit_pos + Vector2(0.0, -450.0)
		])
		current_config.exit_configs.append(new_exit)
	else:
		current_config.exit_configs[0].exit_points = PackedVector2Array([
			exit_pos,
			exit_pos + Vector2(0.0, -180.0),
			exit_pos + Vector2(0.0, -450.0)
		])

	_mark_dirty()
	_fit_canvas()
	_update_canvas()


func _generate_straight_oval_loop(straight_length: float = 240.0, radius: float = 120.0, is_horizontal: bool = true, arc_points: int = 16) -> void:
	if not current_config:
		return

	# Disable tilemap mode - smooth vector loop on canvas
	current_config.use_tilemap = false
	current_config.placed_tiles.clear()
	current_config.track_texture = null
	if is_instance_valid(use_tilemap_check):
		use_tilemap_check.button_pressed = false

	var pts := PackedVector2Array()
	var half_s: float = maxf(0.0, straight_length * 0.5)
	var r: float = maxf(10.0, radius)
	var n_arc: int = maxi(6, arc_points)

	if is_horizontal:
		# Horizontal Stadium (straight top & bottom, curved left & right caps)
		# 1. Bottom straight segment: from (+half_s, +r) to (-half_s, +r)
		if half_s > 0.0:
			pts.append(Vector2(snappedf(half_s, 0.01), snappedf(r, 0.01)))
			pts.append(Vector2(0.0, snappedf(r, 0.01)))
			pts.append(Vector2(snappedf(-half_s, 0.01), snappedf(r, 0.01)))
		else:
			pts.append(Vector2(0.0, snappedf(r, 0.01)))

		# 2. Left curved cap (semicircle centered at (-half_s, 0))
		for i in range(1, n_arc):
			var a: float = (float(i) / float(n_arc)) * PI
			var px: float = -half_s - r * sin(a)
			var py: float = r * cos(a)
			pts.append(Vector2(snappedf(px, 0.01), snappedf(py, 0.01)))

		# 3. Top straight segment: from (-half_s, -r) to (+half_s, -r)
		if half_s > 0.0:
			pts.append(Vector2(snappedf(-half_s, 0.01), snappedf(-r, 0.01)))
			pts.append(Vector2(0.0, snappedf(-r, 0.01)))
			pts.append(Vector2(snappedf(half_s, 0.01), snappedf(-r, 0.01)))
		else:
			pts.append(Vector2(0.0, snappedf(-r, 0.01)))

		# 4. Right curved cap (semicircle centered at (+half_s, 0))
		for i in range(1, n_arc):
			var a: float = PI + (float(i) / float(n_arc)) * PI
			var px: float = half_s - r * sin(a)
			var py: float = r * cos(a)
			pts.append(Vector2(snappedf(px, 0.01), snappedf(py, 0.01)))
	else:
		# Vertical Stadium (straight left & right, curved top & bottom caps)
		# 1. Right straight segment: from (+r, -half_s) to (+r, +half_s)
		if half_s > 0.0:
			pts.append(Vector2(snappedf(r, 0.01), snappedf(-half_s, 0.01)))
			pts.append(Vector2(snappedf(r, 0.01), 0.0))
			pts.append(Vector2(snappedf(r, 0.01), snappedf(half_s, 0.01)))
		else:
			pts.append(Vector2(snappedf(r, 0.01), 0.0))

		# 2. Bottom curved cap (semicircle centered at (0, +half_s))
		for i in range(1, n_arc):
			var a: float = (float(i) / float(n_arc)) * PI
			var px: float = r * cos(a)
			var py: float = half_s + r * sin(a)
			pts.append(Vector2(snappedf(px, 0.01), snappedf(py, 0.01)))

		# 3. Left straight segment: from (-r, +half_s) to (-r, -half_s)
		if half_s > 0.0:
			pts.append(Vector2(snappedf(-r, 0.01), snappedf(half_s, 0.01)))
			pts.append(Vector2(snappedf(-r, 0.01), 0.0))
			pts.append(Vector2(snappedf(-r, 0.01), snappedf(-half_s, 0.01)))
		else:
			pts.append(Vector2(snappedf(-r, 0.01), 0.0))

		# 4. Top curved cap (semicircle centered at (0, -half_s))
		for i in range(1, n_arc):
			var a: float = PI + (float(i) / float(n_arc)) * PI
			var px: float = r * cos(a)
			var py: float = -half_s + r * sin(a)
			pts.append(Vector2(snappedf(px, 0.01), snappedf(py, 0.01)))

	# Close loop
	pts.append(pts[0])
	current_config.loop_points = pts

	# Auto-connect Entry Point at the bottom
	_ensure_entry_configs()
	if not current_config.entry_configs.is_empty():
		var ep_pos: Vector2 = Vector2(0.0, r) if is_horizontal else Vector2(0.0, half_s + r)
		current_config.entry_configs[0].entry_point = ep_pos
		current_config.entry_configs[0].queue_step = Vector2(0.0, 44.0)
		current_config.entry_configs[0].queue_base_position = ep_pos + Vector2(0.0, 44.0)
		_sync_legacy_queue_fields()

	# Auto-connect Exit Point at the top
	var exit_pos: Vector2 = Vector2(0.0, -r) if is_horizontal else Vector2(0.0, -half_s - r)
	current_config.has_exit = true
	if current_config.exit_configs.is_empty():
		var new_exit := ExitConfig.new()
		new_exit.label = "Exit 1"
		new_exit.exit_points = PackedVector2Array([
			exit_pos,
			exit_pos + Vector2(0.0, -180.0),
			exit_pos + Vector2(0.0, -450.0)
		])
		current_config.exit_configs.append(new_exit)
	else:
		current_config.exit_configs[0].exit_points = PackedVector2Array([
			exit_pos,
			exit_pos + Vector2(0.0, -180.0),
			exit_pos + Vector2(0.0, -450.0)
		])

	_mark_dirty()
	_fit_canvas()
	_update_canvas()


func _generate_ellipse_loop(radius_x: float = 180.0, radius_y: float = 120.0, count: int = 32) -> void:
	if not current_config:
		return

	# Disable tilemap mode - smooth vector loop on canvas
	current_config.use_tilemap = false
	current_config.placed_tiles.clear()
	current_config.track_texture = null
	if is_instance_valid(use_tilemap_check):
		use_tilemap_check.button_pressed = false

	var pts := PackedVector2Array()
	var rx: float = maxf(10.0, radius_x)
	var ry: float = maxf(10.0, radius_y)
	var n: int = maxi(12, count)
	for i in range(n):
		var a: float = (float(i) / float(n)) * TAU
		var px: float = -rx * sin(a)
		var py: float = ry * cos(a)
		pts.append(Vector2(snappedf(px, 0.01), snappedf(py, 0.01)))
	pts.append(pts[0])
	current_config.loop_points = pts

	# Auto-connect Entry Point at the bottom (y = +ry)
	_ensure_entry_configs()
	if not current_config.entry_configs.is_empty():
		var ep_pos := Vector2(0.0, ry)
		current_config.entry_configs[0].entry_point = ep_pos
		current_config.entry_configs[0].queue_step = Vector2(0.0, 44.0)
		current_config.entry_configs[0].queue_base_position = ep_pos + Vector2(0.0, 44.0)
		_sync_legacy_queue_fields()

	# Auto-connect Exit Point at the top (y = -ry)
	var exit_pos := Vector2(0.0, -ry)
	current_config.has_exit = true
	if current_config.exit_configs.is_empty():
		var new_exit := ExitConfig.new()
		new_exit.label = "Exit 1"
		new_exit.exit_points = PackedVector2Array([
			exit_pos,
			exit_pos + Vector2(0.0, -180.0),
			exit_pos + Vector2(0.0, -450.0)
		])
		current_config.exit_configs.append(new_exit)
	else:
		current_config.exit_configs[0].exit_points = PackedVector2Array([
			exit_pos,
			exit_pos + Vector2(0.0, -180.0),
			exit_pos + Vector2(0.0, -450.0)
		])

	_mark_dirty()
	_fit_canvas()
	_update_canvas()


## Generates a closed circuit using modular tiles (tilesprite.png), auto-traces the loop curve,
## and connects entry and exit roads seamlessly underneath the track.
func _generate_tile_track(sh: int = 5, sv: int = 3) -> void:
	if not current_config:
		return

	# Enable tilemap mode with modular road tiles
	current_config.use_tilemap = true
	current_config.track_texture = null
	if current_config.tile_grid_size <= 10.0:
		current_config.tile_grid_size = 96.0
	var g_size: float = current_config.tile_grid_size

	if is_instance_valid(use_tilemap_check):
		use_tilemap_check.button_pressed = true

	current_config.placed_tiles.clear()

	var w_tiles: int = maxi(2, sh + 2)
	var h_tiles: int = maxi(2, sv + 2)

	var half_w: int = int(floor(float(w_tiles) * 0.5))
	var x_start: int = -half_w
	var x_end: int = x_start + w_tiles - 1

	var half_h: int = int(floor(float(h_tiles) * 0.5))
	var y_start: int = -half_h
	var y_end: int = y_start + h_tiles - 1

	# 1. 4 Corners (IDs from TILE_INFOS):
	# Top-Left: Turn BR (id 9, connects DOWN and RIGHT)
	current_config.placed_tiles[Vector2i(x_start, y_start)] = 9
	# Top-Right: Turn BL (id 3, connects DOWN and LEFT)
	current_config.placed_tiles[Vector2i(x_end, y_start)] = 3
	# Bottom-Right: Turn TL (id 6, connects UP and LEFT)
	current_config.placed_tiles[Vector2i(x_end, y_end)] = 6
	# Bottom-Left: Turn TR (id 12, connects UP and RIGHT)
	current_config.placed_tiles[Vector2i(x_start, y_end)] = 12

	# 2. Horizontal straight segments (id 5, Straight H)
	for x in range(x_start + 1, x_end):
		current_config.placed_tiles[Vector2i(x, y_start)] = 5
		current_config.placed_tiles[Vector2i(x, y_end)] = 5

	# 3. Vertical straight segments (id 10, Straight V)
	for y in range(y_start + 1, y_end):
		current_config.placed_tiles[Vector2i(x_start, y)] = 10
		current_config.placed_tiles[Vector2i(x_end, y)] = 10

	# 4. Auto-generate loop Curve2D points from the placed tiles
	_auto_generate_loop_from_tiles()

	# 5. Connect Entry Point seamlessly at the bottom center of the track
	var center_x: float = (float(x_start) + float(x_end)) * 0.5 * g_size
	var ep_pos := Vector2(center_x, float(y_end) * g_size)
	_ensure_entry_configs()
	if not current_config.entry_configs.is_empty():
		var ec: EntryConfig = current_config.entry_configs[0]
		ec.entry_point = ep_pos
		ec.queue_step = Vector2(0.0, 44.0)
		ec.queue_base_position = ep_pos + Vector2(0.0, 44.0)
		_sync_legacy_queue_fields()

	# 6. Connect Exit Point seamlessly at the top center of the track
	var exit_pos := Vector2(center_x, float(y_start) * g_size)
	current_config.has_exit = true
	if current_config.exit_configs.is_empty():
		var new_exit := ExitConfig.new()
		new_exit.label = "Exit 1"
		new_exit.exit_points = PackedVector2Array([
			exit_pos,
			exit_pos + Vector2(0.0, -180.0),
			exit_pos + Vector2(0.0, -450.0)
		])
		current_config.exit_configs.append(new_exit)
	else:
		current_config.exit_configs[0].exit_points = PackedVector2Array([
			exit_pos,
			exit_pos + Vector2(0.0, -180.0),
			exit_pos + Vector2(0.0, -450.0)
		])

	_mark_dirty()
	_fit_canvas()
	_update_canvas()


func _build_tile_settings(parent: Control) -> void:
	tile_settings_box = VBoxContainer.new()
	tile_settings_box.add_theme_constant_override("separation", 4)
	parent.add_child(tile_settings_box)

	# Row 1: Actions & Tools
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 6)
	tile_settings_box.add_child(row1)

	use_tilemap_check = CheckBox.new()
	use_tilemap_check.text = "Enable Tiles"
	use_tilemap_check.tooltip_text = "Enable tilemap route for this level"
	use_tilemap_check.toggled.connect(func(v: bool):
		if current_config:
			current_config.use_tilemap = v
			_mark_dirty()
			_update_canvas()
	)
	row1.add_child(use_tilemap_check)

	row1.add_child(_make_label("  Grid:"))
	tile_grid_spin = _make_spinbox(48.0, 200.0, 2.0, 96.0, 50.0)
	tile_grid_spin.value_changed.connect(func(v: float):
		if current_config:
			current_config.tile_grid_size = v
			_mark_dirty()
			_update_canvas()
	)
	row1.add_child(tile_grid_spin)

	var auto_btn := Button.new()
	auto_btn.text = "⚡ Auto-Generate Loop"
	auto_btn.tooltip_text = "Trace placed road tiles and auto-generate loop Curve2D points"
	auto_btn.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
	auto_btn.pressed.connect(_auto_generate_loop_from_tiles)
	row1.add_child(auto_btn)

	var clear_btn := Button.new()
	clear_btn.text = "🧹 Clear Tiles"
	clear_btn.tooltip_text = "Clear all placed tiles from this level"
	clear_btn.pressed.connect(func():
		if current_config:
			current_config.placed_tiles.clear()
			_mark_dirty()
			_update_canvas()
	)
	row1.add_child(clear_btn)

	# Row 2: Modular Road Track Presets
	var row_presets := HBoxContainer.new()
	row_presets.add_theme_constant_override("separation", 6)
	tile_settings_box.add_child(row_presets)

	row_presets.add_child(_make_label("📐 Track Presets — Straight H:"))
	var tile_h_spin := _make_spinbox(0.0, 10.0, 1.0, 3.0, 42.0)
	tile_h_spin.tooltip_text = "Number of horizontal straight tiles on top and bottom"
	row_presets.add_child(tile_h_spin)

	row_presets.add_child(_make_label(" Straight V:"))
	var tile_v_spin := _make_spinbox(0.0, 10.0, 1.0, 0.0, 42.0)
	tile_v_spin.tooltip_text = "Number of vertical straight tiles on left and right"
	row_presets.add_child(tile_v_spin)

	var stamp_oval_tile_btn := Button.new()
	stamp_oval_tile_btn.text = "🏎️ Stamp Tile Oval"
	stamp_oval_tile_btn.tooltip_text = "Stamp stadium/oval road track using modular tiles with straight sections"
	stamp_oval_tile_btn.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0))
	stamp_oval_tile_btn.pressed.connect(func() -> void:
		_stamp_tile_oval(int(tile_h_spin.value), int(tile_v_spin.value))
	)
	row_presets.add_child(stamp_oval_tile_btn)

	var stamp_circle_tile_btn := Button.new()
	stamp_circle_tile_btn.text = "⭕ 2×2 Round"
	stamp_circle_tile_btn.tooltip_text = "Stamp a 2x2 rounded corner track"
	stamp_circle_tile_btn.pressed.connect(func() -> void:
		_stamp_tile_oval(0, 0)
	)
	row_presets.add_child(stamp_circle_tile_btn)

	var stamp_circle3_tile_btn := Button.new()
	stamp_circle3_tile_btn.text = "⭕ 3×3 Round"
	stamp_circle3_tile_btn.tooltip_text = "Stamp a 3x3 rounded track (1 straight tile per side)"
	stamp_circle3_tile_btn.pressed.connect(func() -> void:
		_stamp_tile_oval(1, 1)
	)
	row_presets.add_child(stamp_circle3_tile_btn)

	var stamp_l13_tile_btn := Button.new()
	stamp_l13_tile_btn.text = "⭐ L13 (5×3)"
	stamp_l13_tile_btn.tooltip_text = "Stamp Level 13 7×5 stadium track"
	stamp_l13_tile_btn.pressed.connect(func() -> void:
		_stamp_tile_oval(5, 3)
	)
	row_presets.add_child(stamp_l13_tile_btn)

	var stamp_l14_tile_btn := Button.new()
	stamp_l14_tile_btn.text = "L14 (3×2)"
	stamp_l14_tile_btn.tooltip_text = "Stamp Level 14 5×4 stadium track"
	stamp_l14_tile_btn.pressed.connect(func() -> void:
		_stamp_tile_oval(3, 2)
	)
	row_presets.add_child(stamp_l14_tile_btn)

	# Row 3: Tile Palette
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 42)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tile_settings_box.add_child(scroll)

	var palette_flow := HBoxContainer.new()
	palette_flow.add_theme_constant_override("separation", 3)
	scroll.add_child(palette_flow)

	tile_palette_btns.clear()
	for i in range(TILE_INFOS.size()):
		var t_info: Dictionary = TILE_INFOS[i]
		var btn := Button.new()
		btn.text = "%d: %s" % [t_info["id"], t_info["name"]]
		btn.custom_minimum_size = Vector2(82, 32)
		btn.tooltip_text = t_info["name"]
		var tid: int = int(t_info["id"])
		btn.pressed.connect(func():
			_select_tile(tid)
		)
		palette_flow.add_child(btn)
		tile_palette_btns.append(btn)
	_update_tile_palette_selection()

	var hint := Label.new()
	hint.text = "Tiles mode: LClick/Drag to stamp tile. RClick to erase. Click '⚡ Auto-Generate Loop' to create route!"
	hint.add_theme_color_override("font_color", Color(0.3, 0.85, 1.0))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	tile_settings_box.add_child(hint)


func _select_tile(tid: int) -> void:
	selected_tile_id = tid
	_update_tile_palette_selection()
	_update_canvas()


func _update_tile_palette_selection() -> void:
	for i in range(tile_palette_btns.size()):
		var btn: Button = tile_palette_btns[i]
		if i == selected_tile_id:
			btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		else:
			btn.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))


func _get_tile_sheet() -> Texture2D:
	if not _tile_sheet_tex:
		if ResourceLoader.exists(_TILE_SHEET_PATH):
			_tile_sheet_tex = load(_TILE_SHEET_PATH)
	return _tile_sheet_tex


func _stamp_tile_oval(sh: int = 5, sv: int = 3) -> void:
	_generate_straight_oval_loop(sh, sv)


func _auto_generate_loop_from_tiles() -> void:
	if not current_config or current_config.placed_tiles.is_empty():
		return

	var g_size: float = current_config.tile_grid_size if current_config.tile_grid_size > 10.0 else 96.0
	var tiles: Dictionary = current_config.placed_tiles

	# Step 1: Build bidirectional adjacency graph
	var adj: Dictionary = {}
	for cell_key in tiles:
		var c: Vector2i = cell_key if cell_key is Vector2i else Vector2i(int(cell_key.x), int(cell_key.y))
		var tid: int = int(tiles[cell_key])
		if tid < 0 or tid >= TILE_INFOS.size():
			continue
		adj[c] = []
		var conns: Array = TILE_INFOS[tid]["conns"]
		for d: Vector2i in conns:
			var neighbor: Vector2i = c + d
			if tiles.has(neighbor) or tiles.has(Vector2(neighbor.x, neighbor.y)):
				var n_tid: int = int(tiles.get(neighbor, tiles.get(Vector2(neighbor.x, neighbor.y), -1)))
				if n_tid >= 0 and n_tid < TILE_INFOS.size():
					var n_conns: Array = TILE_INFOS[n_tid]["conns"]
					if -d in n_conns:
						adj[c].append(neighbor)

	# Step 2: Prune dead-end branches (tiles with <= 1 connection) until only cycles remain
	var pruned := true
	while pruned:
		pruned = false
		var to_remove: Array[Vector2i] = []
		for c: Vector2i in adj:
			if adj[c].size() <= 1:
				to_remove.append(c)
		if not to_remove.is_empty():
			pruned = true
			for c: Vector2i in to_remove:
				for neighbor: Vector2i in adj[c]:
					if adj.has(neighbor):
						adj[neighbor].erase(c)
				adj.erase(c)

	if adj.is_empty():
		push_warning("Level Builder: No closed loop found in placed tiles. Please make sure the track forms a complete closed circuit.")
		return

	# Step 3: Pick any start cell in the cycle and walk the cycle
	var start_cell: Vector2i = adj.keys()[0]
	var path_cells: Array[Vector2i] = []
	var visited: Dictionary = {}
	var curr: Vector2i = start_cell
	var prev: Vector2i = Vector2i(9999, 9999)

	for _step in range(1000):
		path_cells.append(curr)
		visited[curr] = true

		var neighbors: Array = adj.get(curr, [])
		var next_cell := Vector2i(9999, 9999)

		for n: Vector2i in neighbors:
			if n != prev:
				if n == start_cell and path_cells.size() >= 3:
					next_cell = n
					break
				elif not visited.has(n):
					next_cell = n
					break

		if next_cell == Vector2i(9999, 9999) or next_cell == start_cell:
			break
		prev = curr
		curr = next_cell

	if path_cells.size() < 3:
		return

	# Step 4: Generate Curve2D points through the traced tiles
	var pts := PackedVector2Array()
	var n_count := path_cells.size()

	for i in range(n_count):
		var prev_c: Vector2i = path_cells[(i - 1 + n_count) % n_count]
		var curr_c: Vector2i = path_cells[i]
		var next_c: Vector2i = path_cells[(i + 1) % n_count]

		var in_vec: Vector2 = Vector2(curr_c - prev_c)
		var out_vec: Vector2 = Vector2(next_c - curr_c)
		var center := Vector2(float(curr_c.x) * g_size, float(curr_c.y) * g_size)

		if in_vec.is_equal_approx(out_vec):
			pts.append(center)
		else:
			var p1 := center - in_vec * (g_size * 0.42)
			var p2 := center + (out_vec - in_vec).normalized() * (g_size * 0.28)
			var p3 := center + out_vec * (g_size * 0.42)
			pts.append(p1)
			pts.append(p2)
			pts.append(p3)

	if pts.size() > 0:
		pts.append(pts[0])
		current_config.loop_points = pts
		_mark_dirty()
		_update_canvas()


func _build_entry_settings(parent: Control) -> void:
	entry_settings_box = VBoxContainer.new()
	entry_settings_box.add_theme_constant_override("separation", 4)
	parent.add_child(entry_settings_box)

	var row0 := HBoxContainer.new()
	row0.add_theme_constant_override("separation", 6)
	entry_settings_box.add_child(row0)

	row0.add_child(_make_label("Entry:"))
	entry_select = OptionButton.new()
	entry_select.custom_minimum_size = Vector2(90, 0)
	entry_select.item_selected.connect(func(idx: int) -> void:
		current_entry_idx = idx
		_sync_entry_ui_from_current()
		_update_canvas()
	)
	row0.add_child(entry_select)

	var add_entry_btn := Button.new()
	add_entry_btn.text = "+"
	add_entry_btn.custom_minimum_size = Vector2(28, 0)
	add_entry_btn.pressed.connect(_add_entry_config)
	row0.add_child(add_entry_btn)

	var del_entry_btn := Button.new()
	del_entry_btn.text = "×"
	del_entry_btn.custom_minimum_size = Vector2(28, 0)
	del_entry_btn.pressed.connect(_delete_entry_config)
	row0.add_child(del_entry_btn)

	row0.add_child(_make_label("  Label:"))
	entry_label_edit = LineEdit.new()
	entry_label_edit.custom_minimum_size = Vector2(80, 0)
	entry_label_edit.text_changed.connect(func(t: String) -> void:
		_get_current_entry_cfg_safe(func(c: EntryConfig) -> void:
			c.label = t
			_mark_dirty()
		)
	)
	row0.add_child(entry_label_edit)

	var align_btn := Button.new()
	align_btn.text = "🎯 Align to Entry"
	align_btn.pressed.connect(_auto_align_queue_to_entry)
	row0.add_child(align_btn)

	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 6)
	entry_settings_box.add_child(row1)

	row1.add_child(_make_label("Queue Pos:"))
	queue_pos_x = _make_spinbox(-3000.0, 3000.0, 1.0, 360.0, 55.0)
	queue_pos_x.value_changed.connect(func(v: float) -> void:
		_get_current_entry_cfg_safe(func(c: EntryConfig) -> void:
			c.queue_base_position.x = v
			_mark_dirty()
			_update_canvas()
		)
	)
	row1.add_child(queue_pos_x)

	queue_pos_y = _make_spinbox(-3000.0, 3000.0, 1.0, 950.0, 55.0)
	queue_pos_y.value_changed.connect(func(v: float) -> void:
		_get_current_entry_cfg_safe(func(c: EntryConfig) -> void:
			c.queue_base_position.y = v
			_mark_dirty()
			_update_canvas()
		)
	)
	row1.add_child(queue_pos_y)

	row1.add_child(_make_label("  Step:"))
	queue_step_x = _make_spinbox(-500.0, 500.0, 1.0, 0.0, 45.0)
	queue_step_x.value_changed.connect(func(v: float) -> void:
		_get_current_entry_cfg_safe(func(c: EntryConfig) -> void:
			c.queue_step.x = v
			_mark_dirty()
			_update_canvas()
		)
	)
	row1.add_child(queue_step_x)

	queue_step_y = _make_spinbox(-500.0, 500.0, 1.0, 44.0, 45.0)
	queue_step_y.value_changed.connect(func(v: float) -> void:
		_get_current_entry_cfg_safe(func(c: EntryConfig) -> void:
			c.queue_step.y = v
			_mark_dirty()
			_update_canvas()
		)
	)
	row1.add_child(queue_step_y)

	var lbl := Label.new()
	lbl.text = "Entry mode: Click canvas to add/move Entry points. Drag 🔵 [Q] on canvas to position the Queue."
	lbl.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	entry_settings_box.add_child(lbl)



func _build_exit_settings(parent: Control) -> void:
	exit_settings_box = VBoxContainer.new()
	exit_settings_box.add_theme_constant_override("separation", 4)
	parent.add_child(exit_settings_box)

	var row1 := HBoxContainer.new()
	exit_settings_box.add_child(row1)
	has_exit_check = CheckBox.new()
	has_exit_check.text = "Has Exit"
	has_exit_check.toggled.connect(_on_has_exit_toggled)
	row1.add_child(has_exit_check)

	var row2 := HBoxContainer.new()
	exit_settings_box.add_child(row2)
	row2.add_child(_make_label("Exit:"))
	exit_select = OptionButton.new()
	exit_select.custom_minimum_size = Vector2(80, 0)
	exit_select.item_selected.connect(func(idx): current_exit_idx = idx; _update_canvas())
	row2.add_child(exit_select)

	var add_exit_btn := Button.new()
	add_exit_btn.text = "+"
	add_exit_btn.custom_minimum_size = Vector2(28, 0)
	add_exit_btn.pressed.connect(_add_exit_config)
	row2.add_child(add_exit_btn)

	var del_exit_btn := Button.new()
	del_exit_btn.text = "×"
	del_exit_btn.custom_minimum_size = Vector2(28, 0)
	del_exit_btn.pressed.connect(_delete_exit_config)
	row2.add_child(del_exit_btn)

	row2.add_child(_make_label("  Label:"))
	exit_label_edit = LineEdit.new()
	exit_label_edit.custom_minimum_size = Vector2(70, 0)
	exit_label_edit.text_changed.connect(func(t): _get_current_exit_cfg_safe(func(c): c.label = t; _mark_dirty()))
	row2.add_child(exit_label_edit)

	row2.add_child(_make_label("  Rule:"))
	rule_select = OptionButton.new()
	rule_select.add_item("any")
	rule_select.add_item("fruit_type")
	rule_select.add_item("entry_match")
	rule_select.add_item("random")
	rule_select.item_selected.connect(func(idx):
		_get_current_exit_cfg_safe(func(c): c.assign_rule = rule_select.get_item_text(idx); _mark_dirty()))
	row2.add_child(rule_select)

	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 6)
	exit_settings_box.add_child(row3)
	row3.add_child(_make_label("Target Fruit:"))
	exit_fruit_select = OptionButton.new()
	exit_fruit_select.custom_minimum_size = Vector2(140, 0)
	exit_fruit_select.add_item("Any Fruit (-1)")
	for i in range(_FRUIT_NAMES.size()):
		exit_fruit_select.add_item("%d - %s" % [i, _FRUIT_NAMES[i]])
	exit_fruit_select.item_selected.connect(func(idx: int):
		var fruit_val: int = idx - 1
		_get_current_exit_cfg_safe(func(c: ExitConfig):
			c.target_fruit_type = fruit_val
			_mark_dirty()
			_update_canvas()
		)
	)
	row3.add_child(exit_fruit_select)

	var hint := Label.new()
	hint.text = "Exit mode: click canvas to add exit path points.  Right-click to delete."
	hint.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	exit_settings_box.add_child(hint)


func _build_right_panel(parent: Control) -> void:
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(200, 0)
	vb.add_theme_constant_override("separation", 6)
	parent.add_child(vb)

	# ── Fruit picker ──────────────────────────────────────────────────────────
	vb.add_child(_make_label("Fruit picker"))

	fruit_grid = GridContainer.new()
	fruit_grid.columns = 5
	fruit_grid.add_theme_constant_override("h_separation", 3)
	fruit_grid.add_theme_constant_override("v_separation", 3)
	vb.add_child(fruit_grid)

	# Target toggle
	var tgt_bar := HBoxContainer.new()
	tgt_bar.add_theme_constant_override("separation", 2)
	vb.add_child(tgt_bar)
	tgt_bar.add_child(_make_label("Add to:"))
	queue_target_btn = Button.new()
	queue_target_btn.text = "Queue"
	queue_target_btn.toggle_mode = true
	queue_target_btn.button_pressed = true
	queue_target_btn.toggled.connect(func(on): if on: _set_fruit_target("queue"))
	tgt_bar.add_child(queue_target_btn)
	initial_target_btn = Button.new()
	initial_target_btn.text = "Initial"
	initial_target_btn.toggle_mode = true
	initial_target_btn.toggled.connect(func(on): if on: _set_fruit_target("initial"))
	tgt_bar.add_child(initial_target_btn)

	vb.add_child(HSeparator.new())

	# ── Queue sequence ────────────────────────────────────────────────────────
	var ql_bar := HBoxContainer.new()
	vb.add_child(ql_bar)
	ql_bar.add_child(_make_label("Queue  Count:"))
	queue_count_spin = _make_spinbox(1.0, 30.0, 1.0, 6.0, 45.0)
	queue_count_spin.value_changed.connect(func(v: float) -> void:
		_get_current_entry_cfg_safe(func(c: EntryConfig) -> void:
			c.queue_count = int(v)
			_sync_legacy_queue_fields()
			_mark_dirty()
			_update_canvas()
		)
	)
	ql_bar.add_child(queue_count_spin)

	var rand_bar := HBoxContainer.new()
	vb.add_child(rand_bar)
	randomize_check = CheckBox.new()
	randomize_check.text = "Randomize queue"
	randomize_check.toggled.connect(func(on: bool) -> void:
		_get_current_entry_cfg_safe(func(c: EntryConfig) -> void:
			c.queue_random_fruit = on
			_sync_legacy_queue_fields()
			_mark_dirty()
		)
	)
	rand_bar.add_child(randomize_check)

	var q_scroll := ScrollContainer.new()
	q_scroll.custom_minimum_size = Vector2(0, 52)
	q_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(q_scroll)
	queue_flow = HFlowContainer.new()
	queue_flow.set_h_size_flags(SIZE_EXPAND_FILL)
	q_scroll.add_child(queue_flow)

	vb.add_child(HSeparator.new())

	# ── Initial circulating ───────────────────────────────────────────────────
	vb.add_child(_make_label("Initial circulating"))

	var i_scroll := ScrollContainer.new()
	i_scroll.custom_minimum_size = Vector2(0, 52)
	i_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(i_scroll)
	initial_flow = HFlowContainer.new()
	initial_flow.set_h_size_flags(SIZE_EXPAND_FILL)
	i_scroll.add_child(initial_flow)

	vb.add_child(HSeparator.new())

	# ── Fruit Sizes ───────────────────────────────────────────────────────────
	_build_fruit_sizes_section(vb)


func _build_fruit_sizes_section(parent: Control) -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	parent.add_child(header)

	fruit_sizes_toggle_btn = Button.new()
	fruit_sizes_toggle_btn.text = "▼ Fruit Sizes (px)"
	fruit_sizes_toggle_btn.flat = true
	fruit_sizes_toggle_btn.set_h_size_flags(SIZE_EXPAND_FILL)
	fruit_sizes_toggle_btn.pressed.connect(func():
		if is_instance_valid(fruit_sizes_box):
			fruit_sizes_box.visible = not fruit_sizes_box.visible
			fruit_sizes_toggle_btn.text = ("▼ Fruit Sizes (px)" if fruit_sizes_box.visible else "▶ Fruit Sizes (px)")
	)
	header.add_child(fruit_sizes_toggle_btn)

	var reset_btn := Button.new()
	reset_btn.text = "↺"
	reset_btn.tooltip_text = "Reset all fruit sizes to defaults"
	reset_btn.custom_minimum_size = Vector2(24, 0)
	reset_btn.pressed.connect(_reset_fruit_sizes_to_default)
	header.add_child(reset_btn)

	fruit_sizes_box = VBoxContainer.new()
	fruit_sizes_box.add_theme_constant_override("separation", 2)
	parent.add_child(fruit_sizes_box)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 3)
	fruit_sizes_box.add_child(grid)

	fruit_size_spins.clear()
	for i in range(_FRUIT_REGIONS.size()):
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 2)
		grid.add_child(cell)

		var icon := TextureRect.new()
		icon.texture = _make_fruit_atlas(i)
		icon.custom_minimum_size = Vector2(20, 20)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.tooltip_text = _FRUIT_NAMES[i]
		cell.add_child(icon)

		var default_sz: float = LevelConfig.DEFAULT_FRUIT_SIZES[i] if i < LevelConfig.DEFAULT_FRUIT_SIZES.size() else 42.0
		var spin := _make_spinbox(20.0, 90.0, 1.0, default_sz, 48.0)
		spin.tooltip_text = "%s size (pixels)" % _FRUIT_NAMES[i]
		spin.value_changed.connect(_on_fruit_size_spin_changed.bind(i))
		cell.add_child(spin)
		fruit_size_spins.append(spin)


func _on_fruit_size_spin_changed(val: float, idx: int) -> void:
	if not current_config:
		return
	_ensure_fruit_sizes()
	if idx < current_config.fruit_sizes.size():
		current_config.fruit_sizes[idx] = val
		_mark_dirty()
		_update_canvas()


func _ensure_fruit_sizes() -> void:
	if not current_config:
		return
	if current_config.fruit_sizes.size() < _FRUIT_REGIONS.size():
		var arr := PackedFloat32Array()
		for i in range(_FRUIT_REGIONS.size()):
			if i < current_config.fruit_sizes.size() and current_config.fruit_sizes[i] > 0.0:
				arr.append(current_config.fruit_sizes[i])
			elif i < LevelConfig.DEFAULT_FRUIT_SIZES.size():
				arr.append(LevelConfig.DEFAULT_FRUIT_SIZES[i])
			else:
				arr.append(42.0)
		current_config.fruit_sizes = arr


func _reset_fruit_sizes_to_default() -> void:
	if not current_config:
		return
	current_config.fruit_sizes = LevelConfig.DEFAULT_FRUIT_SIZES.duplicate()
	_sync_fruit_sizes_ui()
	_mark_dirty()
	_update_canvas()


func _sync_fruit_sizes_ui() -> void:
	if not current_config:
		return
	for i in range(mini(fruit_size_spins.size(), _FRUIT_REGIONS.size())):
		var sz: float = current_config.get_fruit_size(i)
		fruit_size_spins[i].set_value_no_signal(sz)


func _build_dialogs() -> void:
	file_dialog = EditorFileDialog.new()
	file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	file_dialog.add_filter("*.png,*.jpg,*.jpeg,*.webp", "Sprite Images")
	file_dialog.current_dir = _SPRITES_DIR
	file_dialog.file_selected.connect(_on_sprite_selected)
	add_child(file_dialog)

	confirm_dialog = ConfirmationDialog.new()
	confirm_dialog.confirmed.connect(_on_delete_confirmed)
	add_child(confirm_dialog)


# ══════════════════════════════════════════════════════════════════════════════
# SECTION 3 — Level List
# ══════════════════════════════════════════════════════════════════════════════

func _ensure_levels_dir() -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(_LEVELS_DIR))


func _scan_level_paths() -> Array[String]:
	var paths: Array[String] = []
	var dir := DirAccess.open(_LEVELS_DIR)
	if not dir:
		return paths
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.ends_with(".tres") and not f.begins_with("_"):
			paths.append("%s/%s" % [_LEVELS_DIR, f])
		f = dir.get_next()
	dir.list_dir_end()
	paths.sort()
	return paths


func _refresh_level_list() -> void:
	for c in level_list_vbox.get_children():
		c.queue_free()

	var paths := _scan_level_paths()
	for path in paths:
		var cfg := load(path) as LevelConfig
		if not cfg:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		level_list_vbox.add_child(row)

		var btn := Button.new()
		btn.text = "%d. %s" % [cfg.level_number, cfg.title]
		btn.set_h_size_flags(SIZE_EXPAND_FILL)
		btn.toggle_mode = true
		btn.button_group = level_btn_group
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_on_level_selected.bind(path))
		if path == current_file_path:
			btn.set_pressed_no_signal(true)
		row.add_child(btn)

		var del := Button.new()
		del.text = "🗑"
		del.flat = true
		del.custom_minimum_size = Vector2(28, 0)
		del.pressed.connect(_on_delete_level.bind(path, cfg.title))
		row.add_child(del)

	# Show/hide the "Create sample levels" button
	var migrate_btn := get_node_or_null("*/MigrateBtn")
	if not migrate_btn:
		# Walk up: find via level_list_vbox parent chain
		var left_panel = level_list_vbox.get_parent().get_parent()
		if left_panel:
			migrate_btn = left_panel.get_node_or_null("MigrateBtn")
	if migrate_btn:
		migrate_btn.visible = paths.is_empty()


func _on_level_selected(path: String) -> void:
	current_file_path = path
	current_config    = load(path) as LevelConfig
	if current_config:
		is_dirty = false
		_sync_ui_from_config()
		_fit_canvas()
		_update_canvas()


func _on_new_level() -> void:
	# Auto-increment level number
	var paths := _scan_level_paths()
	var max_num := 0
	for p in paths:
		var c := load(p) as LevelConfig
		if c and c.level_number > max_num:
			max_num = c.level_number

	current_config             = LevelConfig.new()
	current_config.level_number = max_num + 1
	current_config.title       = "Level %d" % current_config.level_number
	current_file_path          = ""
	is_dirty                   = true
	_sync_ui_from_config()
	_fit_canvas()
	_update_canvas()
	_refresh_level_list()


func _on_delete_level(path: String, title: String) -> void:
	_pending_delete_path = path
	confirm_dialog.dialog_text = "Delete '%s'?\nThis cannot be undone." % title
	confirm_dialog.popup_centered()


func _on_delete_confirmed() -> void:
	if _pending_delete_path.is_empty():
		return
	DirAccess.remove_absolute(
		ProjectSettings.globalize_path(_pending_delete_path))
	if current_file_path == _pending_delete_path:
		current_config    = null
		current_file_path = ""
	_pending_delete_path = ""
	_refresh_level_list()
	_refresh_queue_display()
	_refresh_initial_display()
	_update_canvas()
	if EditorInterface.get_resource_filesystem():
		EditorInterface.get_resource_filesystem().scan()


# ══════════════════════════════════════════════════════════════════════════════
# SECTION 4 — Config ↔ UI Sync
# ══════════════════════════════════════════════════════════════════════════════

func _sync_ui_from_config() -> void:
	if not current_config:
		return
	_ensure_entry_configs()
	_block_signals(true)
	timer_spin.value      = current_config.level_time
	speed_spin.value      = current_config.speed
	gap_spin.value        = current_config.min_gap
	has_exit_check.button_pressed  = current_config.has_exit
	route_pos_x.value   = current_config.route_position.x
	route_pos_y.value   = current_config.route_position.y
	route_scale_x.value = current_config.route_scale.x
	route_scale_y.value = current_config.route_scale.y
	current_config.route_rotation = 0.0

	if is_instance_valid(use_tilemap_check):
		use_tilemap_check.button_pressed = current_config.use_tilemap
	if is_instance_valid(tile_grid_spin):
		tile_grid_spin.value = current_config.tile_grid_size if current_config.tile_grid_size > 10.0 else 96.0

	if current_config.track_texture and current_config.track_texture.resource_path:
		sprite_name_lbl.text = current_config.track_texture.resource_path.get_file()
	else:
		sprite_name_lbl.text = "(none)"

	_block_signals(false)
	_refresh_entry_select()
	_refresh_exit_select()
	_refresh_initial_display()
	_sync_fruit_sizes_ui()
	_update_mode_settings_visibility()


func _block_signals(blocked: bool) -> void:
	for node in [timer_spin, speed_spin, gap_spin, randomize_check,
	             queue_count_spin, has_exit_check,
	             route_pos_x, route_pos_y, route_scale_x,
	             route_scale_y,
	             queue_pos_x, queue_pos_y, queue_step_x, queue_step_y]:
		if is_instance_valid(node):
			node.set_block_signals(blocked)
	for spin in fruit_size_spins:
		if is_instance_valid(spin):
			spin.set_block_signals(blocked)


func _ensure_entry_configs() -> void:
	if not current_config:
		return
	if current_config.entry_configs.is_empty():
		current_config.entry_configs = current_config.get_entry_configs().duplicate(true)


func _get_current_entry_cfg() -> EntryConfig:
	if not current_config:
		return null
	_ensure_entry_configs()
	if current_config.entry_configs.is_empty():
		return null
	current_entry_idx = clampi(current_entry_idx, 0, current_config.entry_configs.size() - 1)
	return current_config.entry_configs[current_entry_idx]


func _get_current_entry_cfg_safe(cb: Callable) -> void:
	var ec := _get_current_entry_cfg()
	if ec:
		cb.call(ec)
		_sync_legacy_queue_fields()
		_mark_dirty()


func _refresh_entry_select() -> void:
	if not is_instance_valid(entry_select):
		return
	entry_select.clear()
	if not current_config:
		return
	_ensure_entry_configs()
	for i in range(current_config.entry_configs.size()):
		entry_select.add_item(current_config.entry_configs[i].label, i)
	if current_config.entry_configs.is_empty():
		if is_instance_valid(entry_label_edit): entry_label_edit.text = ""
	else:
		current_entry_idx = clampi(current_entry_idx, 0, current_config.entry_configs.size() - 1)
		entry_select.select(current_entry_idx)
		if is_instance_valid(entry_label_edit):
			entry_label_edit.text = current_config.entry_configs[current_entry_idx].label
	_sync_entry_ui_from_current()


func _sync_entry_ui_from_current() -> void:
	var ec := _get_current_entry_cfg()
	if not ec:
		return
	_block_signals(true)
	if is_instance_valid(entry_label_edit):
		entry_label_edit.text = ec.label
	if is_instance_valid(queue_pos_x):
		queue_pos_x.value = ec.queue_base_position.x
	if is_instance_valid(queue_pos_y):
		queue_pos_y.value = ec.queue_base_position.y
	if is_instance_valid(queue_step_x):
		queue_step_x.value = ec.queue_step.x
	if is_instance_valid(queue_step_y):
		queue_step_y.value = ec.queue_step.y
	if is_instance_valid(queue_count_spin):
		queue_count_spin.value = float(ec.queue_count)
	if is_instance_valid(randomize_check):
		randomize_check.button_pressed = ec.queue_random_fruit
	_block_signals(false)
	_refresh_queue_display()


func _add_entry_config() -> void:
	if not current_config:
		return
	_ensure_entry_configs()
	var idx := current_config.entry_configs.size()
	var ec := EntryConfig.new()
	ec.label = "Entry %d" % (idx + 1)
	ec.entry_point = Vector2(0.0, 105.0) if idx == 0 else Vector2(randf_range(-100.0, 100.0), randf_range(-100.0, 100.0))
	ec.queue_step = Vector2(0.0, 44.0)
	ec.queue_base_position = ec.entry_point + ec.queue_step
	ec.queue_count = 6
	ec.queue_fruit_indices = PackedInt32Array([0, 1, 2, 3])
	ec.queue_random_fruit = false
	current_config.entry_configs.append(ec)
	current_entry_idx = current_config.entry_configs.size() - 1
	_sync_legacy_queue_fields()
	_refresh_entry_select()
	_mark_dirty()
	_update_canvas()


func _delete_entry_config() -> void:
	if not current_config:
		return
	_ensure_entry_configs()
	if current_config.entry_configs.size() <= 1:
		push_warning("Level Builder: Cannot delete the only entry point.")
		return
	current_config.entry_configs.remove_at(current_entry_idx)
	current_entry_idx = clampi(current_entry_idx - 1, 0, current_config.entry_configs.size() - 1)
	_sync_legacy_queue_fields()
	_refresh_entry_select()
	_mark_dirty()
	_update_canvas()


func _sync_legacy_queue_fields() -> void:
	if not current_config:
		return
	var eps := PackedVector2Array()
	for ec in current_config.entry_configs:
		eps.append(ec.entry_point)
	current_config.entry_points = eps
	if not current_config.entry_configs.is_empty():
		var first: EntryConfig = current_config.entry_configs[0]
		current_config.queue_count = first.queue_count
		current_config.queue_fruit_indices = first.queue_fruit_indices
		current_config.queue_random_fruit = first.queue_random_fruit
		current_config.queue_step = first.queue_step
		current_config.queue_base_position = current_config.route_position + first.queue_base_position


func _auto_align_queue_to_entry() -> void:
	if not current_config:
		return
	var ec := _get_current_entry_cfg()
	if not ec:
		return
	var step_offset := ec.queue_step
	if step_offset.length_squared() < 0.001:
		step_offset = Vector2(0.0, 44.0)
	ec.queue_base_position = ec.entry_point + step_offset
	_sync_entry_ui_from_current()
	_sync_legacy_queue_fields()
	_mark_dirty()
	_update_canvas()


func _mark_dirty() -> void:
	is_dirty = true


# ══════════════════════════════════════════════════════════════════════════════
# SECTION 5 — Mode Tabs
# ══════════════════════════════════════════════════════════════════════════════

func _set_mode(m: EditMode) -> void:
	edit_mode    = m
	selected_idx = -1
	current_exit_idx = 0
	_update_mode_settings_visibility()
	_update_tab_styles()
	_update_canvas()


func _update_mode_settings_visibility() -> void:
	if is_instance_valid(loop_settings_box):
		loop_settings_box.visible  = (edit_mode == EditMode.LOOP)
	if is_instance_valid(tile_settings_box):
		tile_settings_box.visible  = (edit_mode == EditMode.TILES)
	if is_instance_valid(entry_settings_box):
		entry_settings_box.visible = (edit_mode == EditMode.ENTRY)
	if is_instance_valid(exit_settings_box):
		exit_settings_box.visible  = (edit_mode == EditMode.EXIT)


func _update_tab_styles() -> void:
	var active_col  := Color(0.3, 0.7, 1.0)
	var default_col := Color(0.7, 0.7, 0.7)
	if is_instance_valid(loop_btn):
		loop_btn.add_theme_color_override("font_color",
			active_col if edit_mode == EditMode.LOOP else default_col)
	if is_instance_valid(tiles_btn):
		tiles_btn.add_theme_color_override("font_color",
			active_col if edit_mode == EditMode.TILES else default_col)
	if is_instance_valid(entry_btn):
		entry_btn.add_theme_color_override("font_color",
			active_col if edit_mode == EditMode.ENTRY else default_col)
	if is_instance_valid(exit_btn):
		exit_btn.add_theme_color_override("font_color",
			active_col if edit_mode == EditMode.EXIT else default_col)


# ══════════════════════════════════════════════════════════════════════════════
# SECTION 6 — Exit Config Management
# ══════════════════════════════════════════════════════════════════════════════

func _refresh_exit_select() -> void:
	if not is_instance_valid(exit_select):
		return
	exit_select.clear()
	if not current_config:
		return
	for i in range(current_config.exit_configs.size()):
		exit_select.add_item(current_config.exit_configs[i].label, i)
	if current_config.exit_configs.is_empty():
		exit_label_edit.text = ""
		if is_instance_valid(exit_fruit_select):
			exit_fruit_select.select(0)
	else:
		current_exit_idx = clampi(current_exit_idx, 0, current_config.exit_configs.size() - 1)
		exit_select.select(current_exit_idx)
		exit_label_edit.text = current_config.exit_configs[current_exit_idx].label
		var rule := current_config.exit_configs[current_exit_idx].assign_rule
		for i in range(rule_select.item_count):
			if rule_select.get_item_text(i) == rule:
				rule_select.select(i)
				break
		if is_instance_valid(exit_fruit_select):
			var target_f: int = current_config.exit_configs[current_exit_idx].target_fruit_type
			exit_fruit_select.select(clampi(target_f + 1, 0, exit_fruit_select.item_count - 1))


func _add_exit_config() -> void:
	if not current_config:
		return
	var letters := "ABCDEFGHIJKLMNOP"
	var idx := current_config.exit_configs.size()
	var ecfg := ExitConfig.new()
	ecfg.label = "Exit %s" % letters[idx % letters.length()]
	ecfg.assign_rule = "any"
	ecfg.target_fruit_type = -1
	current_config.exit_configs.append(ecfg)
	current_config.has_exit = true
	has_exit_check.set_pressed_no_signal(true)
	current_exit_idx = current_config.exit_configs.size() - 1
	_refresh_exit_select()
	_mark_dirty()
	_update_canvas()


func _delete_exit_config() -> void:
	if not current_config or current_config.exit_configs.is_empty():
		return
	current_config.exit_configs.remove_at(current_exit_idx)
	if current_config.exit_configs.is_empty():
		current_config.has_exit = false
		has_exit_check.set_pressed_no_signal(false)
	current_exit_idx = clampi(current_exit_idx - 1, 0, current_config.exit_configs.size() - 1)
	_refresh_exit_select()
	_mark_dirty()
	_update_canvas()


func _on_has_exit_toggled(on: bool) -> void:
	if not current_config:
		return
	current_config.has_exit = on
	if on and current_config.exit_configs.is_empty():
		_add_exit_config()
	_mark_dirty()
	_update_canvas()


func _get_current_exit_cfg_safe(cb: Callable) -> void:
	if not current_config or current_config.exit_configs.is_empty():
		return
	if current_exit_idx >= current_config.exit_configs.size():
		return
	cb.call(current_config.exit_configs[current_exit_idx])
	_mark_dirty()


# ══════════════════════════════════════════════════════════════════════════════
# SECTION 7 — Sprite Picker
# ══════════════════════════════════════════════════════════════════════════════

func _on_choose_sprite() -> void:
	if not current_config:
		_on_new_level()
	file_dialog.popup_centered(Vector2i(900, 600))


func _on_sprite_selected(path: String) -> void:
	if not current_config:
		return
	var tex := load(path) as Texture2D
	if not tex:
		return
	current_config.track_texture = tex
	sprite_name_lbl.text = path.get_file()
	_mark_dirty()
	_fit_canvas()
	_update_canvas()


# ══════════════════════════════════════════════════════════════════════════════
# SECTION 8 — Fruit Picker / Queue / Initial
# ══════════════════════════════════════════════════════════════════════════════

func _get_sheet() -> Texture2D:
	if not _sheet_tex or not is_instance_valid(_sheet_tex):
		_sheet_tex = load(_FRUIT_SHEET) as Texture2D
	return _sheet_tex


func _make_fruit_atlas(idx: int) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas  = _get_sheet()
	atlas.region = _FRUIT_REGIONS[idx] as Rect2
	return atlas


func _refresh_fruit_grid() -> void:
	for c in fruit_grid.get_children():
		c.queue_free()
	if not _get_sheet():
		return
	for i in range(_FRUIT_REGIONS.size()):
		var btn := Button.new()
		btn.icon         = _make_fruit_atlas(i)
		btn.expand_icon  = true
		btn.custom_minimum_size = Vector2(34, 34)
		btn.tooltip_text = _FRUIT_NAMES[i]
		btn.pressed.connect(_on_fruit_picked.bind(i))
		fruit_grid.add_child(btn)


func _on_fruit_picked(idx: int) -> void:
	if not current_config:
		return
	if fruit_target == "queue":
		var ec := _get_current_entry_cfg()
		if ec:
			var arr := PackedInt32Array(ec.queue_fruit_indices)
			arr.append(idx)
			ec.queue_fruit_indices = arr
			_sync_legacy_queue_fields()
			_refresh_queue_display()
	else:
		var arr := PackedInt32Array(current_config.initial_fruit_indices)
		arr.append(idx)
		current_config.initial_fruit_indices = arr
		_refresh_initial_display()
	_mark_dirty()
	_update_canvas()


func _set_fruit_target(t: String) -> void:
	fruit_target = t
	if is_instance_valid(queue_target_btn):
		queue_target_btn.set_pressed_no_signal(t == "queue")
	if is_instance_valid(initial_target_btn):
		initial_target_btn.set_pressed_no_signal(t == "initial")


func _refresh_queue_display() -> void:
	for c in queue_flow.get_children():
		c.queue_free()
	if not current_config or not _get_sheet():
		return
	var ec := _get_current_entry_cfg()
	if not ec:
		return
	for i in range(ec.queue_fruit_indices.size()):
		var fi := ec.queue_fruit_indices[i]
		queue_flow.add_child(_make_item_chip(fi, func(): _remove_queue_item(i)))


func _remove_queue_item(i: int) -> void:
	if not current_config:
		return
	var ec := _get_current_entry_cfg()
	if not ec:
		return
	var arr := PackedInt32Array(ec.queue_fruit_indices)
	if i < arr.size():
		arr.remove_at(i)
		ec.queue_fruit_indices = arr
		_sync_legacy_queue_fields()
		_refresh_queue_display()
		_mark_dirty()


func _refresh_initial_display() -> void:
	for c in initial_flow.get_children():
		c.queue_free()
	if not current_config or not _get_sheet():
		return
	for i in range(current_config.initial_fruit_indices.size()):
		var fi := current_config.initial_fruit_indices[i]
		initial_flow.add_child(_make_item_chip(fi, func(): _remove_initial_item(i)))


func _remove_initial_item(i: int) -> void:
	if not current_config:
		return
	var arr := PackedInt32Array(current_config.initial_fruit_indices)
	arr.remove_at(i)
	current_config.initial_fruit_indices = arr
	_refresh_initial_display()
	_mark_dirty()


func _on_timer_changed(value: float) -> void:
	if current_config: current_config.level_time = value; _mark_dirty()

func _on_randomize_toggled(on: bool) -> void:
	if current_config: current_config.queue_random_fruit = on; _mark_dirty()


# ══════════════════════════════════════════════════════════════════════════════
# SECTION 9 — Play / Save
# ══════════════════════════════════════════════════════════════════════════════

func _on_play() -> void:
	if not current_config:
		push_warning("Level Builder: No level loaded. Create or open a level first.")
		return
	_ensure_entry_configs()
	_sync_legacy_queue_fields()
	_ensure_levels_dir()
	var err := ResourceSaver.save(current_config, _PREVIEW_TRES)
	if err != OK:
		push_error("Level Builder: Could not save preview to '%s' (err %d)" % [_PREVIEW_TRES, err])
		return
	# Write flag file so Gameplay.gd knows to load the preview
	var flag := FileAccess.open(_PREVIEW_FLAG, FileAccess.WRITE)
	if flag:
		flag.store_string("preview")
		flag.close()
	EditorInterface.play_custom_scene(_GAMEPLAY_SCENE)


func _on_save() -> void:
	if not current_config:
		return
	_ensure_entry_configs()
	_sync_legacy_queue_fields()
	if current_file_path.is_empty():
		current_file_path = "%s/level_%02d.tres" % [_LEVELS_DIR, current_config.level_number]
	_ensure_levels_dir()
	var err := ResourceSaver.save(current_config, current_file_path)
	if err == OK:
		is_dirty = false
		_refresh_level_list()
		if EditorInterface.get_resource_filesystem():
			EditorInterface.get_resource_filesystem().scan()
	else:
		push_error("Level Builder: Save failed for '%s' (err %d)" % [current_file_path, err])


# ══════════════════════════════════════════════════════════════════════════════
# SECTION 10 — Canvas: Coordinate helpers
# ══════════════════════════════════════════════════════════════════════════════

func _world_to_canvas(world: Vector2, canvas: Control) -> Vector2:
	return world * canvas_zoom + canvas.size * 0.5 + canvas_pan

func _canvas_to_world(cpos: Vector2, canvas: Control) -> Vector2:
	return (cpos - canvas.size * 0.5 - canvas_pan) / canvas_zoom

func _fit_canvas() -> void:
	if not is_instance_valid(canvas_ctrl):
		return
	var csz := canvas_ctrl.size
	if csz.x < 10 or csz.y < 10:
		return
	canvas_pan = Vector2.ZERO
	if show_device_frame and selected_device_idx < DEVICE_PRESETS.size():
		var preset: Dictionary = DEVICE_PRESETS[selected_device_idx]
		var dev_w: float = preset["w"]
		var dev_h: float = preset["h"]
		var eff_w: float = 720.0
		var eff_h: float = 720.0 * (dev_h / dev_w)
		canvas_zoom = minf(csz.x / eff_w, csz.y / eff_h) * 0.85
		var ry: float = 560.0
		if current_config and current_config.route_position.y > 0.0:
			ry = current_config.route_position.y
		var route_screen_y: float = eff_h * (ry / 1280.0)
		var screen_center_offset_y: float = -(route_screen_y - eff_h * 0.5)
		canvas_pan = Vector2(0.0, screen_center_offset_y * canvas_zoom)
		return
	if current_config and current_config.track_texture:
		var tsz := current_config.track_texture.get_size()
		if tsz.x > 0 and tsz.y > 0:
			canvas_zoom = minf(csz.x / tsz.x, csz.y / tsz.y) * 0.82
			return
	canvas_zoom = 0.5

func _on_canvas_resized() -> void:
	_fit_canvas()
	_update_canvas()

func _update_canvas() -> void:
	if is_instance_valid(canvas_ctrl):
		canvas_ctrl.queue_redraw()

func _zoom_at(mouse: Vector2, canvas: Control, factor: float) -> void:
	var w_before := _canvas_to_world(mouse, canvas)
	canvas_zoom = clampf(canvas_zoom * factor, 0.04, 8.0)
	canvas_pan += mouse - _world_to_canvas(w_before, canvas)
	canvas.queue_redraw()


# ══════════════════════════════════════════════════════════════════════════════
# SECTION 11 — Canvas: Drawing
# ══════════════════════════════════════════════════════════════════════════════

func on_canvas_draw(canvas: Control) -> void:
	var csz := canvas.size
	canvas.draw_rect(Rect2(Vector2.ZERO, csz), Color(0.13, 0.13, 0.13))

	if not current_config:
		var fb := ThemeDB.fallback_font
		var msg := "Select a level or click '+ New level'"
		var tw   := fb.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		canvas.draw_string(fb, Vector2(csz.x * 0.5 - tw * 0.5, csz.y * 0.5),
			msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.5, 0.5, 0.5))
		return

	_draw_grid(canvas)
	_draw_device_frame(canvas)

	# Sprite
	if current_config.track_texture:
		var tex: Texture2D = current_config.track_texture
		var tsz: Vector2 = tex.get_size() * canvas_zoom
		var center: Vector2 = canvas.size * 0.5 + canvas_pan
		var tpos: Vector2 = center - tsz * 0.5
		canvas.draw_texture_rect(tex, Rect2(tpos, tsz), false, Color(1, 1, 1, 0.88))

	# Entry and Exit Roads (base layer under tiles)
	_draw_editor_roads(canvas)

	# Placed road tiles
	_draw_placed_tiles(canvas)
	if edit_mode == EditMode.TILES:
		_draw_tile_grid_and_ghost(canvas)

	# Loop path
	var lp := current_config.loop_points
	if lp.size() >= 2:
		for i in range(lp.size() - 1):
			canvas.draw_line(_world_to_canvas(lp[i], canvas),
				_world_to_canvas(lp[i + 1], canvas), Color(0.2, 0.9, 0.4, 0.85), 1.8)
		# Close loop
		canvas.draw_line(_world_to_canvas(lp[-1], canvas),
			_world_to_canvas(lp[0], canvas), Color(0.2, 0.9, 0.4, 0.4), 1.0)

	# Loop points
	for i in range(lp.size()):
		var cp := _world_to_canvas(lp[i], canvas)
		var selected := (edit_mode == EditMode.LOOP and i == selected_idx)
		var col := Color.YELLOW if selected else Color(0.2, 0.95, 0.4)
		canvas.draw_circle(cp, 6.0 if selected else 4.0, col)
		if i == 0:
			canvas.draw_string(ThemeDB.fallback_font, cp + Vector2(7, -4),
				"[0]", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.8, 1, 0.4, 0.8))

	# Entry points, approach paths, and Queues
	if current_config:
		_ensure_entry_configs()
		var e_configs := current_config.get_entry_configs()
		var sheet := _get_sheet()

		for i in range(e_configs.size()):
			var ec: EntryConfig = e_configs[i]
			var is_current: bool = (edit_mode == EditMode.ENTRY and i == current_entry_idx)
			var ep_canvas := _world_to_canvas(ec.entry_point, canvas)

			# 1. Approach path / Entry Road
			var step_dir := ec.queue_step
			if step_dir.length_squared() < 0.01:
				step_dir = Vector2(0, 44)
			var tail_world: Vector2 = ec.entry_point + step_dir * float(maxi(1, ec.queue_count))
			var tail_canvas := _world_to_canvas(tail_world, canvas)
			var road_col := Color(0.2, 0.7, 1.0, 0.35) if is_current else Color(0.2, 0.45, 0.65, 0.18)
			canvas.draw_line(ep_canvas, tail_canvas, road_col, 8.0 * canvas_zoom)

			# 2. Entry marker (triangle)
			var tri := PackedVector2Array([
				ep_canvas + Vector2(-8, -9), ep_canvas + Vector2(-8, 9), ep_canvas + Vector2(10, 0)
			])
			var ep_col := Color.YELLOW if (is_current and selected_idx == i and not selected_is_queue) else (Color(1.0, 0.8, 0.2) if is_current else Color(1.0, 0.55, 0.0))
			canvas.draw_polygon(tri, [ep_col, ep_col, ep_col])
			canvas.draw_string(ThemeDB.fallback_font, ep_canvas + Vector2(13, -4),
				"E%d" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ep_col)

			# 3. Queue Slots & Foods
			var q_count: int = ec.queue_count
			var q_indices := ec.queue_fruit_indices
			var q_base_canvas := _world_to_canvas(ec.queue_base_position, canvas)

			if q_count > 1:
				var p_last_canvas := q_base_canvas + ec.queue_step * canvas_zoom * float(q_count - 1)
				canvas.draw_line(q_base_canvas, p_last_canvas, Color(0.2, 0.7, 1.0, 0.5 if is_current else 0.25), 2.0)

			for qi in range(q_count):
				var slot_canvas: Vector2 = q_base_canvas + ec.queue_step * canvas_zoom * float(qi)
				var fruit_idx: int = 0
				if q_indices.size() > 0:
					fruit_idx = q_indices[qi % q_indices.size()]

				var is_first: bool = (qi == 0)
				var f_size: float = current_config.get_fruit_size(fruit_idx) if current_config else 42.0
				var size_ratio: float = f_size / 42.0
				var base_radius: float = clampf(14.0 * canvas_zoom, 7.0, 18.0)
				var q_radius: float = base_radius * size_ratio
				var is_q_selected: bool = (selected_is_queue and selected_queue_idx == i and is_first)

				var bg_col := Color.YELLOW if is_q_selected else (Color(0.2, 0.8, 1.0, 0.95) if (is_first and is_current) else (Color(0.2, 0.6, 1.0, 0.7) if is_first else Color(0.15, 0.35, 0.65, 0.5)))
				canvas.draw_circle(slot_canvas, q_radius + 2.0, bg_col)

				if sheet and fruit_idx >= 0 and fruit_idx < _FRUIT_REGIONS.size():
					var f_rect: Rect2 = _FRUIT_REGIONS[fruit_idx] as Rect2
					var draw_sz := (q_radius * 2.0)
					var dest_rect := Rect2(slot_canvas - Vector2(draw_sz * 0.5, draw_sz * 0.5), Vector2(draw_sz, draw_sz))
					canvas.draw_texture_rect_region(sheet, dest_rect, f_rect)

				if is_first:
					var tag_col := Color.YELLOW if is_q_selected else (Color(0.35, 0.85, 1.0) if is_current else Color(0.5, 0.7, 0.9, 0.7))
					canvas.draw_string(ThemeDB.fallback_font, slot_canvas + Vector2(q_radius + 5.0, 4.0),
						"Queue %d [Q]" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, tag_col)

	# Exit paths (editing indicators, dashed centerline, control points)
	if current_config and current_config.has_exit:
		for ei in range(current_config.exit_configs.size()):
			var ecfg: ExitConfig = current_config.exit_configs[ei]
			var is_current: bool = (edit_mode == EditMode.EXIT and ei == current_exit_idx)
			var ecol := Color(1.0, 0.35, 0.35, 0.95) if is_current else Color(0.85, 0.6, 0.6, 0.75)
			var pts  := ecfg.exit_points
			for j in range(pts.size()):
				var cp := _world_to_canvas(pts[j], canvas)
				var sel := (is_current and j == selected_idx)
				canvas.draw_circle(cp, 7.0 if sel else 4.5, Color.YELLOW if sel else ecol)
				if j < pts.size() - 1:
					_draw_dashed(canvas, cp, _world_to_canvas(pts[j + 1], canvas), ecol)
			if pts.size() >= 1:
				var exit_txt := ecfg.label
				if ecfg.target_fruit_type >= 0 and ecfg.target_fruit_type < _FRUIT_NAMES.size():
					exit_txt += " (%s)" % _FRUIT_NAMES[ecfg.target_fruit_type]
				elif ecfg.target_fruit_type == -1:
					exit_txt += " (Any)"
				var p0_canvas := _world_to_canvas(pts[0], canvas)
				canvas.draw_string(ThemeDB.fallback_font,
					p0_canvas + Vector2(10, -6),
					exit_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ecol)

				# Direction arrow at exit junction
				if pts.size() >= 2:
					var p1_canvas := _world_to_canvas(pts[1], canvas)
					var arrow_dir := (p1_canvas - p0_canvas).normalized()
					var arrow_perp := Vector2(-arrow_dir.y, arrow_dir.x)
					var tri := PackedVector2Array([
						p0_canvas + arrow_dir * 16.0,
						p0_canvas - arrow_dir * 4.0 + arrow_perp * 8.0,
						p0_canvas - arrow_dir * 4.0 - arrow_perp * 8.0
					])
					var arrow_col := FoodTextures.get_fruit_color(ecfg.target_fruit_type)
					canvas.draw_polygon(tri, [arrow_col, arrow_col, arrow_col])

	# Coordinate readout at origin
	var orig := _world_to_canvas(Vector2.ZERO, canvas)
	canvas.draw_circle(orig, 3.0, Color(0.4, 0.4, 0.9, 0.6))

	# Mode hint
	var hint := ""
	match edit_mode:
		EditMode.LOOP:  hint = "Loop — LClick: add point | Drag: move | RClick: delete | Scroll: zoom | MClick: pan"
		EditMode.TILES: hint = "Tiles — LClick/Drag: stamp tile | RClick/Drag: erase | Auto-Gen: build loop"
		EditMode.ENTRY: hint = "Entry — LClick: add entry | Drag [Q]: move queue | RClick: delete entry"
		EditMode.EXIT:  hint = "Exit — LClick: add exit point | RClick: delete"
	if hint:
		canvas.draw_string(ThemeDB.fallback_font, Vector2(6, csz.y - 8),
			hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.5, 0.5, 0.8))


func _draw_grid(canvas: Control) -> void:
	var csz := canvas.size
	var step_w := 50.0
	var step_c := step_w * canvas_zoom
	if step_c < 8.0:
		return
	var orig_w := _canvas_to_world(Vector2.ZERO, canvas)
	var sx: float = floor(orig_w.x / step_w) * step_w
	var sy: float = floor(orig_w.y / step_w) * step_w
	var x := sx
	while _world_to_canvas(Vector2(x, 0), canvas).x < csz.x + step_c:
		var cx := _world_to_canvas(Vector2(x, 0), canvas).x
		var col := Color(0.35, 0.35, 0.55, 0.7) if is_zero_approx(x) else Color(0.25, 0.25, 0.25, 0.35)
		canvas.draw_line(Vector2(cx, 0), Vector2(cx, csz.y), col, 1.0)
		x += step_w
	var y := sy
	while _world_to_canvas(Vector2(0, y), canvas).y < csz.y + step_c:
		var cy := _world_to_canvas(Vector2(0, y), canvas).y
		var col := Color(0.35, 0.35, 0.55, 0.7) if is_zero_approx(y) else Color(0.25, 0.25, 0.25, 0.35)
		canvas.draw_line(Vector2(0, cy), Vector2(csz.x, cy), col, 1.0)
		y += step_w


func _draw_editor_roads(canvas: Control) -> void:
	if not current_config:
		return
	var is_tilemap: bool = current_config.use_tilemap
	var has_sprite: bool = (current_config.track_texture != null)
	var border_w: float = (74.0 if is_tilemap else 68.0) * canvas_zoom
	var asphalt_w: float = 50.0 * canvas_zoom
	var border_col := Color(0.925, 0.898, 0.824, 0.95) if (is_tilemap or not has_sprite) else Color(0.28, 0.28, 0.28, 0.85)
	var asphalt_col := Color(0.424, 0.424, 0.424, 0.95) if (is_tilemap or not has_sprite) else Color(0.24, 0.25, 0.28, 0.95)

	# 1. Entry roads (rendered underneath loop and tiles)
	_ensure_entry_configs()
	for ec: EntryConfig in current_config.get_entry_configs():
		var ep: Vector2 = ec.entry_point
		var step_dir: Vector2 = ec.queue_step.normalized()
		if step_dir.length_squared() < 0.01:
			step_dir = Vector2.DOWN
		var far_p: Vector2 = ep + step_dir * 1200.0
		var c_ep: Vector2 = _world_to_canvas(ep, canvas)
		var c_far: Vector2 = _world_to_canvas(far_p, canvas)

		# Outer border (cream)
		canvas.draw_line(c_ep, c_far, border_col, border_w)
		canvas.draw_circle(c_far, border_w * 0.5, border_col)

		if is_tilemap or not has_sprite:
			# Inner asphalt (grey)
			canvas.draw_line(c_ep, c_far, asphalt_col, asphalt_w)
			canvas.draw_circle(c_far, asphalt_w * 0.5, asphalt_col)

	# 2. Exit roads (rendered underneath loop and tiles)
	if current_config.has_exit:
		for ecfg: ExitConfig in current_config.exit_configs:
			var pts: PackedVector2Array = ecfg.exit_points
			if pts.is_empty():
				continue
			var c_pts: PackedVector2Array = []
			for p in pts:
				c_pts.append(_world_to_canvas(p, canvas))
			if pts.size() >= 2:
				var last_pt: Vector2 = pts[-1]
				var prev_pt: Vector2 = pts[-2]
				var dir: Vector2 = (last_pt - prev_pt).normalized()
				if dir.length_squared() > 0.001:
					c_pts.append(_world_to_canvas(last_pt + dir * 1200.0, canvas))
			elif pts.size() == 1:
				c_pts.append(_world_to_canvas(pts[0] + Vector2.UP * 1200.0, canvas))

			if c_pts.size() >= 2:
				# Outer border (cream)
				canvas.draw_polyline(c_pts, border_col, border_w)
				canvas.draw_circle(c_pts[-1], border_w * 0.5, border_col)

				if is_tilemap or not has_sprite:
					# Inner asphalt (grey)
					canvas.draw_polyline(c_pts, asphalt_col, asphalt_w)
					canvas.draw_circle(c_pts[-1], asphalt_w * 0.5, asphalt_col)

	# 3. Procedural Loop Road (when not using tilemap or sprite texture, rendered on top of entry/exit roads)
	if not is_tilemap and not has_sprite and current_config.loop_points.size() >= 3:
		var c_loop: PackedVector2Array = []
		for p in current_config.loop_points:
			c_loop.append(_world_to_canvas(p, canvas))
		if c_loop.size() >= 3:
			if c_loop[0] != c_loop[-1]:
				c_loop.append(c_loop[0])
			var lp_border_w: float = 68.0 * canvas_zoom
			var lp_asphalt_w: float = 50.0 * canvas_zoom
			# Outer border (cream)
			canvas.draw_polyline(c_loop, border_col, lp_border_w)
			for cp in c_loop:
				canvas.draw_circle(cp, lp_border_w * 0.5, border_col)
			# Inner asphalt (grey)
			canvas.draw_polyline(c_loop, asphalt_col, lp_asphalt_w)
			for cp in c_loop:
				canvas.draw_circle(cp, lp_asphalt_w * 0.5, asphalt_col)


func _draw_placed_tiles(canvas: Control) -> void:
	if not current_config or current_config.placed_tiles.is_empty():
		return
	var sheet := _get_tile_sheet()
	if not sheet:
		return
	var g_size: float = current_config.tile_grid_size if current_config.tile_grid_size > 10.0 else 96.0
	var scale: float = (g_size / TILE_BASE_SIZE) * canvas_zoom * 1.025

	for cell_key in current_config.placed_tiles:
		var cell := Vector2i.ZERO
		if cell_key is Vector2i:
			cell = cell_key
		elif cell_key is Vector2:
			cell = Vector2i(int(cell_key.x), int(cell_key.y))
		else:
			continue
		var tid: int = int(current_config.placed_tiles[cell_key])
		if tid < 0 or tid >= TILE_INFOS.size():
			continue

		var cell_world := Vector2(float(cell.x) * g_size, float(cell.y) * g_size)
		var cell_c := _world_to_canvas(cell_world, canvas)
		var t_info: Dictionary = TILE_INFOS[tid]
		var t_rect: Rect2 = t_info["rect"]
		var t_offset: Vector2 = t_info.get("offset", Vector2.ZERO)
		var dest_size := t_rect.size * scale
		var dest_center := cell_c + t_offset * scale
		var rect_c := Rect2(dest_center - dest_size * 0.5, dest_size)
		canvas.draw_texture_rect_region(sheet, rect_c, t_rect, Color.WHITE)


func _draw_tile_grid_and_ghost(canvas: Control) -> void:
	if not current_config:
		return
	var g_size: float = current_config.tile_grid_size if current_config.tile_grid_size > 10.0 else 96.0
	var sheet := _get_tile_sheet()

	if hover_grid_cell.x != 9999 and selected_tile_id >= 0 and selected_tile_id < TILE_INFOS.size():
		var cell_world := Vector2(float(hover_grid_cell.x) * g_size, float(hover_grid_cell.y) * g_size)
		var cell_c := _world_to_canvas(cell_world, canvas)
		var cell_w := g_size * canvas_zoom
		var grid_rect := Rect2(cell_c - Vector2(cell_w, cell_w) * 0.5, Vector2(cell_w, cell_w))

		canvas.draw_rect(grid_rect, Color(1.0, 0.85, 0.2, 0.8), false, 2.0)

		if sheet:
			var scale: float = (g_size / TILE_BASE_SIZE) * canvas_zoom * 1.025
			var t_info: Dictionary = TILE_INFOS[selected_tile_id]
			var t_rect: Rect2 = t_info["rect"]
			var t_offset: Vector2 = t_info.get("offset", Vector2.ZERO)
			var dest_size := t_rect.size * scale
			var dest_center := cell_c + t_offset * scale
			var rect_c := Rect2(dest_center - dest_size * 0.5, dest_size)
			canvas.draw_texture_rect_region(sheet, rect_c, t_rect, Color(1, 1, 1, 0.55))


func _draw_device_frame(canvas: Control) -> void:
	if not show_device_frame or selected_device_idx >= DEVICE_PRESETS.size():
		return

	var preset: Dictionary = DEVICE_PRESETS[selected_device_idx]
	var dev_w: float = preset["w"]
	var dev_h: float = preset["h"]
	var preset_name: String = preset["name"]

	var eff_w: float = 720.0
	var eff_h: float = 720.0 * (dev_h / dev_w)

	var ry: float = 560.0
	if current_config and current_config.route_position.y > 0.0:
		ry = current_config.route_position.y

	var route_screen_y: float = eff_h * (ry / 1280.0)

	var screen_left: float   = -eff_w * 0.5
	var screen_right: float  =  eff_w * 0.5
	var screen_top: float    = -route_screen_y
	var screen_bottom: float =  eff_h - route_screen_y
	var screen_center_y: float = screen_top + eff_h * 0.5

	var tl_c := _world_to_canvas(Vector2(screen_left, screen_top), canvas)
	var br_c := _world_to_canvas(Vector2(screen_right, screen_bottom), canvas)
	var screen_rect := Rect2(tl_c, br_c - tl_c)

	# 1. Phone screen background surface
	canvas.draw_rect(screen_rect, Color(0.16, 0.17, 0.22, 0.45))

	# 2. Outer phone frame border
	var frame_col := Color(0.25, 0.75, 1.0, 0.85)
	canvas.draw_rect(screen_rect, frame_col, false, 2.0)

	# 3. Screen Center crosshair lines
	var h_left_c  := _world_to_canvas(Vector2(screen_left, screen_center_y), canvas)
	var h_right_c := _world_to_canvas(Vector2(screen_right, screen_center_y), canvas)
	_draw_dashed(canvas, h_left_c, h_right_c, Color(0.25, 0.75, 1.0, 0.35), 1.0, 6.0)

	var v_top_c    := _world_to_canvas(Vector2(0, screen_top), canvas)
	var v_bottom_c := _world_to_canvas(Vector2(0, screen_bottom), canvas)
	_draw_dashed(canvas, v_top_c, v_bottom_c, Color(0.25, 0.75, 1.0, 0.35), 1.0, 6.0)

	# 4. Safe Zones
	# Top UI Header Safe Area (~14% of screen height)
	var top_ui_h: float = eff_h * 0.14
	var top_ui_bottom_y: float = screen_top + top_ui_h
	var top_ui_tl := tl_c
	var top_ui_br := _world_to_canvas(Vector2(screen_right, top_ui_bottom_y), canvas)
	canvas.draw_rect(Rect2(top_ui_tl, top_ui_br - top_ui_tl), Color(1.0, 0.25, 0.25, 0.08))
	_draw_dashed(canvas, Vector2(tl_c.x, top_ui_br.y), top_ui_br, Color(1.0, 0.35, 0.35, 0.4), 1.0, 4.0)

	# Bottom Queue / Tap Safe Area (~28% of screen height)
	var bot_ui_h: float = eff_h * 0.28
	var bot_ui_top_y: float = screen_bottom - bot_ui_h
	var bot_ui_tl := _world_to_canvas(Vector2(screen_left, bot_ui_top_y), canvas)
	var bot_ui_br := br_c
	canvas.draw_rect(Rect2(bot_ui_tl, bot_ui_br - bot_ui_tl), Color(0.2, 0.85, 0.4, 0.07))
	_draw_dashed(canvas, bot_ui_tl, Vector2(br_c.x, bot_ui_tl.y), Color(0.2, 0.85, 0.4, 0.4), 1.0, 4.0)

	# 5. Route Center Crosshair (0, 0)
	var route_c := _world_to_canvas(Vector2.ZERO, canvas)
	var ch_size := 8.0
	canvas.draw_line(route_c + Vector2(-ch_size, 0), route_c + Vector2(ch_size, 0), Color(1.0, 0.85, 0.2, 0.8), 1.5)
	canvas.draw_line(route_c + Vector2(0, -ch_size), route_c + Vector2(0, ch_size), Color(1.0, 0.85, 0.2, 0.8), 1.5)

	# 6. Text Labels
	var font := ThemeDB.fallback_font
	canvas.draw_string(font, tl_c + Vector2(8, -8), preset_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, frame_col)
	canvas.draw_string(font, tl_c + Vector2(8, 16), "⏳ TOP UI (Timer / Score)", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.4, 0.4, 0.75))
	var mid_label := "--- Screen Middle (H: %d) ---" % int(eff_h)
	canvas.draw_string(font, h_left_c + Vector2(8, -4), mid_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.3, 0.8, 1.0, 0.6))
	canvas.draw_string(font, route_c + Vector2(10, -4), "⭕ Route (0,0)", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.85, 0.2, 0.9))
	canvas.draw_string(font, bot_ui_tl + Vector2(8, 16), "🍎 PLAYER QUEUE / TAP AREA", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.3, 0.9, 0.5, 0.75))


func _draw_dashed(canvas: Control, a: Vector2, b: Vector2,
                   col: Color, w: float = 1.5, dash: float = 9.0) -> void:
	var dir := (b - a)
	var dist := dir.length()
	if dist < 0.001:
		return
	dir = dir / dist
	var t := 0.0
	var on := true
	while t < dist:
		var t2 := minf(t + dash, dist)
		if on:
			canvas.draw_line(a + dir * t, a + dir * t2, col, w)
		t = t2
		on = not on


# ══════════════════════════════════════════════════════════════════════════════
# SECTION 12 — Canvas: Input
# ══════════════════════════════════════════════════════════════════════════════

func on_canvas_input(event: InputEvent, canvas: Control) -> void:
	if not current_config:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_zoom_at(mb.position, canvas, 1.12)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_zoom_at(mb.position, canvas, 1.0 / 1.12)
			MOUSE_BUTTON_MIDDLE:
				if mb.pressed:
					is_panning = true
					pan_start_mouse = mb.position
					pan_start_offset = canvas_pan
				else:
					is_panning = false
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_handle_left_click(mb.position, canvas)
				else:
					is_dragging = false
					selected_is_queue = false
					selected_idx = -1
					is_painting_tile = false
					canvas.queue_redraw()
			MOUSE_BUTTON_RIGHT:
				if mb.pressed:
					_handle_right_click(mb.position, canvas)
				else:
					is_erasing_tile = false
					canvas.queue_redraw()

	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if is_panning:
			canvas_pan = pan_start_offset + (mm.position - pan_start_mouse)
			canvas.queue_redraw()
		elif edit_mode == EditMode.TILES and current_config:
			var mw := _canvas_to_world(mm.position, canvas)
			var g_size: float = current_config.tile_grid_size if current_config.tile_grid_size > 10.0 else 96.0
			var cell := Vector2i(round(mw.x / g_size), round(mw.y / g_size))
			if hover_grid_cell != cell:
				hover_grid_cell = cell
				if is_painting_tile:
					current_config.placed_tiles[cell] = selected_tile_id
					current_config.use_tilemap = true
					if is_instance_valid(use_tilemap_check):
						use_tilemap_check.set_pressed_no_signal(true)
					_mark_dirty()
				elif is_erasing_tile:
					current_config.placed_tiles.erase(cell)
					_mark_dirty()
				canvas.queue_redraw()
		elif is_dragging:
			if selected_is_queue and current_config:
				var world := _canvas_to_world(mm.position, canvas)
				if selected_queue_idx >= 0 and selected_queue_idx < current_config.entry_configs.size():
					current_config.entry_configs[selected_queue_idx].queue_base_position = world
					if selected_queue_idx == current_entry_idx:
						if is_instance_valid(queue_pos_x): queue_pos_x.set_value_no_signal(world.x)
						if is_instance_valid(queue_pos_y): queue_pos_y.set_value_no_signal(world.y)
					_sync_legacy_queue_fields()
					_mark_dirty()
					canvas.queue_redraw()
			elif selected_idx >= 0:
				_move_selected_point(_canvas_to_world(mm.position, canvas))
				canvas.queue_redraw()


func _handle_left_click(mouse: Vector2, canvas: Control) -> void:
	var world := _canvas_to_world(mouse, canvas)

	match edit_mode:
		EditMode.LOOP:
			var hit := _hit_loop_point(mouse, canvas)
			if hit >= 0:
				selected_idx    = hit
				is_dragging     = true
				drag_start_world = world
			else:
				# Add new loop point
				var arr := PackedVector2Array(current_config.loop_points)
				# Insert before closing point if last == first
				if arr.size() > 1 and arr[0].is_equal_approx(arr[-1]):
					arr.insert(arr.size() - 1, world)
				else:
					arr.append(world)
				current_config.loop_points = arr
				selected_idx = arr.size() - 1
				_mark_dirty()

		EditMode.TILES:
			var g_size: float = current_config.tile_grid_size if current_config.tile_grid_size > 10.0 else 96.0
			var cell := Vector2i(round(world.x / g_size), round(world.y / g_size))
			is_painting_tile = true
			current_config.placed_tiles[cell] = selected_tile_id
			current_config.use_tilemap = true
			if is_instance_valid(use_tilemap_check):
				use_tilemap_check.set_pressed_no_signal(true)
			_mark_dirty()
			_update_canvas()

		EditMode.ENTRY:
			if current_config:
				_ensure_entry_configs()
				var hit_q := _hit_entry_queue(mouse, canvas)
				if hit_q >= 0:
					current_entry_idx = hit_q
					selected_queue_idx = hit_q
					selected_is_queue = true
					is_dragging = true
					selected_idx = -1
					_sync_entry_ui_from_current()
					canvas_ctrl.queue_redraw()
					return

				var hit_ep := _hit_entry_point(mouse, canvas)
				if hit_ep >= 0:
					current_entry_idx = hit_ep
					selected_idx = hit_ep
					is_dragging  = true
					_sync_entry_ui_from_current()
				else:
					var idx := current_config.entry_configs.size()
					var ec := EntryConfig.new()
					ec.label = "Entry %d" % (idx + 1)
					ec.entry_point = world
					ec.queue_step = Vector2(0.0, 44.0)
					ec.queue_base_position = world + ec.queue_step
					ec.queue_count = 6
					ec.queue_fruit_indices = PackedInt32Array([0, 1, 2, 3])
					ec.queue_random_fruit = false
					current_config.entry_configs.append(ec)
					current_entry_idx = current_config.entry_configs.size() - 1
					selected_idx = current_entry_idx
					_sync_legacy_queue_fields()
					_refresh_entry_select()
					_mark_dirty()

		EditMode.EXIT:
			if current_config.exit_configs.is_empty():
				_add_exit_config()
			var hit := _hit_exit_point(mouse, canvas)
			if hit >= 0:
				selected_idx = hit
				is_dragging  = true
			else:
				var ecfg := current_config.exit_configs[current_exit_idx]
				var arr  := PackedVector2Array(ecfg.exit_points)
				arr.append(world)
				ecfg.exit_points = arr
				selected_idx = arr.size() - 1
				_mark_dirty()

	canvas_ctrl.queue_redraw()


func _handle_right_click(mouse: Vector2, canvas: Control) -> void:
	match edit_mode:
		EditMode.LOOP:
			var hit := _hit_loop_point(mouse, canvas)
			if hit >= 0:
				var arr := PackedVector2Array(current_config.loop_points)
				arr.remove_at(hit)
				current_config.loop_points = arr
				selected_idx = -1
				_mark_dirty()

		EditMode.TILES:
			var world := _canvas_to_world(mouse, canvas)
			var g_size: float = current_config.tile_grid_size if current_config.tile_grid_size > 10.0 else 96.0
			var cell := Vector2i(round(world.x / g_size), round(world.y / g_size))
			is_erasing_tile = true
			current_config.placed_tiles.erase(cell)
			_mark_dirty()
			_update_canvas()

		EditMode.ENTRY:
			var hit := _hit_entry_point(mouse, canvas)
			if hit >= 0:
				if current_config.entry_configs.size() <= 1:
					push_warning("Level Builder: Cannot delete the only entry point.")
					return
				current_config.entry_configs.remove_at(hit)
				current_entry_idx = clampi(current_entry_idx - 1, 0, current_config.entry_configs.size() - 1)
				selected_idx = -1
				_sync_legacy_queue_fields()
				_refresh_entry_select()
				_mark_dirty()

		EditMode.EXIT:
			if current_config.exit_configs.is_empty():
				return
			var hit := _hit_exit_point(mouse, canvas)
			if hit >= 0:
				var ecfg := current_config.exit_configs[current_exit_idx]
				var arr  := PackedVector2Array(ecfg.exit_points)
				arr.remove_at(hit)
				ecfg.exit_points = arr
				selected_idx = -1
				_mark_dirty()

	canvas_ctrl.queue_redraw()


func _move_selected_point(world: Vector2) -> void:
	match edit_mode:
		EditMode.LOOP:
			if selected_idx >= 0 and selected_idx < current_config.loop_points.size():
				var arr := PackedVector2Array(current_config.loop_points)
				arr[selected_idx] = world
				# Sync closing point
				if arr.size() > 1 and arr[0].is_equal_approx(arr[-1]):
					if selected_idx == 0:
						arr[arr.size() - 1] = world
					elif selected_idx == arr.size() - 1:
						arr[0] = world
				current_config.loop_points = arr
				_mark_dirty()

		EditMode.ENTRY:
			if selected_idx >= 0 and selected_idx < current_config.entry_configs.size():
				current_config.entry_configs[selected_idx].entry_point = world
				_sync_legacy_queue_fields()
				_mark_dirty()

		EditMode.EXIT:
			if current_config.exit_configs.is_empty(): return
			var ecfg := current_config.exit_configs[current_exit_idx]
			if selected_idx >= 0 and selected_idx < ecfg.exit_points.size():
				var arr := PackedVector2Array(ecfg.exit_points)
				arr[selected_idx] = world
				ecfg.exit_points = arr
				_mark_dirty()


func _hit_loop_point(mouse: Vector2, canvas: Control) -> int:
	for i in range(current_config.loop_points.size()):
		if _world_to_canvas(current_config.loop_points[i], canvas).distance_to(mouse) <= 9.0:
			return i
	return -1


func _hit_entry_point(mouse: Vector2, canvas: Control) -> int:
	if not current_config:
		return -1
	_ensure_entry_configs()
	for i in range(current_config.entry_configs.size()):
		var ep: Vector2 = current_config.entry_configs[i].entry_point
		if _world_to_canvas(ep, canvas).distance_to(mouse) <= 9.0:
			return i
	return -1


func _hit_entry_queue(mouse: Vector2, canvas: Control) -> int:
	if not current_config:
		return -1
	_ensure_entry_configs()
	for i in range(current_config.entry_configs.size()):
		var q_pos: Vector2 = current_config.entry_configs[i].queue_base_position
		if _world_to_canvas(q_pos, canvas).distance_to(mouse) <= 16.0:
			return i
	return -1

func _hit_exit_point(mouse: Vector2, canvas: Control) -> int:
	if current_config.exit_configs.is_empty(): return -1
	var ecfg := current_config.exit_configs[current_exit_idx]
	for i in range(ecfg.exit_points.size()):
		if _world_to_canvas(ecfg.exit_points[i], canvas).distance_to(mouse) <= 9.0:
			return i
	return -1


# ══════════════════════════════════════════════════════════════════════════════
# SECTION 13 — Sample level creation (Migration from hardcoded data)
# ══════════════════════════════════════════════════════════════════════════════

func _create_sample_levels() -> void:
	_ensure_levels_dir()

	# ── Level 1 ──────────────────────────────────────────────────────────────
	var l1 := LevelConfig.new()
	l1.level_number      = 1
	l1.title             = "Level 1"
	l1.track_texture     = load("res://Assets/Sprites/Levl1.png")
	l1.route_position    = Vector2(353.18, 821.28)
	l1.route_scale       = Vector2(1.1746, 1.5204)
	l1.route_rotation    = 0.0
	l1.loop_points       = PackedVector2Array([
		Vector2(-21.13, -59.01), Vector2(-218.99, -41.0),
		Vector2(-272.99, 11.0),  Vector2(-259.99, 211.0),
		Vector2(-223.99, 260.0), Vector2(217.0,   260.0),
		Vector2(264.0,   227.0), Vector2(256.0,  -12.0),
		Vector2(189.0,  -48.0),  Vector2(50.38,  -57.04),
		Vector2(-21.13, -59.01),
	])
	l1.speed             = 65.0
	l1.min_gap           = 42.0
	l1.level_time        = 30.0
	l1.entry_points      = PackedVector2Array([Vector2(-21.13, -59.01)])
	l1.has_exit          = false
	l1.queue_count       = 4
	l1.queue_fruit_indices   = PackedInt32Array([0, 1, 2, 3])
	l1.queue_base_position   = Vector2(349.0, 960.0)
	l1.queue_step            = Vector2(0.0, 44.0)
	l1.initial_fruit_indices = PackedInt32Array([2, 3, 4, 5, 6])
	ResourceSaver.save(l1, _LEVELS_DIR + "/level_01.tres")

	# ── Level 2 ──────────────────────────────────────────────────────────────
	var l2 := LevelConfig.new()
	l2.level_number   = 2
	l2.title          = "Level 2"
	l2.track_texture  = load("res://Assets/Sprites/Level2sprite.png")
	l2.route_position = Vector2(360.0, 560.0)
	l2.route_scale    = Vector2(1.35, 1.35)
	l2.route_rotation = 0.0
	l2.loop_points = PackedVector2Array([
		Vector2(0.0,    105.0),  Vector2(-40.18,  97.0),
		Vector2(-74.25,  74.25), Vector2(-97.0,   40.18),
		Vector2(-105.0,   0.0),  Vector2(-97.0,  -40.18),
		Vector2(-74.25, -74.25), Vector2(-40.18, -97.0),
		Vector2(0.0,   -105.0),  Vector2(40.18,  -97.0),
		Vector2(74.25,  -74.25), Vector2(97.0,   -40.18),
		Vector2(105.0,    0.0),  Vector2(97.0,    40.18),
		Vector2(74.25,   74.25), Vector2(40.18,   97.0),
		Vector2(0.0,    105.0),
	])
	l2.speed         = 75.0
	l2.min_gap       = 45.0
	l2.level_time    = 30.0
	l2.entry_points  = PackedVector2Array([Vector2(0.0, 105.0)])
	l2.has_exit      = true
	var e2 := ExitConfig.new()
	e2.label        = "Exit A"
	e2.exit_points  = PackedVector2Array([
		Vector2(0.0, -105.0), Vector2(0.0, -260.0), Vector2(0.0, -500.0)
	])
	e2.assign_rule  = "any"
	l2.exit_configs      = [e2]
	l2.queue_count       = 6
	l2.queue_fruit_indices   = PackedInt32Array([0, 1, 2, 3, 0, 1])
	l2.queue_base_position   = Vector2(360.0, 750.0)
	l2.queue_step            = Vector2(0.0, 44.0)
	l2.initial_fruit_indices = PackedInt32Array([2, 3, 4])
	ResourceSaver.save(l2, _LEVELS_DIR + "/level_02.tres")

	# ── Level 3 ──────────────────────────────────────────────────────────────
	var l3 := LevelConfig.new()
	l3.level_number   = 3
	l3.title          = "Level 3"
	l3.track_texture  = load("res://Assets/Sprites/Levl3_track.png")
	l3.route_position = Vector2(360.0, 560.0)
	l3.route_scale    = Vector2(1.15, 1.15)
	l3.route_rotation = 0.0
	l3.loop_points = PackedVector2Array([
		Vector2(0.0,    160.0),  Vector2(-190.0,  160.0),
		Vector2(-255.0, 105.0),  Vector2(-255.0, -105.0),
		Vector2(-190.0, -160.0), Vector2(0.0,   -160.0),
		Vector2(190.0,  -160.0), Vector2(255.0,  -105.0),
		Vector2(255.0,   105.0), Vector2(190.0,   160.0),
		Vector2(0.0,    160.0),
	])
	l3.speed      = 85.0
	l3.min_gap    = 46.0
	l3.level_time = 30.0
	l3.entry_points = PackedVector2Array([Vector2(0.0, 160.0)])
	l3.has_exit   = true
	var e3 := ExitConfig.new()
	e3.label       = "Exit A"
	e3.exit_points = PackedVector2Array([
		Vector2(0.0, -160.0), Vector2(0.0, -360.0), Vector2(0.0, -550.0)
	])
	e3.assign_rule = "any"
	l3.exit_configs      = [e3]
	l3.queue_count       = 8
	l3.queue_fruit_indices   = PackedInt32Array([0, 1, 2, 3, 0, 1, 2, 3])
	l3.queue_base_position   = Vector2(360.0, 795.0)
	l3.queue_step            = Vector2(0.0, 44.0)
	l3.initial_fruit_indices = PackedInt32Array([2, 3, 4, 5])
	ResourceSaver.save(l3, _LEVELS_DIR + "/level_03.tres")

	_refresh_level_list()
	if EditorInterface.get_resource_filesystem():
		EditorInterface.get_resource_filesystem().scan()


# ══════════════════════════════════════════════════════════════════════════════
# SECTION 14 — Small UI helpers
# ══════════════════════════════════════════════════════════════════════════════

func _make_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	return lbl

func _make_spinbox(mn: float, mx: float, step: float, val: float, min_w: float = 60.0) -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = mn
	sb.max_value = mx
	sb.step      = step
	sb.value     = val
	sb.custom_minimum_size = Vector2(min_w, 0)
	return sb

func _make_tab_btn(text: String, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text    = text
	btn.flat    = false
	btn.pressed.connect(cb)
	return btn

func _add_vsep(parent: Control) -> void:
	parent.add_child(VSeparator.new())

func _make_item_chip(fruit_idx: int, on_delete: Callable) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	var tr := TextureRect.new()
	tr.texture      = _make_fruit_atlas(fruit_idx)
	tr.custom_minimum_size = Vector2(28, 28)
	tr.expand_mode  = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(tr)
	var del := Button.new()
	del.text = "×"
	del.flat = true
	del.custom_minimum_size = Vector2(14, 0)
	del.add_theme_font_size_override("font_size", 10)
	del.pressed.connect(on_delete)
	box.add_child(del)
	return box

