class_name LootSystem
extends Node
## Butin des vagues spéciales et de boss (GAME_CONCEPT §4.7 ; chemin réseau :
## /root/Game/Loot). Tirages : LootRules ; fin de partie : ProfileLoot.
##
## Le SERVEUR tire et valide tout, pour chaque joueur (butin personnel) :
## * armes : à la fin d'une vague spéciale ou de boss vaincue
##   (RoundManager.wave_cleared), LootRules.weapons_for_wave armes par joueur,
##   posées au sol devant lui (LootDrop, à sa couleur), diffusées à toutes les
##   machines (_cl_spawn / _cl_remove). Ramassage : [F] (InteractionSystem :
##   distance, niveau, vue), puis srv_pick : propriétaire seulement, place
##   libre dans l'inventaire de partie (Session.give_to_bag) ; inventaire
##   plein : message, l'arme reste au sol. Une arme de niveau trop élevé se
##   ramasse quand même (elle ne s'équipe pas encore).
## * pièces et échantillons : tirés à chaque zombie de vague spéciale ou de
##   boss tué (ZombieManager.zombie_killed), pour chaque joueur, rangés
##   directement dans son onglet des pièces et ses échantillons de partie
##   (sans limite) ; envoyés au seul joueur concerné (_cl_loot).
## * montage d'une pièce depuis l'inventaire, n'importe où (srv_mount, règle
##   OwnedWeapon.can_mount) : la pièce quitte l'onglet et rejoint l'arme.

## Messages au joueur (codes envoyés par le serveur, traduits par le client).
const MSG_PICKED := "picked"
const MSG_BAG_FULL := "bag_full"
const MSG_NOT_YOURS := "not_yours"
const MSG_PART := "part"
const MSG_MOUNTED := "mounted"
const MSG_MOUNT_REFUSED := "mount_refused"
## Distance de pose devant le joueur (m) ; écart angulaire entre deux armes.
const DROP_DIST := 1.5
const DROP_SPREAD := 0.7

signal loot_changed

var game: Game
## Serveur : pid -> pièces de la partie (format LootRules.roll_part) et
## pid -> {sorte: quantité}.
var parts: Dictionary = {}
var samples: Dictionary = {}
## Toutes les machines : armes au sol, id -> LootDrop.
var drops: Dictionary = {}
## Joueur local : ses pièces et échantillons de la partie (copie du serveur).
var my_parts: Array = []
var my_samples: Dictionary = {}
## Tests : force la chance des pièces et des échantillons (< 0 : règles).
var debug_part_chance := -1.0
var debug_sample_chance := -1.0
var _rng := RandomNumberGenerator.new()
var _next_id := 1
var _limit := NetGuard.Limiter.new(10.0, 10.0)
var _counter: Label


func _ready() -> void:
	game = get_parent()
	_rng.randomize()
	if multiplayer.is_server():
		game.zombies.zombie_killed.connect(_on_killed)
		game.rounds.wave_cleared.connect(_on_wave_cleared)
		Net.player_left.connect(_on_player_left)


# --------------------------------------------------------------------------
# Serveur : tirages
# --------------------------------------------------------------------------

## Type de vague spéciale d'un zombie tué ("dogs"), "" s'il n'en est pas un.
func special_kind(z: Zombie) -> String:
	if z is Hellhound and game.rounds.wave == WaveRules.SPECIAL:
		return "dogs"
	return ""


func _on_killed(zid: int) -> void:
	var z := game.zombies.get_zombie(zid)
	if z == null:
		return
	var kind := special_kind(z)
	if kind == "":
		return
	for pid in game.session.data:
		var pd: PlayerData = game.session.data[pid]
		var got := LootRules.roll_samples(kind, _rng, debug_sample_chance)
		var changed := not got.is_empty()
		if not got.is_empty():
			var mine: Dictionary = samples.get(pid, {})
			for s in got:
				mine[s] = int(mine.get(s, 0)) + 1
			samples[pid] = mine
		if LootRules.part_drops(_rng, debug_part_chance):
			var p := LootRules.roll_part(pd.level, _rng, "lootp:%d" % _take_id())
			var list: Array = parts.get(pid, [])
			list.append(p)
			parts[pid] = list
			changed = true
			_tell(pid, MSG_PART, LootRules.part_title(p))
		if changed:
			_send_loot(pid)


## Vague spéciale ou de boss vaincue : armes posées devant chaque joueur.
func _on_wave_cleared(wave: String, round_n: int) -> void:
	var n := LootRules.weapons_for_wave(wave)
	for pid in game.session.data:
		for k in n:
			var w := LootRules.roll_weapon(round_n, _rng, "loot:%d" % _take_id())
			srv_drop(pid, w, k)


func _take_id() -> int:
	_next_id += 1
	return _next_id - 1


## Serveur : pose l'arme `w` au sol pour le joueur `pid` (k-ième arme).
func srv_drop(pid: int, w: Dictionary, k := 0) -> int:
	if not multiplayer.is_server():
		return -1
	var id := _take_id()
	_cl_spawn.rpc(id, pid, drop_position(pid, k), w)
	return id


## Point de pose devant le joueur (au sol, jamais dans un mur).
func drop_position(pid: int, k: int) -> Vector3:
	var p: Player = game.players.get(pid)
	if p == null:
		return Vector3.ZERO
	var base := p.srv_origin()
	var fwd := p.aim_direction() if p.is_inside_tree() else Vector3.FORWARD
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	# 0, puis alternativement à droite et à gauche (vague de boss : 2 armes).
	@warning_ignore("integer_division")
	var step := (k + 1) / 2
	fwd = fwd.rotated(Vector3.UP, DROP_SPREAD * float(step) * (1.0 if k % 2 == 1 else -1.0))
	var target := base + fwd * DROP_DIST
	if not p.is_inside_tree():
		return target
	var space := p.get_world_3d().direct_space_state
	var up := Vector3.UP * 0.5
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(base + up, target + up, 1))
	if not hit.is_empty():
		target = base + (Vector3(hit.position.x, base.y, hit.position.z) - base) * 0.6
	var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(target + Vector3.UP * 1.0, target + Vector3.DOWN * 2.0, 1))
	if not down.is_empty() and absf(down.position.y - base.y) < 1.0:
		target.y = down.position.y
	else:
		target.y = base.y
	return target


## Serveur : le joueur `pid` veut ramasser `d` (distance déjà validée).
func srv_pick(d: LootDrop, pid: int) -> void:
	if not multiplayer.is_server() or not drops.has(d.drop_id):
		return
	if pid != d.owner_pid:
		print("[Loot] %d : l'arme %d appartient à %d" % [pid, d.drop_id, d.owner_pid])
		_tell(pid, MSG_NOT_YOURS, Net.player_name(d.owner_pid))
		return
	if not game.session.give_to_bag(pid, d.weapon):
		_tell(pid, MSG_BAG_FULL, "")
		return
	_tell(pid, MSG_PICKED, WeaponDB.display_name(String(d.weapon.get("id", ""))))
	_cl_remove.rpc(d.drop_id)


func _on_player_left(pid: int) -> void:
	parts.erase(pid)
	samples.erase(pid)
	for id in drops.keys():
		if (drops[id] as LootDrop).owner_pid == pid:
			_cl_remove.rpc(id)


## Serveur : pièces et échantillons de `pid`, à lui seul.
func _send_loot(pid: int) -> void:
	var ps: Array = parts.get(pid, [])
	var ss: Dictionary = samples.get(pid, {})
	if pid == multiplayer.get_unique_id():
		_cl_loot(ps.duplicate(true), ss.duplicate())
	elif multiplayer.has_multiplayer_peer():
		_cl_loot.rpc_id(pid, ps, ss)


func _tell(pid: int, code: String, arg: String) -> void:
	if pid == multiplayer.get_unique_id():
		_cl_msg(code, arg)
	else:
		_cl_msg.rpc_id(pid, code, arg)


# --------------------------------------------------------------------------
# Montage d'une pièce (client -> serveur)
# --------------------------------------------------------------------------

## Client : monte la pièce `part_uid` sur l'arme `idx` de la rangée `row`
## (0 : en main, 1 : inventaire).
func request_mount(part_uid: String, row: int, idx: int) -> void:
	srv_mount.rpc_id(1, part_uid, row, idx)


@rpc("any_peer", "call_local", "reliable")
func srv_mount(part_uid: Variant, row: Variant, idx: Variant) -> void:
	var pid := NetGuard.alive_sender(self, game, _limit)
	if pid == NetGuard.NO_SENDER or not (part_uid is String and row is int and idx is int):
		return
	var pd := game.session.get_data(pid)
	var list: Array = parts.get(pid, [])
	var at := -1
	for i in list.size():
		if String(list[i].get("uid", "")) == part_uid:
			at = i
			break
	var arr: Array = pd.weapons if row == 0 else pd.bag
	if at < 0 or row < 0 or row > 1 or idx < 0 or idx >= arr.size():
		return
	var w: Dictionary = arr[idx]
	var why := LootRules.mount_refusal(w, list[at], pd.level)
	if why != "":
		print("[Loot] montage refusé (%d) : %s" % [pid, why])
		_tell(pid, MSG_MOUNT_REFUSED, why)
		return
	LootRules.mount(w, list[at])
	list.remove_at(at)
	game.session.sync_inventory(pid)
	_send_loot(pid)
	_tell(pid, MSG_MOUNTED, WeaponDB.display_name(String(w.get("id", ""))))


# --------------------------------------------------------------------------
# Toutes les machines
# --------------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _cl_spawn(id: int, owner: int, pos: Vector3, w: Dictionary) -> void:
	if drops.has(id) or not NetGuard.finite_vec(pos) or not WeaponDB.exists(String(w.get("id", ""))):
		return
	var d := LootDrop.new()
	d.setup(id, owner, w, pos, self)
	game.world.add_child(d)
	game.interact.register(d)
	drops[id] = d


@rpc("authority", "call_local", "reliable")
func _cl_remove(id: int) -> void:
	var d: LootDrop = drops.get(id)
	if d == null:
		return
	drops.erase(id)
	game.interact.unregister(d)
	d.queue_free()


@rpc("authority", "call_remote", "reliable")
func _cl_loot(ps: Array, ss: Dictionary) -> void:
	my_parts = ps.slice(0, 4096)
	my_samples = {}
	for k in ss:
		if (k is String or k is StringName) and (ss[k] is int):
			my_samples[String(k)] = maxi(int(ss[k]), 0)
	_refresh_counter()
	loot_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _cl_msg(code: String, arg: String) -> void:
	var t := msg_text(code, arg)
	if t != "" and game.hud:
		game.hud.flash_message(t)


## Texte d'un message du serveur, dans la langue du joueur (pure).
static func msg_text(code: String, arg: String) -> String:
	match code:
		MSG_PICKED:
			return Lang.t("%s rangée dans l'inventaire", "%s stored in your backpack") % arg
		MSG_BAG_FULL:
			return Lang.t("Inventaire plein : libérez une place", "Backpack full: free a slot")
		MSG_NOT_YOURS:
			return Lang.t("Ce butin appartient à %s", "This loot belongs to %s") % arg
		MSG_PART:
			return Lang.t("Pièce trouvée : %s", "Part found: %s") % arg
		MSG_MOUNTED:
			return Lang.t("Pièce installée sur %s", "Part mounted on %s") % arg
		MSG_MOUNT_REFUSED:
			match arg:
				"no_slot":
					return Lang.t("Aucun emplacement de pièce libre", "No free part slot")
				"weapon_level":
					return Lang.t("Pièce de niveau trop élevé pour cette arme", "Part level too high for this weapon")
				"player_level":
					return Lang.t("Niveau de joueur insuffisant pour cette pièce", "Your level is too low for this part")
			return Lang.t("Montage impossible", "Cannot mount this part")
	return ""


## Compteur discret des échantillons et pièces de la partie (HUD, joueur local).
func _refresh_counter() -> void:
	if game.hud == null:
		return
	if _counter == null:
		_counter = HudStyle.label("", 16, HudStyle.TEXT_DIM, "text", 3)
		_counter.anchor_left = 1.0
		_counter.anchor_right = 1.0
		_counter.offset_left = -520
		_counter.offset_right = -24
		_counter.offset_top = 150
		_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_counter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		game.hud.add_child(_counter)
	_counter.text = counter_text(my_samples, my_parts.size())
	_counter.visible = _counter.text != ""


## Texte du compteur : « CROC 2 · COLLIER 1 · PIÈCES 1 » ("" : rien). Pure.
static func counter_text(ss: Dictionary, n_parts: int) -> String:
	var items := PackedStringArray()
	var keys := ss.keys()
	keys.sort()
	for k in keys:
		if int(ss[k]) > 0:
			items.append("%s %d" % [LootRules.sample_name(String(k)), int(ss[k])])
	if n_parts > 0:
		items.append(Lang.t("PIÈCES %d", "PARTS %d") % n_parts)
	return " · ".join(items)


## Texte du compteur affiché ("" : masqué ; tests).
func counter_shown() -> String:
	return _counter.text if _counter and _counter.visible else ""
