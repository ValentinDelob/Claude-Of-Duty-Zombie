extends AutotestScenario
## @rendu : a besoin du rendu (lancé avec fenêtre hors écran par check.sh).
## Zombies modélisés dans Blender (ZombieGlb, assets/models/zombies/) dans le
## hall de KINO : le modèle se charge sur l'ossature du jeu, puis captures de
## face, de profil, gros plan du visage et poses d'animation (marche, course,
## attaque) pour juger le rendu sous l'éclairage du jeu.

var H := AutotestHelpers
var game: Game
var zm: ZombieManager
var cam: Camera3D
var _next_id := 61001
var _shown: Array[Zombie] = []
const STAGE := Vector3(74.0, 2.032, 96.0)


func run() -> void:
	timeout_sec = 180
	ZombieModel.use_model = true
	var m := ZombieGlb.load_model(ZombieModel.MODEL_PATH)
	at.check(not m.is_empty(), "modèle Blender chargé")
	if m.is_empty():
		return
	var mesh: ArrayMesh = m.mesh
	var verts := mesh.surface_get_array_len(0)
	print("[zombie_model_look] sommets : %d, os : %s" % [verts, m.overrides.keys()])
	at.check(m.overrides.size() == RigBuilder.BONES.size(), "toutes les articulations du jeu présentes")
	var p := await H.start_solo_game(self, "kino")
	if p == null:
		return
	game = Game.instance
	zm = game.zombies
	game.combat.debug_invulnerable = true
	game.rounds.paused = true
	for zid in zm.zombies.keys():
		zm.despawn(zid)
	p.teleport_to(STAGE + Vector3(0, 0.05, 6.0), 0.0)
	game.hud.visible = false
	cam = Camera3D.new()
	cam.fov = 50.0
	cam.far = 80.0
	game.add_child(cam)
	cam.make_current()
	var states := [[Zombie.State.IDLE, 0.0, 0], [Zombie.State.CHASE, 1.0, 0], [Zombie.State.CHASE, 1.0, 3], [Zombie.State.ATTACK, 1.0, 1]]
	var row: Array[Zombie] = []
	for i in states.size():
		var s: Array = states[i]
		var z := Zombie.new()
		z.setup(_next_id, i * 7, s[2], false)
		_next_id += 1
		zm.add_child(z)
		z.global_position = STAGE + Vector3((i - 1.5) * 1.1, 0, 0)
		z.state = s[0]
		z._state_time = 0.0
		z.anim_speed = s[1]
		row.append(z)
		_shown.append(z)
	await seconds(0.6)
	for z in row:
		var hy := z.head_position().y - STAGE.y
		at.check(hy > 1.35 and hy < 1.9, "hitbox de tête à hauteur de tête (%.2f m)" % hy)
	cam.look_at_from_position(STAGE + Vector3(0, 1.15, 4.6), STAGE + Vector3(0, 0.95, 0))
	await seconds(0.3)
	await at.screenshot("front")
	for z in row:
		z.rotation.y = PI * 0.5
		z.yaw = PI * 0.5
	await seconds(0.45)
	await at.screenshot("profile")
	for z in row:
		z.rotation.y = 0.0
		z.yaw = 0.0
	var h := row[0].head_position()
	cam.look_at_from_position(h + Vector3(0.3, 0.04, 0.62), h + Vector3(0, -0.04, 0))
	await seconds(0.3)
	await at.screenshot("close")
	cam.look_at_from_position(STAGE + Vector3(1.6, 1.5, 2.4), STAGE + Vector3(0, 1.0, 0))
	await seconds(0.7)
	await at.screenshot("three_quarter")
	for z in _shown:
		z.queue_free()
	p.camera.make_current()
	cam.queue_free()
