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
## Armes en main (GAME_CONCEPT §4.12) : 0 à GameWeapon.HANDS armes de partie
## (Dictionary, voir GameWeapon : id, munitions, niveau, rareté, pièces), sans
## trou ; `slot` : celle qui est tenue.
var weapons: Array = []
var slot := 0
## Inventaire de partie : 0 à GameWeapon.BAG armes de partie, échangeables
## avec les armes en main (GameWeapon.swap, Combat.srv_swap). Gardé tel quel
## à terre, à la mort et à la réapparition.
var bag: Array = []
## Niveau du joueur (profil, annoncé au début de la partie :
## Session.srv_set_loadout) : une arme de niveau supérieur ne s'équipe pas
## (§4.9). Répliqué avec les statistiques (tableau des scores).
var level := 1
## Couteau de mêlée (KnifeDB).
var knife := KnifeDB.DEFAULT
## Armes mises de côté pendant que le joueur est à terre ou mort (serveur,
## copie chez les clients : inventory_dict).
var saved_weapons: Array = []
## Emplacement de grenade (GAME_CONCEPT §4.12 bis) : UNE sorte d'objet à la
## fois (`throwable`, ThrowableRules.Kind) et sa quantité (`grenades`, au plus
## ThrowableRules.SLOT_MAX). Vide (0), l'emplacement redevient « grenades ».
var throwable: int = ThrowableRules.Kind.FRAG
var grenades := ThrowableRules.FRAG_START


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


func is_alive() -> bool:
	return life == Life.ALIVE


func inventory_dict() -> Dictionary:
	return {"weapons": weapons.duplicate(true), "slot": slot, "knife": knife, "bag": bag.duplicate(true),
		"saved": saved_weapons.duplicate(true)}


func apply_inventory(d: Dictionary) -> void:
	weapons = d.get("weapons", []).duplicate(true)
	slot = d.get("slot", 0)
	knife = d.get("knife", KnifeDB.DEFAULT)
	bag = d.get("bag", []).duplicate(true)
	# Armes mises de côté à terre ou mort : le client les compte dans son
	# butin si l'équipe s'évacue pendant qu'il est spectateur (ProfileLoot).
	var s: Variant = d.get("saved", [])
	saved_weapons = (s as Array).duplicate(true) if s is Array else []


## Puissance (GAME_CONCEPT §4.13) : somme des scores des armes en main.
func power() -> int:
	return GameWeapon.power(weapons)


func stats_dict() -> Dictionary:
	return {"points": points, "kills": kills, "headshots": headshots, "downs": downs,
		"revives": revives, "health": health, "max_health": max_health, "life": life,
		"throwable": throwable, "grenades": grenades, "level": level}


func apply_stats(d: Dictionary) -> void:
	points = d.get("points", points)
	kills = d.get("kills", kills)
	headshots = d.get("headshots", headshots)
	downs = d.get("downs", downs)
	revives = d.get("revives", revives)
	health = d.get("health", health)
	max_health = d.get("max_health", max_health)
	life = d.get("life", life)
	throwable = d.get("throwable", throwable)
	grenades = d.get("grenades", grenades)
	level = d.get("level", level)
