class_name BuildRules
extends RefCounted
## Règles de la station de construction (GAME_CONCEPT §4.8, §4.11, §4.12) :
## prix en ferraille, durée en manches, recharge des munitions, recyclage et
## contrôle d'une demande de construction. Pures, partagées par le serveur
## (qui décide) et l'interface (affichage) ; tests : tests/test_build_rules.gd.
##
## Valeurs PROVISOIRES (GAME_CONCEPT §6 bis) :
##   * prix = 500 × (1 + 0,15 × (niveau − 1)) × rareté (commune 1, rare 1,5,
##     épique 2,2, légendaire 3,2, unique 4), arrondi à 10 : arme de base
##     (niveau 1, commune) 500, niveau 10 rare 1 760, niveau 50 unique 16 700.
##     Les pièces installées ne changent pas le prix (pour l'instant).
##   * durée : prix < 1 500 → 1 manche, < 4 000 → 2 manches, sinon 3.
##     Une construction de 1 manche est prête à la FIN de la manche en cours,
##     de 2 manches à la fin de la suivante, etc. Lancée entre deux manches
##     (entracte, attente du début), la manche « en cours » est la suivante.
##   * recharge des munitions (arme en main) : 30 % du prix de construction,
##     arrondi à 10 (150 pour le pistolet de base).
##   * recyclage : 50 % du prix de construction, arrondi à 10 ; une arme de
##     base (exemplaire « base:<id> », donné à tous dès le départ) ne rapporte
##     rien (sinon de la ferraille gratuite à chaque départ) ; une arme prêtée
##     à terre ne se recycle pas ; la DERNIÈRE arme du joueur non plus
##     (weapon_count).

const BASE_PRICE := 500
## Hausse du prix par niveau au-dessus de 1 (fraction du prix de base).
const LEVEL_STEP := 0.15
## Multiplicateur de prix par rareté (ordre de OwnedWeapon.Rarity).
const RARITY_MULT := [1.0, 1.5, 2.2, 3.2, 4.0]
## Seuils de durée : prix < ROUND_STEPS[i] → i + 1 manches ; au-delà : MAX_ROUNDS.
const ROUND_STEPS := [1500, 4000]
const MAX_ROUNDS := 3
## Recharge et recyclage : fractions du prix de construction.
const REFILL_SHARE := 0.3
const RECYCLE_SHARE := 0.5
## Arrondi des prix (ferraille).
const ROUNDING := 10

## Motifs de refus d'une construction (codes, traduits par refusal_text).
const OK := ""
const INVALID := "invalid"
const LEVEL := "level"
const BUSY := "busy"
const NOT_ALIVE := "not_alive"
## Refus d'un recyclage : ce serait la dernière arme du joueur.
const LAST_WEAPON := "last_weapon"


# --------------------------------------------------------------------------
# Prix et durée
# --------------------------------------------------------------------------

## Prix de construction (ferraille) d'une arme de partie (GameWeapon).
static func price(w: Dictionary) -> int:
	if w.is_empty():
		return 0
	var lvl := GameWeapon.level_of(w)
	var mult: float = RARITY_MULT[GameWeapon.rarity_of(w)]
	return _round(float(BASE_PRICE) * (1.0 + LEVEL_STEP * float(lvl - 1)) * mult)


## Prix d'un exemplaire du profil (liste de la station).
static func owned_price(o: OwnedWeapon) -> int:
	return price(GameWeapon.from_owned(o)) if o != null else 0


## Durée d'une construction (manches, 1 à MAX_ROUNDS) selon son prix.
static func rounds(build_price: int) -> int:
	for i in ROUND_STEPS.size():
		if build_price < int(ROUND_STEPS[i]):
			return i + 1
	return MAX_ROUNDS


## Manche à la fin de laquelle une construction lancée maintenant est prête :
## `round_n` manche en cours, `active` vrai pendant la manche (faux pendant
## l'entracte ou avant la manche 1 : la manche en cours est alors la suivante).
static func ready_round(round_n: int, active: bool, build_price: int) -> int:
	var current := round_n if active else round_n + 1
	return maxi(current, 1) + rounds(build_price) - 1


## Prix de la recharge des munitions de l'arme `w`.
static func refill_price(w: Dictionary) -> int:
	if w.is_empty():
		return 0
	return maxi(_round(float(price(w)) * REFILL_SHARE), ROUNDING)


## Chargeur et réserve déjà pleins (la recharge ne servirait à rien) ?
static func ammo_full(w: Dictionary) -> bool:
	if w.is_empty():
		return true
	var s := GameWeapon.stats(w)
	return int(w.get("mag", 0)) >= int(s.mag) and int(w.get("reserve", 0)) >= int(s.reserve)


## Exemplaire d'arme de base (donné à tous, BaseWeapons) ?
static func is_base_copy(w: Dictionary) -> bool:
	return String(w.get("uid", "")).begins_with(BaseWeapons.UID_PREFIX)


## Ferraille rendue par le recyclage de `w` (§4.12).
static func recycle_value(w: Dictionary) -> int:
	if w.is_empty() or is_base_copy(w) or bool(w.get("loaned", false)):
		return 0
	return _round(float(price(w)) * RECYCLE_SHARE)


static func _round(v: float) -> int:
	return roundi(v / float(ROUNDING)) * ROUNDING


# --------------------------------------------------------------------------
# Demande de construction (serveur)
# --------------------------------------------------------------------------

## Arme demandée par un client (exemplaire de SON arsenal, que le serveur ne
## connaît pas) relue en sûreté : arme à feu connue (WeaponDB), niveau 1 à 50,
## rareté connue, identifiant d'exemplaire propre, pièces bornées (pas plus que
## d'emplacements, niveau ≤ arme, modificateurs connus). Munitions pleines.
## {} si la demande est inutilisable.
static func clean_weapon(d: Variant) -> Dictionary:
	if not d is Dictionary:
		return {}
	var id: Variant = d.get("id")
	if not (id is String or id is StringName) or not WeaponDB.exists(String(id)):
		return {}
	var lvl := ProfileValues.to_int(d.get("level"), 1, 1, PlayerProfile.MAX_LEVEL)
	var r := ProfileValues.to_int(d.get("rarity"), 0, 0, RARITY_MULT.size() - 1)
	var uid := ProfileValues.clean_id(d.get("uid", ""))
	var parts := []
	var ps: Variant = d.get("parts", [])
	if ps is Array:
		for p in ps:
			if parts.size() >= OwnedWeapon.slots_for(r as OwnedWeapon.Rarity):
				break
			if not p is Dictionary:
				continue
			var pid := ProfileValues.clean_id(p.get("id", ""))
			var pl := ProfileValues.to_int(p.get("level"), 0, 0, PlayerProfile.MAX_LEVEL)
			if pid == "" or pl < 1 or pl > lvl:
				continue
			parts.append({"id": pid, "uid": ProfileValues.clean_id(p.get("uid", "")), "level": pl,
				"mods": WeaponPart.clean_mods(p.get("mods", {}))})
	return GameWeapon.make(String(id), lvl, r, parts, uid)


## Raison du refus d'une construction de l'arme `w` (déjà relue par
## clean_weapon) par le joueur `pd` ; `busy` : il a déjà une construction (en
## cours ou prête, pas encore récupérée). La ferraille se vérifie à part
## (Session.try_spend).
static func build_refusal(pd: PlayerData, w: Dictionary, busy: bool) -> String:
	if pd == null or w.is_empty():
		return INVALID
	if pd.life != PlayerData.Life.ALIVE:
		return NOT_ALIVE
	if busy:
		return BUSY
	if not GameWeapon.can_equip(w, pd.level):
		return LEVEL
	return OK


# --------------------------------------------------------------------------
# Recyclage (§4.12) : règles sur PlayerData
# --------------------------------------------------------------------------

## Arme de la rangée `row` (0 : en main, 1 : inventaire), place `i` ; {} si vide.
static func weapon_at(pd: PlayerData, row: int, i: int) -> Dictionary:
	var list: Array = pd.weapons if row == 0 else pd.bag
	return list[i] if row in [0, 1] and i >= 0 and i < list.size() else {}


## Armes du joueur au sens du recyclage : armes en main et inventaire de
## partie, hors arme prêtée à terre (reprise ensuite, MatchRules). Le couteau
## (attaque séparée) et l'emplacement de grenade ne sont pas des armes ; une
## arme en construction à la station ne compte pas tant qu'elle n'est pas
## récupérée (elle peut ne jamais l'être : place manquante, mort...).
static func weapon_count(pd: PlayerData) -> int:
	if pd == null:
		return 0
	var n := 0
	for list: Array in [pd.weapons, pd.bag]:
		for w: Variant in list:
			if w is Dictionary and not (w as Dictionary).is_empty() and not bool((w as Dictionary).get("loaned", false)):
				n += 1
	return n


## Raison du refus d'un recyclage ("" : permis). On ne recycle jamais sa
## dernière arme, en main ou dans l'inventaire (LAST_WEAPON, seul refus
## montré au joueur : recycle_refusal_text).
static func recycle_refusal(pd: PlayerData, row: int, i: int) -> String:
	if pd == null:
		return "joueur inconnu"
	if pd.life != PlayerData.Life.ALIVE:
		return "joueur à terre ou mort"
	var w := weapon_at(pd, row, i)
	if w.is_empty():
		return "place vide"
	if bool(w.get("loaned", false)):
		return "arme prêtée"
	if weapon_count(pd) <= 1:
		return LAST_WEAPON
	return ""


## Texte pour le joueur d'un refus de recyclage ("" : rien à montrer).
static func recycle_refusal_text(code: String) -> String:
	if code == LAST_WEAPON:
		return Lang.t("Impossible de recycler votre dernière arme", "You can't recycle your last weapon")
	return ""


## Retire l'arme (recyclage) et la rend ({} : refus). Les armes en main restent
## sans trou ; l'arme tenue reste la même si elle n'est pas concernée, sinon
## l'emplacement tenu garde son numéro (borné). Mains vides permises.
static func take(pd: PlayerData, row: int, i: int) -> Dictionary:
	if recycle_refusal(pd, row, i) != "":
		return {}
	var w := weapon_at(pd, row, i)
	if row == 1:
		pd.bag.remove_at(i)
		return w
	pd.weapons.remove_at(i)
	if pd.slot > i:
		pd.slot -= 1
	pd.slot = clampi(pd.slot, 0, maxi(pd.weapons.size() - 1, 0))
	return w


# --------------------------------------------------------------------------
# Liste de la station
# --------------------------------------------------------------------------

## Armes constructibles affichées par la station : armes de base puis arsenal
## du profil, dans l'ordre. Seules les armes à feu (WeaponDB) : une arme de
## mêlée (le couteau de base) reste l'attaque séparée, elle ne se tient pas
## en main et ne se construit donc pas.
static func catalog(profile: PlayerProfile) -> Array[OwnedWeapon]:
	var out: Array[OwnedWeapon] = []
	for o in BaseWeapons.all():
		if WeaponDB.exists(o.weapon_id):
			out.append(o)
	if profile != null:
		for o in profile.weapons:
			if WeaponDB.exists(o.weapon_id):
				out.append(o)
	return out


## Texte d'un refus pour le joueur local (codes de build_refusal).
static func refusal_text(code: String) -> String:
	match code:
		LEVEL:
			return Lang.t("Niveau trop bas pour cette arme", "Your level is too low for this weapon")
		BUSY:
			return Lang.t("Une construction à la fois", "One build at a time")
		INVALID:
			return Lang.t("Arme inconnue", "Unknown weapon")
	return ""


## Durée lisible : « 1 manche » / « 2 manches ».
static func rounds_text(n: int) -> String:
	return (Lang.t("%d manche", "%d round") if n <= 1 else Lang.t("%d manches", "%d rounds")) % n
