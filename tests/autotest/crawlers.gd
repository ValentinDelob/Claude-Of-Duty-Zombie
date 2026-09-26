extends AutotestScenario
## Démembrement et RAMPANTS (BO1) dans le vrai jeu : une grenade qui ne tue pas
## arrache les jambes (le zombie devient un rampant : hitboxes couchées, lent,
## se traîne vers le joueur et frappe au ras du sol), tir au bras (l'avant-bras
## tombe), tir à la tête mortel (la tête éclate), explosion mortelle (corps
## déchiqueté), morceaux au sol qui disparaissent, pool borné. Captures.

var H := AutotestHelpers
var game: Game
var p: Player
var pd: PlayerData


func equip(id: String) -> void:
	pd.weapons = [WeaponDB.new_instance(WeaponDB.STARTING_WEAPON), WeaponDB.new_instance(id)]
	pd.slot = 1
	game.combat.cancel_reload(1)
	game.session.sync_inventory(1)
	await until(func(): return p.weapons.current().get("id", "") == id, 2.0, "arme %s en main" % id)
	await seconds(WeaponController.SWITCH_TIME + 0.25)


func pull_trigger() -> void:
	var before: int = p.weapons.current().get("mag", 0)
	p.input.fire = true
	var t := 0.0
	while p.weapons.current().get("mag", 0) == before and t < 0.5:
		await tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	p.input.fire = false
	await seconds(0.25)


func bone_pos(z: Zombie, b: String) -> Vector3:
	return (z.skel.global_transform * z.skel.get_bone_global_pose(z.bones[b])).origin


func run() -> void:
	timeout_sec = 120
	p = await H.start_solo_game(self)
	if p == null:
		return
	game = Game.instance
	pd = game.session.local_data()
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await H.clear_zombies(self)
	var gibs: GibPool = game.fx_root.gibs
	at.check(gibs != null and gibs.active_count() == 0, "pool de morceaux prêt")
	var origin := MapData.cell_to_world(Vector2i(4, 7), 0.05)
	p.teleport_to(origin, -PI * 0.5)
	await seconds(0.3)

	# 1. Grenade qui ne tue pas : jambes arrachées, RAMPANT.
	ZombieGibs.debug_chance = 1.0
	var z := await H.dummy_zombie(self, origin + Vector3(6.5, 0, 0), 4000)
	H.aim_at(p, origin + Vector3(4.5, 0.5, 0))
	p.input.grenade = true
	await seconds(0.3)
	p.input.grenade = false
	await until(func(): return z.health < 4000, 6.0, "explosion de la grenade")
	await seconds(0.05)
	await at.screenshot("grenade_gib")
	at.check(z.is_alive() and z.is_crawler() and (z.gibs & ZombieGibs.LEGS) != 0, "survivant sans jambes : rampant (PV %d, masque %d)" % [z.health, z.gibs])
	at.check(gibs.active_count() >= 2, "les deux jambes tombent (%d morceaux)" % gibs.active_count())
	await seconds(1.2)
	H.aim_at(p, z.global_position + Vector3.UP * 0.3)
	await seconds(0.1)
	await at.screenshot("crawler_down")
	at.check(z.hit_body.global_position.y < 0.45, "hitbox du corps couchée (y %.2f)" % z.hit_body.global_position.y)
	at.check(z.head_position().y < 0.9, "tête au ras du sol (y %.2f)" % z.head_position().y)
	at.check(bone_pos(z, "hips").y < 0.45, "bassin au sol (y %.2f)" % bone_pos(z, "hips").y)

	# 2. Le rampant se traîne vers le joueur, lentement, puis frappe bas.
	z.speed_mult = 1.0
	var start := z.global_position
	await seconds(2.0)
	var moved := Vector2(z.global_position.x - start.x, z.global_position.z - start.z).length()
	at.check(moved > 0.6 and moved < 2.0 * ZombieGibs.CRAWL_SPEED + 0.3, "se traîne à %.2f m/s" % (moved / 2.0))
	p.teleport_to(z.global_position + Vector3(-2.2, 0, 0), -PI * 0.5)
	p.pitch = -0.55
	await seconds(0.6)
	await at.screenshot("crawler_crawl")
	game.combat.debug_invulnerable = false
	var hp0 := pd.health
	var hit: bool = await until(func(): return pd.health < hp0, 8.0, "le rampant frappe")
	at.check(hit, "le rampant frappe le joueur (%d PV)" % pd.health)
	game.combat.debug_invulnerable = true
	await seconds(0.25)
	await at.screenshot("crawler_attack")
	at.check(z.is_crawler() and z.state != Zombie.State.DEAD, "toujours rampant")
	await H.clear_zombies(self)
	await seconds(0.2)

	# 3. Tir au bras (M14 en visée) : l'avant-bras tombe, le zombie reste debout.
	p.teleport_to(origin, -PI * 0.5)
	p.pitch = 0.0
	await equip("m14")
	p.input.aim = true
	await seconds(0.4)
	# 105 dégâts sur 400 PV : plus de 10 % (zombie_should_gib).
	z = await H.dummy_zombie(self, origin + Vector3(4.0, 0, 0), 400)
	z.rotation.y = -PI * 0.5
	z.yaw = -PI * 0.5
	await seconds(0.2)
	var n0 := gibs.active_count()
	# Milieu de l'avant-bras gauche (tendu devant le zombie) ; jusqu'à 5 tirs
	# (dispersion résiduelle en visée), PV remis à 400 : le zombie survit.
	var shots := 0
	while shots < 5 and (z.gibs & (ZombieGibs.ARM_L | ZombieGibs.ARM_R)) == 0:
		shots += 1
		z.health = 400
		var fxf := z.skel.global_transform * z.skel.get_bone_global_pose(z.bones.forearm_l)
		H.aim_at(p, fxf.origin - fxf.basis.y.normalized() * 0.15)
		await pull_trigger()
		await seconds(0.3)
	var arm_off := (z.gibs & (ZombieGibs.ARM_L | ZombieGibs.ARM_R)) != 0
	at.check(arm_off and not z.is_crawler() and z.is_alive(), "tir au bras : avant-bras arraché en %d tir(s) (masque %d, PV %d)" % [shots, z.gibs, z.health])
	at.check(gibs.active_count() > n0, "le bras tombe au sol")
	p.input.aim = false
	await seconds(0.5)
	await at.screenshot("arm_gib")

	# 4. Tir à la tête mortel : la tête éclate (éclats de crâne).
	z.health = 50
	n0 = gibs.active_count()
	H.aim_at(p, z.head_position())
	await pull_trigger()
	at.check(not z.is_alive() and z._headless, "la tête éclate")
	at.check(gibs.active_count() >= mini(n0 + 4, GibPool.MAX_GIBS), "éclats de crâne (%d morceaux)" % gibs.active_count())
	await seconds(0.1)
	await at.screenshot("head_pop")

	# 5. Explosion mortelle : corps déchiqueté.
	var zs := []
	for k in 3:
		zs.append(await H.dummy_zombie(self, origin + Vector3(6.0, 0, (k - 1) * 0.9), 300))
	var t0 := Time.get_ticks_usec()
	game.combat.explosion(1, origin + Vector3(6.0, 0.2, 0), 3.0, 1000, 0)
	var cost := (Time.get_ticks_usec() - t0) / 1000.0
	# Mesure indicative (machine partagée) : les meshes des morceaux sont
	# construits aux images suivantes (GibPool.BUILD_PER_FRAME).
	print("[perf] explosion mortelle, 3 corps déchiquetés : %.2f ms" % cost)
	await seconds(0.1)
	await at.screenshot("death_gibs")
	var torn := 0
	for zz: Zombie in zs:
		if not zz.is_alive() and zz.gibs != 0:
			torn += 1
	at.check(torn == 3, "explosion mortelle : %d/3 corps déchiquetés" % torn)
	at.check(gibs.active_count() <= GibPool.MAX_GIBS, "pool borné (%d/%d)" % [gibs.active_count(), GibPool.MAX_GIBS])
	await seconds(1.5)
	await at.screenshot("gibs_ground")

	# 6. Les morceaux disparaissent après quelques secondes.
	await until(func(): return gibs.active_count() == 0, GibPool.LIFE + 2.0, "morceaux retirés")
	at.check(gibs.active_count() == 0, "plus aucun morceau au sol")

	# 7. Sans chance forcée : une explosion faible (< 10 % des PV) n'arrache rien.
	ZombieGibs.debug_chance = -1.0
	z = await H.dummy_zombie(self, origin + Vector3(5.0, 0, 0), 20000)
	game.combat.explosion(1, origin + Vector3(5.0, 0.2, 0), 3.0, 1000, 0)
	await seconds(0.2)
	at.check(z.gibs == 0 and not z.is_crawler(), "coup trop faible : aucun démembrement")
	await H.clear_zombies(self)
