class_name BaseWeapons
extends RefCounted
## Armes de base (GAME_CONCEPT §4.10) : niveau 1, communes, sans pièce,
## données à tous les joueurs, toujours disponibles. Elles ne sont pas rangées
## dans l'arsenal du profil (on ne peut donc ni les retirer ni les recycler) ;
## une arme de base améliorée en partie et ramenée devient un nouvel
## exemplaire de l'arsenal (PlayerProfile.add_weapon).
##
## Armes de base : le pistolet de départ (WeaponDB.STARTING_WEAPON, la
## PÉTOIRE) et la BATTE de baseball (WeaponDB.BASE_MELEE), arme de corps à
## corps qui prend un emplacement en main. Le couteau n'est plus une arme de
## base : il reste l'attaque rapide séparée de tous les joueurs (KnifeDB).

## Armes de départ choisies : au moins 1, au plus 3 (§4.10).
const MIN_START := 1
const MAX_START := 3
## Préfixe des identifiants d'exemplaire des armes de base.
const UID_PREFIX := "base:"
## Anciennes armes de base d'un profil enregistré -> arme qui les remplace
## (le couteau de mêlée, arme de base provisoire avant la batte).
const RENAMED := {"knife": "bat"}

## Identifiants des armes de base, dans l'ordre d'affichage.
static func ids() -> PackedStringArray:
	return PackedStringArray([WeaponDB.STARTING_WEAPON, WeaponDB.BASE_MELEE])


static func is_base(id: String) -> bool:
	return id in ids()


## Sélection par défaut (valide) : toutes les armes de base, dans la limite de 3.
static func default_selection() -> PackedStringArray:
	return ids().slice(0, MAX_START)


## Exemplaire d'une arme de base : niveau 1, commune, sans pièce ; null si
## `id` n'est pas une arme de base.
static func make(id: String) -> OwnedWeapon:
	if not is_base(id):
		return null
	var w := OwnedWeapon.create(id, 1, OwnedWeapon.Rarity.COMMON)
	w.uid = UID_PREFIX + id
	return w


## Toutes les armes de base, sous forme d'exemplaires.
static func all() -> Array[OwnedWeapon]:
	var out: Array[OwnedWeapon] = []
	for id in ids():
		out.append(make(id))
	return out


## Sélection nettoyée : armes de base seulement (une ancienne arme de base
## est remplacée par la nouvelle, RENAMED), sans doublon, au plus 3 ; la
## sélection par défaut si rien de valide ne reste.
static func clean_selection(sel: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if sel is Array or sel is PackedStringArray:
		for v in sel:
			if not (v is String or v is StringName):
				continue
			var id: String = RENAMED.get(String(v), String(v))
			if is_base(id) and not id in out:
				out.append(id)
				if out.size() >= MAX_START:
					break
	return out if out.size() >= MIN_START else default_selection()


## Sélection d'un profil enregistré mise à jour : chaque ancienne arme de
## base (RENAMED, ex. le couteau) devient celle qui la remplace (la batte) ;
## autre valeur rendue telle quelle. Un profil qui partait avec le couteau
## part donc avec la batte, sans que la sélection compte comme abîmée.
static func migrate(sel: Variant) -> Variant:
	if not (sel is Array or sel is PackedStringArray):
		return sel
	var out := []
	for v in sel:
		out.append(RENAMED.get(String(v), v) if (v is String or v is StringName) else v)
	return out


## Vrai si `sel` est déjà une sélection valide (1 à 3 armes de base distinctes).
static func selection_ok(sel: Variant) -> bool:
	if not (sel is Array or sel is PackedStringArray):
		return false
	if sel.size() < MIN_START or sel.size() > MAX_START:
		return false
	var clean := clean_selection(sel)
	if clean.size() != sel.size():
		return false
	for i in clean.size():
		var v: Variant = sel[i]
		if not (v is String or v is StringName) or String(v) != clean[i]:
			return false
	return true
