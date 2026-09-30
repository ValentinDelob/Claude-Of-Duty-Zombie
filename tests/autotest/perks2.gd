extends AutotestScenario
## Atouts de Five / Ascension (BO1) sur BUNKER K-7 : NOVA FLOP (PhD Flopper)
## et DEADEYE DRAM (Deadshot Daiquiri).
## * NOVA FLOP : achat (2000), aucun dégât d'une grenade gardée en main (qui
##   tue pourtant le zombie voisin), plongeon en sprint qui explose à
##   l'atterrissage et tue des zombies de la manche 10 (50 points chacun),
##   rien sans l'atout.
## * DEADEYE DRAM : achat (1500), la visée s'aimante vers la tête du zombie
##   le plus proche du centre (rien sans l'atout), dispersion en hanche et
##   recul réduits.
## Captures : les deux machines, l'explosion du plongeon, la visée, les icônes.

var H := AutotestHelpers
var game: Game
var p: Player
var pd: PlayerData
var booms: Array = []
var _kick := 0.0
var _pitch0 := 0.0

## Laboratoire : allée dégagée (ligne 23, x 33 à 52).
const LAB_ROW := 23


func buy(marker: String) -> PerkMachine:
	var m: PerkMachine = game.interact.get_obj("perk_" + marker)
	p.teleport_to(m.interact_point() + Vector3(0, -1.15, 0))
	H.aim_at(p, m.global_position + Vector3.UP * 1.3)
	await seconds(0.3)  # mise en joue après le téléport
	p.input.interact_pressed = true
	await until(func(): return pd.has_perk(m.perk_id), 2.0, "atout %s acheté" % m.perk_id)
	return m


## Fin de la boisson (délai du contrôleur et animation de la vue).
func drink_done() -> bool:
	return GameClock.now() >= p.weapons._drink_end and not p.weapons.view.is_drinking()


## Vue de la machine à 3,2 m, de face.
func shoot_machine(m: PerkMachine, shot: String) -> void:
	var back := m.global_position - m.interact_point()
	back.y = 0.0
	p.teleport_to(m.global_position - back.normalized() * 3.2 + Vector3(0, 0.05, 0))
	H.aim_at(p, m.global_position + Vector3.UP * 1.2)
	await seconds(0.6)  # capture : image posée après le téléport
	await at.screenshot(shot)


func lab(x: float, z: float) -> Vector3:
	return Vector3(x, 0.05, z)


## Sprint vers +X dans le laboratoire puis plongeon ; retourne le point d'atterrissage.
func sprint_dive() -> Vector3:
	p.input.crouch = false
	p.teleport_to(lab(34.5, LAB_ROW + 0.5), -PI * 0.5)
	p.pitch = 0.0
	await seconds(0.3)  # posé après le téléport avant de courir
	p.input.move = Vector2(0, 1)
	p.input.sprint = true
	await seconds(0.45)  # élan du sprint (touche tenue)
	p.input.crouch = true
	await until(func(): return p.diving, 0.5, "plongeon déclenché")
	await until(func(): return not p.diving, 1.5, "atterrissage")
	var landed := p.global_position
	p.input.move = Vector2.ZERO
	p.input.sprint = false
	await seconds(0.05)  # touches relâchées
	return landed


## Zombies immobiles (santé de la manche 10) autour du point d'atterrissage
## prévu, hors de la trajectoire du plongeon.
func ring_of_zombies() -> Array:
	var hp := RoundRules.zombie_health(10)
	var out := []
	for pos in [lab(41.5, 21.5), lab(41.0, 25.6), lab(42.6, 25.3)]:
		var zid := game.zombies.spawn(pos, 0, hp)
		game.zombies.get_zombie(zid).speed_mult = 0.0
		out.append(game.zombies.get_zombie(zid))
	await H.emerged(self, out)
	return out


func alive_count(list: Array) -> int:
	var n := 0
	for z: Zombie in list:
		if is_instance_valid(z) and z.is_alive():
			n += 1
	return n


func aim_error(z: Zombie) -> float:
	return rad_to_deg(p.aim_direction().angle_to(z.head_position() - p.camera.global_position))


func run() -> void:
	timeout_sec = 180
	p = await H.start_solo_game(self, "bunker_k7")
	if p == null:
		return
	game = Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	pd = game.session.local_data()
	for id in game.doors:
		game.doors[id].srv_open()
	(game.interact.get_obj("power") as PowerSwitch).srv_use(1)
	game.throwables.exploded.connect(func(kind: int, pos: Vector3, pid: int): booms.append([kind, pos, pid]))
	await seconds(0.8)  # portes (collisions différées) et courant posés avant les captures

	# ------------------------------------------------ machines
	var nova: PerkMachine = game.interact.get_obj("perk_(")
	var dead: PerkMachine = game.interact.get_obj("perk_)")
	at.check(nova != null and nova.perk_id == "nova" and dead != null and dead.perk_id == "deadeye", "machines NOVA FLOP et DEADEYE DRAM sur la carte")
	if nova == null or dead == null:
		return
	at.check(game.map_data.zone_at(MapData.world_to_cell(nova.global_position)) == "c", "NOVA FLOP au laboratoire")
	await shoot_machine(nova, "nova_machine")
	await shoot_machine(dead, "deadeye_machine")

	# ------------------------------------------------ sans l'atout : rien
	var zs := await ring_of_zombies()
	await sprint_dive()
	await seconds(0.4)  # rien à attendre : on vérifie qu'aucune explosion n'a lieu
	at.check(alive_count(zs) == 3, "sans NOVA FLOP : le plongeon n'explose pas")
	await H.clear_zombies(self)
	p.input.crouch = false
	await seconds(0.8)  # le joueur se relève du plongeon

	# ------------------------------------------------ achat NOVA FLOP
	game.session.add_points(1, 10000 - pd.points)
	await until(func(): return pd.points == 10000, 2.0, "points crédités")
	await buy("(")
	at.check(pd.has_perk("nova") and pd.points == 8000, "NOVA FLOP acheté 2000 (points %d)" % pd.points)
	await until(drink_done, 4.0, "fin de la boisson NOVA FLOP")

	# Grenade gardée en main : explose, tue le voisin, aucun dégât au joueur.
	game.combat.debug_invulnerable = false
	pd.grenades = 2
	pd.health = pd.max_health
	game.session.sync_stats(1)
	p.teleport_to(lab(36.5, 24.5), -PI * 0.5)
	p.pitch = 0.0
	await seconds(0.3)  # posé après le téléport
	var zc := await H.dummy_zombie(self, p.global_position + Vector3(2.2, 0, 0), 800)
	var n0 := booms.size()
	p.input.grenade = true
	var ok: bool = await until(func(): return booms.size() > n0, ThrowableRules.FUSE + 1.5, "grenade explose dans la main")
	await seconds(0.05)  # capture de l'explosion
	await at.screenshot("nova_grenade_in_hand")
	p.input.grenade = false
	await seconds(0.3)  # laisse arriver d'éventuels dégâts au joueur (vérifié nul ensuite)
	at.check(ok and (booms[-1][1] as Vector3).distance_to(p.global_position) < 1.6, "explosion dans la main")
	at.check(not zc.is_alive(), "le zombie voisin est tué")
	at.check(pd.health == pd.max_health and pd.life == PlayerData.Life.ALIVE, "NOVA FLOP : aucun dégât (%d/%d PV)" % [pd.health, pd.max_health])
	await H.clear_zombies(self)

	# Plongeon explosif : tue les zombies de la manche 10 alentour.
	zs = await ring_of_zombies()
	pd.health = pd.max_health
	game.session.sync_stats(1)
	var pts0 := pd.points
	var landed := await sprint_dive()
	await seconds(0.03)  # capture de l'explosion
	await at.screenshot("nova_dive_blast")
	await until(func(): return alive_count(zs) == 0 and pd.points - pts0 == 3 * PointsRules.SPLASH_KILL, 2.0, "zombies tués par le plongeon et points crédités")
	var dists := []
	for z: Zombie in zs:
		dists.append("%.1f" % Vector2(z.global_position.x - landed.x, z.global_position.z - landed.z).length())
	at.check(alive_count(zs) == 0, "plongeon explosif : %d/3 zombies tués (distances %s m)" % [3 - alive_count(zs), ", ".join(dists)])
	at.check(pd.points - pts0 == 3 * PointsRules.SPLASH_KILL, "points comme une explosion (+%d)" % (pd.points - pts0))
	at.check(pd.health == pd.max_health, "aucun dégât au plongeur (%d PV)" % pd.health)
	p.input.crouch = false
	await seconds(0.8)  # le joueur se relève du plongeon
	await H.clear_zombies(self)
	game.combat.debug_invulnerable = true

	# ------------------------------------------------ DEADEYE DRAM
	# Sans l'atout : la visée ne bouge pas.
	p.teleport_to(lab(35.5, 24.5), -PI * 0.5)
	p.pitch = 0.0
	await seconds(0.3)  # posé après le téléport
	var zt := await H.dummy_zombie(self, lab(43.5, 25.4), 100000)
	p.yaw = -PI * 0.5
	p.pitch = 0.0
	await seconds(0.1)  # vue posée
	var err0 := aim_error(zt)
	p.input.aim = true
	await seconds(0.4)  # fenêtre mesurée : la visée ne doit pas bouger
	var err_plain := aim_error(zt)
	at.check(err0 > 4.0 and absf(err_plain - err0) < 1.0, "sans DEADEYE : pas d'aimantation (%.1f° -> %.1f°)" % [err0, err_plain])
	p.input.aim = false
	await seconds(0.4)  # retour à la hanche (touche relâchée)
	# Recul et dispersion de référence (tir à la hanche, M1911).
	var ref := await hip_shots(4)
	var before_buy := pd.points
	await buy(")")
	at.check(pd.has_perk("deadeye") and pd.points == before_buy - 1500, "DEADEYE DRAM acheté 1500 (%d -> %d)" % [before_buy, pd.points])
	await until(drink_done, 4.0, "fin de la boisson DEADEYE DRAM")
	# Avec l'atout : passage en visée -> la vue glisse vers la tête.
	p.teleport_to(lab(35.5, 24.5), -PI * 0.5)
	await seconds(0.3)  # posé après le téléport
	# Écart de départ imposé (4° à côté de la tête) : ne dépend pas du
	# balancement du zombie.
	H.aim_at(p, zt.head_position())
	p.yaw += deg_to_rad(4.0)
	p.rotation.y = p.yaw
	await frames(2)
	err0 = aim_error(zt)
	p.input.aim = true
	# Mise en joue puis glissement (0,1 s) : on attend l'aimantation (sous charge,
	# la mise en joue peut prendre plus longtemps que prévu).
	await until(func(): return aim_error(zt) < 1.2, 1.5, "aimantation")
	var err_snap := aim_error(zt)
	at.check(err0 > 2.5 and err_snap < 1.2, "DEADEYE : visée aimantée vers la tête (%.1f° -> %.2f°)" % [err0, err_snap])
	at.check(p.weapons.deadeye.last_target_id == zt.id, "cible : le zombie devant")
	await seconds(0.4)  # capture : visée posée
	await at.screenshot("deadeye_snap")
	# La tête est touchée : tir visé.
	await H.shoot(self, p, 0.3)
	await seconds(0.4)  # entre deux gestes du joueur
	p.input.aim = false
	await seconds(0.4)  # retour à la hanche (touche relâchée)
	var perk := await hip_shots(4)
	at.check(perk[0] < ref[0] * 0.7, "dispersion en hanche réduite (%.2f° -> %.2f°)" % [ref[0], perk[0]])
	at.check(perk[1] < ref[1] * 0.7, "recul réduit (%.2f° -> %.2f°)" % [ref[1], perk[1]])
	await H.clear_zombies(self)
	await seconds(0.3)  # capture : HUD posé
	await at.screenshot("perk_icons")
	var icons: PackedStringArray = game.hud._perk_icons.perks
	at.check("nova" in icons and "deadeye" in icons, "icônes NOVA FLOP et DEADEYE DRAM dans le HUD (%s)" % ", ".join(icons))

	# À terre : les atouts sont perdus (comme les autres).
	game.perks.srv_clear(1)
	await until(func(): return not pd.has_perk("nova"), 2.0, "atouts retirés")
	at.check(not pd.has_perk("nova") and PerkDB.explosive_self_mult(pd) == 1.0, "atouts perdus")


## Tirs à la hanche au M1911 vers le mur : [dispersion moyenne (°), recul (°)].
func hip_shots(n: int) -> Array:
	var w: Dictionary = pd.current_weapon()
	w.mag = WeaponDB.stats(w.id, w.pap).mag
	game.session.sync_inventory(1)
	p.teleport_to(lab(35.5, 23.5), -PI * 0.5)
	await seconds(0.4)  # posé après le téléport (et arme sortie)
	var spread := 0.0
	var kick := 0.0
	var on_fire := func():
		_kick = p.weapons.feel.last_kick_deg
	p.weapons.fired.connect(on_fire)
	for i in n:
		p.pitch = 0.0
		p.yaw = -PI * 0.5
		p.weapons.feel.reset()
		_pitch0 = p.pitch
		await seconds(0.05)  # entre deux tirs
		_pitch0 = p.pitch
		await H.shoot(self, p, 0.3)
		spread += p.weapons.last_spread_deg
		kick += _kick
	p.weapons.fired.disconnect(on_fire)
	p.pitch = 0.0
	return [spread / n, kick / n]
