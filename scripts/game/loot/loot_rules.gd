class_name LootRules
extends RefCounted
## Tirages du butin des vagues spéciales et de boss (GAME_CONCEPT §4.7).
## Règles pures, avec le générateur aléatoire fourni par l'appelant (le
## serveur : LootSystem) ; tests/test_loot.gd.
##
## * Armes : à la fin d'une vague spéciale vaincue, WEAPONS_SPECIAL arme par
##   joueur ; vague de boss : WEAPONS_BOSS (aucun boss n'existe encore).
##   Niveau tiré entre manche − 6 et manche + 2, au moins 1, jamais sous le
##   niveau de base de l'arme (WeaponDB.base_level), au plus 50. Le niveau
##   dépend de la manche, pas du joueur.
##   Rareté : commune 60 %, rare 20 %, épique 12,5 %, légendaire 5 %, unique 2,5 %.
##   Arme tirée uniformément parmi les armes à feu de WeaponDB, HORS armes de
##   base (BaseWeapons : le pistolet de départ, toujours disponible au hub,
##   n'est pas un butin intéressant). Choix provisoire.
## * Pièces : PART_CHANCE (5 %) par zombie de vague spéciale ou de boss tué,
##   pour chaque joueur ; niveau entre niveau du joueur − 10 (au moins 1) et
##   niveau du joueur. Modificateurs PROVISOIRES : un premier modificateur
##   toujours en bonus ; PART_SECOND_CHANCE (35 %) d'en avoir un second,
##   différent, qui est un malus une fois sur deux (PART_MALUS_CHANCE) ;
##   valeurs de 5 à 25 % (pas de 1 %). Noms : GameWeapon.MODS.
## * Échantillons : chaque type de vague spéciale a 2 ou 3 sortes
##   (SAMPLES) ; chaque sorte a SAMPLE_CHANCE (20 %) de tomber par zombie tué
##   de cette vague, pour chaque joueur. Hasard pur, sans limite.

const WEAPONS_SPECIAL := 1
const WEAPONS_BOSS := 2
## Écart du niveau d'une arme trouvée par rapport à la manche.
const LEVEL_BELOW := 6
const LEVEL_ABOVE := 2
## Probabilités des raretés (%), dans l'ordre de OwnedWeapon.Rarity.
const RARITY_WEIGHTS := [60.0, 20.0, 12.5, 5.0, 2.5]

const PART_CHANCE := 0.05
const PART_LEVEL_BELOW := 10
const PART_MODS := ["damage", "fire_rate", "reload", "recoil", "accuracy", "mag", "reserve"]
## Valeurs des modificateurs (fractions), en pas de 1 %.
const PART_MOD_MIN := 5
const PART_MOD_MAX := 25
const PART_SECOND_CHANCE := 0.35
const PART_MALUS_CHANCE := 0.5

const SAMPLE_CHANCE := 0.2
## Type de vague spéciale -> sortes d'échantillons [identifiant, FR, EN].
## Identifiant enregistré dans le profil (PlayerProfile.samples).
const SAMPLES := {
	"dogs": [["dog_fang", "CROC", "FANG"], ["dog_fur", "TOUFFE DE POILS", "TUFT OF FUR"],
		["dog_collar", "COLLIER", "COLLAR"]],
}
## Noms des modificateurs affichés [FR, EN].
const MOD_NAMES := {
	"damage": ["dégâts", "damage"], "fire_rate": ["cadence", "fire rate"],
	"reload": ["rechargement", "reload"], "recoil": ["recul", "recoil"],
	"accuracy": ["précision", "accuracy"], "mag": ["chargeur", "magazine"],
	"reserve": ["réserve", "reserve"],
}


## Armes par joueur pour une vague du type `wave` (WaveRules.SPECIAL / BOSS).
static func weapons_for_wave(wave: String) -> int:
	match wave:
		WaveRules.SPECIAL:
			return WEAPONS_SPECIAL
		WaveRules.BOSS:
			return WEAPONS_BOSS
	return 0


## Armes qui peuvent tomber (triées : tirage reproductible avec une graine).
static func weapon_pool() -> PackedStringArray:
	var out := PackedStringArray()
	for id in WeaponDB.WEAPONS:
		if not BaseWeapons.is_base(id):
			out.append(id)
	out.sort()
	return out


## Bornes du niveau d'une arme de niveau de base `base` trouvée à la manche
## `round_n` : [min, max].
static func weapon_level_range(round_n: int, base := 1) -> Vector2i:
	var cap := PlayerProfile.MAX_LEVEL
	var lo := clampi(maxi(round_n - LEVEL_BELOW, maxi(base, 1)), 1, cap)
	var hi := clampi(maxi(round_n + LEVEL_ABOVE, lo), 1, cap)
	return Vector2i(lo, hi)


static func roll_weapon_level(round_n: int, base: int, rng: RandomNumberGenerator) -> int:
	var r := weapon_level_range(round_n, base)
	# Tirage sur toute la plage −6 / +2, puis ramené dans les bornes (un
	# tirage sous le niveau de base donne le niveau de base).
	var raw := rng.randi_range(round_n - LEVEL_BELOW, round_n + LEVEL_ABOVE)
	return clampi(raw, r.x, r.y)


## Rareté pour un tirage `x` dans [0, 100[ (pure).
static func rarity_for(x: float) -> int:
	var acc := 0.0
	for i in RARITY_WEIGHTS.size():
		acc += RARITY_WEIGHTS[i]
		if x < acc:
			return i
	return RARITY_WEIGHTS.size() - 1


static func roll_rarity(rng: RandomNumberGenerator) -> int:
	return rarity_for(rng.randf() * 100.0)


## Arme de partie trouvée à la manche `round_n` (identifiant d'exemplaire `uid`).
static func roll_weapon(round_n: int, rng: RandomNumberGenerator, uid := "") -> Dictionary:
	var pool := weapon_pool()
	var id := pool[rng.randi_range(0, pool.size() - 1)]
	return GameWeapon.make(id, roll_weapon_level(round_n, WeaponDB.base_level(id), rng), roll_rarity(rng), [], uid)


## Bornes du niveau d'une pièce trouvée par un joueur de niveau `player_level`.
static func part_level_range(player_level: int) -> Vector2i:
	var hi := clampi(player_level, 1, PlayerProfile.MAX_LEVEL)
	return Vector2i(maxi(hi - PART_LEVEL_BELOW, 1), hi)


## Pièce trouvée (format des pièces d'une arme de partie, GameWeapon) :
## {"id", "uid", "level", "mods"}.
static func roll_part(player_level: int, rng: RandomNumberGenerator, uid := "") -> Dictionary:
	var r := part_level_range(player_level)
	var lvl := rng.randi_range(r.x, r.y)
	var first: String = PART_MODS[rng.randi_range(0, PART_MODS.size() - 1)]
	var mods := {first: _mod_value(rng)}
	if rng.randf() < PART_SECOND_CHANCE:
		var second := first
		while second == first:
			second = PART_MODS[rng.randi_range(0, PART_MODS.size() - 1)]
		var v := _mod_value(rng)
		mods[second] = -v if rng.randf() < PART_MALUS_CHANCE else v
	return {"id": "part_" + first, "uid": uid, "level": lvl, "mods": mods}


static func _mod_value(rng: RandomNumberGenerator) -> float:
	return rng.randi_range(PART_MOD_MIN, PART_MOD_MAX) / 100.0


## Une pièce tombe-t-elle (`chance` < 0 : PART_CHANCE) ?
static func part_drops(rng: RandomNumberGenerator, chance := -1.0) -> bool:
	return rng.randf() < (PART_CHANCE if chance < 0.0 else chance)


## Échantillons tombés pour un joueur, pour un zombie tué d'une vague du
## type `kind` ("dogs") : identifiants (0 à 3).
static func roll_samples(kind: String, rng: RandomNumberGenerator, chance := -1.0) -> PackedStringArray:
	var out := PackedStringArray()
	var c := SAMPLE_CHANCE if chance < 0.0 else chance
	for s in SAMPLES.get(kind, []):
		if rng.randf() < c:
			out.append(s[0])
	return out


## Raison du refus du montage de la pièce `part` (format roll_part) sur
## l'arme de partie `w` par un joueur de niveau `player_level` (règle
## OwnedWeapon.can_mount) : "no_slot", "weapon_level", "player_level",
## "invalid" ; "" : permis.
static func mount_refusal(w: Dictionary, part: Dictionary, player_level: int) -> String:
	if w.is_empty() or part.is_empty() or w.get("loaned", false):
		return "invalid"
	var o := GameWeapon.to_owned(w)
	var p := WeaponPart.create(String(part.get("id", "part")), int(part.get("level", 1)), part.get("mods", {}))
	p.uid = String(part.get("uid", ""))
	if o.can_mount(p, player_level):
		return ""
	if o.free_slots() <= 0:
		return "no_slot"
	if p.level > o.level:
		return "weapon_level"
	if p.level > player_level:
		return "player_level"
	return "invalid"


## Monte la pièce sur l'arme de partie (mount_refusal d'abord). Les munitions
## en cours restent, bornées par le nouveau chargeur et la nouvelle réserve.
static func mount(w: Dictionary, part: Dictionary) -> void:
	var ps: Array = w.get("parts", [])
	ps.append({"id": String(part.get("id", "part")), "uid": String(part.get("uid", "")),
		"level": clampi(int(part.get("level", 1)), 1, PlayerProfile.MAX_LEVEL),
		"mods": WeaponPart.clean_mods(part.get("mods", {}))})
	w["parts"] = ps
	var s := GameWeapon.stats(w)
	w["mag"] = mini(int(w.get("mag", 0)), int(s.mag))
	w["reserve"] = mini(int(w.get("reserve", 0)), int(s.reserve))


## Nom affiché d'un échantillon (identifiant brut s'il est inconnu).
static func sample_name(id: String) -> String:
	for kind in SAMPLES:
		for s in SAMPLES[kind]:
			if s[0] == id:
				return Lang.t(s[1], s[2])
	return id


## Texte des modificateurs d'une pièce : « +12 % dégâts, −5 % recul ».
static func mods_text(mods: Dictionary) -> String:
	var parts := PackedStringArray()
	for k in mods:
		var v := float(mods[k])
		var n: Array = MOD_NAMES.get(String(k), [String(k), String(k)])
		parts.append("%s%d %% %s" % ["+" if v >= 0.0 else "−", roundi(absf(v) * 100.0), Lang.t(n[0], n[1])])
	return ", ".join(parts)


## Nom court d'une pièce : « PIÈCE NIV. 7 ».
static func part_title(p: Dictionary) -> String:
	return Lang.t("PIÈCE NIV. %d", "PART LVL %d") % clampi(int(p.get("level", 1)), 1, PlayerProfile.MAX_LEVEL)
