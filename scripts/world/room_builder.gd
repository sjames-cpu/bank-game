extends TileMapLayer

## Fills this TileMapLayer with a simple rectangular room at runtime:
## a ring of wall tiles around the edge, floor tiles everywhere inside.
## Building it in code (instead of hand-painting cells) keeps the
## placeholder layout easy to resize while there's no real level yet.

const ROOM_WIDTH := 12
const ROOM_HEIGHT := 8

const FLOOR_TILE := Vector2i(0, 0)
const WALL_TILE := Vector2i(1, 0)
const SOURCE_ID := 0

func _ready() -> void:
	for x in ROOM_WIDTH:
		for y in ROOM_HEIGHT:
			var is_wall := x == 0 or y == 0 or x == ROOM_WIDTH - 1 or y == ROOM_HEIGHT - 1
			var atlas_coords := WALL_TILE if is_wall else FLOOR_TILE
			set_cell(Vector2i(x, y), SOURCE_ID, atlas_coords)
