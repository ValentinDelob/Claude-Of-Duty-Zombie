class_name Session
extends Node
## Registre des PlayerData (chemin réseau : /root/Game/Session).
##
## Le serveur modifie les données puis appelle sync_*() : les clients reçoivent
## une copie. Personne d'autre que le serveur n'écrit dans ces données.

signal stats_changed(peer_id: int)
signal inventory_changed(peer_id: int)
## Gain/perte de points (affichage des « +10 » dans le HUD).
signal points_event(peer_id: int, delta: int)

var data: Dictionary = {}  # peer_id -> PlayerData


func get_data(pid: int) -> PlayerData:
	return data.get(pid)


func local_data() -> PlayerData:
	return data.get(multiplayer.get_unique_id())


## Crée les données d'un joueur (sur toutes les machines, à l'apparition).
func create(pid: int) -> PlayerData:
	var pd := PlayerData.new(pid)
	pd.weapons = [WeaponDB.new_instance(WeaponDB.STARTING_WEAPON)]
	data[pid] = pd
	return pd


func remove(pid: int) -> void:
	data.erase(pid)
	loadouts.erase(pid)


# --------------------------------------------------------------------------
# Armes de départ et niveau (GAME_CONCEPT §4.10, §4.12)
# --------------------------------------------------------------------------

## Serveur : niveau et armes de départ annoncés par chaque joueur
## (pid -> {"level": int, "ids": PackedStringArray}), appliqués à son
## apparition (apply_loadout).
var loadouts: Dictionary = {}
## Messages d'armes de départ acceptés (un par partie, quelques-uns au plus).
var _loadout_limit := NetGuard.Limiter.new(1.0, 4.0)


## Chaque machine, juste avant d'annoncer la fin de son chargement
## (Game._ready) : niveau et armes de départ de son profil (local à chaque
## joueur). Même canal fiable que l'annonce de chargement : le serveur les a
## avant de faire apparaître les joueurs.
func send_local_loadout(profile: PlayerProfile = null) -> void:
	if profile == null:
		profile = ProfileStore.load_profile()
	srv_set_loadout.rpc_id(1, profile.level(), Array(profile.starting_weapons))


@rpc("any_peer", "call_local", "reliable")
func srv_set_loadout(lvl: Variant, ids: Variant) -> void:
	var pid := NetGuard.server_sender(self, _loadout_limit)
	if pid == NetGuard.NO_SENDER:
		return
	# Armes de BASE seulement (§4.10) : le serveur ne connaît pas l'arsenal du
	# client, il fabrique lui-même les exemplaires (niveau 1, communs). Le
	# niveau vient du profil local du joueur (non vérifiable ici), borné.
	if ids is Array or ids is PackedStringArray:
		ids = ids.slice(0, 8)
	loadouts[pid] = {"level": ProfileValues.to_int(lvl, 1, 1, PlayerProfile.MAX_LEVEL),
		"ids": BaseWeapons.clean_selection(ids)}


## Armes en main au départ pour une sélection d'armes de base : une arme à
## feu par emplacement choisi, dans l'ordre ; un emplacement non choisi reste
## vide. Une arme de corps à corps de base (aujourd'hui le couteau, en
## attendant la batte) reste l'attaque séparée de mêlée : elle ne prend pas
## d'emplacement en main (choix provisoire, voir GAME_CONCEPT §6 bis). Pure.
static func starting_hands(ids: PackedStringArray) -> Array:
	var out := []
	for id in ids:
		var o := BaseWeapons.make(id)
		if o != null and WeaponDB.exists(id) and out.size() < GameWeapon.HANDS:
			out.append(GameWeapon.from_owned(o))
	return out


## Serveur : applique le niveau et les armes de départ annoncés par `pid`
## (rien d'annoncé : arme de départ par défaut, niveau 1).
func apply_loadout(pid: int) -> void:
	var pd: PlayerData = data.get(pid)
	if pd == null or not loadouts.has(pid):
		return
	var lo: Dictionary = loadouts[pid]
	pd.level = int(lo.level)
	pd.weapons = starting_hands(lo.ids)
	pd.slot = 0
	pd.bag = []
	for id in lo.ids:
		if KnifeDB.exists(id):
			pd.knife = id
			break


# --------------------------------------------------------------------------
# API serveur
# --------------------------------------------------------------------------

func add_points(pid: int, amount: int) -> void:
	if not multiplayer.is_server() or not data.has(pid) or amount == 0:
		return
	var pd: PlayerData = data[pid]
	pd.points = maxi(pd.points + amount, 0)
	_cl_points.rpc(pid, pd.points, amount)


## Débite `amount` si le joueur en a les moyens. Retourne false sinon.
## Un montant négatif est refusé (il créditerait des points au lieu d'en débiter).
func try_spend(pid: int, amount: int) -> bool:
	if not multiplayer.is_server() or not data.has(pid) or amount < 0:
		return false
	var pd: PlayerData = data[pid]
	if pd.points < amount:
		return false
	pd.points -= amount
	_cl_points.rpc(pid, pd.points, -amount)
	return true


func sync_stats(pid: int) -> void:
	if multiplayer.is_server() and data.has(pid):
		_cl_stats.rpc(pid, data[pid].stats_dict())


func sync_inventory(pid: int) -> void:
	if multiplayer.is_server() and data.has(pid):
		_cl_inventory.rpc(pid, data[pid].inventory_dict())


## Serveur : range une arme (construite, ramassée) dans l'inventaire de partie
## du joueur ; faux s'il est plein (GAME_CONCEPT §4.11 : une place libre est
## nécessaire).
func give_to_bag(pid: int, w: Dictionary) -> bool:
	if not multiplayer.is_server() or not data.has(pid) or not GameWeapon.add_to_bag(data[pid], w):
		return false
	sync_inventory(pid)
	return true


## Envoie tout l'état à tout le monde (début de partie).
func sync_all() -> void:
	for pid in data:
		sync_stats(pid)
		sync_inventory(pid)


# --------------------------------------------------------------------------
# Réception côté clients (et serveur, via call_local)
# --------------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _cl_points(pid: int, total: int, delta: int) -> void:
	var pd: PlayerData = data.get(pid)
	if pd == null:
		return
	pd.points = total
	points_event.emit(pid, delta)
	stats_changed.emit(pid)


@rpc("authority", "call_local", "reliable")
func _cl_stats(pid: int, d: Dictionary) -> void:
	var pd: PlayerData = data.get(pid)
	if pd == null:
		return
	if not multiplayer.is_server():
		pd.apply_stats(d)
	stats_changed.emit(pid)


@rpc("authority", "call_local", "reliable")
func _cl_inventory(pid: int, d: Dictionary) -> void:
	var pd: PlayerData = data.get(pid)
	if pd == null:
		return
	if not multiplayer.is_server():
		pd.apply_inventory(d)
	inventory_changed.emit(pid)
