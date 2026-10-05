extends AutotestScenario
## @couvre scripts/editor/map_raster.gd scripts/editor/map_validator.gd scripts/editor/map_vertical.gd scripts/editor/map_layout_export.gd scripts/game/map/mesh_nav.gd scripts/game/zombies/zombie.gd
## Niveaux libres (étape 1b, tests/test_levels_free.gd : split_hall) : une
## halle haute de 9,5 m avec deux mezzanines (3,5 et 7 m) et, collé à l'est,
## un demi-niveau à 1,5 m relié par une rampe à travers le mur commun. Un
## zombie qui court rejoint le joueur sur le demi-niveau (il monte la rampe),
## puis sur la mezzanine de 7 m (il prend l'escalier qui saute le niveau
## 3,5 m : le seul chemin).

const Free := preload("res://tests/test_levels_free.gd")
const MAP_ID := "halle_demi_niveau"
## Repère du jeu = repère de l'éditeur + 4,25 m (MapLayoutExport).
const OFF := 4.25

var H := AutotestHelpers
var game: Game
var nav: MeshNav
var p: Player
var doc: EditorMap


func run() -> void:
	timeout_sec = 300
	doc = Free.split_hall()
	doc.carte["id"] = MAP_ID
	var dir := EditorMap.map_dir(MAP_ID)
	if doc.save_dir(dir) != OK:
		at.fail("carte d'essai non enregistrée dans " + dir)
		return
	p = await H.start_solo_game(self, EditorMapDef.CUSTOM_PREFIX + MAP_ID)
	if p == null:
		return
	game = Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await H.clear_zombies(self)
	nav = game.nav as MeshNav
	at.check(nav != null and nav.lanes.size() == 3, "un couloir d'ancres par escalier (%d)" % (nav.lanes.size() if nav else 0))
	if nav == null or not await until(func(): return nav.ensure_anchors(), 5.0, "ancres posées"):
		return
	for l in nav.lanes:
		at.check(l.ok, "%s : ancres sur le navmesh %s" % [l.name, l.problem])
	# Demi-niveau (1,5 m), puis mezzanine de 7 m (escalier qui saute 3,5 m).
	await chase(Vector2(36.0, 8.0), 1.5, "le demi-niveau à 1,5 m (rampe à travers le mur)")
	await chase(Vector2(20.0, 3.0), 7.0, "la mezzanine à 7 m (escalier qui saute le niveau 3,5 m)")
	game.combat.debug_invulnerable = false


## Point du monde au-dessus de (x, y) de l'éditeur, à l'altitude `alt`.
func world(x: float, y: float, alt: float) -> Vector3:
	return Vector3(x + OFF, alt, y + OFF)


## Joueur posé en `at_xy` à l'altitude `alt` ; un zombie qui court part du sol
## de la halle et le rejoint (2,5 m), en passant par cette altitude.
func chase(at_xy: Vector2, alt: float, label: String) -> void:
	p.teleport_to(world(at_xy.x, at_xy.y, alt) + Vector3.UP * 0.05)
	await seconds(0.5)
	at.check(absf(p.global_position.y - alt) < 0.35, "%s : joueur posé (y %.2f)" % [label, p.global_position.y])
	var z := game.zombies.get_zombie(game.zombies.spawn(nav.closest_point(world(3.0, 8.0, 0.0)), RoundRules.SPRINT, 100000))
	await H.emerged(self, [z])
	var t0 := GameClock.now()
	var top := [0.0]
	var ok: bool = await until(func():
		if is_instance_valid(z):
			top[0] = maxf(top[0], z.global_position.y)
		return is_instance_valid(z) and z.global_position.distance_to(p.global_position) < 2.5, 90.0, "zombie sur " + label)
	at.check(ok, "zombie qui court arrivé sur %s en %.1f s" % [label, GameClock.now() - t0])
	at.check(top[0] > alt - 0.4, "%s : le zombie est monté à %.2f m (attendu %.1f)" % [label, top[0], alt])
	await H.clear_zombies(self)
