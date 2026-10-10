class_name PlayerData
extends RefCounted
## État de gameplay d'un joueur. Le serveur possède la version qui fait foi ;
## les clients en reçoivent une copie (Session._cl_*).

enum Life { ALIVE, DOWNED, DEAD }

const BASE_HEALTH := 100
## Ferraille au départ de la partie (`points` = ferraille, GAME_CONCEPT §4.8) :
## chaque joueur part de 0.
const STARTING_POINTS := 0

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
## Arme de bonus tenue (FAUCHEUSE : WeaponDB.POWERUP_WEAPONS), {} sinon : elle
## remplace l'arme en main tant que le joueur est debout ; l'inventaire reste
## intact dessous et revient à la fin du bonus.
var powerup_weapon: Dictionary = {}
## Grenades à fragmentation (2 au départ, +2 par manche, 4 au plus) et
## SINGE-TAMBOUR (arme tactique de la boîte mystère). Voir ThrowableRules.
var grenades := ThrowableRules.FRAG_START
var monkeys := 0
var has_monkeys := false


func _init(id := 0) -> void:
	peer_id = id


func current_weapon() -> Dictionary:
	if not powerup_weapon.is_empty() and life == Life.ALIVE:
		return powerup_weapon
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
	return {"weapons": weapons.duplicate(true), "slot": slot, "knife": knife, "powerup": powerup_weapon.duplicate()}


func apply_inventory(d: Dictionary) -> void:
	weapons = d.get("weapons", []).duplicate(true)
	slot = d.get("slot", 0)
	knife = d.get("knife", KnifeDB.DEFAULT)
	powerup_weapon = d.get("powerup", {}).duplicate()


func stats_dict() -> Dictionary:
	return {"points": points, "kills": kills, "headshots": headshots, "downs": downs,
		"revives": revives, "health": health, "max_health": max_health, "life": life,
		"perks": perks, "grenades": grenades, "monkeys": monkeys, "has_monkeys": has_monkeys}


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
	grenades = d.get("grenades", grenades)
	monkeys = d.get("monkeys", monkeys)
	has_monkeys = d.get("has_monkeys", has_monkeys)
