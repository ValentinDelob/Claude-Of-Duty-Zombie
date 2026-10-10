extends AutotestScenario
## @niveau long
## Soak (hors check.sh, préfixe long_) : un bot joue de nombreuses manches sur
## une carte (BUNKER K-7 ici ; long_soak_draft pour l'autre) en abattant
## lui-même les zombies et en utilisant tout ce que la
## carte propose PAR LE VRAI CHEMIN D'INTERACTION (visée, [F], validation du
## serveur) : portes et débris, courant, caisse au hasard, grenades et
## peluches leurres, téléporteur, pièges, mise à terre par les zombies puis
## auto-réanimation (solo, activée par le soak), manche de chiens.
##   godot --headless --fixed-fps 60 --path . -- --autotest=long_soak
##
## Invariants vérifiés en continu (échec au premier écart, avec le détail) :
## positions finies (joueur, zombies), aucun zombie immobile en poursuite
## plus de 20 s, points jamais négatifs, munitions jamais au-dessus du
## maximum, emplacement de grenade dans ses bornes, manche qui finit, aucune
## invite sur un objet épuisé (porte ouverte),
## pas d'état « à terre » bloqué, et AUCUN message d'erreur ni avertissement
## du moteur pendant la partie (journal capturé par un Logger).

var H := AutotestHelpers
var game: Game
var p: Player
var pd: PlayerData
## Carte jouée et manche à atteindre (surchargées par les variantes).
var map_id := "bunker_k7"
var target_round := 10
## Manche de chiens forcée (0 : aucune).
var dog_round := 6
var budget_sec := 900.0

var _log: SoakLogger
var _t := 0.0
var _zombie_track: Dictionary = {}  # zid -> [ancre, temps]
var _stuck_reported: Dictionary = {}
var _round_t0 := 0.0
var _round_seen := 0
var _downed_since := -1.0
var _pause_track := false
var _counts: Dictionary = {}
var _dog_seen := false
## Écarts d'invariants : type -> nombre (échec au premier de chaque type).
var _reports: Dictionary = {}
var _failsafe_missed: Dictionary = {}
## Endroits où des zombies sont restés coincés 20 s : "position zone" -> nombre.
var _stuck_spots: Dictionary = {}


## Journal du moteur : erreurs et avertissements (tous fils).
class SoakLogger extends Logger:
	var lines: PackedStringArray = []
	var _mutex := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		var kind: String = ["ERROR", "WARNING", "SCRIPT ERROR", "SHADER ERROR"][clampi(error_type, 0, 3)]
		_mutex.lock()
		if lines.size() < 200:
			lines.append("%s: %s (%s) at %s:%d %s" % [kind, rationale if rationale != "" else code, code, file, line, function])
		_mutex.unlock()

	func _log_message(message: String, error: bool) -> void:
		if not error:
			return
		_mutex.lock()
		if lines.size() < 200:
			lines.append("STDERR: " + message.strip_edges())
		_mutex.unlock()

	func snapshot() -> PackedStringArray:
		_mutex.lock()
		var out := lines.duplicate()
		_mutex.unlock()
		return out


func count(what: String) -> void:
	_counts[what] = int(_counts.get(what, 0)) + 1


# --------------------------------------------------------------------------
# Déroulement
# --------------------------------------------------------------------------

func configure() -> void:
	pass


func run() -> void:
	configure()
	timeout_sec = int(budget_sec) + 60
	_log = SoakLogger.new()
	OS.add_logger(_log)
	p = await H.start_solo_game(self, map_id)
	if p == null:
		OS.remove_logger(_log)
		return
	game = Game.instance
	pd = game.session.local_data()
	game.combat.debug_invulnerable = true
	if dog_round > 0:
		game.rounds.dogs.debug_force_next(dog_round)
	game.rounds.round_started.connect(func(n: int): print("[soak] manche %d à t=%.0f s (%d points, %d kills)" % [n, _t, pd.points, pd.kills]))
	var real0 := Time.get_ticks_msec()
	var errands := errand_list()
	var next_errand := 0
	var repeat := repeat_list()
	while _t < budget_sec and game.rounds.round_n <= target_round:
		if GameState.state == GameState.State.GAME_OVER:
			at.fail("GAME OVER inattendu à la manche %d" % game.rounds.round_n)
			break
		# Une course toutes les 15 s de jeu, entre deux combats ; la liste
		# faite, on recommence ce qui se refait (boîte, pièges, bonus...).
		if _t >= next_errand * 15.0 + 3.0 and game.rounds.round_n >= 1:
			var e: Array = errands[next_errand] if next_errand < errands.size() else repeat[(next_errand - errands.size()) % repeat.size()]
			next_errand += 1
			print("[soak] course « %s » (manche %d, t=%.0f s)" % [e[0], game.rounds.round_n, _t])
			await (e[1] as Callable).call()
			continue
		await fight_tick()
	p.input.fire = false
	print("[soak] %s : manche %d atteinte en %.0f s de jeu (%.0f s réelles), %d kills, %d points ; actions : %s" % [map_id, game.rounds.round_n, _t, (Time.get_ticks_msec() - real0) / 1000.0, pd.kills, pd.points, str(_counts)])
	at.check(game.rounds.round_n > target_round, "%s : manches 1 à %d jouées (manche %d)" % [map_id, target_round, game.rounds.round_n])
	at.check(next_errand >= errands.size(), "toutes les actions faites (%d / %d)" % [next_errand, errands.size()])
	for kind: String in _reports:
		print("[soak] écart « %s » vu %d fois" % [kind, _reports[kind]])
	for spot: String in _stuck_spots:
		print("[soak] endroit où des zombies restent coincés : %s (%d fois)" % [spot, _stuck_spots[spot]])
	if dog_round > 0:
		at.check(_dog_seen, "manche de chiens jouée (manche %d)" % dog_round)
	await frames(2)
	OS.remove_logger(_log)
	var errs := _log.snapshot()
	for l in errs.slice(0, 20):
		print("[soak] journal : " + l)
	at.check(errs.is_empty(), "aucune erreur ni avertissement du moteur pendant la partie (%d)" % errs.size())


## Actions refaites en boucle une fois la liste faite.
func repeat_list() -> Array:
	return [
		["caisse", func(): await use_box(2)],
		["pièges", use_traps],
		["grenades", throw_grenades],
		["téléporteur", use_teleporter],
		["peluche leurre", throw_decoy],
		["à terre puis réanimation", downed_and_self_revive],
	]


## Actions dans l'ordre (nom, coroutine).
func errand_list() -> Array:
	return [
		["portes", open_doors],
		["courant", power_on],
		["arme", equip_weapon],
		["caisse", func(): await use_box(3)],
		["grenades", throw_grenades],
		["à terre puis réanimation", downed_and_self_revive],
		["téléporteur", use_teleporter],
		["pièges", use_traps],
		["peluche leurre", throw_decoy],
		["caisse (2)", func(): await use_box(3)],
	]


# --------------------------------------------------------------------------
# Combat et invariants
# --------------------------------------------------------------------------

func step(dt := 0.1) -> void:
	await seconds(dt)
	_t += dt
	check_invariants()


func nearest_visible() -> Zombie:
	var best: Zombie = null
	var best_d := 40.0
	var space := p.get_world_3d().direct_space_state
	for z: Zombie in game.zombies.alive:
		if z.state == Zombie.State.EMERGE:
			continue
		var d := z.global_position.distance_to(p.global_position)
		if d < best_d:
			var q := PhysicsRayQueryParameters3D.create(p.eye_position(), z.head_position(), 1)
			if space.intersect_ray(q).is_empty():
				best = z
				best_d = d
	return best


func fight_tick() -> void:
	var z := nearest_visible()
	if z:
		H.aim_at(p, z.head_position())
		p.input.fire = trigger(p, pd)
	else:
		p.input.fire = false
		# Personne en vue depuis longtemps : on va vers la horde (comme un joueur).
		if game.rounds.phase == RoundManager.Phase.ACTIVE and game.zombies.alive_count() > 0 and fmod(_t, 12.0) < 0.1:
			seek_horde()
	var w := pd.current_weapon()
	if not w.is_empty() and w.reserve < 60:
		WeaponDB.refill(pd, pd.slot)
		game.session.sync_inventory(1)
	await step()


## Détente du bot : maintenue pour une arme automatique, relâchée une image
## sur deux pour une arme semi-automatique (M1911...), comme un doigt.
static func trigger(pl: Player, data: PlayerData) -> bool:
	var w := data.current_weapon()
	if w.is_empty() or WeaponDB.stats(w.id, w.pap).get("auto", false):
		return true
	return not pl.input.fire


## Se place près d'un zombie en poursuite (sans le toucher).
func seek_horde() -> void:
	for z: Zombie in game.zombies.alive:
		if z.state == Zombie.State.CHASE or z.state == Zombie.State.IDLE:
			var path := game.nav.find_path(z.global_position, p.global_position)
			if path.size() >= 2:
				var k := maxi(path.size() - 3, 0)
				var spot := path[k]
				if spot.distance_to(z.global_position) > 4.0:
					p.teleport_to(spot + Vector3.UP * 0.05)
					count("rapprochements")
					return


## Ce qui touche le corps d'un zombie dans les 4 directions (diagnostic).
func probe(z: Zombie) -> PackedStringArray:
	var out := PackedStringArray()
	var space := z.get_world_3d().direct_space_state
	for dir: Vector3 in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		var q := PhysicsRayQueryParameters3D.create(z.global_position + Vector3.UP * 0.5, z.global_position + Vector3.UP * 0.5 + dir * 0.8, z.collision_mask)
		q.exclude = [z.get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and hit.collider is Node:
			out.append("%s -> %s à %.2f m" % [dir, (hit.collider as Node).name, (hit.position as Vector3).distance_to(q.from)])
	return out


## Écart d'invariant : échec la première fois pour ce type, compté ensuite.
func report(kind: String, msg: String) -> void:
	var n := int(_reports.get(kind, 0))
	_reports[kind] = n + 1
	if n == 0:
		at.fail(msg)
	elif n < 12:
		print("[soak] écart (%s) : %s" % [kind, msg])


func is_finite3(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


func check_invariants() -> void:
	var round_n := game.rounds.round_n
	# Positions.
	if not is_finite3(p.global_position):
		report("nan_joueur", "position du joueur non finie : %s" % p.global_position)
	for z: Zombie in game.zombies.alive:
		if not is_finite3(z.global_position):
			report("nan_zombie", "position non finie du zombie %d (%s) : %s" % [z.id, Zombie.State.keys()[z.state], z.global_position])
	# Points, munitions, objets à lancer.
	if pd.points < 0:
		report("points", "points négatifs : %d" % pd.points)
	for w: Dictionary in pd.weapons:
		var s := WeaponDB.stats(w.id, w.pap)
		if int(w.mag) > int(s.mag) or int(w.reserve) > int(s.reserve) or int(w.mag) < 0 or int(w.reserve) < 0:
			report("munitions", "munitions hors bornes %s%s : %d/%d (max %d/%d)" % [w.id, "+" if w.pap else "", w.mag, w.reserve, s.mag, s.reserve])
	if pd.grenades < 0 or pd.grenades > ThrowableRules.SLOT_MAX or not ThrowableRules.NAMES.has(pd.throwable):
		report("lancers", "emplacement de grenade hors bornes : %d (sorte %d)" % [pd.grenades, pd.throwable])
	if pd.health < 0 or pd.health > pd.max_health:
		report("sante", "santé hors bornes : %d / %d" % [pd.health, pd.max_health])
	# Invites : jamais sur un objet épuisé.
	var f := game.interact.focused
	if f != null and f.prompt(1) == "":
		report("invite_vide", "objet visé sans invite : %s" % f.interact_id)
	for id: String in game.interact.objects:
		var o: Interactable = game.interact.objects[id]
		var sold := false
		if o is Door:
			sold = (o as Door).is_open
		if sold and o.prompt(1) != "":
			report("invite_epuise", "invite sur un objet épuisé %s : « %s »" % [id, o.prompt(1)])
	# À terre : jamais bloqué.
	if pd.life == PlayerData.Life.DOWNED:
		if _downed_since < 0.0:
			_downed_since = _t
		elif _t - _downed_since > DownedSystem.BLEEDOUT_TIME + 5.0:
			report("a_terre_bloque", "à terre depuis %.0f s (bloqué)" % (_t - _downed_since))
	else:
		_downed_since = -1.0
		if GameState.state == GameState.State.PLAYER_DOWN:
			report("player_down", "état PLAYER_DOWN alors que le joueur est debout")
	# Manche qui finit.
	if round_n != _round_seen:
		_round_seen = round_n
		_round_t0 = _t
	if game.rounds.dogs.active:
		_dog_seen = true
	if game.rounds.phase == RoundManager.Phase.ACTIVE and _t - _round_t0 > 240.0:
		var desc := PackedStringArray()
		for z: Zombie in game.zombies.alive.slice(0, 6):
			desc.append("%d %s %s zone %s" % [z.id, Zombie.State.keys()[z.state], z.global_position, game.layout.zone_at(z.global_position)])
		report("manche_bloquee", "manche %d pas finie après 240 s (reste %d, à faire apparaître %d) : %s" % [round_n, game.rounds.remaining(), game.rounds.to_spawn, ", ".join(desc)])
		# On débloque pour continuer le soak (l'écart est déjà signalé).
		_round_t0 = _t
		for zid in game.zombies.alive.map(func(zz: Zombie): return zz.id):
			game.zombies.kill(zid, false, Vector3.FORWARD)
	# Zombies immobiles en poursuite (hors voyage en téléporteur, où la cible
	# est hors d'atteinte).
	var tp := game.teleporter
	var away := tp != null and tp.state == Teleporter.State.ACTIVE
	if _pause_track or away:
		_zombie_track.clear()
		return
	var seen := {}
	for z: Zombie in game.zombies.alive:
		seen[z.id] = true
		# Au contact du joueur, la horde se bouscule derrière ceux qui
		# frappent : immobile n'y est pas bloqué.
		if z.state != Zombie.State.CHASE or z.global_position.distance_to(p.global_position) < 4.0:
			_zombie_track.erase(z.id)
			continue
		var tr: Array = _zombie_track.get(z.id, [])
		if tr.is_empty() or (tr[0] as Vector3).distance_to(z.global_position) > 0.75:
			_zombie_track[z.id] = [z.global_position, _t]
		elif _t - float(tr[1]) > 20.0 and not _stuck_reported.has(z.id):
			_stuck_reported[z.id] = true
			# Cible hors d'atteinte à pied (salle du téléporteur...) : les
			# zombies attendent, comme dans BO1.
			if game.nav.find_path(z.global_position, p.global_position).is_empty():
				count("zombies sans chemin (joueur hors d'atteinte)")
				continue
			# Coincé 20 s alors qu'un chemin existe : endroit du décor à revoir
			# (relevé), le filet de BO1 doit le retirer à 30 s.
			count("zombies coincés 20 s")
			var spot := "%s zone %s" % [Vector3i(z.global_position.round()), game.layout.zone_at(z.global_position)]
			_stuck_spots[spot] = int(_stuck_spots.get(spot, 0)) + 1
			print("[soak] zombie %d coincé 20 s en %s (zone %s ; joueur en %s zone %s, manche %d ; chemin %d/%d, vitesse %s ; obstacles : %s)" % [z.id, z.global_position, game.layout.zone_at(z.global_position), p.global_position, game.layout.zone_at(p.global_position), round_n,
				z._path_i, z._path.size(), z.velocity, ", ".join(probe(z))])
		elif _t - float(tr[1]) > Spawner.FAILSAFE_TIME + (Spawner.FAILSAFE_CRAWLER_EXTRA if z.is_crawler() else 0.0) + 8.0 and not _failsafe_missed.has(z.id):
			_failsafe_missed[z.id] = true
			if game.nav.find_path(z.global_position, p.global_position).is_empty():
				continue
			report("zombie_immobile", "zombie %d%s immobile depuis %.0f s en %s (zone %s), jamais retiré par le filet (joueur en %s zone %s, manche %d ; cible %s, chemin %d/%d, vitesse %s, leurré %s)" % [z.id, " (chien)" if z is Hellhound else "", _t - float(tr[1]), z.global_position, game.layout.zone_at(z.global_position), p.global_position, game.layout.zone_at(p.global_position), round_n,
				z.target.name if z.target else "aucune", z._path_i, z._path.size(), z.velocity, z.lured])
	for zid in _zombie_track.keys():
		if not seen.has(zid):
			_zombie_track.erase(zid)


# --------------------------------------------------------------------------
# Aller à un objet et l'utiliser comme un joueur
# --------------------------------------------------------------------------

## Points au sol libres autour de l'objet, d'où l'on voit son point d'interaction.
func stand_points(obj: Interactable) -> Array[Vector3]:
	var ip := obj.interact_point()
	var space := p.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.6
	var out: Array[Vector3] = []
	for d: float in [1.2, 0.9, 1.6, 2.0]:
		for k in 16:
			var a := TAU * k / 16.0
			var c := ip + Vector3(sin(a), 0.0, cos(a)) * d
			var down := PhysicsRayQueryParameters3D.create(c + Vector3.UP * 0.6, c + Vector3.DOWN * 3.0, 1)
			var hit := space.intersect_ray(down)
			if hit.is_empty():
				continue
			var foot: Vector3 = hit.position
			if ip.y - foot.y > 2.3 or ip.y - foot.y < 0.0:
				continue
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = capsule
			q.transform = Transform3D(Basis.IDENTITY, foot + Vector3.UP * 0.95)
			q.collision_mask = p.collision_mask
			q.exclude = [p.get_rid()]
			if not space.intersect_shape(q, 1).is_empty():
				continue
			var eye := foot + Vector3.UP * 1.6
			var sight := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, ip, 1))
			if not sight.is_empty() and (sight.position as Vector3).distance_to(ip) > 0.7:
				continue
			out.append(foot)
	return out


## Se place devant l'objet (du côté atteignable depuis la position actuelle)
## et attend qu'il soit visé. Faux si aucun point ne convient.
func approach(obj: Interactable) -> bool:
	p.input.fire = false
	if obj == null:
		return false
	var from := p.global_position
	var cands := stand_points(obj)
	# D'abord les points où l'on peut aller à pied.
	var walk: Array[Vector3] = []
	var other: Array[Vector3] = []
	for c in cands:
		var path := game.nav.find_path(from, c)
		if not path.is_empty():
			walk.append(c)
		else:
			other.append(c)
	for c: Vector3 in walk + other:
		p.teleport_to(c + Vector3.UP * 0.05)
		H.aim_at(p, obj.interact_point())
		for i in 6:
			await step(0.05)
			if game.interact.focused == obj:
				return true
			H.aim_at(p, obj.interact_point())
	return false


## Visé puis [F] ; attend `done` (ou 2 s). Vrai si `done` est vrai.
func press(obj: Interactable, done: Callable, what: String, limit := 2.0) -> bool:
	if not await approach(obj):
		print("[soak] %s : impossible de viser %s (%d points au sol)" % [what, obj.interact_id if obj else "?", stand_points(obj).size() if obj else 0])
		count("visées manquées")
		return false
	p.input.interact_pressed = true
	var t := 0.0
	while t < limit:
		await step(0.05)
		t += 0.05
		if done.call():
			count(what)
			return true
	print("[soak] %s : [F] sans effet sur %s (« %s »)" % [what, obj.interact_id, obj.prompt(1)])
	return false


func afford(n: int) -> void:
	if pd.points < n:
		game.session.add_points(1, n - pd.points + 100)


# --------------------------------------------------------------------------
# Actions
# --------------------------------------------------------------------------

## Ouvre toutes les portes et débris payants, de proche en proche.
func open_doors() -> void:
	for pass_n in 8:
		var progress := false
		for id: String in game.doors:
			var d: Door = game.doors[id]
			if d.is_open or d.power_door:
				continue
			afford(d.cost)
			var before := pd.points
			if await press(d, func(): return d.is_open, "portes"):
				at.check(before - pd.points == d.cost, "porte %s ouverte pour %d (%d débités)" % [id, d.cost, before - pd.points])
				progress = true
		if not progress:
			break
	var closed := PackedStringArray()
	for id: String in game.doors:
		if not game.doors[id].is_open and not game.doors[id].power_door:
			closed.append(id)
	at.check(closed.is_empty(), "toutes les portes payantes ouvertes par [F] (restent : %s)" % ", ".join(closed))


func power_on() -> void:
	var sw: Interactable = game.interact.get_obj("power")
	if sw == null:
		return
	await press(sw, func(): return game.power_on, "courant", 4.0)
	at.check(game.power_on, "courant rétabli par le levier")


## Arme puissante en main pour la suite (plus d'achats muraux : donnée).
func equip_weapon() -> void:
	WeaponDB.give(pd, "hk21")
	game.session.sync_inventory(1)
	await step(0.5)


## Caisse au hasard : tirages par le vrai chemin ([F]), objet pris sur
## l'emplacement de grenade.
func use_box(spins: int) -> void:
	var box: MysteryBox = game.interact.get_obj("box")
	if box == null:
		return
	for i in spins:
		var t := 0.0
		while box.state != MysteryBox.State.IDLE and t < MysteryBox.READY_TIME + 6.0:
			await fight_tick()
			t += 0.1
		afford(MysteryBox.COST)
		var before := pd.points
		if not await press(box, func(): return box.state != MysteryBox.State.IDLE, "caisse"):
			continue
		# Jamais plus que le prix (un kill encore en vol peut ajouter de la
		# ferraille pendant l'achat).
		at.check(before - pd.points <= MysteryBox.COST, "caisse : %d débités (prix %d)" % [before - pd.points, MysteryBox.COST])
		t = 0.0
		while box.state == MysteryBox.State.ROLLING and t < MysteryBox.ROLL_TIME + 2.0:
			await step()
			t += 0.1
		if box.state == MysteryBox.State.READY:
			var it := ThrowableRules.crate_item(box.item)
			await press(box, func(): return box.state != MysteryBox.State.READY, "caisse : objet pris")
			at.check(not it.is_empty() and pd.throwable == int(it.kind) and pd.grenades == ThrowableRules.SLOT_MAX, "caisse : %s pris (%d)" % [box.item, pd.grenades])
			count("objets de la caisse")


func throw_at_horde() -> bool:
	var sys := game.throwables
	var before := sys.items.size()
	var z := nearest_visible()
	if z:
		H.aim_at(p, z.global_position + Vector3.UP * 2.0)
	p.input.grenade = true
	await step(0.4)
	p.input.grenade = false
	var t := 0.0
	while t < 1.5:
		await step()
		t += 0.1
		if sys.items.size() > before:
			return true
	return false


func throw_grenades() -> void:
	await wait_for_horde()
	for i in 2:
		if pd.grenades <= 0:
			break
		var n := pd.grenades
		var kind := pd.throwable
		if await throw_at_horde():
			count("grenades" if kind == ThrowableRules.Kind.FRAG else "peluches leurres")
		at.check(pd.grenades == n - 1, "objet lancé (réserve %d -> %d)" % [n, pd.grenades])
		await step(4.5 if kind == ThrowableRules.Kind.FRAG else 9.0)


## Peluche leurre : tirage forcé à la caisse, puis lancée sur la horde.
func throw_decoy() -> void:
	if pd.throwable != ThrowableRules.Kind.DECOY or pd.grenades <= 0:
		var box: MysteryBox = game.interact.get_obj("box")
		if box == null:
			return
		var t := 0.0
		while box.state != MysteryBox.State.IDLE and t < 30.0:
			await fight_tick()
			t += 0.1
		box.force_result = "decoy"
		await use_box(1)
	await wait_for_horde()
	var n := pd.grenades
	if pd.throwable == ThrowableRules.Kind.DECOY and n > 0 and await throw_at_horde():
		count("peluches leurres")
		at.check(pd.grenades == n - 1, "peluche lancée (réserve %d -> %d)" % [n, pd.grenades])
		await step(9.0)


## Attend quelques zombies en jeu (combat en attendant).
func wait_for_horde() -> void:
	var t := 0.0
	while game.zombies.alive_count() < 2 and t < 40.0:
		await fight_tick()
		t += 0.1


## Mis à terre par les zombies (plus d'invulnérabilité, on ne tire plus),
## puis auto-réanimation en solo (DownedSystem.solo_self_revive, activée par
## le soak : plus d'atout LAZARUS).
func downed_and_self_revive() -> void:
	game.downed.solo_self_revive = true
	await wait_for_horde()
	var weapons_before := pd.weapons.size()
	game.combat.debug_invulnerable = false
	p.input.fire = false
	var t := 0.0
	while pd.life == PlayerData.Life.ALIVE and t < 60.0:
		# On va au contact de la horde s'il le faut.
		if fmod(t, 8.0) < 0.1:
			seek_horde()
		await step()
		t += 0.1
	if pd.life == PlayerData.Life.ALIVE:
		print("[soak] pas mis à terre par les zombies en 60 s : dégâts forcés")
		game.combat.damage_player(1, 1000, p.global_position + Vector3.FORWARD)
		await step(0.3)
	at.check(pd.life == PlayerData.Life.DOWNED, "à terre (%s)" % PlayerData.Life.keys()[pd.life])
	count("mises à terre")
	# À terre : on tire au pistolet sur ce qui approche.
	t = 0.0
	while pd.life == PlayerData.Life.DOWNED and t < DownedSystem.SOLO_SELF_REVIVE + 5.0:
		await fight_tick()
		t += 0.1
	game.combat.debug_invulnerable = true
	at.check(pd.life == PlayerData.Life.ALIVE and GameState.state != GameState.State.PLAYER_DOWN, "auto-réanimation (%.1f s)" % t)
	at.check(pd.weapons.size() == weapons_before, "armes rendues après la réanimation (%d / %d)" % [pd.weapons.size(), weapons_before])


func use_teleporter() -> void:
	var tp := game.teleporter
	if tp == null:
		return
	var t := 0.0
	while tp.state != Teleporter.State.IDLE and t < 120.0:
		await fight_tick()
		t += 0.1
	if tp.needs_link and tp.link != Teleporter.Link.LINKED:
		if tp.link == Teleporter.Link.UNLINKED:
			await press(tp, func(): return tp.link == Teleporter.Link.PRIMED, "téléporteur : pad")
		if tp.mainframe:
			await press(tp.mainframe, func(): return tp.link == Teleporter.Link.LINKED, "téléporteur : poste central")
	afford(tp.cost)
	if not await press(tp, func(): return tp.state != Teleporter.State.IDLE, "téléporteur"):
		return
	# Rester sur le pad pendant la charge.
	p.teleport_to(tp.global_position + Vector3.UP * 0.1)
	t = 0.0
	while tp.state == Teleporter.State.CHARGING and t < 10.0:
		await step()
		t += 0.1
	at.check(tp.state == Teleporter.State.ACTIVE, "téléporteur parti")
	t = 0.0
	while tp.state == Teleporter.State.ACTIVE and t < tp.stay_time + 5.0:
		await fight_tick()
		t += 0.1
	at.check(tp.state == Teleporter.State.COOLDOWN, "retour du téléporteur")


func use_traps() -> void:
	for id: String in game.interact.objects.keys():
		var trap := game.interact.get_obj(id) as ElectricTrap
		if trap == null or trap.state != ElectricTrap.State.IDLE:
			continue
		afford(ElectricTrap.COST)
		var lever: Interactable = game.interact.get_obj(id + "_b")
		var target: Interactable = lever if lever and randi() % 2 == 0 else trap
		await press(target, func(): return trap.state == ElectricTrap.State.ACTIVE, "pièges")
		# Pas dans le piège : on s'écarte d'un pas s'il le faut.
		if trap.contains(p.global_position):
			p.teleport_to(p.global_position - (trap.global_position - p.global_position).normalized() * 1.5)
		await step(0.3)
