extends AutotestScenario
## Lunette (L96A1, Dragunov ; lunette courte de l'AUG) : écran de lunette
## affiché et arme masquée, zoom fort, balancement lent de la visée,
## respiration retenue avec [Maj] (quelques secondes, puis souffle), tir
## précis au centre du réticule, retour à la vue normale.

var H := AutotestHelpers
var game: Game
var p: Player
var pd: PlayerData
var _dir := Vector3.ZERO
var _hit := Vector3.ZERO


func equip(id: String) -> void:
	pd.weapons = [WeaponDB.new_instance(WeaponDB.STARTING_WEAPON), WeaponDB.new_instance(id)]
	pd.slot = 1
	game.combat.cancel_reload(1)
	game.session.sync_inventory(1)
	await until(func(): return p.weapons.current().get("id", "") == id, 2.0, "arme %s en main" % id)
	await seconds(WeaponController.SWITCH_TIME + 0.25)


## Amplitude (°) du décalage de visée sur `dur` secondes.
func sway_amp(dur: float) -> float:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var t := 0.0
	while t < dur:
		var o := p.weapons.aim_offset()
		lo = Vector2(minf(lo.x, o.x), minf(lo.y, o.y))
		hi = Vector2(maxf(hi.x, o.x), maxf(hi.y, o.y))
		await tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	return rad_to_deg((hi - lo).length())


func run() -> void:
	timeout_sec = 120
	p = await H.start_solo_game(self)
	if p == null:
		return
	game = Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await H.clear_zombies(self)
	pd = game.session.local_data()
	p.weapons.fired.connect(func():
		_dir = p.aim_direction()
		if not p.weapons.last_impacts.is_empty():
			_hit = p.weapons.last_impacts[0][0])
	p.teleport_to(MapData.cell_to_world(Vector2i(2, 3), 0.05), -PI * 0.5)
	await seconds(0.4)
	var eye := p.camera.global_position
	# Zombie immobile à ~18 m, pour la capture et le tir.
	var z := await H.dummy_zombie(self, Vector3(eye.x + 18.0, 0.0, eye.z), 100000)

	await equip("l96a1")
	var s := WeaponDB.stats("l96a1")
	H.aim_at(p, z.head_position())
	await seconds(0.2)
	await at.screenshot("hip_l96a1")
	p.input.aim = true
	await seconds(0.15)
	at.check(not p.weapons.scoped, "mise en joue progressive (pas de lunette instantanée)")
	await seconds(float(s.ads_time) + 0.3)
	at.check(p.weapons.scoped and game.hud.scope.visible and game.hud.scope.kind == "sniper", "écran de lunette affiché")
	at.check(not p.weapons.view.model.visible, "arme masquée dans la lunette")
	at.check(absf(p.camera.fov - float(s.scope_fov)) < 0.3, "zoom de la lunette : %.1f° (champ normal %.0f°)" % [p.camera.fov, Settings.fov])
	at.check(p.weapons.ads_look_mult() < 0.3, "sensibilité réduite dans la lunette (x%.2f)" % p.weapons.ads_look_mult())
	# Balancement libre, puis respiration retenue.
	var free := await sway_amp(2.0)
	await at.screenshot("scope_l96a1")
	p.input.sprint = true
	await seconds(0.5)
	at.check(p.weapons.feel.holding, "respiration retenue avec [Maj]")
	var held := await sway_amp(1.5)
	at.check(free > 0.25 and held < free * 0.25, "balancement %.2f° libre, %.2f° souffle retenu" % [free, held])
	# Tir souffle retenu : l'impact est au centre du réticule.
	# Visée au torse : la tête d'un zombie immobile oscille (animation d'attente)
	# et, à 18 m, la moindre image lente la faisait sortir du réticule.
	H.aim_at(p, z.hit_body.global_position)
	await seconds(0.25)
	var before := z.health
	_hit = Vector3.ZERO
	p.input.fire = true
	await until(func(): return _hit != Vector3.ZERO, 1.0, "tir parti")
	p.input.fire = false
	await until(func(): return z.health < before, 1.0, "dégâts appliqués")
	var center_pt := p.camera.global_position + _dir * p.camera.global_position.distance_to(_hit)
	at.check(_hit != Vector3.ZERO and _hit.distance_to(center_pt) < 0.01, "impact au centre du réticule (%.3f m)" % _hit.distance_to(center_pt))
	at.check(z.health < before, "zombie touché à 18 m dans la lunette (%d -> %d PV)" % [before, z.health])
	await at.screenshot("scope_l96a1_fire")
	# Souffle épuisé : la respiration relâche seule, balancement accru.
	await until(func(): return not p.weapons.feel.holding, ShotFeel.HOLD_TIME + 0.5, "souffle épuisé")
	at.check(not p.weapons.feel.holding and p.weapons.feel.gasp > 0.0, "souffle épuisé après %.0f s : respiration relâchée" % ShotFeel.HOLD_TIME)
	var gasp := await sway_amp(1.0)
	at.check(gasp > free * 0.9, "balancement accru en reprenant son souffle (%.2f°)" % gasp)
	p.input.sprint = false
	p.input.aim = false
	await seconds(0.5)
	at.check(not p.weapons.scoped and not game.hud.scope.visible and p.weapons.view.model.visible, "sortie de la lunette : arme visible")
	at.check(absf(p.camera.fov - Settings.fov) < 2.0, "champ de vision rétabli (%.1f°)" % p.camera.fov)

	# Dragunov : lunette plus large.
	await equip("dragunov")
	H.aim_at(p, z.head_position())
	p.input.aim = true
	await seconds(float(WeaponDB.stats("dragunov").ads_time) + 0.5)
	at.check(p.weapons.scoped and absf(p.camera.fov - 15.0) < 0.3, "Dragunov : lunette x%.1f (%.1f°)" % [Settings.fov / p.camera.fov, p.camera.fov])
	await at.screenshot("scope_dragunov")
	p.input.aim = false
	await seconds(0.4)

	# AUG : lunette courte (anneau), sans balancement.
	await equip("aug")
	H.aim_at(p, z.head_position())
	p.input.aim = true
	await seconds(float(WeaponDB.stats("aug").ads_time) + 0.5)
	at.check(p.weapons.scoped and game.hud.scope.kind == "optic", "AUG : lunette courte")
	var aug_sway := await sway_amp(1.0)
	at.check(aug_sway < 0.01, "AUG : pas de balancement (%.3f°)" % aug_sway)
	await at.screenshot("scope_aug")
	p.input.aim = false
	await seconds(0.3)
