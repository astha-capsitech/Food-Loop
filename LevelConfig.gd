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
## One or more entry positions (sprite-local). Foods enter the loop here.
## Multiple entries are used in round-robin order.
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


## Returns the baked-length progress offset of entry_points[entry_idx] along
## [param curve]. Falls back to 0.0 when no entry points are defined.
func get_entry_progress(curve: Curve2D, entry_idx: int = 0) -> float:
	if entry_points.is_empty():
		return 0.0
	var ep: Vector2 = entry_points[entry_idx % entry_points.size()]
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
