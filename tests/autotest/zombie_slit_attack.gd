extends AutotestScenario
## @couvre scripts/game/zombies/zombie.gd scripts/game/map/mesh_nav.gd
## Joueur réfugié au fond d'une fente de 0,72 m (trop étroite pour le navmesh,
## érodé de 0,4 m ; assez large pour lui, 0,35 m de rayon), enfoncé de 1,6 m,
## bien au-delà de Zombie.ATTACK_RANGE depuis la bouche : le zombie, parti de
## biais, doit entrer et frapper. Près du joueur (Zombie.SLIM_RANGE) ou quand
## le chemin n'arrive pas à portée, la ligne droite est permise dès que le
## TRONC passe ; une fente plus étroite que le tronc reste fermée
## (zombie_corridors, « fente »).

const MAP_ID := "fente_attaque"
const ROOM := 12.0
## Fente : deux barrières invisibles (bloc_invisible, hors de la grille du
## validateur, qui ne voit qu'un goulot de 1 m), 0,72 m libres entre elles,
## SLIT_LEN de long depuis le mur nord ; bouche à y = SLIT_LEN.
const SLIT := 0.72
const SLIT_LEN := 2.5
## Largeur de chaque barrière (de cx ± SLIT/2 vers l'extérieur).
const SIDE := 1.0
const DEPTH_IN := 1.6
## Axe de la fente : deux cases libres de 0,5 m pour le validateur (goulot,
## pas d'erreur ; centres des cases sur les multiples de 0,5 m).
const SLIT_X := 6.25

var H := AutotestHelpers


static func slit_map() -> EditorMap:
	var doc := EditorMap.blank(MAP_ID, "FENTE", "SLIT")
	var zid := String(doc.add_zone("Salle", "Room").id)
	doc.pieces.append({"id": doc.new_id("p"), "nom": "Salle", "altitude": 0, "zone": zid,
		"contour": [[0, 0], [ROOM, 0], [ROOM, ROOM], [0, ROOM]]})
	doc.depart = zid
	var cx := SLIT_X
	for s in [-1.0, 1.0]:
		var x0: float = cx + s * SLIT * 0.5
		var x1: float = cx + s * (SLIT * 0.5 + SIDE)
		doc.objets.append({"id": doc.new_id("i"), "type": "bloc_invisible", "altitude": 0,
			"sommets": [[x0, 0.0], [x1, 0.0], [x1, SLIT_LEN], [x0, SLIT_LEN]]})
	doc.objets.append({"id": "s1", "type": "depart", "altitude": 0, "position": [3.0, 10.0]})
	doc.objets.append({"id": "b1", "type": "boite", "altitude": 0, "position": [ROOM - 2.25, ROOM], "mur": "s", "depart": true})
	doc.ouvertures.append({"id": "o1", "type": "fenetre", "altitude": 0, "position": [2.25, ROOM]})
	return doc


static func w3(x: float, y: float, h := 0.0) -> Vector3:
	return Vector3(x + MapGeom.WORLD_OFFSET, h, y + MapGeom.WORLD_OFFSET)


func run() -> void:
	timeout_sec = 90
	var doc := slit_map()
	var v := MapRaster.build(doc).v
	v.analyze()
	for e in v.errors():
		at.fail("carte d'essai : " + String(e.fr))
	if doc.save_dir(EditorMap.map_dir(MAP_ID)) != OK:
		at.fail("carte d'essai non enregistrée")
		return
	var p := await H.start_solo_game(self, EditorMapDef.CUSTOM_PREFIX + MAP_ID)
	if p == null:
		return
	var game := Game.instance
	game.rounds.paused = true
	await H.clear_zombies(self)
	var nav := game.nav as MeshNav
	at.check(nav != null, "carte en maillage")
	if nav == null:
		return
	var cx := SLIT_X
	# Largeur libre mesurée (couche du décor, à 1,1 m du sol) : la fente est bien là.
	var space := game.get_world_3d().direct_space_state
	var q := PhysicsPointQueryParameters3D.new()
	q.collision_mask = 1 | Barricade.BARRIER_LAYER
	var free := 0.0
	for k in 101:
		q.position = w3(cx - 0.5 + k * 0.01, SLIT_LEN - DEPTH_IN, 1.1)
		if space.intersect_point(q, 1).is_empty():
			free += 0.01
	at.check(absf(free - SLIT) < 0.05, "fente de %.2f m libres" % free)
	at.check(not nav.is_walkable(w3(cx, SLIT_LEN - DEPTH_IN)), "navmesh hors de la fente")
	p.teleport_to(w3(cx, SLIT_LEN - DEPTH_IN, 0.05))
	await seconds(0.3)
	var pd := game.session.local_data()
	var hp := pd.health
	var zid := game.zombies.spawn(nav.closest_point(w3(cx + 2.5, 8.0)), RoundRules.WALK, 100000, ZombieManager.KIND_ZOMBIE)
	var z := game.zombies.get_zombie(zid)
	await H.emerged(self, [z])
	var hit: bool = await until(func(): return pd.health < hp or pd.life != PlayerData.Life.ALIVE, 25.0, "joueur dans la fente attaqué")
	var zp := z.global_position if is_instance_valid(z) else Vector3.INF
	at.check(hit, "joueur enfoncé de %.1f m dans une fente de %.2f m : attaqué (zombie en %s)" % [DEPTH_IN, SLIT, zp])
	game.combat.debug_invulnerable = true
	await H.clear_zombies(self)
