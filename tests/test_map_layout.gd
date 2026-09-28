extends TestCase
## MapLayout sur les cartes grille : mêmes emplacements, identifiants et
## bloqueurs que la lecture directe de la grille (MapData, MapDef).


func _layout(id: String) -> GridMapLayout:
	var def: MapDef = load(Game.MAP_SCRIPTS[id]).new()
	var layout := def.create_layout() as GridMapLayout
	assert_true(layout != null, "%s : carte grille" % id)
	return layout


func test_counts_match_grid_markers() -> void:
	for id in ["bunker_k7", "test_arena"]:
		var l := _layout(id)
		var m := l.data.markers
		assert_eq(l.player_spawns().size(), m.get("P", []).size(), "%s : départs des joueurs" % id)
		assert_eq(l.zombie_spawns().size(), m.get("Z", []).size(), "%s : apparitions" % id)
		assert_eq(l.box_spots().size(), m.get("X", []).size(), "%s : emplacements de boîte" % id)
		assert_eq(l.traps().size(), m.get("H", []).size(), "%s : un piège par levier" % id)
		assert_eq(l.windows().size(), BarricadeLayout.analyze(l.data).size(), "%s : fenêtres" % id)
		var n_doors := 0
		for d in l.def.doors:
			n_doors += MapDef.group_cells(m.get(d, [])).size()
		assert_eq(l.doors().size(), n_doors, "%s : portes" % id)
		assert_eq(l.start_zone(), "a")


func test_markers_on_the_floor_facing_a_wall() -> void:
	var l := _layout("bunker_k7")
	for list in [l.wall_buys(), l.perks(), l.box_spots(), l.grenade_buys()]:
		for mk: MapMarker in list:
			assert_near(mk.pos.y, 0.0, 0.001, "%s au sol" % mk.id)
			assert_near(mk.wall.length(), 1.0, 0.001, "%s : direction du mur unitaire" % mk.id)
			assert_true(l.data.is_wall(mk.cell + Vector2i(roundi(mk.wall.x), roundi(mk.wall.z))), "%s contre un mur" % mk.id)
			assert_eq(l.zone_at(mk.pos), l.data.zone_at(mk.cell), "%s : zone" % mk.id)
	var ids := []
	for mk in l.wall_buys():
		ids.append(mk.id)
	assert_true("R" in ids and "V" in ids, "identifiants des achats muraux = marqueurs")
	for mk in l.grenade_buys():
		assert_eq(mk.id, "%d_%d" % [mk.cell.x, mk.cell.y], "identifiant réseau des grenades inchangé")


func test_doors_and_blockers() -> void:
	var l := _layout("bunker_k7")
	l.create_nav()
	var nav := l.nav as NavGrid
	for d in l.doors():
		assert_eq(d.block, "door_" + d.id)
		assert_eq(d.data.zones.size(), 2, "porte %s entre deux zones" % d.id)
		var c: Vector2i = d.data.cells[0]
		assert_false(nav.is_walkable(c), "porte %s fermée au départ" % d.id)
		l.set_blocked(d.block, false)
		assert_true(nav.is_walkable(c), "porte %s ouverte" % d.id)
		assert_true(l.is_walkable_at(MapData.cell_to_world(c)))


func test_windows_neutral_fields() -> void:
	var l := _layout("bunker_k7")
	for w: BarricadeLayout.Opening in l.windows():
		assert_eq(w.pos, MapData.cell_to_world(w.cell), "fenêtre %d : position" % w.index)
		assert_eq(w.inward_dir, Vector3(w.inward.x, 0, w.inward.y))
		assert_eq(w.spawn_points.size(), w.spawns.size())
		assert_eq(w.seed, hash(w.cell), "planches identiques à avant")


func test_teleporter_and_exit_zone() -> void:
	var l := _layout("bunker_k7")
	var tp := l.teleporter()
	assert_false(tp.is_empty(), "BUNKER K-7 : téléporteur")
	assert_true(tp.mainframe == null, "pas de poste central sur une carte grille (le A du bunker est un achat mural)")
	assert_eq(l.teleporter_exit_zone(), "p", "arrivée dans la salle du rituel")
	assert_eq(l.zone_at(tp.exit), "p")


func test_box_teddy_bear_odds_like_bo1() -> void:
	assert_near(MysteryBox.skull_chance(3, 0), 0.0, 0.001, "rien avant le 4e tirage")
	assert_near(MysteryBox.skull_chance(4, 0), 0.15, 0.001, "15 % du 4e au 7e")
	assert_near(MysteryBox.skull_chance(7, 3), 0.15, 0.001)
	assert_near(MysteryBox.skull_chance(8, 0), 1.0, 0.001, "départ forcé au 8e si jamais parti")
	assert_near(MysteryBox.skull_chance(8, 1), 0.3, 0.001, "30 % du 8e au 12e")
	assert_near(MysteryBox.skull_chance(13, 2), 0.5, 0.001, "50 % ensuite")
