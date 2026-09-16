extends TileMapLayer

## Procedurally builds the branch floor plan. It's a vertical mirror of the
## paper floor-plan reference: a back-office row (Vault / Manager's Office /
## Conference Room / Accounting) runs along the TOP, walled off from one
## open floor below it that holds the Marketing+Loan bullpen, the Teller
## Area, and the Waiting Lounge near the entrance. Mirroring it this way
## puts the entrance at the BOTTOM of the room, matching this project's
## top-down convention of walking in from the south rather than the north.
##
## Each back-office room gets exactly one door gap punched through the
## dividing wall into the open floor below - there's no door system yet
## (see teller_room.gd's doc comment on why every role shares this one
## room), so a gap in the wall tiles is the whole "door": nothing stops
## the player walking through it.
##
## Floor/wall material varies by zone (back-office rooms get a wood floor
## and a maroon-trimmed "office" wall; the open floor keeps the marble
## floor and gold-trimmed "lobby" wall) plus two small accent overlays on
## top of the open floor: a rug under the Waiting Lounge couches, and a
## carpet runner down the Teller queue lane.

const ROOM_WIDTH := 24
const ROOM_HEIGHT := 22
const BACK_OFFICE_ROWS := 7 # y < 7 is back-office interior; y == 7 is the dividing wall

const FLOOR_MARBLE := Vector2i(0, 0)
const WALL_LOBBY := Vector2i(1, 0)
const FLOOR_WOOD := Vector2i(2, 0)
const WALL_OFFICE := Vector2i(3, 0)
const FLOOR_RUG := Vector2i(4, 0)
const FLOOR_RUNNER := Vector2i(5, 0)
const SOURCE_ID := 0

## Column dividers splitting the back-office row into 4 rooms:
## Vault (1-5) | Manager's Office (7-12) | Conference Room (14-18) | Accounting (20-22)
const BACK_OFFICE_DIVIDERS := [6, 13, 19]
## One door gap per back-office room, punched through the row-7 wall.
const BACK_OFFICE_DOORS := [3, 9, 10, 16, 21]
## Main entrance gap in the bottom outer wall.
const ENTRANCE_DOOR_COLUMNS := [11, 12]

## Carpet runner down the Teller queue lane, right under the queue Marker2Ds.
const QUEUE_LANE_COLUMN := 17
const QUEUE_LANE_ROWS := [11, 12, 13, 14, 15, 16]

## Rug under the Waiting Lounge couch cluster.
const RUG_COLUMNS := [4, 5, 6, 7, 8, 9, 10]
const RUG_ROWS := [15, 16, 17, 18, 19]

func _ready() -> void:
	for x in ROOM_WIDTH:
		for y in ROOM_HEIGHT:
			set_cell(Vector2i(x, y), SOURCE_ID, _tile_for(x, y))

func _tile_for(x: int, y: int) -> Vector2i:
	var in_back_office := y <= BACK_OFFICE_ROWS

	var is_outer_edge := x == 0 or x == ROOM_WIDTH - 1 or y == 0 or y == ROOM_HEIGHT - 1
	if is_outer_edge:
		var is_entrance := y == ROOM_HEIGHT - 1 and x in ENTRANCE_DOOR_COLUMNS
		if is_entrance:
			return FLOOR_MARBLE
		return WALL_OFFICE if in_back_office else WALL_LOBBY

	if y < BACK_OFFICE_ROWS:
		return WALL_OFFICE if x in BACK_OFFICE_DIVIDERS else FLOOR_WOOD

	if y == BACK_OFFICE_ROWS:
		return FLOOR_WOOD if x in BACK_OFFICE_DOORS else WALL_OFFICE

	if x == QUEUE_LANE_COLUMN and y in QUEUE_LANE_ROWS:
		return FLOOR_RUNNER

	if x in RUG_COLUMNS and y in RUG_ROWS:
		return FLOOR_RUG

	return FLOOR_MARBLE
