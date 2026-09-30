class_name InteractionSystem
extends Node
## Registre et réseau des objets interactifs (chemin réseau : /root/Game/Interact).
##
## Client : trouve l'objet visé par le joueur local, affiche l'invite, envoie
## la demande au serveur. Serveur : vérifie la distance réelle du joueur puis
## délègue à Interactable.srv_use(). Les changements d'état sont diffusés à
## toutes les machines.

const MAX_SERVER_DISTANCE := 3.5

var game: Game
var objects: Dictionary = {}  # id -> Interactable
## Objet actuellement visé par le joueur local.
var focused: Interactable
var _holding: Interactable
## Serveur : demandes d'interaction par joueur (un humain en fait 5 à 10 / s).
var _limit := NetGuard.Limiter.new(20.0, 20.0)
## Serveur : fins d'interaction (une par demande acceptée, même cadence).
var _release_limit := NetGuard.Limiter.new(20.0, 20.0)


func _ready() -> void:
	game = get_parent()


func register(obj: Interactable) -> void:
	assert(obj.interact_id != "" and not objects.has(obj.interact_id), "id d'interaction invalide ou dupliqué : " + obj.interact_id)
	objects[obj.interact_id] = obj
	obj.system = self


func unregister(obj: Interactable) -> void:
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
		srv_interact.rpc_id(1, focused.interact_id)
	if _holding and (not inp.interact or focused != _holding):
		srv_release.rpc_id(1, _holding.interact_id)
		_holding = null


func _find_focus(p: Player) -> Interactable:
	var pd := game.session.get_data(p.peer_id)
	if pd == null or pd.life != PlayerData.Life.ALIVE:
		return null
	var eye := p.eye_position()
	var fwd := p.aim_direction()
	var best: Interactable = null
	var best_score := -INF
	for obj: Interactable in objects.values():
		if not obj.is_visible_in_tree():
			continue
		var to := obj.interact_point() - eye
		var d := to.length()
		if d > obj.interact_range + 0.6:
			continue
		var facing := fwd.dot(to / maxf(d, 0.001))
		if facing < 0.35 and d > 1.0:
			continue
		if not obj.can_interact(p.peer_id) or weapon_locked(obj, pd):
			continue
		var score := facing * 2.0 - d
		if score > best_score:
			best_score = score
			best = obj
	return best


## Arme de bonus en main (FAUCHEUSE) : ni arme au mur, ni boîte mystère, ni
## Pack-a-Punch tant que le bonus dure (comme BO1).
static func weapon_locked(obj: Interactable, pd: PlayerData) -> bool:
	return not pd.powerup_weapon.is_empty() and (obj is WallBuy or obj is MysteryBox or obj is PackAPunch)


# --------------------------------------------------------------------------
# Serveur
# --------------------------------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func srv_interact(id: String) -> void:
	if not multiplayer.is_server():
		return
	var pid := multiplayer.get_remote_sender_id()
	# Inondation de demandes : chaque refus envoie un message (achat refusé...).
	if not _limit.allow(pid):
		return
	var obj: Interactable = objects.get(id)
	var p: Player = game.players.get(pid)
	var pd := game.session.get_data(pid)
	if obj == null or p == null or pd == null or pd.life != PlayerData.Life.ALIVE or weapon_locked(obj, pd):
		return
	if p.global_position.distance_to(obj.interact_point()) > obj.interact_range + MAX_SERVER_DISTANCE:
		print("[Interact] %d trop loin de %s" % [pid, id])
		return
	obj.srv_use(pid)


@rpc("any_peer", "call_local", "reliable")
func srv_release(id: String) -> void:
	if not multiplayer.is_server():
		return
	var pid := multiplayer.get_remote_sender_id()
	if not _release_limit.allow(pid):
		return
	# Joueur connu seulement (un pair pas encore entré dans la partie n'a rien
	# à relâcher). Ni distance ni « vivant » exigés : relâcher ne fait
	# qu'arrêter une action (réparation, réanimation), jamais en démarrer une ;
	# un joueur tombé à terre en pleine action doit pouvoir la relâcher.
	var obj: Interactable = objects.get(id)
	if obj == null or not game.players.has(pid) or game.session.get_data(pid) == null:
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


## Serveur : refus (points insuffisants...) signalé au seul joueur concerné.
func deny(pid: int, reason: String) -> void:
	if reason == "Pas assez de points":
		VoxSystem.say(pid, "no_money", 0.6)
	elif reason == "Pas de courant":
		VoxSystem.say(pid, "no_power", 0.7)
	if pid == multiplayer.get_unique_id():
		_cl_denied(reason)
	else:
		_cl_denied.rpc_id(pid, reason)


@rpc("authority", "call_remote", "reliable")
func _cl_denied(reason: String) -> void:
	Audio.play_2d("denied", -4.0, 0.0)
	game.hud.flash_message(reason)


## Serveur : son d'achat joué pour tout le monde à la position de l'objet.
func purchase_fx(obj: Interactable) -> void:
	_cl_purchase_fx.rpc(obj.interact_id)


@rpc("authority", "call_local", "reliable")
func _cl_purchase_fx(id: String) -> void:
	var obj: Interactable = objects.get(id)
	if obj:
		Audio.play_3d("purchase", obj.interact_point(), -2.0, 0.02)
