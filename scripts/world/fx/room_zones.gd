extends Node2D
class_name RoomZones

## Subtle floor tints that tell the branch's areas apart (tellers, loans,
## the vault room, the manager's office), drawn over the floor tiles but
## under all furniture and characters, plus a small sign for each zone.
## Tints are kept faint on purpose: characters and furniture must still
## stand out. Zones are data (ZONES, in tiles of the room's TileMapLayer).
## Add it as a child of the room's TileMapLayer: it then draws right after
## the tiles, behind everything else in the room.

const TILE: int = 32

## name, floor area in tiles (interior only, never walls), tint, and where
## the sign's text sits (bottom-centre, in world pixels).
const ZONES: Array[Dictionary] = [
	{"name": "VAULT", "tiles": Rect2i(1, 1, 5, 6), "tint": Color(0.55, 0.68, 0.95, 0.16), "sign": Vector2(64, 252)},
	{"name": "MANAGER", "tiles": Rect2i(7, 1, 6, 6), "tint": Color(0.95, 0.72, 0.3, 0.14), "sign": Vector2(256, 252)},
	{"name": "LOANS", "tiles": Rect2i(1, 8, 11, 7), "tint": Color(0.75, 0.6, 0.95, 0.13), "sign": Vector2(208, 272)},
	{"name": "TELLERS", "tiles": Rect2i(13, 8, 10, 10), "tint": Color(0.45, 0.85, 0.7, 0.13), "sign": Vector2(560, 272)},
]

func _draw() -> void:
	for zone in ZONES:
		var tiles: Rect2i = zone["tiles"]
		var tint: Color = zone["tint"]
		draw_rect(Rect2(Vector2(tiles.position * TILE), Vector2(tiles.size * TILE)), tint, true)

## Puts each zone's sign on `parent` (a y-sorted layer, so characters pass
## in front of a sign that hangs over the floor).
static func add_signs(parent: Node2D) -> Array[WallSign]:
	var signs: Array[WallSign] = []
	for zone in ZONES:
		var at: Vector2 = zone["sign"]
		var zone_name: String = zone["name"]
		signs.append(WallSign.create(parent, zone_name, at))
	return signs
