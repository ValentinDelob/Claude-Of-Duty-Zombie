class_name GameWeapon
extends RefCounted
## Arme de partie (GAME_CONCEPT §4.9, §4.12, §4.13) : exemplaire tenu en main
## ou rangé dans l'inventaire de partie, avec son niveau, sa rareté et ses
## pièces. Données et règles pures, partagées par le serveur (dégâts, cadence,
## munitions, échanges) et les clients (prédiction, HUD).
##
## Une arme de partie est un Dictionary sérialisable (envoyé tel quel par
## Session.sync_inventory) :
##   {"id", "pap" (en sommeil, toujours faux), "mag", "reserve",
##    "uid" (exemplaire : OwnedWeapon.uid, "" pour une arme prêtée),
##    "level" (1 à PlayerProfile.MAX_LEVEL), "rarity" (OwnedWeapon.Rarity),
##    "parts": [{"id", "level", "mods": {statistique: fraction}}]}
## L'exemplaire de profil correspondant est un OwnedWeapon (from_owned /
## to_owned) : c'est lui qui décrit l'arme ; le dictionnaire y ajoute les
## munitions de la partie.
##
## Statistiques effectives (stats) : celles de WeaponDB, puis
##   * niveau : dégâts × (1 + 0,1 × (niveau − 1)) (§4.9 : une arme niveau 11
##     fait le double de son niveau 1) ;
##   * pièces : modificateurs additionnés par statistique (bonus positif, malus
##     négatif, en fraction : {"damage": 0.25, "fire_rate": -0.05}), appliqués
##     ensuite (voir MODS).
## Exemple : niveau 5, pièces +25 % et +10 % de dégâts : 100 × 1,4 × 1,35 = 189.

## Armes en main (§4.12) et places de l'inventaire de partie.
const HANDS := 3
const BAG := 4
## Hausse des dégâts par niveau, en fraction des dégâts de base (§4.3, §4.9).
const LEVEL_DAMAGE_STEP := 0.1
## Facteur le plus bas qu'un malus peut atteindre (jamais 0, jamais négatif :
## −95 % de cadence donne au pire 10 % de la cadence de base).
const MIN_FACTOR := 0.1

## Modificateurs des pièces : nom -> [clés de WeaponDB touchées, sens].
## Sens « mul » : valeur × (1 + m) (plus = mieux : dégâts, cadence, chargeur,
## réserve) ; « div » : valeur ÷ (1 + m) (plus petit = mieux : temps de
## rechargement, recul, dispersion). Un bonus est donc toujours positif :
## « rechargement +20 % » = durée ÷ 1,2.
const MODS := {
	"damage": [["damage", "splash_damage", "burn_dps"], "mul"],
	"fire_rate": [["rpm"], "mul"],
	"reload": [["reload"], "div"],
	"recoil": [["recoil", "recoil_side"], "div"],
	"accuracy": [["spread_hip", "spread_move", "bloom", "spread_ads"], "div"],
	"mag": [["mag"], "mul"],
	"reserve": [["reserve"], "mul"],
}
## Autres noms acceptés (WeaponPart parlait de « rate »).
const MOD_ALIASES := {"rate": "fire_rate", "precision": "accuracy", "magazine": "mag", "ammo": "reserve"}
## Statistiques entières (arrondies, chargeur d'au moins 1 coup).
const INT_STATS := ["damage", "splash_damage", "rpm", "mag", "reserve"]

## Couleurs des raretés (HUD, panneau d'inventaire ; même ordre que
## OwnedWeapon.Rarity).
const RARITY_COLORS := [Color(0.82, 0.82, 0.78), Color(0.35, 0.62, 1.0), Color(0.72, 0.4, 1.0),
	Color(1.0, 0.62, 0.15), Color(0.95, 0.25, 0.3)]
const RARITY_NAMES := [["COMMUNE", "COMMON"], ["RARE", "RARE"], ["ÉPIQUE", "EPIC"],
	["LÉGENDAIRE", "LEGENDARY"], ["UNIQUE", "UNIQUE"]]

static var _cache: Dictionary = {}


# --------------------------------------------------------------------------
# Création et conversion
# --------------------------------------------------------------------------

## Nouvelle arme de partie, chargeur et réserve pleins (statistiques effectives).
## `parts` : pièces au format du dictionnaire (voir en-tête) ou WeaponPart.
static func make(id: String, lvl := 1, rarity := 0, parts: Array = [], uid := "") -> Dictionary:
	var ps := []
	for p in parts:
		var pd := _part_dict(p)
		if not pd.is_empty():
			ps.append(pd)
	var w := {"id": id, "pap": false, "mag": 0, "reserve": 0, "uid": uid,
		"level": clampi(lvl, 1, PlayerProfile.MAX_LEVEL),
		"rarity": clampi(rarity, 0, OwnedWeapon.RARITY_KEYS.size() - 1), "parts": ps}
	var s := stats(w)
	w.mag = int(s.mag)
	w.reserve = int(s.reserve)
	return w


## Arme de partie d'un exemplaire du profil (arme de départ, arme construite).
static func from_owned(o: OwnedWeapon) -> Dictionary:
	if o == null:
		return {}
	return make(o.weapon_id, o.level, o.rarity, o.parts, o.uid)


## Exemplaire décrit par une arme de partie (pour le butin à l'évacuation).
static func to_owned(w: Dictionary) -> OwnedWeapon:
	var o := OwnedWeapon.create(String(w.get("id", "")), level_of(w), rarity_of(w) as OwnedWeapon.Rarity)
	o.uid = String(w.get("uid", ""))
	for pd in w.get("parts", []):
		if o.parts.size() >= o.slot_count():
			break
		var p := WeaponPart.create(String(pd.get("id", "part")), int(pd.get("level", 1)), pd.get("mods", {}))
		p.uid = String(pd.get("uid", ""))
		o.parts.append(p)
	return o


static func _part_dict(p: Variant) -> Dictionary:
	if p is WeaponPart:
		return {"id": p.part_id, "uid": p.uid, "level": p.level, "mods": p.mods.duplicate()}
	if p is Dictionary:
		return {"id": String(p.get("id", "")), "uid": String(p.get("uid", "")),
			"level": clampi(int(p.get("level", 1)), 1, PlayerProfile.MAX_LEVEL),
			"mods": WeaponPart.clean_mods(p.get("mods", {}))}
	return {}


# --------------------------------------------------------------------------
# Niveau, rareté, score, puissance
# --------------------------------------------------------------------------

static func level_of(w: Dictionary) -> int:
	return clampi(int(w.get("level", 1)), 1, PlayerProfile.MAX_LEVEL)


static func rarity_of(w: Dictionary) -> int:
	return clampi(int(w.get("rarity", 0)), 0, OwnedWeapon.RARITY_KEYS.size() - 1)


## Score (§4.9) : niveau de l'arme + somme des niveaux de ses pièces.
static func score(w: Dictionary) -> int:
	if w.is_empty():
		return 0
	var s := level_of(w)
	for p in w.get("parts", []):
		s += clampi(int(p.get("level", 1)), 1, PlayerProfile.MAX_LEVEL)
	return s


## Puissance (§4.13) : somme des scores des armes en main (l'inventaire ne
## compte pas).
static func power(hands: Array) -> int:
	var total := 0
	for i in mini(hands.size(), HANDS):
		total += score(hands[i])
	return total


## Un joueur de niveau `player_level` peut-il équiper l'arme (§4.9) ?
static func can_equip(w: Dictionary, player_level: int) -> bool:
	return not w.is_empty() and level_of(w) <= player_level


static func rarity_color(r: int) -> Color:
	return RARITY_COLORS[clampi(r, 0, RARITY_COLORS.size() - 1)]


static func rarity_name(r: int) -> String:
	var n: Array = RARITY_NAMES[clampi(r, 0, RARITY_NAMES.size() - 1)]
	return Lang.t(n[0], n[1])


## Point d'accroche de l'effet visuel des raretés légendaire et unique (§4.9 :
## éclats, éclairs… sur l'arme seule, sans aucun avantage) : "legendary",
## "unique" ou "" (aucun effet). Rien ne l'affiche encore ; le futur effet
## (ViewModel pour la vue FPS, PlayerModel pour les coéquipiers) lira cette
## valeur, sans jamais toucher aux statistiques.
static func visual_effect(w: Dictionary) -> String:
	match rarity_of(w):
		OwnedWeapon.Rarity.LEGENDARY:
			return "legendary"
		OwnedWeapon.Rarity.UNIQUE:
			return "unique"
	return ""


# --------------------------------------------------------------------------
# Statistiques effectives
# --------------------------------------------------------------------------

## Multiplicateur de dégâts du niveau (1 au niveau 1, 2 au niveau 11).
static func damage_mult(lvl: int) -> float:
	return 1.0 + LEVEL_DAMAGE_STEP * float(clampi(lvl, 1, PlayerProfile.MAX_LEVEL) - 1)


## Modificateurs des pièces additionnés par statistique (noms de MODS ; les
## noms inconnus sont ignorés).
static func mod_totals(parts: Array) -> Dictionary:
	var out := {}
	for p in parts:
		var mods: Variant = p.mods if p is WeaponPart else (p.get("mods", {}) if p is Dictionary else {})
		if not mods is Dictionary:
			continue
		for k in mods:
			var key := String(k)
			key = MOD_ALIASES.get(key, key)
			var v: Variant = mods[k]
			if MODS.has(key) and (v is float or v is int) and is_finite(float(v)):
				out[key] = float(out.get(key, 0.0)) + float(v)
	return out


## Statistiques `base` (WeaponDB.stats) d'une arme de niveau `lvl` portant les
## modificateurs `totals` (mod_totals). Pure ; rend une copie modifiable.
static func apply(base: Dictionary, lvl: int, totals: Dictionary) -> Dictionary:
	var s := base.duplicate()
	var lm := damage_mult(lvl)
	for k in MODS.damage[0]:
		if s.has(k):
			s[k] = float(s[k]) * lm
	for m in totals:
		var spec: Array = MODS[m]
		var f := maxf(1.0 + float(totals[m]), MIN_FACTOR)
		for k in spec[0]:
			if s.has(k):
				s[k] = float(s[k]) * f if spec[1] == "mul" else float(s[k]) / f
	for k in INT_STATS:
		if s.has(k):
			s[k] = maxi(roundi(float(s[k])), 1 if k == "mag" or k == "rpm" else 0)
	return s


## Statistiques effectives d'une arme de partie (lecture seule, en cache ;
## une arme niveau 1 sans pièce rend exactement WeaponDB.stats).
static func stats(w: Dictionary) -> Dictionary:
	var id := String(w.get("id", ""))
	var pap := bool(w.get("pap", false))
	var base := WeaponDB.stats(id, pap)
	var lvl := level_of(w)
	var parts: Array = w.get("parts", [])
	if lvl == 1 and parts.is_empty():
		return base
	var totals := mod_totals(parts)
	var keys := totals.keys()
	keys.sort()
	var key := "%s|%s|%d" % [id, pap, lvl]
	for k in keys:
		key += "|%s=%s" % [k, totals[k]]
	var main := not ThreadGuard.worker()
	if main and _cache.has(key):
		return _cache[key]
	var s := apply(base, lvl, totals)
	s.make_read_only()
	if main:
		_cache[key] = s
	return s


static func fire_interval(w: Dictionary) -> float:
	return 60.0 / float(stats(w).rpm)


## Multiplicateur de dégâts selon la distance (WeaponDB.falloff, portée de
## l'arme de partie).
static func falloff(w: Dictionary, distance: float) -> float:
	var r: float = stats(w).range
	if distance <= r:
		return 1.0
	return clampf(1.0 - 0.5 * (distance - r) / r, 0.5, 1.0)


## Remplit chargeur et réserve (statistiques effectives).
static func refill(w: Dictionary) -> void:
	var s := stats(w)
	w.mag = int(s.mag)
	w.reserve = int(s.reserve)


# --------------------------------------------------------------------------
# Équipement et inventaire de partie (§4.12) : règles pures sur PlayerData
# --------------------------------------------------------------------------

## Range une arme (construite, ramassée) dans la première place libre de
## l'inventaire ; faux s'il est plein.
static func add_to_bag(pd: PlayerData, w: Dictionary) -> bool:
	if w.is_empty() or pd.bag.size() >= BAG:
		return false
	pd.bag.append(w)
	return true


## Raison du refus d'un échange entre l'emplacement en main `hand` (0 à
## HANDS − 1) et la place d'inventaire `bag` (0 à BAG − 1) ; "" s'il est
## permis. Une place vide d'un côté : l'arme passe simplement de l'autre.
static func swap_refusal(pd: PlayerData, hand: int, bag: int) -> String:
	if pd == null:
		return "joueur inconnu"
	if pd.life != PlayerData.Life.ALIVE:
		return "joueur à terre ou mort"
	if hand < 0 or hand >= HANDS or bag < 0 or bag >= BAG:
		return "place invalide"
	var hw: Dictionary = pd.weapons[hand] if hand < pd.weapons.size() else {}
	var bw: Dictionary = pd.bag[bag] if bag < pd.bag.size() else {}
	if hw.is_empty() and bw.is_empty():
		return "places vides"
	if not bw.is_empty() and not can_equip(bw, pd.level):
		return "niveau trop élevé"
	return ""


## Échange (swap_refusal d'abord) : l'arme en main va dans l'inventaire et
## inversement, munitions comprises. Les emplacements restent sans trou (une
## arme sortie de la main décale les suivantes) ; l'arme tenue reste la même
## si elle n'est pas concernée, sinon l'emplacement tenu garde son numéro.
## Rend la raison du refus ("" : fait).
static func swap(pd: PlayerData, hand: int, bag: int) -> String:
	var why := swap_refusal(pd, hand, bag)
	if why != "":
		return why
	var has_h := hand < pd.weapons.size()
	var has_b := bag < pd.bag.size()
	if has_h and has_b:
		var tmp: Dictionary = pd.weapons[hand]
		pd.weapons[hand] = pd.bag[bag]
		pd.bag[bag] = tmp
	elif has_h:
		pd.bag.append(pd.weapons[hand])
		pd.weapons.remove_at(hand)
		if pd.slot > hand:
			pd.slot -= 1
	else:
		pd.weapons.append(pd.bag[bag])
		pd.bag.remove_at(bag)
		if pd.weapons.size() == 1:
			pd.slot = 0
	pd.slot = clampi(pd.slot, 0, maxi(pd.weapons.size() - 1, 0))
	return ""
