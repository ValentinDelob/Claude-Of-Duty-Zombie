extends AutotestScenario
## @rendu : captures des effets de combat CUBIQUES (VoxelFx, en cours :
## capture à retirer du check une fois les effets livrés).
## @niveau perf : hors check par défaut (captures seulement) ; lancer avec
## sh tools/scenario.sh fx_look.
## BUNKER K-7, face à un mur proche : impacts (béton, métal, bois) en vol
## puis trous de balle ; gerbes et taches de sang ; flamme de bouche d'un
## autre joueur et flamme FPS ; douilles ; explosion de grenade (début,
## boule de feu, fumée, trace au sol) ; explosion d'arme spéciale ; terre
## d'un zombie qui sort du sol. Captures : tests/_out/shots/fx_look_*.png.

var H := AutotestHelpers
var game: Game
var p: Player


func run() -> void:
	timeout_sec = 120
	p = await H.start_solo_game(self, "bunker_k7")
	if p == null:
		return
	game = Game.instance
	game.combat.debug_invulnerable = true
	game.rounds.paused = true
	await H.clear_zombies(self)
	(game.interact.get_obj("power") as PowerSwitch).srv_use(1)
	p.teleport_to(MapData.cell_to_world(Vector2i(35, 31), 0.05))
	# Bandeau « courant rétabli » parti avant les captures.
	await seconds(4.5)
	var wall := _nearest_wall()
	at.check(wall.size() == 2, "mur proche trouvé")
	if wall.size() != 2:
		return
	var hit: Vector3 = wall[0]
	var n: Vector3 = wall[1]
	# Recul à 2 m du mur, regard sur lui.
	var stand := hit + n * 2.0
	p.teleport_to(Vector3(stand.x, p.global_position.y, stand.z))
	await seconds(0.3)
	H.aim_at(p, hit)
	await seconds(0.4)
	var fx := game.fx_root
	var side := n.cross(Vector3.UP).normalized()

	# Impacts : béton, métal, bois (en vol), puis les trous seuls.
	for r in 3:
		for k in 3:
			fx.impact(hit + side * (k - 1) * 0.5 + Vector3.UP * (r - 1) * 0.35, n, false, ["concrete", "metal", "wood"][k])
	await frames(1)
	await at.screenshot("impacts")
	await seconds(1.5)
	for k in 12:
		fx.impact(hit + side * randf_range(-0.6, 0.6) + Vector3.UP * randf_range(-0.4, 0.4), n, false, "concrete")
	await seconds(1.5)
	await at.screenshot("trous")

	# Sang : gerbes en vol, puis taches au sol et au mur.
	var body := hit + n * 1.0
	for k in 3:
		fx.blood_hit(body + side * (k - 1) * 0.3, -n, 1.0)
	await frames(4)
	await at.screenshot("sang")
	fx.blood_decal(Vector3(body.x, Fx.floor_under(body) + 0.05, body.z), Vector3.UP, 1.0)
	fx.blood_decal(hit + side * 0.8, n, 0.6)
	await seconds(1.5)
	await at.screenshot("sang_taches")

	# Flamme d'un autre joueur (vue de côté), douilles en l'air.
	var muzzle := p.camera.global_position + (hit - p.camera.global_position) * 0.5 + side * 0.3
	fx.muzzle_flash(muzzle, side + n * 0.6)
	# Capture : la flamme (0,05 s) tenue le temps de la prise de vue.
	fx._flash_life.fill(0.3)
	for k in 4:
		fx.eject_shell(muzzle + Vector3.UP * 0.1, Vector3(randf_range(-1, 1), 2.2, randf_range(-1, 1)), ["pistol", "rifle", "shotgun", "rifle"][k])
	await frames(1)
	await at.screenshot("flamme_monde")
	await seconds(0.35)
	await at.screenshot("douilles")

	# Flamme FPS (fusil M14 en main, comme le scénario muzzle_flash).
	var pd := game.session.local_data()
	pd.weapons = [WeaponDB.new_instance(WeaponDB.STARTING_WEAPON), WeaponDB.new_instance("m14")]
	pd.slot = 1
	game.session.sync_inventory(1)
	await until(func(): return p.weapons.current().get("id", "") == "m14", 2.0, "M14 en main")
	await seconds(WeaponController.SWITCH_TIME + 0.6)
	p.input.fire = true
	await until(func(): return p.weapons.view._flash_rig.visible, 1.0, "flamme FPS visible")
	await at.screenshot("flamme_fps")
	p.input.fire = false
	await seconds(1.5)

	# Grenade : début, boule de feu, fumée, trace au sol.
	var gpos := body + n * 0.5
	gpos.y = Fx.floor_under(gpos) + 0.05
	H.aim_at(p, gpos + Vector3.UP * 0.6)
	await seconds(0.2)
	game.throwables.explosion_fx(gpos, ThrowableRules.Kind.FRAG)
	await frames(2)
	await at.screenshot("grenade_debut")
	await seconds(0.15)
	await at.screenshot("grenade_feu")
	await seconds(0.5)
	await at.screenshot("grenade_fumee")
	await seconds(2.5)
	await at.screenshot("grenade_trace")

	# Explosion d'arme spéciale (Fx.explosion).
	fx.explosion(gpos + Vector3.UP * 0.3, 2.5)
	await frames(4)
	await at.screenshot("explosion")
	await seconds(2.0)

	# Terre d'un zombie qui sort du sol.
	fx.dirt_burst(Vector3(gpos.x, Fx.floor_under(gpos), gpos.z))
	await seconds(0.12)
	await at.screenshot("emergence")


## Mur le plus proche du joueur (1,5 à 6 m) : [point touché, normale] ou [].
func _nearest_wall() -> Array:
	var space := p.get_world_3d().direct_space_state
	var from := p.camera.global_position
	var best := []
	var best_d := INF
	for i in 16:
		var a := TAU * i / 16.0
		var to := from + Vector3(cos(a), 0.0, sin(a)) * 6.0
		var q := PhysicsRayQueryParameters3D.create(from, to, 1)
		var r := space.intersect_ray(q)
		if r.is_empty():
			continue
		var d := from.distance_to(r.position)
		var nn: Vector3 = r.normal
		if d > 1.5 and d < best_d and absf(nn.y) < 0.2:
			best_d = d
			best = [r.position, nn]
	return best
