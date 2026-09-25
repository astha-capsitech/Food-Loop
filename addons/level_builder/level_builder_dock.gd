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
const _GAMEPLAY_SCENE := "res://Gameplay.tscn"

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

enum EditMode { LOOP, ENTRY, EXIT }

# ─── State ────────────────────────────────────────────────────────────────────
var current_config: LevelConfig = null
var current_file_path: String   = ""
var is_dirty: bool              = false

var edit_mode: EditMode = EditMode.LOOP
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
var exit_select: OptionButton
var exit_label_edit: LineEdit
var rule_select: OptionButton
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
var selected_is_queue: bool = false
var file_dialog: EditorFileDialog
var confirm_dialog: ConfirmationDialog
var _pending_delete_path: String = ""


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
	entry_btn = _make_tab_btn("Entry", func(): _set_mode(EditMode.ENTRY))
	exit_btn  = _make_tab_btn("Exit",  func(): _set_mode(EditMode.EXIT))
	tab_bar.add_child(loop_btn)
	tab_bar.add_child(entry_btn)
	tab_bar.add_child(exit_btn)

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
	route_pos_x.value_changed.connect(func(v): if current_config: current_config.route_position.x = v; _mark_dirty())
	row2.add_child(route_pos_x)
	route_pos_y = _make_spinbox(-3000.0, 3000.0, 1.0, 640.0, 50.0)
	route_pos_y.value_changed.connect(func(v): if current_config: current_config.route_position.y = v; _mark_dirty())
	row2.add_child(route_pos_y)

	row2.add_child(_make_label("  Scale:"))
	route_scale_x = _make_spinbox(0.05, 10.0, 0.01, 1.0, 45.0)
	route_scale_x.value_changed.connect(func(v): if current_config: current_config.route_scale.x = v; _mark_dirty())
	row2.add_child(route_scale_x)
	route_scale_y = _make_spinbox(0.05, 10.0, 0.01, 1.0, 45.0)
	route_scale_y.value_changed.connect(func(v): if current_config: current_config.route_scale.y = v; _mark_dirty())
	row2.add_child(route_scale_y)

	# Row 3: Auto Circle Generator
	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 6)
	loop_settings_box.add_child(row3)
	row3.add_child(_make_label("⭕ Circle Generator — Radius:"))
	var radius_spin := _make_spinbox(10.0, 1000.0, 1.0, 105.0, 50.0)
	row3.add_child(radius_spin)
	row3.add_child(_make_label("  Points:"))
	var count_spin := _make_spinbox(6.0, 64.0, 1.0, 16.0, 45.0)
	row3.add_child(count_spin)
	var make_circle_btn := Button.new()
	make_circle_btn.text = "✨ Generate Circle Loop"
	make_circle_btn.pressed.connect(func() -> void:
		_generate_circle_loop(radius_spin.value, int(count_spin.value))
	)
	row3.add_child(make_circle_btn)


func _generate_circle_loop(radius: float = 105.0, count: int = 16) -> void:
	if not current_config:
		return
	var pts := PackedVector2Array()
	for i in range(count):
		var angle: float = (float(i) / float(count)) * TAU
		var x: float = -radius * sin(angle)
		var y: float = radius * cos(angle)
		pts.append(Vector2(snappedf(x, 0.01), snappedf(y, 0.01)))
	pts.append(pts[0])
	current_config.loop_points = pts
	_mark_dirty()
	_update_canvas()


func _build_entry_settings(parent: Control) -> void:
	entry_settings_box = VBoxContainer.new()
	entry_settings_box.add_theme_constant_override("separation", 4)
	parent.add_child(entry_settings_box)

	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 6)
	entry_settings_box.add_child(row1)

	row1.add_child(_make_label("Queue Pos:"))
	queue_pos_x = _make_spinbox(-3000.0, 3000.0, 1.0, 360.0, 55.0)
	queue_pos_x.value_changed.connect(func(v: float) -> void:
		if current_config:
			current_config.queue_base_position.x = v
			_mark_dirty()
			_update_canvas()
	)
	row1.add_child(queue_pos_x)

	queue_pos_y = _make_spinbox(-3000.0, 3000.0, 1.0, 950.0, 55.0)
	queue_pos_y.value_changed.connect(func(v: float) -> void:
		if current_config:
			current_config.queue_base_position.y = v
			_mark_dirty()
			_update_canvas()
	)
	row1.add_child(queue_pos_y)

	row1.add_child(_make_label("  Step:"))
	queue_step_x = _make_spinbox(-500.0, 500.0, 1.0, 0.0, 45.0)
	queue_step_x.value_changed.connect(func(v: float) -> void:
		if current_config:
			current_config.queue_step.x = v
			_mark_dirty()
			_update_canvas()
	)
	row1.add_child(queue_step_x)

	queue_step_y = _make_spinbox(-500.0, 500.0, 1.0, 44.0, 45.0)
	queue_step_y.value_changed.connect(func(v: float) -> void:
		if current_config:
			current_config.queue_step.y = v
			_mark_dirty()
			_update_canvas()
	)
	row1.add_child(queue_step_y)

	var align_btn := Button.new()
	align_btn.text = "🎯 Align to Entry"
	align_btn.pressed.connect(_auto_align_queue_to_entry)
	row1.add_child(align_btn)

	var lbl := Label.new()
	lbl.text = "Entry: Click to place Entry points. Drag the 🔵 [Q] circle on canvas to position the Queue."
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

	var hint := Label.new()
	hint.text = "Exit mode: click canvas to add exit path points.  Right-click to delete."
	hint.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	exit_settings_box.add_child(hint)


func _build_right_panel(parent: Control) -> void:
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(185, 0)
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
	queue_count_spin.value_changed.connect(func(v): if current_config: current_config.queue_count = int(v); _mark_dirty())
	ql_bar.add_child(queue_count_spin)

	var rand_bar := HBoxContainer.new()
	vb.add_child(rand_bar)
	randomize_check = CheckBox.new()
	randomize_check.text = "Randomize queue"
	randomize_check.toggled.connect(_on_randomize_toggled)
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
	_block_signals(true)
	timer_spin.value      = current_config.level_time
	speed_spin.value      = current_config.speed
	gap_spin.value        = current_config.min_gap
	randomize_check.button_pressed = current_config.queue_random_fruit
	queue_count_spin.value = float(current_config.queue_count)
	has_exit_check.button_pressed  = current_config.has_exit
	route_pos_x.value   = current_config.route_position.x
	route_pos_y.value   = current_config.route_position.y
	route_scale_x.value = current_config.route_scale.x
	route_scale_y.value = current_config.route_scale.y
	current_config.route_rotation = 0.0

	if is_instance_valid(queue_pos_x): queue_pos_x.value = current_config.queue_base_position.x
	if is_instance_valid(queue_pos_y): queue_pos_y.value = current_config.queue_base_position.y
	if is_instance_valid(queue_step_x): queue_step_x.value = current_config.queue_step.x
	if is_instance_valid(queue_step_y): queue_step_y.value = current_config.queue_step.y

	if current_config.track_texture and current_config.track_texture.resource_path:
		sprite_name_lbl.text = current_config.track_texture.resource_path.get_file()
	else:
		sprite_name_lbl.text = "(none)"

	_block_signals(false)
	_refresh_exit_select()
	_refresh_queue_display()
	_refresh_initial_display()
	_update_mode_settings_visibility()


func _block_signals(blocked: bool) -> void:
	for node in [timer_spin, speed_spin, gap_spin, randomize_check,
	             queue_count_spin, has_exit_check,
	             route_pos_x, route_pos_y, route_scale_x,
	             route_scale_y,
	             queue_pos_x, queue_pos_y, queue_step_x, queue_step_y]:
		if is_instance_valid(node):
			node.set_block_signals(blocked)


func _auto_align_queue_to_entry() -> void:
	if not current_config:
		return
	if current_config.entry_points.is_empty():
		return
	var ep0: Vector2 = current_config.entry_points[0]
	var step_offset := current_config.queue_step
	if step_offset.length_squared() < 0.001:
		step_offset = Vector2(0.0, 44.0)
	current_config.queue_base_position = current_config.route_position + ep0 + step_offset
	_sync_ui_from_config()
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
	else:
		current_exit_idx = clampi(current_exit_idx, 0, current_config.exit_configs.size() - 1)
		exit_select.select(current_exit_idx)
		exit_label_edit.text = current_config.exit_configs[current_exit_idx].label
		var rule := current_config.exit_configs[current_exit_idx].assign_rule
		for i in range(rule_select.item_count):
			if rule_select.get_item_text(i) == rule:
				rule_select.select(i)
				break


func _add_exit_config() -> void:
	if not current_config:
		return
	var letters := "ABCDEFGHIJKLMNOP"
	var idx := current_config.exit_configs.size()
	var ecfg := ExitConfig.new()
	ecfg.label = "Exit %s" % letters[idx % letters.length()]
	ecfg.assign_rule = "any"
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
		var arr := PackedInt32Array(current_config.queue_fruit_indices)
		arr.append(idx)
		current_config.queue_fruit_indices = arr
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
	for i in range(current_config.queue_fruit_indices.size()):
		var fi := current_config.queue_fruit_indices[i]
		queue_flow.add_child(_make_item_chip(fi, func(): _remove_queue_item(i)))


func _remove_queue_item(i: int) -> void:
	if not current_config:
		return
	var arr := PackedInt32Array(current_config.queue_fruit_indices)
	arr.remove_at(i)
	current_config.queue_fruit_indices = arr
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

	# Sprite
	if current_config.track_texture:
		var tex: Texture2D = current_config.track_texture
		var tsz: Vector2 = tex.get_size() * canvas_zoom
		var center: Vector2 = canvas.size * 0.5 + canvas_pan
		var tpos: Vector2 = center - tsz * 0.5
		canvas.draw_texture_rect(tex, Rect2(tpos, tsz), false, Color(1, 1, 1, 0.88))

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

	# Entry points
	for i in range(current_config.entry_points.size()):
		var ep := _world_to_canvas(current_config.entry_points[i], canvas)
		var selected := (edit_mode == EditMode.ENTRY and i == selected_idx)
		# Triangle arrow pointing right (entry marker)
		var tri := PackedVector2Array([
			ep + Vector2(-8, -9), ep + Vector2(-8, 9), ep + Vector2(10, 0)
		])
		canvas.draw_polygon(tri,
			[Color(1.0, 0.6, 0.0) if not selected else Color.YELLOW,
			 Color(1.0, 0.6, 0.0) if not selected else Color.YELLOW,
			 Color(1.0, 0.6, 0.0) if not selected else Color.YELLOW])
		canvas.draw_string(ThemeDB.fallback_font, ep + Vector2(13, -4),
			"E%d" % i, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.7, 0.3))

	# Exit paths
	if current_config.has_exit:
		for ei in range(current_config.exit_configs.size()):
			var ecfg: ExitConfig = current_config.exit_configs[ei]
			var ecol := Color(1.0, 0.35, 0.35, 0.9) if ei == current_exit_idx else Color(0.8, 0.5, 0.5, 0.6)
			var pts  := ecfg.exit_points
			for j in range(pts.size()):
				var cp := _world_to_canvas(pts[j], canvas)
				var sel := (edit_mode == EditMode.EXIT and ei == current_exit_idx and j == selected_idx)
				canvas.draw_circle(cp, 6.0 if sel else 4.0, Color.YELLOW if sel else ecol)
				if j < pts.size() - 1:
					_draw_dashed(canvas, cp, _world_to_canvas(pts[j + 1], canvas), ecol)
			if pts.size() >= 1:
				canvas.draw_string(ThemeDB.fallback_font,
					_world_to_canvas(pts[0], canvas) + Vector2(8, -4),
					ecfg.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ecol)

	# Queue visual preview
	if current_config:
		var q_count: int = current_config.queue_count
		var q_indices := current_config.queue_fruit_indices
		var sheet := _get_sheet()

		# Queue base position relative to route center
		var q_base_rel: Vector2 = current_config.queue_base_position - current_config.route_position
		var q_base_canvas: Vector2 = _world_to_canvas(q_base_rel, canvas)

		# Draw queue connector line
		if q_count > 1:
			var p0_canvas: Vector2 = q_base_canvas
			var p_last_canvas: Vector2 = q_base_canvas + current_config.queue_step * canvas_zoom * float(q_count - 1)
			canvas.draw_line(p0_canvas, p_last_canvas, Color(0.2, 0.7, 1.0, 0.45), 2.0)

		for qi in range(q_count):
			var slot_canvas: Vector2 = q_base_canvas + current_config.queue_step * canvas_zoom * float(qi)

			var fruit_idx: int = 0
			if q_indices.size() > 0:
				fruit_idx = q_indices[qi % q_indices.size()]

			var is_first: bool = (qi == 0)
			var q_radius: float = clampf(14.0 * canvas_zoom, 7.0, 18.0)

			var bg_col := Color(0.2, 0.8, 1.0, 0.95) if (is_first and selected_is_queue) else (Color(0.2, 0.6, 1.0, 0.8) if is_first else Color(0.15, 0.35, 0.65, 0.6))
			canvas.draw_circle(slot_canvas, q_radius + 2.0, bg_col)

			if sheet and fruit_idx >= 0 and fruit_idx < _FRUIT_REGIONS.size():
				var f_rect: Rect2 = _FRUIT_REGIONS[fruit_idx] as Rect2
				var draw_sz := (q_radius * 2.0)
				var dest_rect := Rect2(slot_canvas - Vector2(draw_sz * 0.5, draw_sz * 0.5), Vector2(draw_sz, draw_sz))
				canvas.draw_texture_rect_region(sheet, dest_rect, f_rect)

			if is_first:
				canvas.draw_string(ThemeDB.fallback_font, slot_canvas + Vector2(q_radius + 5.0, 4.0),
					"Queue [Q]", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.35, 0.85, 1.0))

	# Coordinate readout at origin
	var orig := _world_to_canvas(Vector2.ZERO, canvas)
	canvas.draw_circle(orig, 3.0, Color(0.4, 0.4, 0.9, 0.6))

	# Mode hint
	var hint := ""
	match edit_mode:
		EditMode.LOOP:  hint = "Loop — LClick: add point | Drag: move | RClick: delete | Scroll: zoom | MClick: pan"
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
					canvas.queue_redraw()
			MOUSE_BUTTON_RIGHT:
				if mb.pressed:
					_handle_right_click(mb.position, canvas)

	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if is_panning:
			canvas_pan = pan_start_offset + (mm.position - pan_start_mouse)
			canvas.queue_redraw()
		elif is_dragging:
			if selected_is_queue and current_config:
				var world := _canvas_to_world(mm.position, canvas)
				current_config.queue_base_position = current_config.route_position + world
				if is_instance_valid(queue_pos_x): queue_pos_x.set_value_no_signal(current_config.queue_base_position.x)
				if is_instance_valid(queue_pos_y): queue_pos_y.set_value_no_signal(current_config.queue_base_position.y)
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

		EditMode.ENTRY:
			if current_config:
				var q_base_rel: Vector2 = current_config.queue_base_position - current_config.route_position
				var q0_canvas: Vector2 = _world_to_canvas(q_base_rel, canvas)
				if q0_canvas.distance_to(mouse) <= 16.0:
					selected_is_queue = true
					is_dragging = true
					selected_idx = -1
					canvas_ctrl.queue_redraw()
					return

			var hit := _hit_entry_point(mouse, canvas)
			if hit >= 0:
				selected_idx = hit
				is_dragging  = true
			else:
				var arr := PackedVector2Array(current_config.entry_points)
				arr.append(world)
				current_config.entry_points = arr
				selected_idx = arr.size() - 1
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

		EditMode.ENTRY:
			var hit := _hit_entry_point(mouse, canvas)
			if hit >= 0:
				var arr := PackedVector2Array(current_config.entry_points)
				arr.remove_at(hit)
				current_config.entry_points = arr
				selected_idx = -1
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
			if selected_idx >= 0 and selected_idx < current_config.entry_points.size():
				var arr := PackedVector2Array(current_config.entry_points)
				arr[selected_idx] = world
				current_config.entry_points = arr
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
	for i in range(current_config.entry_points.size()):
		if _world_to_canvas(current_config.entry_points[i], canvas).distance_to(mouse) <= 9.0:
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

