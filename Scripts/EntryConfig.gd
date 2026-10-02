# EntryConfig.gd
# Defines a single entry point, its entry path, and its fruit queue.
# Stored as a sub-resource inside LevelConfig.
@tool
extends Resource
class_name EntryConfig

## Human-readable label for this entry (e.g. "Entry 1", "Entry 2").
@export var label: String = "Entry 1"

## Loop entry position in sprite-local coordinate space.
@export var entry_point: Vector2 = Vector2.ZERO

## Position of the first queue slot relative to route center.
@export var queue_base_position: Vector2 = Vector2(0.0, 150.0)

## Displacement vector per queue slot (e.g. Vector2(0, 44) = downward line).
@export var queue_step: Vector2 = Vector2(0.0, 44.0)

## Total number of food items in this queue at level start.
@export var queue_count: int = 6

## Fixed sequence of fruit indices for this queue (into FoodTextures.FRUIT_REGIONS).
@export var queue_fruit_indices: PackedInt32Array = []

## When true, each queue slot in this queue is filled with a random fruit.
@export var queue_random_fruit: bool = false
