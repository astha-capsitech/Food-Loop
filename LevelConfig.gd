# LevelConfig.gd
# Resource-based level configuration for Food Circle Loop.
# Each level is persisted as a .tres file under res://Levels/.
# No level data should ever be hardcoded in GDScript — use the Level Builder editor plugin.
@tool
extends Resource
class_name LevelConfig

@export var level_number: int = 1
@export var title: String = "New Level"

## Track sprite rendered behind the loop path.
@export var track_texture: Texture2D

# ─── Route Transform ─────────────────────────────────────────────────────────
@export_group("Route Transform")
## World position of the Sprite2D (route) node in Gameplay.tscn.
@export var route_position: Vector2 = Vector2(360.0, 640.0)
## Scale applied to the Sprite2D.
@export var route_scale: Vector2 = Vector2.ONE
## Rotation applied to the Sprite2D (radians).
@export var route_rotation: float = 0.0

# ─── Loop Path ───────────────────────────────────────────────────────────────
@export_group("Loop Path")
## Ordered points that define the closed food loop (sprite-local coordinates).
@export var loop_points: PackedVector2Array = []
## Food movement speed along the loop (pixels/second, sprite-local).
@export var speed: float = 70.0
## Minimum progress-distance between an existing food and the entry point
## before a new entry is considered a collision.
@export var min_gap: float = 44.0

# ─── Timer ───────────────────────────────────────────────────────────────────
@export_group("Timer")
## Countdown seconds the player has to clear this level.
@export var level_time: float = 30.0

# ─── Entry / Exit ─────────────────────────────────────────────────────────────
@export_group("Entry and Exit")
## Ordered list of entry configurations. Each holds an entry point, approach path, and queue.
@export var entry_configs: Array[EntryConfig] = []
## Legacy entry positions (sprite-local). Maintained for backwards compatibility.
@export var entry_points: PackedVector2Array = []
## Whether this level has at least one exit path.
@export var has_exit: bool = false
## Ordered list of exit path configurations.
## Each ExitConfig holds the exit path points and routing rule.
@export var exit_configs: Array[ExitConfig] = []

# ─── Fruit Queue ──────────────────────────────────────────────────────────────
@export_group("Fruit Queue")
## Fixed sequence of fruit indices (into FoodTextures.FRUIT_REGIONS) for the player queue.
## Ignored when queue_random_fruit is true.
@export var queue_fruit_indices: PackedInt32Array = []
## When true each queue slot is filled with a random fruit; queue_fruit_indices is ignored.
@export var queue_random_fruit: bool = false
## Total number of food items in the player queue at level start.
@export var queue_count: int = 6
## World position of the first queue slot (Sprite2D world space).
@export var queue_base_position: Vector2 = Vector2(360.0, 950.0)
## Offset applied per queue slot (e.g. Vector2(0, 44) = vertical stack downward).
@export var queue_step: Vector2 = Vector2(0.0, 44.0)

# ─── Initial Circulating ─────────────────────────────────────────────────────
@export_group("Initial Circulating")
## Fruit indices for obstacle foods already circulating when the level starts.
## The number of obstacles equals this array's size.
@export var initial_fruit_indices: PackedInt32Array = []

# ─── Fruit Sizes ─────────────────────────────────────────────────────────────
@export_group("Fruit Sizes")
## Target display sizes (in pixels) for each of the 10 fruit types.
## If empty or not set, DEFAULT_FRUIT_SIZES are used automatically.
@export var fruit_sizes: PackedFloat32Array = []

const DEFAULT_FRUIT_SIZES: PackedFloat32Array = [
	44.0, # 0: Apple
	42.0, # 1: Orange
	34.0, # 2: Plum / Blueberry
	40.0, # 3: Peach
	48.0, # 4: Pineapple
	42.0, # 5: Pear
	44.0, # 6: Banana
	36.0, # 7: Grape
	34.0, # 8: Lemon
	50.0  # 9: Watermelon
]


# ─── Helpers ─────────────────────────────────────────────────────────────────

## Returns a Curve2D built from loop_points, auto-closing the loop if the
## last point differs from the first.
func get_loop_curve() -> Curve2D:
	var curve := Curve2D.new()
	for p: Vector2 in loop_points:
		curve.add_point(p)
	if loop_points.size() > 0 and loop_points[0] != loop_points[-1]:
		curve.add_point(loop_points[0])
	return curve


## Returns all entry configurations.
## If entry_configs is empty, synthesizes default EntryConfig(s) from legacy fields
## to guarantee 100% backward compatibility with existing level resources.
func get_entry_configs() -> Array[EntryConfig]:
	if not entry_configs.is_empty():
		return entry_configs

	var synthesized: Array[EntryConfig] = []
	if not entry_points.is_empty():
		for i in range(entry_points.size()):
			var ec := EntryConfig.new()
			ec.label = "Entry %d" % (i + 1)
			ec.entry_point = entry_points[i]
			ec.queue_step = queue_step
			ec.queue_count = queue_count
			ec.queue_fruit_indices = queue_fruit_indices
			ec.queue_random_fruit = queue_random_fruit
			ec.queue_base_position = queue_base_position - route_position if i == 0 else entry_points[i] + queue_step
			synthesized.append(ec)
	else:
		var ec := EntryConfig.new()
		ec.label = "Entry 1"
		ec.entry_point = Vector2.ZERO
		ec.queue_step = queue_step
		ec.queue_count = queue_count
		ec.queue_fruit_indices = queue_fruit_indices
		ec.queue_random_fruit = queue_random_fruit
		ec.queue_base_position = queue_base_position - route_position
		synthesized.append(ec)
	return synthesized


## Returns the baked-length progress offset of entry_configs[entry_idx] along
## [param curve]. Falls back to 0.0 when no entry points are defined.
func get_entry_progress(curve: Curve2D, entry_idx: int = 0) -> float:
	var cfgs := get_entry_configs()
	if cfgs.is_empty():
		return 0.0
	var ep: Vector2 = cfgs[entry_idx % cfgs.size()].entry_point
	return curve.get_closest_offset(ep)


## Returns the baked-length progress offset of the first point of
## exit_configs[exit_idx] along [param curve].
## Returns -1.0 when this level has no exit or the index is out of range.
func get_exit_progress(curve: Curve2D, exit_idx: int = 0) -> float:
	if not has_exit or exit_configs.is_empty():
		return -1.0
	if exit_idx >= exit_configs.size():
		return -1.0
	var cfg: ExitConfig = exit_configs[exit_idx]
	if cfg.exit_points.is_empty():
		return -1.0
	return curve.get_closest_offset(cfg.exit_points[0])


## Returns the target display size (in pixels) for the given fruit type index.
## Falls back safely to DEFAULT_FRUIT_SIZES for legacy levels where fruit_sizes is empty.
func get_fruit_size(index: int) -> float:
	if fruit_sizes.size() > index and fruit_sizes[index] > 0.0:
		return fruit_sizes[index]
	if index >= 0 and index < DEFAULT_FRUIT_SIZES.size():
		return DEFAULT_FRUIT_SIZES[index]
	return 42.0
