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
