class_name WeaponPart
extends RefCounted
## Pièce d'arme possédée (GAME_CONCEPT §4.9) : rangée dans l'onglet des pièces
## du profil (illimité) ou installée sur une arme (OwnedWeapon.parts).
## Données pures, sans interface ; (dé)sérialisées par to_dict / from_dict.

## Longueur maximale d'un identifiant (pièce définie, exemplaire, modificateur).
const MAX_ID_LEN := 64
## Nombre maximal de modificateurs lus depuis un fichier (garde-fou).
const MAX_MODS := 32

## Identifiant unique de l'exemplaire (attribué par le profil : "p12").
var uid := ""
## Identifiant de la pièce définie (catalogue des pièces, à venir).
var part_id := ""
## Niveau de la pièce (1 à PlayerProfile.MAX_LEVEL).
var level := 1
## Modificateurs : nom de statistique -> valeur (ex. {"damage": 0.25,
## "rate": -0.05} pour « +25 % de dégâts, −5 % de coups par seconde »).
var mods: Dictionary = {}


static func create(id: String, lvl := 1, modifiers := {}) -> WeaponPart:
	var p := WeaponPart.new()
	p.part_id = id
	p.level = clampi(lvl, 1, PlayerProfile.MAX_LEVEL)
	p.mods = clean_mods(modifiers)
	return p


func to_dict() -> Dictionary:
	return {"uid": uid, "id": part_id, "level": level, "mods": mods.duplicate()}


## Pièce lue depuis un fichier, ou null si l'entrée est inutilisable
## (identifiant absent, mauvais types).
static func from_dict(d: Variant) -> WeaponPart:
	if not d is Dictionary:
		return null
	var id: Variant = d.get("id")
	if not id is String or not ProfileValues.id_ok(id):
		return null
	var p := WeaponPart.new()
	p.part_id = id
	p.uid = ProfileValues.clean_id(d.get("uid", ""))
	p.level = ProfileValues.to_int(d.get("level"), 1, 1, PlayerProfile.MAX_LEVEL)
	p.mods = clean_mods(d.get("mods", {}))
	return p


## Modificateurs nettoyés : clés texte non vides, valeurs numériques finies.
static func clean_mods(m: Variant) -> Dictionary:
	var out := {}
	if not m is Dictionary:
		return out
	for k in m:
		if out.size() >= MAX_MODS:
			break
		var v: Variant = m[k]
		if (k is String or k is StringName) and ProfileValues.id_ok(String(k)) \
				and (v is float or v is int) and is_finite(float(v)):
			out[String(k)] = float(v)
	return out
