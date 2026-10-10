class_name DownedSystem
extends Node
## Joueurs à terre et réanimation (chemin réseau : /root/Game/Downed).
##
## Serveur : à 0 PV, un joueur passe DOWNED (au lieu de mourir). Il rampe, garde
## un pistolet, peut tirer. Un coéquipier le réanime en maintenant [F] près de
## lui ; sinon il se vide de son sang et meurt (retour à la manche suivante).
## En solo, tomber à terre met fin à la partie. L'auto-réanimation
## (`self_revive`, ancien atout LAZARUS TONIC) reste prévue mais plus rien ne
## la programme aujourd'hui.

## Valeurs de Black Ops 1 (saignement 45 s, réanimation 3 s ; auto-réanimation
## au bout d'une dizaine de secondes).
const BLEEDOUT_TIME := 45.0
const REVIVE_TIME := 3.0
const SOLO_SELF_REVIVE := 10.0
const REVIVE_RANGE := 2.4
const REVIVED_HEALTH := 100

signal state_changed(pid: int)

var game: Game
## pid -> {bleed_end, reviver, revive_start, revive_dur, self_revive}
## (côté serveur : temps absolus ; côté client : copie pour l'affichage)
var downed: Dictionary = {}
## Durée de saignement (modifiable par les tests).
var bleedout_time := BLEEDOUT_TIME
## Serveur : auto-réanimation en solo (ancien atout LAZARUS TONIC). Aucune
## source dans le jeu aujourd'hui ; les tests l'activent pour éprouver l'état
## à terre en solo sans finir la partie.
var solo_self_revive := false


func _ready() -> void:
	game = get_parent()


func is_downed(pid: int) -> bool:
	return downed.has(pid)


# --------------------------------------------------------------------------
# Serveur
# --------------------------------------------------------------------------

## Serveur : le joueur tombe à terre.
func srv_down(pid: int) -> void:
	var pd := game.session.get_data(pid)
	if pd == null or pd.life != PlayerData.Life.ALIVE:
		return
	pd.life = PlayerData.Life.DOWNED
	pd.downs += 1
	# BO1 : 5 % de la ferraille perdue. Elle n'est plus rendue au sauveteur :
	# la ferraille ne se gagne qu'en tuant (GAME_CONCEPT §4.8).
	var lost := PointsRules.downed_loss(pd.points)
	game.session.add_points(pid, -lost)
	# Dernier recours : on garde le pistolet (ou on en reçoit un).
	pd.saved_weapons = pd.weapons.duplicate(true)
	pd.weapons = [last_stand_weapon(pd.saved_weapons)]
	pd.slot = 0
	# Répliques : celui qui tombe, un coéquipier qui le voit, le dernier debout.
	VoxSystem.say(pid, "downed")
	if game.vox:
		var mates := game.vox.teammates(pid)
		if not mates.is_empty():
			game.vox.later(1.2, mates.pick_random(), "teammate_down", 0.9)
		if mates.size() == 1 and game.session.data.size() > 1:
			game.vox.later(3.8, mates[0], "last_alive")
	game.combat.cancel_reload(pid)
	var entry := {"bleed_end": GameClock.now() + bleedout_time, "bleed_total": bleedout_time, "reviver": 0, "revive_start": 0.0, "revive_dur": 0.0, "self_revive": 0.0}
	if Net.mode == Net.Mode.SOLO and solo_self_revive:
		entry.self_revive = GameClock.now() + SOLO_SELF_REVIVE
	downed[pid] = entry
	game.session.sync_stats(pid)
	game.session.sync_inventory(pid)
	print("[Downed] %s est à terre" % Net.player_name(pid))
	_broadcast(pid)
	game.check_game_over()


## Pistolets du dernier recours, du moins bon au meilleur (level.pistol_values
## de BO1 ; « + » : drapeau `pap` en sommeil, voir WeaponDB).
const LAST_STAND_RANK := ["m1911", "cz75", "python", "python+", "cz75+", "m1911+"]


## Arme tenue à terre (last_stand_best_pistol / last_stand_pistol_swap de
## BO1) : le meilleur pistolet possédé, avec deux chargeurs de réserve en plus
## (M1911 : au moins deux chargeurs) ; sans pistolet, un M1911 neuf avec deux
## chargeurs de réserve.
static func last_stand_weapon(weapons: Array) -> Dictionary:
	var best := -1
	var best_rank := -1
	for i in weapons.size():
		var w: Dictionary = weapons[i]
		var rank := LAST_STAND_RANK.find(String(w.get("id", "")) + ("+" if w.get("pap", false) else ""))
		if rank > best_rank:
			best_rank = rank
			best = i
	if best < 0:
		var fresh := WeaponDB.new_instance(WeaponDB.STARTING_WEAPON)
		fresh.reserve = int(WeaponDB.stats(WeaponDB.STARTING_WEAPON).mag) * 2
		return fresh
	var out: Dictionary = (weapons[best] as Dictionary).duplicate()
	var s := WeaponDB.stats(out.id, out.pap)
	var two_mags := int(s.mag) * 2
	if out.id == WeaponDB.STARTING_WEAPON and not out.pap:
		# BO1 fixe la réserve du M1911 à deux chargeurs ; on ne retire rien.
		out.reserve = maxi(int(out.reserve), two_mags)
	else:
		# Jamais au-delà de la réserve maximale de l'arme (SetWeaponAmmoStock
		# de BO1 plafonne) : un CZ75 plein passait à 135 / 105, et revenait
		# ainsi après la réanimation.
		out.reserve = mini(int(out.reserve) + two_mags, int(s.reserve))
	return out


## Serveur : un coéquipier commence à réanimer `target`.
func srv_start_revive(reviver: int, target: int) -> void:
	var e: Dictionary = downed.get(target, {})
	var rpd := game.session.get_data(reviver)
	if e.is_empty() or reviver == target or rpd == null or rpd.life != PlayerData.Life.ALIVE:
		return
	if e.reviver != 0:
		return
	if not _in_range(reviver, target):
		return
	e.reviver = reviver
	e.revive_start = GameClock.now()
	e.revive_dur = REVIVE_TIME
	VoxSystem.say(reviver, "revive_start", 0.7)
	_broadcast(target)


func srv_stop_revive(reviver: int, target: int) -> void:
	var e: Dictionary = downed.get(target, {})
	if e.is_empty() or e.reviver != reviver:
		return
	e.reviver = 0
	e.revive_start = 0.0
	_broadcast(target)


func _in_range(a: int, b: int) -> bool:
	var pa: Player = game.players.get(a)
	var pb: Player = game.players.get(b)
	# Références du serveur (dernier état accepté de chacun, Player.srv_origin) :
	# ni le sauveteur ni le joueur à terre (qui rampe lentement) ne sont jugés
	# sur leur position interpolée, en retard avec de la latence.
	return pa != null and pb != null and in_revive_range(pa.srv_origin(), pb.srv_origin())


## Règle pure : sauveteur en `reviver_pos` assez près du joueur à terre.
static func in_revive_range(reviver_pos: Vector3, downed_pos: Vector3) -> bool:
	return reviver_pos.distance_to(downed_pos) <= REVIVE_RANGE + 0.8


func _process(_delta: float) -> void:
	if not multiplayer.is_server() or downed.is_empty():
		return
	var t := GameClock.now()
	for pid in downed.keys():
		var e: Dictionary = downed[pid]
		if e.self_revive > 0.0 and t >= e.self_revive:
			_revive(pid)
			continue
		if e.reviver != 0:
			var rpd := game.session.get_data(e.reviver)
			if rpd == null or rpd.life != PlayerData.Life.ALIVE or not _in_range(e.reviver, pid):
				srv_stop_revive(e.reviver, pid)
			elif t - e.revive_start >= e.revive_dur:
				var rev: int = e.reviver
				_revive(pid)
				VoxSystem.say_later(0.6, pid, "revived")
				var r := game.session.get_data(rev)
				if r:
					r.revives += 1
					game.session.sync_stats(rev)
					# Plus de ferraille pour une réanimation (GAME_CONCEPT §4.8).
				continue
		# Pas de fin de saignement pendant une réanimation en cours.
		if e.reviver == 0 and t >= e.bleed_end:
			_bleed_out(pid)


func _revive(pid: int) -> void:
	var pd := game.session.get_data(pid)
	downed.erase(pid)
	if pd == null:
		return
	pd.life = PlayerData.Life.ALIVE
	pd.health = mini(REVIVED_HEALTH, pd.max_health)
	# On récupère ses armes, avec les munitions du pistolet utilisé à terre.
	var used: Dictionary = pd.weapons[0] if not pd.weapons.is_empty() else {}
	pd.weapons = pd.saved_weapons.duplicate(true) if not pd.saved_weapons.is_empty() else [WeaponDB.new_instance(WeaponDB.STARTING_WEAPON)]
	# L'arme utilisée à terre, si le joueur la possédait, revient avec ses
	# munitions ; un M1911 prêté (aucun pistolet possédé) est repris.
	if not used.is_empty():
		for i in pd.weapons.size():
			if pd.weapons[i].id == used.id and pd.weapons[i].pap == used.pap:
				pd.weapons[i] = used
				break
	pd.saved_weapons = []
	pd.slot = clampi(pd.slot, 0, pd.weapons.size() - 1)
	game.session.sync_stats(pid)
	game.session.sync_inventory(pid)
	print("[Downed] %s est réanimé" % Net.player_name(pid))
	_cl_revived.rpc(pid)
	_broadcast(pid)


func _bleed_out(pid: int) -> void:
	downed.erase(pid)
	var pd := game.session.get_data(pid)
	if pd:
		pd.saved_weapons = []
	# BO1 (player_died_penalty) : chacun des autres joueurs encore en jeu perd
	# 10 % de ses points quand un coéquipier succombe.
	for other in game.session.data:
		var opd: PlayerData = game.session.data[other]
		if other != pid and opd.life != PlayerData.Life.DEAD:
			game.session.add_points(other, -PointsRules.no_revive_loss(opd.points))
	print("[Downed] %s a succombé" % Net.player_name(pid))
	VoxSystem.say(pid, "death")
	if game.vox:
		var mates := game.vox.teammates(pid)
		if not mates.is_empty():
			game.vox.later(1.0, mates.pick_random(), "teammate_dead")
	_broadcast(pid)
	game.kill_player(pid)


## Serveur : un joueur quitte la partie.
func forget(pid: int) -> void:
	downed.erase(pid)
	for other in downed:
		if downed[other].reviver == pid:
			downed[other].reviver = 0
			_broadcast(other)


# --------------------------------------------------------------------------
# Réplication
# --------------------------------------------------------------------------

func _broadcast(pid: int) -> void:
	var t := GameClock.now()
	var e: Dictionary = downed.get(pid, {})
	if e.is_empty():
		_cl_state.rpc(pid, false, 0.0, 0, 0.0, 0.0)
	else:
		var progress: float = (t - e.revive_start) if e.reviver != 0 else 0.0
		_cl_state.rpc(pid, true, e.bleed_end - t, e.reviver, progress, e.revive_dur)


@rpc("authority", "call_local", "reliable")
func _cl_state(pid: int, is_down: bool, bleed_time: float, reviver: int, progress: float, dur: float) -> void:
	var t := GameClock.now()
	var was_down := _was_shown.has(pid)
	if not multiplayer.is_server():
		if is_down:
			# Durée totale : celle du premier état reçu pour cette mise à terre.
			var total: float = downed.get(pid, {}).get("bleed_total", bleed_time)
			downed[pid] = {"bleed_end": t + bleed_time, "bleed_total": total, "reviver": reviver, "revive_start": t - progress, "revive_dur": dur, "self_revive": 0.0}
		else:
			downed.erase(pid)
	var p: Player = game.players.get(pid)
	if p:
		p.set_downed(is_down)
	if is_down and not was_down:
		_was_shown[pid] = true
		if p:
			Audio.play_3d("player_down", p.global_position + Vector3.UP, 0.0, 0.0)
		if pid == multiplayer.get_unique_id():
			if GameState.state in [GameState.State.PLAYING, GameState.State.ROUND_END]:
				GameState.set_state(GameState.State.PLAYER_DOWN)
		else:
			game.hud.flash_message(Lang.t("%s EST À TERRE !", "%s IS DOWN!") % Net.player_name(pid).to_upper())
	elif not is_down and was_down:
		_was_shown.erase(pid)
		if pid == multiplayer.get_unique_id() and GameState.state == GameState.State.PLAYER_DOWN:
			var pause := game.rounds.phase == RoundManager.Phase.INTERMISSION
			GameState.set_state(GameState.State.ROUND_END if pause else GameState.State.PLAYING)
	state_changed.emit(pid)


var _was_shown: Dictionary = {}


@rpc("authority", "call_local", "reliable")
func _cl_revived(pid: int) -> void:
	var p: Player = game.players.get(pid)
	if p:
		Audio.play_3d("revive", p.global_position + Vector3.UP, 0.0, 0.0)
	if pid == multiplayer.get_unique_id():
		game.hud.show_banner(Lang.t("RÉANIMÉ", "REVIVED"), 1.2)


## Toutes les machines : infos pour le HUD.
func bleed_left(pid: int) -> float:
	var e: Dictionary = downed.get(pid, {})
	return maxf(e.get("bleed_end", 0.0) - GameClock.now(), 0.0)


## Part du saignement écoulée (0 : vient de tomber, 1 : mort imminente).
func bleed_fraction(pid: int) -> float:
	var total: float = downed.get(pid, {}).get("bleed_total", 0.0)
	if total <= 0.0:
		return 0.0
	return 1.0 - clampf(bleed_left(pid) / total, 0.0, 1.0)


func revive_progress(pid: int) -> float:
	var e: Dictionary = downed.get(pid, {})
	if e.is_empty() or e.reviver == 0 or e.revive_dur <= 0.0:
		return 0.0
	return clampf((GameClock.now() - e.revive_start) / e.revive_dur, 0.0, 1.0)


## Avancement de l'auto-réanimation, 0 si aucune. Connu
## seulement du serveur, c'est-à-dire du joueur lui-même en solo.
func self_revive_progress(pid: int) -> float:
	var end: float = downed.get(pid, {}).get("self_revive", 0.0)
	if end <= 0.0:
		return 0.0
	return clampf(1.0 - (end - GameClock.now()) / SOLO_SELF_REVIVE, 0.001, 1.0)


func reviver_of(pid: int) -> int:
	return downed.get(pid, {}).get("reviver", 0)


## Serveur : une auto-réanimation est-elle programmée ?
func will_self_revive(pid: int) -> bool:
	return downed.get(pid, {}).get("self_revive", 0.0) > 0.0
