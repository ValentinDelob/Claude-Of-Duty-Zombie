class_name PlayerData
extends RefCounted
## État de gameplay d'un joueur. Le serveur possède la version qui fait foi ;
## les clients en reçoivent une copie (Session._cl_*).

enum Life { ALIVE, DOWNED, DEAD }

const BASE_HEALTH := 100
const STARTING_POINTS := 500

var peer_id := 0
var points := STARTING_POINTS
var kills := 0
var headshots := 0
var downs := 0
var revives := 0
var health := BASE_HEALTH
var max_health := BASE_HEALTH
var life: Life = Life.ALIVE
## Array de Dictionary {id, pap, mag, reserve} (voir WeaponDB.new_instance)
var weapons: Array = []
var slot := 0
## Couteau de mêlée (KnifeDB) : "knife", ou "bowie" une fois acheté.
var knife := KnifeDB.DEFAULT
var perks: PackedStringArray = []
## Armes mises de côté pendant que le joueur est à terre (serveur).
var saved_weapons: Array = []


func _init(id := 0) -> void:
	peer_id = id


func current_weapon() -> Dictionary:
	if weapons.is_empty():
		return {}
	return weapons[clampi(slot, 0, weapons.size() - 1)]


func has_weapon(id: String) -> int:
	for i in weapons.size():
		if weapons[i].id == id:
			return i
	return -1


func has_perk(id: String) -> bool:
	return id in perks


func is_alive() -> bool:
	return life == Life.ALIVE


func inventory_dict() -> Dictionary:
	return {"weapons": weapons.duplicate(true), "slot": slot, "knife": knife}


func apply_inventory(d: Dictionary) -> void:
	weapons = d.get("weapons", []).duplicate(true)
	slot = d.get("slot", 0)
	knife = d.get("knife", KnifeDB.DEFAULT)


func stats_dict() -> Dictionary:
	return {"points": points, "kills": kills, "headshots": headshots, "downs": downs,
		"revives": revives, "health": health, "max_health": max_health, "life": life,
		"perks": perks}


func apply_stats(d: Dictionary) -> void:
	points = d.get("points", points)
	kills = d.get("kills", kills)
	headshots = d.get("headshots", headshots)
	downs = d.get("downs", downs)
	revives = d.get("revives", revives)
	health = d.get("health", health)
	max_health = d.get("max_health", max_health)
	life = d.get("life", life)
	perks = d.get("perks", perks)
