extends TestCase
## Cohérence de la carte KINO (Kino der Toten à l'échelle 1, carte en
## maillage décrite par assets/maps/kino/layout.json) : registre et menus,
## réglages de la carte, emplacements de BO1 et leurs zones, plan de l'écran
## de sélection. Données seules (aucune construction de scène) ; le jeu sur la
## carte est vérifié par les scénarios kino_tour, kino_gameplay, kino_theater.

var def: MapDef
var layout: MeshMapLayout


func before_each() -> void:
	def = load(Game.MAP_SCRIPTS["kino"]).new()
	layout = def.create_layout() as MeshMapLayout


func test_registered_in_game_and_menus() -> void:
	assert_true(Game.MAP_SCRIPTS.has("kino"), "KINO enregistrée dans Game.MAP_SCRIPTS")
	assert_false(Game.MAP_SCRIPTS.has("kino_v2"), "plus d'identifiant kino_v2")
	assert_eq(Game.MENU_MAPS, ["bunker_k7", "kino"], "cartes proposées dans les menus")
	assert_eq(def.id, "kino")
	assert_eq(def.display_name, "KINO")
	assert_true(def.description != "", "texte d'accroche")
	assert_true(layout != null, "carte en maillage")
	assert_eq(String(layout.data.get("id", "")), "kino", "description de la carte")
	assert_true(ResourceLoader.exists(layout.glb_path), "architecture construite (%s)" % layout.glb_path)


func test_map_settings() -> void:
	assert_eq(def.music, "ambience_kino", "ambiance sonore du théâtre")
	assert_eq(def.teleport_banner, "SALLE DE PROJECTION")
	assert_true(def.teleporter_link, "téléporteur à relier au poste central")
	assert_eq(def.teleporter_cost, 0, "voyage gratuit")
	assert_eq(def.teleporter_stay, 30.0, "30 s en salle de projection")
	assert_eq(def.teleporter_link_cooldown, 90.0, "90 s de recharge")
	assert_eq(def.look.get("grade"), TheaterLook.GRADE, "étalonnage du théâtre")
	assert_eq(def.look.get("volumetric_albedo"), TheaterLook.DUST_ALBEDO, "poussière du théâtre")


func test_zone_names_cover_every_zone() -> void:
	var zones: Dictionary = layout.data.get("zones", {})
	assert_eq(zones.size(), 10, "10 zones")
	for z in zones:
		assert_true(def.zone_names.has(z), "zone %s nommée" % z)
	for z in def.zone_names:
		assert_true(zones.has(z), "nom %s : zone décrite" % z)
	assert_eq(def.zone_display_name("p"), "Salle de projection")


func test_doors_of_bo1() -> void:
	var costs := {}
	var power := []
	for m in layout.doors():
		assert_eq(m.data.zones.size(), 2, "porte %s relie deux zones %s" % [m.id, m.data.zones])
		for z in m.data.zones:
			assert_true(def.zone_names.has(z), "porte %s : zone %s connue" % [m.id, z])
		if m.data.power:
			power.append(m.id)
		else:
			costs[m.id] = m.data.cost
	power.sort()
	assert_eq(power, ["courant_hall", "courant_salle", "rideau"], "portes ouvertes par le courant")
	assert_eq(costs, {"1": 750, "2": 750, "3": 1000, "4": 1250, "5": 1250, "5b": 1250,
			"6": 1000, "6b": 1000, "7": 1250, "8": 1250}, "prix des portes de BO1")
	# Deux portes depuis le hall, 750 chacune : salle basse et salle haute.
	var from_hall := {}
	for m in layout.doors():
		if "a" in m.data.zones and not m.data.power:
			from_hall[m.data.zones[0] if m.data.zones[1] == "a" else m.data.zones[1]] = m.data.cost
	assert_eq(from_hall, {"b": 750, "e": 750})


func test_wall_buys_of_bo1() -> void:
	# Arsenal mural de Kino der Toten : arme -> [zone, prix].
	var expected := {"olympia": ["a", 500], "m14": ["a", 500], "mpl": ["b", 1000],
			"ak74u": ["c", 1200], "pm63": ["e", 1000], "mp40": ["f", 1000],
			"stakeout": ["f", 1500], "mp5k": ["g", 1000], "m16": ["h", 1200], "bowie": ["t", 3000]}
	var placed := {}
	for m in layout.wall_buys():
		var wid: String = m.data.weapon
		assert_true(WeaponDB.exists(wid) or KnifeDB.exists(wid), "objet %s connu" % wid)
		var cost := KnifeDB.wall_cost(wid) if KnifeDB.exists(wid) else WeaponDB.wall_cost(wid)
		placed[wid] = [m.zone, cost]
	assert_eq(placed, expected, "achats muraux dans leurs zones, prix de BO1")
	var nades := layout.grenade_buys()
	assert_eq(nades.size(), 1, "un achat de grenades")


func test_perks_of_bo1() -> void:
	var placed := {}
	for m in layout.perks():
		assert_true(PerkDB.exists(m.data.perk), "atout %s connu" % m.data.perk)
		placed[m.data.perk] = m.zone
	# Quick Revive (hall), Juggernog (théâtre), Speed Cola (Foyer), Double Tap
	# (ruelle) ; NOVA FLOP et DEADEYE DRAM n'existent pas sur Kino.
	assert_eq(placed, {"lazarus": "a", "titan": "t", "rapid": "f", "twin": "c"})


func test_box_windows_traps() -> void:
	var spots := layout.box_spots()
	assert_eq(spots.size(), 9, "9 emplacements de boîte")
	assert_eq(def.box_starts.size(), 8, "départ tiré parmi 8 emplacements")
	assert_false(1 in def.box_starts, "jamais le balcon du hall au départ")
	for i in def.box_starts:
		assert_true(i >= 0 and i < spots.size(), "départ %d valide" % i)
	var zones := {}
	for m in spots:
		zones[m.zone] = true
	assert_eq(zones.size(), 9, "une boîte par zone accessible (%s)" % str(zones.keys()))
	assert_eq(layout.box_boards().size(), 5, "5 tableaux à la craie")
	var windows := layout.windows()
	assert_eq(windows.size(), 22, "22 fenêtres")
	for w: BarricadeLayout.Opening in windows:
		assert_true(def.zone_names.has(w.zone) and w.zone != "p", "fenêtre %d dans une zone jouable (%s)" % [w.index, w.zone])
		assert_false(w.spawn_points.is_empty(), "fenêtre %d : apparition du dehors" % w.index)
	var traps := layout.traps()
	assert_eq(traps.size(), 5, "5 pièges")
	var fire := 0
	for t in traps:
		assert_true(t.data.has("lever2"), "%s : un levier à chaque bout" % t.id)
		assert_eq(t.data.get("active"), 40.0, "%s : 40 s" % t.id)
		assert_eq(t.data.get("cooldown"), 60.0, "%s : 60 s de recharge" % t.id)
		if t.data.fire:
			fire += 1
	assert_eq(fire, 1, "une fosse à feu")


func test_start_power_teleporter() -> void:
	var starts := layout.player_spawns()
	assert_eq(starts.size(), 4, "4 départs")
	for s in starts:
		assert_eq(layout.zone_at(s), "a", "départ dans le hall")
	assert_eq(layout.player_spawn_yaw(), 0.0, "regard vers la scène (nord)")
	assert_eq(layout.power_switch().zone, "h", "courant dans les coulisses")
	assert_eq(layout.pack_a_punch().zone, "p", "Pack-a-Punch en salle de projection")
	var tp := layout.teleporter()
	assert_eq(layout.zone_at(tp.pad), "t", "pad sur l'avant-scène")
	assert_eq(layout.teleporter_exit_zone(), "p", "arrivée en salle de projection")
	var mf: MapMarker = tp.mainframe
	assert_true(mf != null and mf.data.get("floor", false), "poste central : disque au sol")
	assert_eq(mf.zone, "a", "poste central dans le hall")
	# Apparitions : chaque zone jouable en a (sauf la salle de projection).
	var spawn_zones := {}
	for s in layout.zombie_spawns():
		spawn_zones[s.zone] = true
	for z in def.zone_names:
		assert_eq(spawn_zones.has(z), z != "p", "apparitions de zombies en zone %s" % z)


func test_menu_preview() -> void:
	var img := MapPreview.render(def)
	assert_true(img.get_width() > 300 and img.get_height() > 300, "plan de la carte (%dx%d)" % [img.get_width(), img.get_height()])
	var gold := 0
	var red := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			# Image en 8 bits par canal : couleurs à 1/255 près.
			var c := img.get_pixel(x, y)
			if Vector3(c.r - MapPreview.DOOR.r, c.g - MapPreview.DOOR.g, c.b - MapPreview.DOOR.b).length() < 0.01:
				gold += 1
			elif Vector3(c.r - MapPreview.START.r, c.g - MapPreview.START.g, c.b - MapPreview.START.b).length() < 0.01:
				red += 1
	assert_true(gold > 20, "portes dorées sur le plan (%d)" % gold)
	assert_true(red > 5, "départ entouré de rouge (%d)" % red)
