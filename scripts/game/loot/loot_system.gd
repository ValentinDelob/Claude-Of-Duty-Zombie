class_name LootSystem
extends Node
## Butin des vagues spéciales et de boss (GAME_CONCEPT §4.7 ; chemin réseau :
## /root/Game/Loot). Tirages : LootRules ; fin de partie : ProfileLoot.
##
## Le SERVEUR tire et valide tout, pour chaque joueur (butin personnel) :
## * armes : à la fin d'une vague spéciale ou de boss vaincue
##   (RoundManager.wave_cleared), LootRules.weapons_for_wave armes par joueur,
##   qui JAILLISSENT du dernier zombie tué de la vague (LootArc : le serveur
##   choisit le point d'arrivée au sol, scatter_point ; chaque machine rejoue
##   l'arc), diffusées à toutes les machines (_cl_spawn / _cl_remove). Ramassage : [F] (InteractionSystem :
##   distance, niveau, vue), puis srv_pick : propriétaire seulement, place
##   libre dans l'inventaire de partie (Session.give_to_bag) ; inventaire
##   plein : message, l'arme reste au sol. Une arme de niveau trop élevé se
##   ramasse quand même (elle ne s'équipe pas encore).
## * pièces et échantillons : tirés à chaque zombie de vague spéciale ou de
##   boss tué (ZombieManager.zombie_killed), pour chaque joueur, rangés
##   directement dans son onglet des pièces et ses échantillons de partie
##   (sans limite) ; envoyés au seul joueur concerné (_cl_loot). Chacun
##   jaillit aussi du corps chez ce joueur (LootPickup, _cl_pops : objet
##   visible qui scintille puis file vers lui quand il passe à côté).
## * fiche de l'objet regardé (LootCard) et sons de ramassage par rareté
##   (LootFx), sur chaque machine.
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
## Butin qui jaillit d'un corps : hauteur de départ (m au-dessus des pieds),
## distance de chute (m), délai (s) au-delà duquel le dernier corps est
## oublié (l'arme est alors posée devant le joueur).
const POP_HEIGHT := 0.7
const SCATTER_MIN := 0.6
const SCATTER_MAX := 1.3
const LAST_KILL_TTL := 20.0
## Distance de la fiche d'un objet regardé (m).
const INSPECT_RANGE := 4.5

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
## Serveur : dernier zombie tué (pieds) et quand (s).
var _last_kill := Vector3.INF
var _last_kill_t := 0.0
## Joueur local : pièces et échantillons qui ont jailli, pas encore ramassés.
var pickups: Array[LootPickup] = []
## Fiche de l'objet regardé (HUD, créée au premier besoin).
var card: LootCard
## Objet dont la fiche est affichée (LootDrop ou LootPickup ; null : aucun).
var looked: Node3D


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

## Sorte d'échantillons d'un zombie tué (clé de LootRules.SAMPLES : "dogs",
## "brancardier", "surgeon"), "" s'il n'est pas un zombie de vague spéciale
## ou de boss. Vague du Brancardier : le Brancardier ET son escorte (zombies
## de la vague, §4.7) ; vague du Chirurgien : le Chirurgien, son escorte et
## les patients relevés par ses opérations.
func special_kind(z: Zombie) -> String:
	if game.rounds.wave == WaveRules.BOSS:
		return "surgeon" if game.rounds.boss_type == WaveRules.CHIRURGIEN else ""
	if game.rounds.wave != WaveRules.SPECIAL:
		return ""
	if z is Hellhound:
		return "dogs"
	if game.rounds.special_type == WaveRules.BRANCARDIER and not z is Hellhound:
		return "brancardier"
	# Vague de l'Infirmière : elle ET son escorte.
	if game.rounds.special_type == WaveRules.INFIRMIERE and not z is Hellhound:
		return "nurse"
	return ""


func _on_killed(zid: int) -> void:
	var z := game.zombies.get_zombie(zid)
	if z == null:
		return
	var kind := special_kind(z)
	if kind == "":
		return
	var at := z.global_position
	_last_kill = at
	_last_kill_t = Time.get_ticks_msec() / 1000.0
	# Le boss lui-même : chaque sorte à coup sûr (trophée, LootRules.BOSS_SAMPLE_CHANCE).
	var chance := debug_sample_chance
	if z is Surgeon and chance < 0.0:
		chance = LootRules.BOSS_SAMPLE_CHANCE
	for pid in game.session.data:
		var pd: PlayerData = game.session.data[pid]
		var got := LootRules.roll_samples(kind, _rng, chance)
		var changed := not got.is_empty()
		var pops := []
		if not got.is_empty():
			var mine: Dictionary = samples.get(pid, {})
			for s in got:
				mine[s] = int(mine.get(s, 0)) + 1
				pops.append([LootPickup.KIND_SAMPLE, {"id": s}])
			samples[pid] = mine
		if LootRules.part_drops(_rng, debug_part_chance):
			var p := LootRules.roll_part(pd.level, _rng, "lootp:%d" % _take_id())
			var list: Array = parts.get(pid, [])
			list.append(p)
			parts[pid] = list
			changed = true
			pops.append([LootPickup.KIND_PART, p])
			_tell(pid, MSG_PART, LootRules.part_title(p))
		if changed:
			_send_loot(pid)
		if not pops.is_empty():
			_send_pops(pid, at, pops)


## Vague spéciale ou de boss vaincue : armes qui jaillissent du dernier
## zombie tué (corps trop ancien ou inconnu : posées devant chaque joueur).
func _on_wave_cleared(wave: String, round_n: int) -> void:
	var n := LootRules.weapons_for_wave(wave)
	var origin: Variant = null
	if _last_kill != Vector3.INF and Time.get_ticks_msec() / 1000.0 - _last_kill_t <= LAST_KILL_TTL:
		origin = _last_kill
	var total := n * game.session.data.size()
	var i := 0
	for pid in game.session.data:
		for k in n:
			var w := LootRules.roll_weapon(round_n, _rng, "loot:%d" % _take_id(), wave)
			if game.challenge:
				w = game.challenge.loot_weapon(w)  # « fonds de tiroir » : commune
			srv_drop(pid, w, k, origin, i, total)
			i += 1
	_last_kill = Vector3.INF


func _take_id() -> int:
	_next_id += 1
	return _next_id - 1


## Serveur : pose l'arme `w` au sol pour le joueur `pid` (k-ième arme).
## `origin` (Vector3, pieds d'un zombie tué) : l'arme en jaillit et retombe
## autour (i-ième des `total` objets de ce corps) ; null : posée devant le
## joueur, après une courte chute sur place.
func srv_drop(pid: int, w: Dictionary, k := 0, origin: Variant = null, i := 0, total := 1) -> int:
	if not multiplayer.is_server():
		return -1
	var id := _take_id()
	var end: Vector3
	var start: Vector3
	if origin is Vector3:
		end = scatter_point(origin, scatter_angle(id, i, total), lerpf(SCATTER_MIN, SCATTER_MAX, _rng.randf()))
		start = (origin as Vector3) + Vector3.UP * POP_HEIGHT
	else:
		end = drop_position(pid, k)
		start = end + Vector3.UP * 0.5
	_cl_spawn.rpc(id, pid, end, w, start)
	return id


## Direction (rad) du i-ième des `total` objets d'un même corps : répartis
## en couronne, décalés par l'identifiant (pure).
static func scatter_angle(id: int, i: int, total: int) -> float:
	return TAU * float(i) / maxf(total, 1) + float(id % 17) * 0.37


## Serveur : point de chute au sol à `dist` m du corps `origin` dans la
## direction `angle` (jamais derrière un mur ; sol trouvé sous le point).
func scatter_point(origin: Vector3, angle: float, dist: float) -> Vector3:
	var dir := Vector3(cos(angle), 0.0, sin(angle))
	var target := origin + dir * dist
	var world: World3D = game.world.get_world_3d() if game and game.world and game.world.is_inside_tree() else null
	if world == null:
		return target
	var space := world.direct_space_state
	var up := Vector3.UP * 0.4
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(origin + up, target + up, 1))
	if not hit.is_empty():
		var back: Vector3 = hit.position - dir * 0.3
		target = Vector3(back.x, origin.y, back.z)
		if (target - origin).dot(dir) < 0.0:
			target = origin
	var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(target + Vector3.UP * 0.8, target + Vector3.DOWN * 2.5, 1))
	if not down.is_empty() and absf(down.position.y - origin.y) < 1.2:
		target.y = down.position.y
	else:
		target.y = origin.y
	return target


## Serveur : pièces et échantillons qui jaillissent du corps (pieds `at`)
## chez le joueur `pid` seul : [[sorte, données, départ, arrivée, graine]].
func _send_pops(pid: int, at: Vector3, pops: Array) -> void:
	var items := []
	for j in pops.size():
		var seed_v := _take_id()
		var ang := scatter_angle(seed_v, j, pops.size()) + _rng.randf() * 0.6
		var end := scatter_point(at, ang, lerpf(SCATTER_MIN, SCATTER_MAX, _rng.randf()))
		items.append([pops[j][0], pops[j][1], at + Vector3.UP * POP_HEIGHT, end, seed_v])
	if pid == multiplayer.get_unique_id():
		_cl_pops(items)
	elif multiplayer.has_multiplayer_peer():
		_cl_pops.rpc_id(pid, items)


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
	_cl_remove.rpc(d.drop_id, true)


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
func _cl_spawn(id: int, owner: int, pos: Vector3, w: Dictionary, start: Vector3) -> void:
	if drops.has(id) or not NetGuard.finite_vec(pos) or not WeaponDB.exists(String(w.get("id", ""))):
		return
	if not NetGuard.finite_vec(start) or start.distance_to(pos) > 6.0:
		start = pos
	var d := LootDrop.new()
	d.setup(id, owner, w, pos, self, start)
	game.world.add_child(d)
	game.interact.register(d)
	drops[id] = d


## `picked` : ramassée (son de sa rareté, gerbe d'étincelles).
@rpc("authority", "call_local", "reliable")
func _cl_remove(id: int, picked := false) -> void:
	var d: LootDrop = drops.get(id)
	if d == null:
		return
	drops.erase(id)
	game.interact.unregister(d)
	if picked:
		_pick_feedback(d.card_point(), d.rarity, d.owner_pid == multiplayer.get_unique_id())
	if looked == d:
		looked = null
	d.queue_free()


## Son de la rareté et gerbe d'étincelles à sa couleur, au point `at` ;
## `mine` : son sans spatialisation (le joueur qui ramasse).
func _pick_feedback(at: Vector3, r: int, mine: bool) -> void:
	if mine:
		Audio.play_2d(LootFx.pickup_sound(r), 0.0, 0.02)
	else:
		Audio.play_3d(LootFx.pickup_sound(r), at, -2.0, 0.02)
	if game.fx_root:
		var c := LootFx.color(r)
		game.fx_root.sparks.burst(at, Vector3.UP, 6 + 3 * r, 1.6, 0.9, 0.45, Color(c.r * 2.0, c.g * 2.0, c.b * 2.0))


## Joueur local : pièces et échantillons qui jaillissent d'un corps
## ([[sorte, données, départ, arrivée, graine]], validés ici).
@rpc("authority", "call_remote", "reliable")
func _cl_pops(items: Array) -> void:
	for it in items.slice(0, 16):
		if not valid_pop(it):
			continue
		var pk := LootPickup.new()
		pk.setup(it[0], it[1], it[2], it[3], it[4])
		game.world.add_child(pk)
		pickups.append(pk)


## Objet jailli reçu bien formé ? (pure : réseau.)
static func valid_pop(it: Variant) -> bool:
	if not (it is Array and it.size() == 5 and it[0] is String and it[1] is Dictionary and it[2] is Vector3 \
			and it[3] is Vector3 and it[4] is int):
		return false
	return String(it[0]) in [LootPickup.KIND_PART, LootPickup.KIND_SAMPLE] and NetGuard.finite_vec(it[2]) \
			and NetGuard.finite_vec(it[3]) and (it[2] as Vector3).distance_to(it[3]) <= 6.0


# --------------------------------------------------------------------------
# Joueur local : objets jaillis, fiche de l'objet regardé
# --------------------------------------------------------------------------

func _process(delta: float) -> void:
	var p := game.local_player if game else null
	var alive := p != null and is_instance_valid(p) and game.session.local_data() != null \
			and game.session.local_data().life == PlayerData.Life.ALIVE
	if not pickups.is_empty():
		var chest: Variant = p.global_position + Vector3.UP * 1.0 if alive else null
		for i in range(pickups.size() - 1, -1, -1):
			var pk := pickups[i]
			if not is_instance_valid(pk):
				pickups.remove_at(i)
				continue
			if pk.tick(delta, chest):
				_pick_feedback(pk.card_point(), pk.rarity, true)
				pickups.remove_at(i)
				if looked == pk:
					looked = null
				pk.queue_free()
	_update_card(p if alive else null)


## Fiche de l'objet regardé par le joueur local `p` (null : aucune).
func _update_card(p: Player) -> void:
	var cands: Array[Node3D] = []
	if p != null and (drops.size() + pickups.size()) > 0 and _can_inspect():
		# Seulement les objets posés (pas pendant le vol : la fiche suivrait
		# l'objet en l'air).
		for d: LootDrop in drops.values():
			if d.age >= float(d.arc.get("settle", 0.0)):
				cands.append(d)
		for pk in pickups:
			if is_instance_valid(pk) and pk.resting():
				cands.append(pk)
	var target: Node3D = null
	if not cands.is_empty():
		var pts := []
		for c in cands:
			pts.append(c.card_point())
		var eye := p.eye_position()
		var i := LootCard.pick(eye, p.aim_direction(), pts, INSPECT_RANGE)
		if i >= 0 and _clear_sight(p, eye, pts[i]):
			target = cands[i]
	looked = target
	if target == null:
		if card:
			card.hide_card()
		return
	var cam := get_viewport().get_camera_3d()
	var at: Vector3 = target.call("card_point")
	if cam == null or cam.is_position_behind(at):
		if card:
			card.hide_card()
		return
	if card == null:
		card = LootCard.new()
		card.name = "LootCard"
		game.hud.add_child(card)
	# Demi-taille de l'objet à l'écran : la fiche se pose à côté, sans le cacher.
	var half: float = target.get("half_size")
	var c := cam.unproject_position(at)
	var reach := (cam.unproject_position(at + cam.global_basis.x * half) - c).length()
	card.show_info(card_info(target, p), c, reach)


## Fiche affichée ? (HUD : l'invite [F] du centre est alors masquée.)
func card_shown() -> bool:
	return card != null and card.shown()


## Données de la fiche de `target` vue par le joueur `p`.
func card_info(target: Node3D, p: Player) -> Dictionary:
	if target is LootDrop:
		var d := target as LootDrop
		var pd := game.session.local_data()
		var me := multiplayer.get_unique_id()
		var hand: Dictionary = p.weapons.current() if p and p.weapons else {}
		var full := pd != null and pd.bag.size() >= GameWeapon.BAG
		var info := LootCard.weapon_info(d.weapon, hand, pd.level if pd else 1,
				"" if d.owner_pid == me else Net.player_name(d.owner_pid), Settings.action_label("interact"), full)
		if d.owner_pid != me:
			info["action_color"] = HudStyle.player_color(Net.player_slot(d.owner_pid))
		return info
	var pk := target as LootPickup
	if pk.kind == LootPickup.KIND_PART:
		return LootCard.part_info(pk.data)
	var sid := String(pk.data.get("id", ""))
	return LootCard.sample_info(sid, int(my_samples.get(sid, 1)))


## Fiche permise : en partie, ni pause ni inventaire ouverts.
func _can_inspect() -> bool:
	if game.hud == null or not GameState.is_in_game():
		return false
	if game.hud.inventory and game.hud.inventory.visible:
		return false
	return not (game.hud.pause_menu and game.hud.pause_menu.visible)


## Rien entre l'œil et l'objet (murs, sols : calque 1).
func _clear_sight(p: Player, eye: Vector3, at: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(eye, at, 1)
	q.exclude = [p.get_rid()]
	return p.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


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
			return Lang.t("%s rangée dans l'inventaire · %s : équiper", "%s stored in your backpack · %s: equip") % [arg, Settings.action_label("inventory")]
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
