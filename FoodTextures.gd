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
