class_name InteractionSystem
extends Node
## Registre et réseau des objets interactifs (chemin réseau : /root/Game/Interact).
##
## Client : trouve l'objet visé par le joueur local, affiche l'invite, envoie
## la demande au serveur. Serveur : vérifie la distance réelle du joueur puis
## délègue à Interactable.srv_use(). Les changements d'état sont diffusés à
## toutes les machines.

const MAX_SERVER_DISTANCE := 3.5
## Écart de hauteur (m) au plus entre les pieds du joueur et le sol de l'objet
## (Interactable.level_y) : on n'utilise un objet que depuis son niveau, comme
## une fenêtre se répare (Barricade.REPAIR_HEIGHT) ; une marche d'escalier
## ou un saut passent, le niveau du dessous ou du dessus (2 m et plus) jamais.
const LEVEL_HEIGHT := 1.2
## Depuis un escalier, l'écart permis croît avec la distance à plat : pente
## d'escalier la plus forte permise (40°, MapValidator.MAX_STAIR_SLOPE :
## tan 40° ≈ 0,84) × distance + marge, borné sous la plus petite hauteur
## de niveau (hauteur sous plafond >= 2 m, plus la dalle). Portes de KINO en haut
## d'escaliers raides (« 3 » de la ruelle, « 5 » de la cage des coulisses) :
## à 2 m sur les marches, 1,45 m plus bas ; coéquipier à terre sur les marches.
const STAIR_GRADE := 0.84
const STAIR_MARGIN := 0.25
const MAX_LEVEL_GAP := 1.9
## Au-delà de LEVEL_HEIGHT (escalier), la ligne de vue doit aussi passer :
## rayon de l'œil vers l'objet (ses propres collisions exclues, own_rids),
## arrêté à cette distance avant lui (mur d'une arme murale), qu'une dalle coupe.
const STAIR_SIGHT_STOP := 0.3
## Hauteur de l'œil d'un joueur debout (pieds déduits de l'œil, pick_focus).
const EYE_HEIGHT := 1.6

var game: Game
var objects: Dictionary = {}  # id -> Interactable
## Les valeurs de `objects`, dans le même ordre (register / unregister) :
## _find_focus les parcourt à chaque pas sans allouer de tableau.
var _list: Array[Interactable] = []
## Objet actuellement visé par le joueur local.
var focused: Interactable
var _holding: Interactable
## Renvoi de la demande tant que [F] reste maintenu (Interactable.resend_while_held).
const HOLD_RESEND_INTERVAL := 0.25
var _resend_t := 0.0
## Serveur : demandes d'interaction par joueur (un humain en fait 5 à 10 / s).
var _limit := NetGuard.Limiter.new(20.0, 20.0)
## Serveur : fins d'interaction (une par demande acceptée, même cadence).
var _release_limit := NetGuard.Limiter.new(20.0, 20.0)


func _ready() -> void:
	game = get_parent()


func register(obj: Interactable) -> void:
	assert(obj.interact_id != "" and not objects.has(obj.interact_id), "id d'interaction invalide ou dupliqué : " + obj.interact_id)
	# Id déjà pris (assert retirée des exports) : le Dictionary garde la place
	# de l'ancien objet, la liste aussi.
	var old: Interactable = objects.get(obj.interact_id)
	var at := _list.find(old) if old != null else -1
	objects[obj.interact_id] = obj
	if at >= 0:
		_list[at] = obj
	else:
		_list.append(obj)
	obj.system = self


func unregister(obj: Interactable) -> void:
	if objects.get(obj.interact_id) == obj:
		_list.erase(obj)
	objects.erase(obj.interact_id)
	if focused == obj:
		focused = null
	if _holding == obj:
		_holding = null


func get_obj(id: String) -> Interactable:
	return objects.get(id)


# --------------------------------------------------------------------------
# Client : visée et envoi
# --------------------------------------------------------------------------

## Appelé par le Player local à chaque image physique (entrées fraîches).
func local_tick(p: Player) -> void:
	focused = _find_focus(p)
	var inp := p.input
	if focused and inp.interact_pressed:
		_holding = focused
		_resend_t = 0.0
		srv_interact.rpc_id(1, focused.interact_id)
	if _holding and (not inp.interact or focused != _holding):
		srv_release.rpc_id(1, _holding.interact_id)
		_holding = null
	elif _holding and _holding.resend_while_held():
		# [F] maintenu sur un objet à maintien idempotent (barricade) : la
		# demande est renvoyée, au cas où le serveur, qui juge la portée sur une
		# position en retard, aurait refusé l'appui fait dès l'invite.
		_resend_t += p.get_physics_process_delta_time()
		if _resend_t >= HOLD_RESEND_INTERVAL:
			_resend_t = 0.0
			srv_interact.rpc_id(1, _holding.interact_id)


func _find_focus(p: Player) -> Interactable:
	var pd := game.session.get_data(p.peer_id)
	if pd == null or pd.life != PlayerData.Life.ALIVE:
		return null
	return pick_focus(p.eye_position(), p.aim_direction(), p.peer_id, pd, p.global_position.y)


## Objet visé depuis l'œil `eye` dans la direction `fwd` par le joueur `pid`
## (vivant, données `pd`) : le mieux placé à portée, devant lui, utilisable.
func pick_focus(eye: Vector3, fwd: Vector3, pid: int, _pd: PlayerData, feet_y := NAN) -> Interactable:
	# Pieds du joueur (sans eux : l'œil moins sa hauteur debout).
	var feet := eye.y - EYE_HEIGHT if is_nan(feet_y) else feet_y
	var best: Interactable = null
	var best_score := -INF
	# Liste gardée (même ordre que `objects`) et distance testée avant la
	# visibilité (remontée de l'arbre) : tous ces tests sont sans effet, le
	# résultat est le même, mais la plupart des objets sont écartés au plus tôt.
	for obj: Interactable in _list:
		var to := obj.interact_point() - eye
		var d := to.length()
		if d > obj.interact_range + 0.6:
			continue
		# Seulement depuis le niveau de l'objet (jamais par-dessous ni par-dessus).
		var ip := obj.interact_point()
		var flat := Vector2(ip.x - eye.x, ip.z - eye.z).length()
		if not same_level(feet, obj.level_y(), flat):
			continue
		if not obj.is_visible_in_tree():
			continue
		var facing := fwd.dot(to / maxf(d, 0.001))
		if facing < 0.35 and d > 1.0:
			continue
		if not obj.can_interact(pid):
			continue
		# Jamais à travers un mur (caisse, Interactable.sight_ok).
		if not obj.sight_ok(eye):
			continue
		# Depuis un escalier (plus d'un mètre d'écart) : rien entre l'œil et l'objet.
		if not stair_sight_ok(obj, feet, eye, ip):
			continue
		var score := facing * 2.0 - d
		if score > best_score:
			best_score = score
			best = obj
	return best


# --------------------------------------------------------------------------
# Serveur
# --------------------------------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func srv_interact(id: String) -> void:
	# Inondation de demandes : chaque refus envoie un message (achat refusé...).
	var pid := NetGuard.alive_sender(self, game, _limit)
	if pid == NetGuard.NO_SENDER:
		return
	var obj: Interactable = objects.get(id)
	var p: Player = game.players.get(pid)
	if obj == null:
		return
	# Référence : dernier état reçu et accepté (Player.srv_origin), pas la
	# position interpolée qui traîne derrière le joueur avec de la latence.
	if not in_reach(p.srv_origin(), obj.srv_point(), obj.interact_range):
		print("[Interact] %d trop loin de %s" % [pid, id])
		return
	# Même niveau que l'objet (jamais depuis le niveau du dessous ou du dessus).
	# Depuis un escalier, l'écart croît avec la distance à plat (level_gap).
	var ref := p.srv_origin()
	var sp := obj.srv_point()
	if not same_level(ref.y, obj.level_y(), Vector2(sp.x - ref.x, sp.z - ref.z).length()):
		print("[Interact] %d : %s à un autre étage" % [pid, id])
		return
	# Ligne de vue depuis l'œil du joueur, à sa position de référence (boîte
	# mystère : jamais à travers un mur, même avec un client modifié ; depuis
	# un escalier : jamais à travers une dalle).
	var eye := ref + srv_eye_offset(p)
	if not obj.sight_ok(eye) or not stair_sight_ok(obj, ref.y, eye, sp):
		print("[Interact] %d : %s hors de vue" % [pid, id])
		return
	obj.srv_use(pid)


## Hauteur de l'œil au-dessus des pieds (accroupi compris) ; joueur hors de
## l'arbre (tests) : 1,5 m.
static func srv_eye_offset(p: Player) -> Vector3:
	if p == null or not p.is_inside_tree() or p.head == null:
		return Vector3.UP * 1.5
	return Vector3.UP * clampf(p.eye_position().y - p.global_position.y, 0.5, 2.0)


## Règle pure : joueur (référence du serveur `ref`) assez près de `point`.
static func in_reach(ref: Vector3, point: Vector3, interact_range: float) -> bool:
	return ref.distance_to(point) <= interact_range + MAX_SERVER_DISTANCE


## Règle pure : pieds du joueur à l'altitude `feet_y` au même niveau qu'un
## objet dont le sol est à `level_y`, à `flat` m à plat de lui : LEVEL_HEIGHT,
## ou l'écart d'un escalier jusqu'à l'objet (level_gap).
static func same_level(feet_y: float, level_y: float, flat := 0.0) -> bool:
	return absf(feet_y - level_y) <= level_gap(flat)


## Écart de hauteur permis à `flat` m à plat de l'objet (STAIR_GRADE).
static func level_gap(flat: float) -> float:
	return clampf(STAIR_GRADE * flat + STAIR_MARGIN, LEVEL_HEIGHT, MAX_LEVEL_GAP)


## Plus haut ou plus bas que LEVEL_HEIGHT (depuis un escalier) : la ligne de
## vue de l'œil `eye` vers `point` (couche du monde) doit passer, jusqu'à
## STAIR_SIGHT_STOP avant l'objet ; une dalle de niveau la coupe. Sinon : vrai.
static func stair_sight_ok(obj: Interactable, feet_y: float, eye: Vector3, point: Vector3) -> bool:
	if absf(feet_y - obj.level_y()) <= LEVEL_HEIGHT or not obj.is_inside_tree():
		return true
	var to := point - eye
	var d := to.length()
	if d <= STAIR_SIGHT_STOP:
		return true
	var space := obj.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(eye, eye + to * ((d - STAIR_SIGHT_STOP) / d), 1, obj.own_rids())
	return space.intersect_ray(q).is_empty()


@rpc("any_peer", "call_local", "reliable")
func srv_release(id: String) -> void:
	# Joueur connu seulement (un pair pas encore entré dans la partie n'a rien
	# à relâcher). Ni distance ni « vivant » exigés : relâcher ne fait
	# qu'arrêter une action (réparation, réanimation), jamais en démarrer une ;
	# un joueur tombé à terre en pleine action doit pouvoir la relâcher.
	var pid := NetGuard.known_sender(self, game, _release_limit)
	var obj: Interactable = objects.get(id)
	if pid == NetGuard.NO_SENDER or obj == null:
		return
	obj.srv_release(pid)


## Serveur : diffuse l'état d'un objet.
func broadcast(obj: Interactable) -> void:
	if multiplayer.is_server():
		_cl_state.rpc(obj.interact_id, obj.get_state())


@rpc("authority", "call_local", "reliable")
func _cl_state(id: String, state: Dictionary) -> void:
	var obj: Interactable = objects.get(id)
	if obj:
		obj.apply_state(state, true)


## Motifs de refus : codes envoyés par le serveur, traduits par chaque
## client dans sa propre langue (deny_text).
const NO_POINTS := "no_points"
const NO_POWER := "no_power"


## Texte affiché pour un motif de refus, dans la langue du joueur local.
static func deny_text(reason: String) -> String:
	match reason:
		NO_POINTS:
			return Lang.t("Pas assez de ferraille", "Not enough scrap")
		NO_POWER:
			return Lang.t("Pas de courant", "No power")
	return ""


## Serveur : refus (points insuffisants...) signalé au seul joueur concerné.
func deny(pid: int, reason: String) -> void:
	if reason == NO_POINTS:
		VoxSystem.say(pid, "no_money", 0.6)
	elif reason == NO_POWER:
		VoxSystem.say(pid, "no_power", 0.7)
	if pid == multiplayer.get_unique_id():
		_cl_denied(reason)
	else:
		_cl_denied.rpc_id(pid, reason)


@rpc("authority", "call_remote", "reliable")
func _cl_denied(reason: String) -> void:
	Audio.play_2d("denied", -4.0, 0.0)
	game.hud.flash_message(deny_text(reason))


## Serveur : son d'achat joué pour tout le monde à la position de l'objet.
func purchase_fx(obj: Interactable) -> void:
	_cl_purchase_fx.rpc(obj.interact_id)


@rpc("authority", "call_local", "reliable")
func _cl_purchase_fx(id: String) -> void:
	var obj: Interactable = objects.get(id)
	if obj:
		Audio.play_3d("purchase", obj.interact_point(), -2.0, 0.02)
