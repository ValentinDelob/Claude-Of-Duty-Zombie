class_name HubRewards
extends RefCounted
## Récompenses du hub (docs/HUB_PLAN.md §5.1, D9, D11) : XP d'un contrat
## selon le niveau du joueur, arme ou pièce créée AU NIVEAU DU JOUEUR. Pur
## (générateur fourni par l'appelant) ; tests/test_contracts.gd,
## tests/test_exchanges.gd.
##
## * XP d'un contrat : XP de base × (1 + facteur × (niveau − 1)), arrondie à
##   10 (facteur : règle « xp_level_factor », 0,02).
## * Arme : « any » = tirage uniforme parmi les armes du butin
##   (LootRules.weapon_pool : hors armes de base) dont le niveau de base est
##   ≤ niveau du joueur ; sinon l'arme nommée. Niveau = niveau du joueur (au
##   moins le niveau de base de l'arme), rareté fixée, aucune pièce.
## * Pièce d'un contrat, selon sa QUALITÉ (provisoire) : « standard » = tirage
##   du butin (LootRules.roll_part) ; « fine » = deux modificateurs distincts,
##   en bonus, de 10 à 25 % ; « superior » = deux bonus de 18 à 25 % ; niveau
##   = niveau du joueur. Identifiant « part_<1er modificateur> » (comme le butin).
## * Pièce d'un échange : modificateurs exacts du catalogue.

## Bornes des bonus par qualité (en %, pas de 1 %) : [min, max, nombre].
const QUALITY_MODS := {
	"fine": [10, 25, 2],
	"superior": [18, 25, 2],
}


## XP d'un contrat d'XP de base `base` remis au niveau `lvl`.
static func contract_xp(base: int, lvl: int, factor := 0.02) -> int:
	var l := clampi(lvl, 1, PlayerProfile.MAX_LEVEL)
	return roundi(maxf(base, 0) * (1.0 + factor * (l - 1)) / 10.0) * 10


## Armes possibles d'une récompense « any » au niveau `lvl` (triées).
static func weapon_choices(lvl: int) -> PackedStringArray:
	var out := PackedStringArray()
	for id in LootRules.weapon_pool():
		if WeaponDB.base_level(id) <= lvl:
			out.append(id)
	return out


## Arme d'une récompense {"weapon", "rarity"} pour un joueur de niveau `lvl` ;
## null si aucune arme n'est possible.
static func make_weapon(reward: Dictionary, lvl: int, rng: RandomNumberGenerator) -> OwnedWeapon:
	var id := String(reward.get("weapon", "any"))
	if id == "any":
		var pool := weapon_choices(lvl)
		if pool.is_empty():
			return null
		id = pool[rng.randi_range(0, pool.size() - 1)]
	if not WeaponDB.exists(id):
		return null
	var r := maxi(OwnedWeapon.rarity_from_key(reward.get("rarity", "common")), 0)
	return OwnedWeapon.create(id, maxi(lvl, WeaponDB.base_level(id)), r as OwnedWeapon.Rarity)


## Pièce de qualité `quality` pour un joueur de niveau `lvl`.
static func make_part(quality: String, lvl: int, rng: RandomNumberGenerator) -> WeaponPart:
	var l := clampi(lvl, 1, PlayerProfile.MAX_LEVEL)
	if not QUALITY_MODS.has(quality):
		# « standard » : tirage du butin, niveau fixé au niveau du joueur.
		var p := LootRules.roll_part(l, rng)
		return WeaponPart.create(String(p.id), l, p.mods)
	var spec: Array = QUALITY_MODS[quality]
	var names: Array = LootRules.PART_MODS.duplicate()
	var mods := {}
	var first := ""
	for i in int(spec[2]):
		var k: String = names.pop_at(rng.randi_range(0, names.size() - 1))
		if first == "":
			first = k
		mods[k] = rng.randi_range(spec[0], spec[1]) / 100.0
	return WeaponPart.create("part_" + first, l, mods)


## Pièce aux modificateurs exacts (échange) au niveau `lvl`.
static func make_exact_part(mods: Dictionary, lvl: int) -> WeaponPart:
	var first := "part"
	for k in mods:
		first = "part_" + String(k)
		break
	return WeaponPart.create(first, clampi(lvl, 1, PlayerProfile.MAX_LEVEL), mods)


## Objet d'une récompense (contrat ou échange) au niveau `lvl` : OwnedWeapon,
## WeaponPart, ou null (« none », aucune arme possible).
static func make_item(reward: Dictionary, lvl: int, rng: RandomNumberGenerator) -> RefCounted:
	match reward.get("kind"):
		"weapon":
			return make_weapon(reward, lvl, rng)
		"part":
			if reward.has("mods"):
				return make_exact_part(reward.mods, lvl)
			return make_part(String(reward.get("quality", "standard")), lvl, rng)
	return null


## Range l'objet au profil ; rend {weapon_uid, part_uid} ("" si rien).
static func give(pr: PlayerProfile, item: RefCounted) -> Dictionary:
	var out := {"weapon_uid": "", "part_uid": ""}
	if item is OwnedWeapon:
		out.weapon_uid = pr.add_weapon(item)
	elif item is WeaponPart:
		out.part_uid = pr.add_part(item)
	return out


## Texte court d'une récompense au niveau `lvl` (interface du hub) :
## « ARME RARE NIV. 7 » (« RARE WEAPON LVL 7 »), « PIÈCE SOIGNÉE NIV. 7 »,
## « PIÈCE NIV. 7 : +15 % dégâts ».
static func describe(reward: Dictionary, lvl: int) -> String:
	match reward.get("kind"):
		"weapon":
			var r := maxi(OwnedWeapon.rarity_from_key(reward.get("rarity", "common")), 0)
			var id := String(reward.get("weapon", "any"))
			var l := lvl if id == "any" or not WeaponDB.exists(id) else maxi(lvl, WeaponDB.base_level(id))
			var what := Lang.t("ARME", "WEAPON") if id == "any" or not WeaponDB.exists(id) \
					else String(WeaponDB.WEAPONS[id].get("name", id))
			# Ordre des mots : « ARME RARE » / « RARE WEAPON ».
			var words := [GameWeapon.rarity_name(r), what, l] if Lang.is_en() else [what, GameWeapon.rarity_name(r), l]
			return Lang.t("%s %s NIV. %d", "%s %s LVL %d") % words
		"part":
			if reward.has("mods"):
				return Lang.t("PIÈCE NIV. %d : %s", "PART LVL %d: %s") % [lvl, LootRules.mods_text(reward.mods)]
			return Lang.t("PIÈCE %s NIV. %d", "%s PART LVL %d") % [HubData.quality_name(String(reward.get("quality", "standard"))), lvl]
	return ""
