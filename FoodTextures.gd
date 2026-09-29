# FoodTextures.gd
# Manages slicing and distribution of fruit sprites from the spritesheet.
extends RefCounted
class_name FoodTextures

const SPRITESHEET_PATH: String = "res://Assets/Sprites/sprite-vegetable-fruit-animation-sprite-removebg-preview.png"

# Bounding boxes for the 10 fruits in the spritesheet
const FRUIT_REGIONS: Array[Rect2] = [
	Rect2(8, 0, 97, 112),     # 0: Apple (Red)
	Rect2(141, 11, 119, 104), # 1: Orange
	Rect2(295, 7, 104, 104),  # 2: Plum / Blueberry (Purple)
	Rect2(453, 3, 110, 111),  # 3: Peach
	Rect2(10, 120, 113, 167), # 4: Pineapple
	Rect2(179, 139, 101, 145),# 5: Pear
	Rect2(318, 155, 136, 109),# 6: Banana
	Rect2(1, 293, 131, 149),  # 7: Grape
	Rect2(167, 333, 140, 82),  # 8: Lemon
	Rect2(345, 309, 124, 127) # 9: Watermelon
]

static var _sheet_texture: Texture2D = null
static var _atlas_textures: Array[AtlasTexture] = []

static func _ensure_textures() -> void:
	if _atlas_textures.is_empty():
		_sheet_texture = load(SPRITESHEET_PATH) as Texture2D
		for region: Rect2 in FRUIT_REGIONS:
			var atlas: AtlasTexture = AtlasTexture.new()
			atlas.atlas = _sheet_texture
			atlas.region = region
			_atlas_textures.append(atlas)

static func get_fruit_texture(index: int) -> AtlasTexture:
	_ensure_textures()
	return _atlas_textures[index % _atlas_textures.size()]

static func get_random_texture() -> AtlasTexture:
	_ensure_textures()
	return _atlas_textures[randi() % _atlas_textures.size()]

static func get_total_fruit_types() -> int:
	return FRUIT_REGIONS.size()

const DEFAULT_FRUIT_SIZES: Array[float] = [
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

static func get_default_fruit_size(index: int) -> float:
	return DEFAULT_FRUIT_SIZES[index % DEFAULT_FRUIT_SIZES.size()]

const FRUIT_NAMES: Array[String] = [
	"Apple", "Orange", "Plum", "Peach", "Pineapple",
	"Pear", "Banana", "Grape", "Lemon", "Watermelon"
]

const FRUIT_COLORS: Array[Color] = [
	Color(1.0, 0.25, 0.25, 0.95),   # 0: Apple (Red)
	Color(1.0, 0.55, 0.1, 0.95),    # 1: Orange (Orange)
	Color(0.7, 0.3, 0.95, 0.95),    # 2: Plum (Purple)
	Color(1.0, 0.6, 0.65, 0.95),    # 3: Peach (Peach)
	Color(0.95, 0.78, 0.15, 0.95),  # 4: Pineapple (Golden)
	Color(0.65, 0.92, 0.25, 0.95),  # 5: Pear (Lime Green)
	Color(1.0, 0.92, 0.08, 0.95),   # 6: Banana (Yellow)
	Color(0.58, 0.18, 0.85, 0.95),  # 7: Grape (Deep Purple)
	Color(0.92, 1.0, 0.2, 0.95),    # 8: Lemon (Neon Yellow)
	Color(1.0, 0.32, 0.45, 0.95)    # 9: Watermelon (Red/Pink)
]

static func get_fruit_color(index: int) -> Color:
	if index >= 0 and index < FRUIT_COLORS.size():
		return FRUIT_COLORS[index]
	return Color(0.2, 0.9, 0.4, 0.9) # Default Neon Green for "any" (-1)

static func get_fruit_name(index: int) -> String:
	if index >= 0 and index < FRUIT_NAMES.size():
		return FRUIT_NAMES[index]
	return "Any"
