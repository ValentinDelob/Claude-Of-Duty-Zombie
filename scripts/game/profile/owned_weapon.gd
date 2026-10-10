class_name OwnedWeapon
extends RefCounted
## Arme physique possédée (GAME_CONCEPT §4.9, §4.11) : un exemplaire d'une
## arme définie, avec son niveau, sa rareté et ses pièces installées.
## Plusieurs exemplaires d'une même arme coexistent (identifiant `uid`
## propre à chacun). Données et règles pures, sans interface.

enum Rarity { COMMON, RARE, EPIC, LEGENDARY, UNIQUE }

## Noms enregistrés dans le fichier (lisibles, indépendants de l'ordre de l'enum).
const RARITY_KEYS := ["common", "rare", "epic", "legendary", "unique"]
## Emplacements de pièces par rareté (§4.9) : 1 / 2 / 3 / 4 / 4.
const SLOTS := [1, 2, 3, 4, 4]

## Identifiant unique de l'exemplaire (attribué par le profil : "w7" ; les
## armes de base ont "base:<id>", voir BaseWeapons).
var uid := ""
## Identifiant de l'arme définie (aujourd'hui WeaponDB ou KnifeDB).
var weapon_id := ""
## Niveau de l'exemplaire (1 à PlayerProfile.MAX_LEVEL).
var level := 1
var rarity: Rarity = Rarity.COMMON
## Pièces installées (WeaponPart), au plus slot_count().
var parts: Array[WeaponPart] = []


static func create(id: String, lvl := 1, r: Rarity = Rarity.COMMON) -> OwnedWeapon:
	var w := OwnedWeapon.new()
	w.weapon_id = id
	w.level = clampi(lvl, 1, PlayerProfile.MAX_LEVEL)
	w.rarity = r
	return w


## Emplacements de pièces de la rareté `r`.
static func slots_for(r: Rarity) -> int:
	return SLOTS[clampi(r, 0, SLOTS.size() - 1)]


func slot_count() -> int:
	return slots_for(rarity)


func free_slots() -> int:
	return maxi(slot_count() - parts.size(), 0)


## Score (§4.9) : niveau de l'arme + somme des niveaux de ses pièces.
func score() -> int:
	var s := level
	for p in parts:
		s += p.level
	return s


## Règle de montage (§4.9) : niveau de la pièce ≤ niveau de l'arme et ≤ niveau
## du joueur, et un emplacement libre.
func can_mount(part: WeaponPart, player_level: int) -> bool:
	return part != null and free_slots() > 0 and part.level <= level and part.level <= player_level \
			and not has_part(part.uid)


## Installe la pièce si la règle le permet.
func mount(part: WeaponPart, player_level: int) -> bool:
	if not can_mount(part, player_level):
		return false
	parts.append(part)
	return true


## Retire la pièce `part_uid` et la rend (null si absente). Règle du jeu :
## une pièce retirée est détruite (§4.9), l'appelant ne la range donc pas.
func unmount(part_uid: String) -> WeaponPart:
	for i in parts.size():
		if parts[i].uid == part_uid:
			var p := parts[i]
			parts.remove_at(i)
			return p
	return null


func has_part(part_uid: String) -> bool:
	if part_uid == "":
		return false
	for p in parts:
		if p.uid == part_uid:
			return true
	return false


static func rarity_key(r: Rarity) -> String:
	return RARITY_KEYS[clampi(r, 0, RARITY_KEYS.size() - 1)]


## Rareté lue depuis son nom ; -1 si inconnu.
static func rarity_from_key(k: Variant) -> int:
	return RARITY_KEYS.find(k) if k is String else -1


func to_dict() -> Dictionary:
	var ps := []
	for p in parts:
		ps.append(p.to_dict())
	return {"uid": uid, "id": weapon_id, "level": level, "rarity": rarity_key(rarity), "parts": ps}


## Arme lue depuis un fichier, ou null si l'entrée est inutilisable. Les
## pièces illisibles ou en trop (plus que d'emplacements) sont écartées et
## comptées dans `dropped` (tableau d'un entier, incrémenté).
static func from_dict(d: Variant, dropped := [0]) -> OwnedWeapon:
	if not d is Dictionary:
		return null
	var id: Variant = d.get("id")
	var r := rarity_from_key(d.get("rarity"))
	if not id is String or not ProfileValues.id_ok(id) or r < 0:
		return null
	var w := OwnedWeapon.create(id, ProfileValues.to_int(d.get("level"), 1, 1, PlayerProfile.MAX_LEVEL), r as Rarity)
	w.uid = ProfileValues.clean_id(d.get("uid", ""))
	var ps: Variant = d.get("parts", [])
	if ps is Array:
		for pd in ps:
			var p := WeaponPart.from_dict(pd)
			if p == null or w.parts.size() >= w.slot_count():
				dropped[0] += 1
				continue
			w.parts.append(p)
	return w
