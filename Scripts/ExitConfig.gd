# ExitConfig.gd
# Defines a single exit path for a level in Food Circle Loop.
# Stored as a sub-resource inside LevelConfig.
@tool
extends Resource
class_name ExitConfig

## Human-readable label for this exit (e.g. "Exit A", "Top Exit").
@export var label: String = "Exit A"

## Points along the exit path in sprite-local coordinate space.
## The first point is the loop trigger; subsequent points form the off-screen path.
@export var exit_points: PackedVector2Array = []

## Routing rule that decides which player fruits use this exit.
## "any"         — any player fruit that reaches this exit point uses it.
## "fruit_type"  — future: only a specific fruit type routes here.
## "entry_match" — future: fruit from the matching entry routes here.
## "random"      — future: fruits are randomly assigned to exits.
@export_enum("any", "fruit_type", "entry_match", "random")
var assign_rule: String = "any"

## Target fruit type index for this exit (-1 = Any Fruit).
## 0: Apple, 1: Orange, 2: Plum, 3: Peach, 4: Pineapple,
## 5: Pear, 6: Banana, 7: Grape, 8: Lemon, 9: Watermelon.
@export var target_fruit_type: int = -1
