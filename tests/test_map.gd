extends TestCase

const ROWS := [
	"#####",
	"#.bP#",
	"#..b#",
	"#####",
]


func test_parse_zones_and_markers() -> void:
	var m := MapData.parse(PackedStringArray(ROWS))
	assert_eq(m.width, 5)
	assert_eq(m.height, 4)
	assert_true(m.is_wall(Vector2i(0, 0)))
	assert_true(m.is_floor(Vector2i(1, 1)))
	assert_eq(m.zone_at(Vector2i(1, 1)), "a")
	assert_eq(m.zone_at(Vector2i(2, 1)), "b")
	assert_eq(m.markers["P"], [Vector2i(3, 1)])
	# Le marqueur hérite de la zone voisine majoritaire (b).
	assert_eq(m.zone_at(Vector2i(3, 1)), "b")
	assert_true(m.is_void(Vector2i(9, 9)))


func test_greedy_rects_cover_walls_exactly() -> void:
	var m := MapData.parse(PackedStringArray(ROWS))
	var rects := m.greedy_rects(func(c): return m.is_wall(c))
	var area := 0
	for r in rects:
		area += r.get_area()
	assert_eq(area, 14)
	assert_true(rects.size() <= 4, "fusion efficace (%d rects)" % rects.size())


## Centre d'un bloc de marqueurs (piège 3x3) : zone de la salle, pas « a ».
func test_marker_block_center_inherits_zone() -> void:
	var m := MapData.parse(PackedStringArray([
		"#######",
		"#bbbbb#",
		"#bEEEb#",
		"#bEEEb#",
		"#bEEEb#",
		"#bbbbb#",
		"#######",
	]))
	assert_eq(m.zone_at(Vector2i(3, 3)), "b", "centre du bloc")
	assert_eq(m.zone_at(Vector2i(2, 2)), "b", "coin du bloc")


func test_world_cell_roundtrip() -> void:
	var c := Vector2i(7, 3)
	assert_eq(MapData.world_to_cell(MapData.cell_to_world(c)), c)
