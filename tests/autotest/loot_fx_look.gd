extends AutotestScenario
## @rendu : captures du BUTIN au sol (LootFx, LootArc, LootCard ; en cours :
## capture à retirer une fois le butin validé).
## @niveau perf : hors check par défaut (captures seulement) ; lancer avec
## sh tools/scenario.sh loot_fx_look.
## BUNKER K-7, courant rétabli : galerie des cinq raretés, arme légendaire
## qui jaillit d'un corps (suite d'images de l'arc), fiche de l'arme
## regardée, pièces et échantillons qui jaillissent puis filent vers le
## joueur. Captures : tests/_out/shots/loot_fx_look_*.png.

var H := AutotestHelpers
var game: Game
var p: Player


func run() -> void:
	timeout_sec = 150
	p = await H.start_solo_game(self, "bunker_k7")
	if p == null:
		return
	game = Game.instance
	game.combat.debug_invulnerable = true
	game.rounds.paused = true
	await H.clear_zombies(self)
	(game.interact.get_obj("power") as PowerSwitch).srv_use(1)
	p.teleport_to(MapData.cell_to_world(Vector2i(35, 31), 0.05))
	await seconds(4.5)
	var dir := _open_dir()
	var side := dir.cross(Vector3.UP).normalized()
	# Recentré entre les murs (rangée de 3,6 m de large), recul de 1 m.
	var space := p.get_world_3d().direct_space_state
	var mid := p.global_position + dir * 3.2 + Vector3.UP * 0.6
	var dl := _ray(space, mid, -side, 6.0)
	var dr := _ray(space, mid, side, 6.0)
	var shift := clampf((dr - dl) * 0.5, -3.0, 3.0)
	var back_d := _ray(space, p.global_position + Vector3.UP * 0.6, -dir, 6.0)
	p.teleport_to(p.global_position + side * shift - dir * minf(1.0, back_d - 0.6))
	await seconds(0.2)
	var base := p.global_position
	var loot := game.loot
	var pd := game.session.local_data()
	pd.weapons = [WeaponDB.new_instance(WeaponDB.STARTING_WEAPON), GameWeapon.make("mp40", 4, 0)]
	pd.slot = 1
	game.session.sync_inventory(1)

	# 1. Galerie : les cinq raretés côte à côte, à 3 m.
	var ids := ["m1911", "mp40", "ak74u", "ak47", "famas"]
	for r in 5:
		var at := base + dir * 3.2 + side * (r - 2) * 0.75
		at.y = Fx.floor_under(at + Vector3.UP * 0.5)
		loot._cl_spawn(900 + r, 1, at, GameWeapon.make(ids[r], 6 + r * 3, r), at + Vector3.UP * 0.6)
	H.aim_at(p, base + dir * 3.2 + Vector3.UP * 1.3)
	await seconds(2.5)
	await at.screenshot("galerie")
	# Regard sur l'arme épique : sa fiche.
	H.aim_at(p, (loot.drops[902] as LootDrop).card_point())
	await seconds(0.5)
	at.check(loot.looked == loot.drops[902] and loot.card_shown(), "fiche de l'arme regardée")
	await at.screenshot("fiche_epique")
	H.aim_at(p, (loot.drops[904] as LootDrop).card_point())
	await seconds(0.4)
	await at.screenshot("fiche_unique")
	# De loin : faisceaux des légendaire et unique.
	var back := base - dir * clampf(_ray(space, base + Vector3.UP * 0.6, -dir, 8.0) - 0.7, 0.0, 6.0)
	if back.distance_to(base) < 2.0:
		back = base - dir * 0.5
	back.y = base.y
	p.teleport_to(back)
	await seconds(0.2)
	H.aim_at(p, base + dir * 3.2 + Vector3.UP * 1.6)
	await seconds(0.5)
	await at.screenshot("galerie_loin")
	for r in 5:
		loot._cl_remove(900 + r)
	p.teleport_to(base)
	await seconds(0.3)

	# 2. Arme légendaire qui jaillit d'un corps à 2,5 m : suite d'images.
	var corpse := base + dir * 2.6 + side * 0.3
	corpse.y = Fx.floor_under(corpse + Vector3.UP * 0.5)
	H.aim_at(p, corpse + Vector3.UP * 0.4)
	await seconds(0.2)
	var did := loot.srv_drop(1, GameWeapon.make("ak47", 9, LootFx.LEGENDARY), 0, corpse)
	await frames(1)
	var t0 := Time.get_ticks_msec()
	for k in [0.06, 0.16, 0.28, 0.42, 0.6, 0.85, 1.4, 2.5]:
		var wait_ms := int(k * 1000.0) - (Time.get_ticks_msec() - t0)
		if wait_ms > 0:
			await seconds(wait_ms / 1000.0)
		await at.screenshot("arc_%03d" % int(k * 100))
	var d: LootDrop = loot.drops.get(did)
	at.check(d != null and d.global_position.distance_to(corpse) > 0.4, "arme retombée à côté du corps")
	H.aim_at(p, d.card_point())
	await seconds(0.4)
	await at.screenshot("fiche_legendaire")
	loot._cl_remove(did, true)
	await frames(3)
	await at.screenshot("ramassage_legendaire")
	await seconds(1.0)

	# 3. Pièces et échantillons qui jaillissent (chez le joueur seul).
	H.aim_at(p, corpse + Vector3.UP * 0.2)
	loot._send_pops(1, corpse, [[LootPickup.KIND_SAMPLE, {"id": "dog_fang"}], [LootPickup.KIND_SAMPLE, {"id": "nurse_badge"}],
		[LootPickup.KIND_SAMPLE, {"id": "surgeon_heart"}],
		[LootPickup.KIND_PART, {"id": "part_damage", "level": 5, "mods": {"damage": 0.22, "fire_rate": 0.18}}]])
	await seconds(0.25)
	await at.screenshot("objets_vol")
	await seconds(1.6)
	await at.screenshot("objets_poses")
	var pk: LootPickup = loot.pickups[2] if loot.pickups.size() > 2 else null
	if pk:
		H.aim_at(p, pk.card_point())
		await seconds(0.4)
		await at.screenshot("fiche_echantillon")
	var part: LootPickup = loot.pickups[3] if loot.pickups.size() > 3 else null
	if part:
		H.aim_at(p, part.card_point())
		await seconds(0.4)
		await at.screenshot("fiche_piece")
	# On passe dessus : ils filent vers le joueur.
	var n := loot.pickups.size()
	p.teleport_to(Vector3(corpse.x, base.y, corpse.z) - dir * 0.3)
	await seconds(0.2)
	H.aim_at(p, corpse + dir * 2.0)
	await at.screenshot("objets_aspires")
	var ok: bool = await until(func(): return loot.pickups.is_empty(), 4.0, "objets ramassés")
	at.check(ok and n == 4, "quatre objets jaillis puis ramassés (%d)" % n)

	# 4. Coût : même vue sans butin, puis avec 10 armes (deux de chaque rareté).
	p.teleport_to(base)
	H.aim_at(p, base + dir * 3.2 + Vector3.UP * 0.4)
	await seconds(1.0)
	var empty := await _fps(2.0)
	for pass_i in 2:
		for k in 10:
			var at2 := base + dir * (2.6 + floorf(k / 5.0) * 1.2) + side * (k % 5 - 2) * 0.7
			at2.y = Fx.floor_under(at2 + Vector3.UP * 0.5)
			loot._cl_spawn(950 + k, 1, at2, GameWeapon.make(ids[k % 5], 5, k % 5 if pass_i == 1 else 0), at2 + Vector3.UP * 0.6)
		await seconds(2.0)
		var full := await _fps(2.0)
		print("[perf] butin (%s) : %.0f fps sans, %.0f fps avec 10 armes (%.2f ms de plus)" % [
			"toutes raretés" if pass_i == 1 else "communes", empty, full, 1000.0 / full - 1000.0 / empty])
		if pass_i == 1:
			await at.screenshot("dix_armes")
			# Détail : sans lumières, puis sans contour (coque + liseré).
			for d2: LootDrop in loot.drops.values():
				if d2.fx.light:
					(d2.fx.light as Light3D).visible = false
			var nol := await _fps(2.0)
			for d2: LootDrop in loot.drops.values():
				for mi: MeshInstance3D in d2.find_children("*", "MeshInstance3D", true, false):
					mi.material_overlay = null
			var nohull := await _fps(2.0)
			for d2: LootDrop in loot.drops.values():
				for gp: GPUParticles3D in d2.find_children("*", "GPUParticles3D", true, false):
					gp.visible = false
			var nopart := await _fps(2.0)
			print("[perf] détail : sans lumières %.0f fps, + sans contour %.0f fps, + sans particules %.0f fps" % [nol, nohull, nopart])
		for k in 10:
			loot._cl_remove(950 + k)
		await frames(2)


func _fps(sec: float) -> float:
	var f0 := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_usec()
	await seconds(sec)
	return float(Engine.get_frames_drawn() - f0) / ((Time.get_ticks_usec() - t0) / 1e6)


## Distance libre depuis `from` dans la direction `d` (au plus `mx` m).
func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, d: Vector3, mx: float) -> float:
	var r := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + d * mx, 1))
	return mx if r.is_empty() else from.distance_to(r.position)


## Direction horizontale la plus dégagée depuis le joueur.
func _open_dir() -> Vector3:
	var space := p.get_world_3d().direct_space_state
	var from := p.camera.global_position
	var best := Vector3.FORWARD
	var best_d := 0.0
	for i in 16:
		var a := TAU * i / 16.0
		var dv := Vector3(cos(a), 0.0, sin(a))
		var r := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + dv * 12.0, 1))
		var dd := 12.0 if r.is_empty() else from.distance_to(r.position)
		if dd > best_d:
			best_d = dd
			best = dv
	return best
