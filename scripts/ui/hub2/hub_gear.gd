class_name HubGear
extends RefCounted
## Textes et règles des armes et des pièces au hub (ARSENAL, fenêtre
## d'installation, JOUER ; docs/HUB_PLAN.md §9). Fonctions pures (testées par
## tests/test_hub_gear.gd) : nom et famille d'une arme, filtre, nom d'une
## pièce et ordre de ses modificateurs, raison d'un refus de montage
## (OwnedWeapon.can_mount), tri des pièces, statistiques effectives
## (GameWeapon.stats).

## Nom d'une pièce d'après son premier modificateur (provisoire, HUB_PLAN
## §3.3 : pas encore de catalogue de pièces) [FR, EN].
const PART_NAMES := {
	"damage": ["Renfort", "Reinforcement"], "fire_rate": ["Ressort", "Spring"], "reload": ["Guide", "Guide rail"],
	"recoil": ["Amortisseur", "Damper"], "accuracy": ["Mire", "Sight"], "mag": ["Rallonge", "Mag extension"],
	"reserve": ["Cartouchière", "Bandolier"],
}

## Familles d'armes (WeaponDB.CLASSES) : nom [FR, EN] (les mots de
## WeaponDB.FAMILIES en casse de phrase, vérifié par tests/test_hub_gear.gd).
const CLASS_NAMES := {
	"pistol": ["Pistolet", "Pistol"], "revolver": ["Revolver", "Revolver"],
	"smg": ["Mitraillette", "SMG"], "rifle": ["Fusil d'assaut", "Assault rifle"],
	"lmg": ["Mitrailleuse", "Machine gun"], "shotgun": ["Fusil à pompe", "Shotgun"],
	"sniper": ["Fusil de précision", "Sniper rifle"], "launcher": ["Lance-grenades", "Grenade launcher"],
	"rocket": ["Lance-roquettes", "Rocket launcher"], "melee": ["Corps à corps", "Melee"],
}

## Précision (0 à 100) = 100 − 12 × dispersion à la hanche (°), provisoire.
const ACCURACY_PER_DEG := 12.0


# --------------------------------------------------------------------------
# Armes
# --------------------------------------------------------------------------

## Arme de corps à corps : la batte (WeaponDB, famille « melee ») ou un
## couteau (KnifeDB, attaque rapide séparée, plus une arme de base).
static func is_melee(id: String) -> bool:
	return WeaponDB.is_melee(id) or (KnifeDB.exists(id) and not WeaponDB.exists(id))


## Nom affiché d'une arme (source unique du hub) : le nom original du jeu
## (WeaponDB.display_name, jamais l'identifiant interne ni un nom réel) ;
## identifiant inconnu : « ? ».
static func weapon_name(id: String) -> String:
	if WeaponDB.exists(id):
		return WeaponDB.display_name(id)
	if KnifeDB.exists(id):
		return KnifeDB.display_name(id)
	return "?"


## Famille d'une arme en casse de phrase (« Mitraillette », « Corps à corps »).
static func weapon_class(id: String) -> String:
	if not WeaponDB.exists(id):
		return Lang.t("Corps à corps", "Melee") if is_melee(id) else Lang.t("Arme", "Weapon")
	var c: Array = CLASS_NAMES.get(String(WeaponDB.stats(id).get("class", "")), ["Arme", "Weapon"])
	return Lang.t(c[0], c[1])


## L'arme passe-t-elle le filtre `filter` (« all », « firearm », « melee »,
## « usable ») pour un joueur de niveau `player_level` ?
static func passes(w: OwnedWeapon, filter: String, player_level: int) -> bool:
	match filter:
		"firearm":
			return not is_melee(w.weapon_id)
		"melee":
			return is_melee(w.weapon_id)
		"usable":
			return w.level <= player_level
	return true


# --------------------------------------------------------------------------
# Pièces
# --------------------------------------------------------------------------

## Modificateur principal d'une pièce : celui de son identifiant
## (« part_<premier modificateur> », LootRules.roll_part, HubRewards), sinon
## le plus grand bonus ; "" sans modificateur. (L'ordre des clés ne compte
## pas : le profil les enregistre triées.)
static func first_mod(p: WeaponPart) -> String:
	var from_id := GameWeapon.MOD_ALIASES.get(p.part_id.trim_prefix("part_"), p.part_id.trim_prefix("part_")) as String
	for k in p.mods:
		if GameWeapon.MOD_ALIASES.get(String(k), String(k)) == from_id:
			return from_id
	var best := ""
	var best_v := -INF
	for k in p.mods:
		var key: String = GameWeapon.MOD_ALIASES.get(String(k), String(k))
		var v := float(p.mods[k])
		if v > best_v or (v == best_v and LootRules.PART_MODS.find(key) < LootRules.PART_MODS.find(best)):
			best = key
			best_v = v
	return best


## Modificateurs dans l'ordre d'affichage : le principal d'abord, puis l'ordre
## de LootRules.PART_MODS.
static func ordered_mods(p: WeaponPart) -> Dictionary:
	var main := first_mod(p)
	var keys := p.mods.keys()
	keys.sort_custom(func(a, b):
		var ka: String = GameWeapon.MOD_ALIASES.get(String(a), String(a))
		var kb: String = GameWeapon.MOD_ALIASES.get(String(b), String(b))
		if (ka == main) != (kb == main):
			return ka == main
		return LootRules.PART_MODS.find(ka) < LootRules.PART_MODS.find(kb))
	var out := {}
	for k in keys:
		out[k] = p.mods[k]
	return out


static func part_name(p: WeaponPart) -> String:
	var n: Array = PART_NAMES.get(first_mod(p), ["Pièce", "Part"])
	return Lang.t(n[0], n[1])


## Raison pour laquelle `p` ne se monte pas sur `w` (joueur de niveau
## `player_level`) ; "" si elle se monte (OwnedWeapon.can_mount).
static func mount_refusal(w: OwnedWeapon, p: WeaponPart, player_level: int) -> String:
	if w == null or p == null:
		return Lang.t("INTROUVABLE", "NOT FOUND")
	if w.uid.begins_with(BaseWeapons.UID_PREFIX):
		return Lang.t("ARME DE BASE", "BASE WEAPON")
	var over_w := p.level > w.level
	var over_p := p.level > player_level
	if over_w and over_p:
		return Lang.t("NIVEAU %d : AU-DESSUS DE L'ARME (%d) ET DU VÔTRE (%d)",
				"LEVEL %d: ABOVE THE WEAPON (%d) AND YOURS (%d)") % [p.level, w.level, player_level]
	if over_w:
		return Lang.t("NIVEAU %d : AU-DESSUS DE L'ARME (%d)", "LEVEL %d: ABOVE THE WEAPON (%d)") % [p.level, w.level]
	if over_p:
		return Lang.t("NIVEAU %d : AU-DESSUS DU VÔTRE (%d)", "LEVEL %d: ABOVE YOURS (%d)") % [p.level, player_level]
	if w.free_slots() <= 0:
		return Lang.t("AUCUN EMPLACEMENT LIBRE", "NO FREE SLOT")
	if not w.can_mount(p, player_level):
		return Lang.t("DÉJÀ INSTALLÉE", "ALREADY MOUNTED")
	return ""


## Tri des pièces : niveau décroissant (`sort` « level »), ou par
## modificateur (« mod » : ordre de LootRules.PART_MODS) puis niveau ; à
## égalité, la plus récente.
static func part_before(a: WeaponPart, b: WeaponPart, sort: String) -> bool:
	var na := a.uid.trim_prefix("p").to_int()
	var nb := b.uid.trim_prefix("p").to_int()
	if sort == "mod":
		var ma := LootRules.PART_MODS.find(first_mod(a))
		var mb := LootRules.PART_MODS.find(first_mod(b))
		if ma != mb:
			return ma < mb
	if a.level != b.level:
		return a.level > b.level
	return na > nb


## La pièce se monte-t-elle sur au moins une arme de l'arsenal ?
static func mountable_anywhere(pr: PlayerProfile, p: WeaponPart) -> bool:
	for w in pr.weapons:
		if w.can_mount(p, pr.level()):
			return true
	return false


# --------------------------------------------------------------------------
# Statistiques
# --------------------------------------------------------------------------

## Statistiques effectives d'un exemplaire (GameWeapon.stats), et les mêmes
## sans ses pièces (pour la part apportée par les pièces).
static func fire_stats(w: OwnedWeapon, with_parts := true) -> Dictionary:
	if with_parts:
		return GameWeapon.stats(GameWeapon.from_owned(w))
	return GameWeapon.stats(GameWeapon.make(w.weapon_id, w.level, w.rarity))


## Précision affichée (0 à 100) d'après la dispersion à la hanche.
static func accuracy(s: Dictionary) -> int:
	return clampi(roundi(100.0 - ACCURACY_PER_DEG * float(s.get("spread_hip", 0.0))), 0, 100)
