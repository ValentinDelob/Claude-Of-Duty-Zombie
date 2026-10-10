class_name PlayerProfile
extends RefCounted
## Profil permanent du joueur (GAME_CONCEPT §4.2, §4.7, §4.9 à §4.12, §4.15) :
## XP et niveau, arsenal d'armes physiques (illimité), onglet des pièces
## (illimité), échantillons (quantité par type, sans limite) et armes de
## départ choisies ; contrats, échanges faits et exemplaires déjà vus au hub
## (version 2, docs/HUB_PLAN.md §5.4). Données et règles pures, sans
## interface ; enregistrement : ProfileStore.
##
## Remplacera à terme le dossier de combat (CareerStats), qui reste pour
## l'instant à part et intact (statistiques de parties, écran du menu).

## Niveau maximum des joueurs et des armes (§4.9, §4.15).
const MAX_LEVEL := 50
## Plafond technique de l'XP et des quantités (évite tout débordement d'entier ;
## inatteignable en pratique).
const VALUE_CAP := 1 << 52

## XP totale gagnée depuis la création du profil. Le niveau en découle
## (level()) : au niveau maximum, l'XP continue d'être comptée.
var xp := 0
## Arsenal : armes physiques (OwnedWeapon), sans limite. Les armes de base
## n'y sont pas (BaseWeapons, toujours disponibles).
var weapons: Array[OwnedWeapon] = []
## Onglet des pièces : pièces non installées (WeaponPart), sans limite.
var parts: Array[WeaponPart] = []
## Échantillons : type -> quantité (> 0).
var samples: Dictionary = {}
## Armes de départ choisies (1 à 3 armes de base, §4.10).
var starting_weapons: PackedStringArray = BaseWeapons.default_selection()
## Compteur des identifiants d'exemplaire ("w1", "p2"...), jamais réutilisés.
var next_uid := 1
## Contrats du scientifique : tableau, actifs, remises (ContractState ;
## règles : ContractRules, docs/HUB_PLAN.md §5).
var contracts := ContractState.new()
## Catalogue d'échanges : identifiant -> nombre d'échanges faits
## (ExchangeRules, §6).
var exchanges_done: Dictionary = {}
## Exemplaires déjà vus au hub (armes, pièces) : les autres portent la
## pastille NOUVEAU (§5.4).
var seen_weapons: PackedStringArray = []
var seen_parts: PackedStringArray = []

static var _thresholds: PackedInt64Array = []


# --------------------------------------------------------------------------
# XP et niveau (§4.15)
# --------------------------------------------------------------------------

## XP pour passer du niveau `lvl` au suivant : 100 × niveau^1,8 (arrondi).
static func xp_to_next(lvl: int) -> int:
	return roundi(100.0 * pow(float(maxi(lvl, 1)), 1.8))


## XP totale nécessaire pour atteindre le niveau `lvl` (0 pour le niveau 1).
static func xp_for_level(lvl: int) -> int:
	if _thresholds.is_empty():
		_thresholds.resize(MAX_LEVEL + 1)
		_thresholds[0] = 0
		_thresholds[1] = 0
		for l in range(2, MAX_LEVEL + 1):
			_thresholds[l] = _thresholds[l - 1] + xp_to_next(l - 1)
	return _thresholds[clampi(lvl, 1, MAX_LEVEL)]


## Niveau atteint avec `total_xp` (1 à MAX_LEVEL).
static func level_for_xp(total_xp: int) -> int:
	var lvl := 1
	while lvl < MAX_LEVEL and total_xp >= xp_for_level(lvl + 1):
		lvl += 1
	return lvl


func level() -> int:
	return level_for_xp(xp)


func is_max_level() -> bool:
	return level() >= MAX_LEVEL


## XP gagnée depuis le début du niveau actuel (au niveau maximum : toute l'XP
## au-delà du seuil du niveau 50).
func xp_in_level() -> int:
	return xp - xp_for_level(level())


## XP manquante pour le niveau suivant (0 au niveau maximum).
func xp_to_next_level() -> int:
	if is_max_level():
		return 0
	return xp_for_level(level() + 1) - xp


## Ajoute de l'XP (ignorée si ≤ 0) ; rend le nombre de niveaux gagnés.
func add_xp(amount: int) -> int:
	if amount <= 0:
		return 0
	var before := level()
	xp = mini(xp + mini(amount, VALUE_CAP), VALUE_CAP)
	return level() - before


# --------------------------------------------------------------------------
# Arsenal (§4.9, §4.11)
# --------------------------------------------------------------------------

## Vrai si le joueur a le niveau d'utiliser (équiper, construire) l'arme.
func can_use(w: OwnedWeapon) -> bool:
	return w != null and w.level <= level()


## Range une arme dans l'arsenal (nouvel exemplaire, rien n'est remplacé) ;
## rend son identifiant d'exemplaire, "" si l'arme est inutilisable. Un
## identifiant absent, déjà pris ou d'arme de base est remplacé ; les pièces
## installées reçoivent aussi un identifiant si besoin.
func add_weapon(w: OwnedWeapon) -> String:
	if w == null or not ProfileValues.id_ok(w.weapon_id):
		return ""
	if w in weapons:
		return w.uid
	if w.uid == "" or w.uid.begins_with(BaseWeapons.UID_PREFIX) or _uid_used(w.uid):
		w.uid = _new_uid("w")
	for p in w.parts:
		if p.uid == "" or _uid_used(p.uid, w):
			p.uid = _new_uid("p")
	weapons.append(w)
	return w.uid


## Retire l'arme `uid` de l'arsenal (recyclage, §4.11) et la rend ; null si
## elle n'y est pas (les armes de base ne se retirent pas).
func remove_weapon(uid: String) -> OwnedWeapon:
	for i in weapons.size():
		if weapons[i].uid == uid:
			var w := weapons[i]
			weapons.remove_at(i)
			return w
	return null


## Arme de l'arsenal ou arme de base d'identifiant `uid`, null sinon.
func get_weapon(uid: String) -> OwnedWeapon:
	if uid == "":
		return null
	for w in weapons:
		if w.uid == uid:
			return w
	if uid.begins_with(BaseWeapons.UID_PREFIX):
		return BaseWeapons.make(uid.substr(BaseWeapons.UID_PREFIX.length()))
	return null


## Met à jour la version `uid` de l'arsenal d'après `from` (niveau, rareté,
## pièces : améliorations faites en partie, rapportées par une évacuation,
## §4.11). Les pièces sans identifiant (ou déjà pris ailleurs) en reçoivent un.
## Faux si `uid` n'est pas une arme de l'arsenal.
func update_weapon(uid: String, from: OwnedWeapon) -> bool:
	var w := _arsenal_weapon(uid)
	if w == null or from == null:
		return false
	w.level = from.level
	w.rarity = from.rarity
	w.parts.clear()
	for p in from.parts:
		if w.parts.size() >= w.slot_count():
			break
		w.parts.append(p)
	for p in w.parts:
		if p.uid == "" or _uid_used(p.uid, w):
			p.uid = _new_uid("p")
	return true


## Exemplaires de l'arsenal de l'arme définie `id`.
func versions_of(id: String) -> Array[OwnedWeapon]:
	var out: Array[OwnedWeapon] = []
	for w in weapons:
		if w.weapon_id == id:
			out.append(w)
	return out


## Recyclable : toute arme de l'arsenal ; jamais une arme de base.
func is_recyclable(uid: String) -> bool:
	return not uid.begins_with(BaseWeapons.UID_PREFIX) and get_weapon(uid) != null


# --------------------------------------------------------------------------
# Pièces (§4.9)
# --------------------------------------------------------------------------

## Range une pièce dans l'onglet des pièces ; rend son identifiant, "" si la
## pièce est inutilisable.
func add_part(p: WeaponPart) -> String:
	if p == null or not ProfileValues.id_ok(p.part_id):
		return ""
	if p in parts:
		return p.uid
	if p.uid == "" or _uid_used(p.uid):
		p.uid = _new_uid("p")
	parts.append(p)
	return p.uid


## Retire une pièce de l'onglet et la rend (null si absente).
func remove_part(uid: String) -> WeaponPart:
	for i in parts.size():
		if parts[i].uid == uid:
			var p := parts[i]
			parts.remove_at(i)
			return p
	return null


func get_part(uid: String) -> WeaponPart:
	for p in parts:
		if p.uid == uid:
			return p
	return null


## Monte une pièce de l'onglet sur une arme de l'arsenal, si la règle le
## permet (OwnedWeapon.can_mount, avec le niveau du joueur). La pièce quitte
## l'onglet.
func mount_part(weapon_uid: String, part_uid: String) -> bool:
	var w := _arsenal_weapon(weapon_uid)
	var p := get_part(part_uid)
	if w == null or p == null or not w.mount(p, level()):
		return false
	remove_part(part_uid)
	return true


## Retire une pièce d'une arme de l'arsenal : elle est détruite (§4.9).
func unmount_part(weapon_uid: String, part_uid: String) -> bool:
	var w := _arsenal_weapon(weapon_uid)
	return w != null and w.unmount(part_uid) != null


# --------------------------------------------------------------------------
# Échantillons (§4.2, §4.2 ter, §4.7)
# --------------------------------------------------------------------------

func sample_count(kind: String) -> int:
	return samples.get(kind, 0)


## Ajoute `n` échantillons du type `kind` ; rend la nouvelle quantité.
func add_samples(kind: String, n: int) -> int:
	if n <= 0 or not ProfileValues.id_ok(kind):
		return sample_count(kind)
	samples[kind] = mini(sample_count(kind) + mini(n, VALUE_CAP), VALUE_CAP)
	return samples[kind]


## Vrai si le profil a toutes les quantités demandées ({type: quantité}).
func has_samples(cost: Dictionary) -> bool:
	for k in cost:
		var n: Variant = cost[k]
		if not (k is String or k is StringName) or not n is int or n < 0:
			return false
		if sample_count(String(k)) < n:
			return false
	return true


## Consomme les quantités demandées (contrat, catalogue d'échanges), tout ou
## rien : rien n'est retiré s'il en manque une.
func consume_samples(cost: Dictionary) -> bool:
	if not has_samples(cost):
		return false
	for k in cost:
		var left: int = sample_count(String(k)) - int(cost[k])
		if left > 0:
			samples[String(k)] = left
		else:
			samples.erase(String(k))
	return true


## Retire `n` échantillons d'un type (faux, et rien retiré, s'il en manque).
func remove_samples(kind: String, n: int) -> bool:
	return consume_samples({kind: n})


# --------------------------------------------------------------------------
# Armes de départ (§4.10)
# --------------------------------------------------------------------------

## Change la sélection (1 à 3 armes de base distinctes) ; faux, sans rien
## changer, si elle est invalide.
func set_starting_weapons(sel: Variant) -> bool:
	if not BaseWeapons.selection_ok(sel):
		return false
	starting_weapons = BaseWeapons.clean_selection(sel)
	return true


## Exemplaires des armes de départ choisies.
func starting_loadout() -> Array[OwnedWeapon]:
	var out: Array[OwnedWeapon] = []
	for id in starting_weapons:
		out.append(BaseWeapons.make(id))
	return out


# --------------------------------------------------------------------------
# Pastilles NOUVEAU du hub (§5.4)
# --------------------------------------------------------------------------

## Vrai si l'arme `uid` de l'arsenal n'a pas encore été vue au hub.
func is_new_weapon(uid: String) -> bool:
	return _arsenal_weapon(uid) != null and not uid in seen_weapons


## Vrai si la pièce `uid` (onglet ou installée) n'a pas encore été vue au hub.
func is_new_part(uid: String) -> bool:
	return _part_exists(uid) and not uid in seen_parts


## Marque une arme vue (sans effet si elle n'est pas dans l'arsenal).
func mark_weapon_seen(uid: String) -> void:
	if _arsenal_weapon(uid) != null and not uid in seen_weapons:
		seen_weapons.append(uid)


## Marque une pièce vue (sans effet si elle n'existe pas).
func mark_part_seen(uid: String) -> void:
	if _part_exists(uid) and not uid in seen_parts:
		seen_parts.append(uid)


## Marque tout l'arsenal et toutes les pièces vus (migration d'un profil v1 :
## rien n'y est nouveau).
func mark_all_seen() -> void:
	for w in weapons:
		mark_weapon_seen(w.uid)
		for p in w.parts:
			mark_part_seen(p.uid)
	for p in parts:
		mark_part_seen(p.uid)


# --------------------------------------------------------------------------
# Sérialisation (format : ProfileStore)
# --------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var ws := []
	for w in weapons:
		ws.append(w.to_dict())
	var ps := []
	for p in parts:
		ps.append(p.to_dict())
	_prune_seen()
	return {
		"xp": xp,
		# Informatif (le niveau se recalcule depuis l'XP au chargement).
		"level": level(),
		"next_uid": next_uid,
		"starting_weapons": Array(starting_weapons),
		"samples": samples.duplicate(),
		"weapons": ws,
		"parts": ps,
		# Version 2 (hub) :
		"contracts": contracts.to_dict(),
		"exchanges": {"done": exchanges_done.duplicate()},
		"seen": {"weapons": Array(seen_weapons), "parts": Array(seen_parts)},
	}


## Profil lu depuis un dictionnaire de fichier. Les entrées illisibles sont
## écartées et comptées dans `dropped` (tableau d'un entier, incrémenté) pour
## que l'appelant garde une copie du fichier d'origine.
static func from_dict(d: Dictionary, dropped := [0]) -> PlayerProfile:
	var pr := PlayerProfile.new()
	pr.xp = ProfileValues.to_int(d.get("xp"), -1, 0, VALUE_CAP)
	if pr.xp < 0:
		pr.xp = 0
		dropped[0] += 1
	pr.next_uid = ProfileValues.to_int(d.get("next_uid"), 1, 1, VALUE_CAP)
	var sel: Variant = d.get("starting_weapons")
	if BaseWeapons.selection_ok(sel):
		pr.starting_weapons = BaseWeapons.clean_selection(sel)
	elif sel != null:
		dropped[0] += 1
	var sm: Variant = d.get("samples", {})
	if sm is Dictionary:
		for k in sm:
			var n := ProfileValues.to_int(sm[k], -1, -1, VALUE_CAP)
			if (k is String or k is StringName) and ProfileValues.id_ok(String(k)) and n >= 0:
				if n > 0:
					pr.samples[String(k)] = n
			else:
				dropped[0] += 1
	var ws: Variant = d.get("weapons", [])
	if ws is Array:
		for wd in ws:
			var w := OwnedWeapon.from_dict(wd, dropped)
			if w == null:
				dropped[0] += 1
			else:
				pr.add_weapon(w)
	var ps: Variant = d.get("parts", [])
	if ps is Array:
		for pd in ps:
			var p := WeaponPart.from_dict(pd)
			if p == null:
				dropped[0] += 1
			else:
				pr.add_part(p)
	# Version 2 (hub, docs/HUB_PLAN.md §5.4). Sections absentes (profil v1) :
	# contrats neufs (graine tirée), aucun échange, tout l'existant déjà vu.
	pr.contracts = ContractState.from_dict(d.get("contracts"), dropped)
	var ex: Variant = d.get("exchanges")
	if ex is Dictionary and ex.get("done", {}) is Dictionary:
		var dn: Dictionary = ex.get("done", {})
		for k in dn:
			var n := ProfileValues.to_int(dn[k], -1, -1, VALUE_CAP)
			if (k is String or k is StringName) and ProfileValues.id_ok(String(k)) and n >= 0:
				if n > 0:
					pr.exchanges_done[String(k)] = n
			else:
				dropped[0] += 1
	elif ex != null:
		dropped[0] += 1
	var seen: Variant = d.get("seen")
	if seen == null:
		pr.mark_all_seen()
	elif seen is Dictionary:
		for key in ["weapons", "parts"]:
			var list: Variant = seen.get(key, [])
			if not list is Array:
				dropped[0] += 1
				continue
			for v in list:
				var uid := ProfileValues.clean_id(v)
				if uid == "":
					dropped[0] += 1
				elif key == "weapons":
					pr.mark_weapon_seen(uid)
				else:
					pr.mark_part_seen(uid)
	else:
		dropped[0] += 1
	return pr


# --------------------------------------------------------------------------
# Interne
# --------------------------------------------------------------------------

func _arsenal_weapon(uid: String) -> OwnedWeapon:
	for w in weapons:
		if w.uid == uid:
			return w
	return null


## Pièce `uid` dans l'onglet ou installée sur une arme de l'arsenal ?
func _part_exists(uid: String) -> bool:
	if uid == "":
		return false
	if get_part(uid) != null:
		return true
	for w in weapons:
		if w.has_part(uid):
			return true
	return false


## Oublie les exemplaires vus qui n'existent plus (recyclés, pièces
## détruites) : le fichier ne grossit pas.
func _prune_seen() -> void:
	var ws := PackedStringArray()
	for uid in seen_weapons:
		if _arsenal_weapon(uid) != null:
			ws.append(uid)
	seen_weapons = ws
	var ps := PackedStringArray()
	for uid in seen_parts:
		if _part_exists(uid):
			ps.append(uid)
	seen_parts = ps


## Identifiant neuf (le compteur avance aussi au-delà des identifiants déjà
## pris, par exemple venus d'un fichier modifié).
func _new_uid(prefix: String) -> String:
	var uid := "%s%d" % [prefix, next_uid]
	while _uid_used(uid):
		next_uid += 1
		uid = "%s%d" % [prefix, next_uid]
	next_uid += 1
	return uid


## Vrai si `uid` est déjà porté par une arme ou une pièce du profil (sauf
## celles de l'arme `skip`, en cours d'ajout).
func _uid_used(uid: String, skip: OwnedWeapon = null) -> bool:
	for w in weapons:
		if w.uid == uid:
			return true
		for p in w.parts:
			if p.uid == uid:
				return true
	for p in parts:
		if p.uid == uid:
			return true
	if skip != null:
		var seen := 0
		for p in skip.parts:
			if p.uid == uid:
				seen += 1
		return seen > 1
	return false
