extends RefCounted
## Explicit campaign street plans. Collision and rendering share these parcels.
static var layouts: Array = []
const ORIGIN = Vector2(22,140)
const CELL = Vector2(31,32)
static func for_stage(number: int) -> Dictionary:
	if layouts.is_empty(): layouts = JSON.parse_string(FileAccess.get_file_as_string("res://game/arena_layouts.json"))
	return layouts[clampi(number-1,0,99)]
static func rectangle(parcel: Dictionary) -> Rect2:
	return Rect2(ORIGIN+Vector2(parcel.x,parcel.y)*CELL,Vector2(parcel.w,parcel.h)*CELL)
static func center(cell: Array) -> Vector2:
	return ORIGIN+(Vector2(cell[0],cell[1])+Vector2(0.5,0.5))*CELL
