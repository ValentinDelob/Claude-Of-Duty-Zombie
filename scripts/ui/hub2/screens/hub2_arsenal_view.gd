class_name Hub2ArsenalView
extends RefCounted
## Règles d'affichage de l'ARSENAL du hub v2 (docs/hub_v2/Arsenal.dc.html) :
## objets du rail (armes : armes de base + arsenal du profil ; pièces non
## installées), filtres TOUTES / À FEU / MÊLÉE / UTILISABLES (pièces :
## TOUTES / MONTABLES), ordre dans une colonne (rareté puis score), les six
## statistiques de la fiche (valeur de BASE + modificateur des pièces « + N »
## vert / « − N » rouge, sans unité ; un rechargement plus long est un malus),
## qualité et effets d'une pièce. Fonctions pures (tests/test_hub2_arsenal.gd).

## Filtres des armes (Y / Tab : cycle) et des pièces.
const FILTERS := ["all", "firearm", "melee", "usable"]
const FILTER_NAMES := {
	"all": ["TOUTES", "ALL"], "firearm": ["À FEU", "FIREARMS"], "melee": ["MÊLÉE", "MELEE"],
	"usable": ["UTILISABLES", "USABLE"],
}
const PART_FILTERS := ["all", "mountable"]
const PART_FILTER_NAMES := {"all": ["TOUTES", "ALL"], "mountable": ["MONTABLES", "MOUNTABLE"]}

## Statistiques de la fiche, dans l'ordre de la maquette (grille 2 colonnes).
const STATS := ["damage", "rpm", "accuracy", "range", "mag", "reload"]
const STAT_LABELS := {
	"damage": ["DÉGÂTS", "DAMAGE"], "rpm": ["CADENCE", "FIRE RATE"], "accuracy": ["PRÉCISION", "ACCURACY"],
	"range": ["PORTÉE", "RANGE"], "mag": ["CHARGEUR", "MAGAZINE"], "reload": ["RECHARGE", "RELOAD"],
}
## Icônes de la maquette (<path d> en viewBox 0 0 24 24, trait 2 px,
## stroke-linecap square, stroke-linejoin miter) : éclat (dégâts), éclair
## (cadence), mire (précision), flèche (portée), balles (chargeur), flèche
## circulaire (recharge).
const ICONS := {
	"damage": "M12 2l2.4 6.9L21 9l-5.2 4.3L17.6 21 12 17l-5.6 4 1.8-7.7L3 9l6.6-.1z",
	"rpm": "M13 2L4 14h7l-1 8 9-12h-7z",
	"accuracy": "M12 2v5M12 17v5M2 12h5M17 12h5M12 9a3 3 0 1 0 0 6a3 3 0 1 0 0-6",
	"range": "M2 12h19M15 6l6 6-6 6M2 7v10",
	"mag": "M5 21V9l2-5 2 5v12zM10 21V9l2-5 2 5v12zM15 21V9l2-5 2 5v12z",
	"reload": "M20 12a8 8 0 1 1-2.3-5.7M20 3v5h-5",
}
## Plus petit = mieux (temps de rechargement) : une hausse est un malus.
const LOWER_IS_BETTER := ["reload"]
## Couleurs des modificateurs (maquette : #4FE3C1 bénéfique, #FF6B57 nuisible).
const GOOD := Color("4FE3C1")
const HARMFUL := Color("FF6B57")

## Qualité d'une pièce (affichage seulement, aucun effet en jeu) d'après le
## total net de ses modificateurs : < 12 % ordinaire, < 20 % solide, sinon
## excellente ; couleurs des raretés commune, rare, épique.
const QUALITY_STEPS := [0.12, 0.2]
const QUALITY_NAMES := [["ORDINAIRE", "ORDINARY"], ["SOLIDE", "STURDY"], ["EXCELLENTE", "EXCELLENT"]]

## Effet d'un modificateur de pièce en clair (« +8 % dégâts ») : nom [FR, EN].
## Les modificateurs « div » (rechargement, recul, précision) sont écrits
## d'après leur effet réel sur la valeur : temps de recharge, recul,
## dispersion ÷ (1 + m) -> « −17 % temps de recharge » pour +20 %.
const EFFECT_NAMES := {
	"damage": ["dégâts", "damage"], "fire_rate": ["cadence", "fire rate"],
	"reload": ["temps de recharge", "reload time"], "recoil": ["recul", "recoil"],
	"accuracy": ["dispersion", "spread"], "mag": ["chargeur", "magazine"], "reserve": ["réserve", "reserve"],
}


# --------------------------------------------------------------------------
# Objets du rail
# --------------------------------------------------------------------------

## Armes de l'onglet ARMES : armes de base puis arsenal, filtrées.
static func weapons(pr: PlayerProfile, filter: String) -> Array:
	var out := []
	if pr == null:
		return out
	for w in BaseWeapons.all():
		if HubGear.passes(w, filter, pr.level()):
			out.append(w)
	for w in pr.weapons:
		if HubGear.passes(w, filter, pr.level()):
			out.append(w)
	return out


## Pièces de l'onglet PIÈCES (non installées), filtrées.
static func parts(pr: PlayerProfile, filter: String) -> Array:
	var out := []
	if pr == null:
		return out
	for p in pr.parts:
		if filter != "mountable" or HubGear.mountable_anywhere(pr, p):
			out.append(p)
	return out


static func is_base(w: OwnedWeapon) -> bool:
	return w != null and w.uid.begins_with(BaseWeapons.UID_PREFIX)


## Ordre des armes d'une colonne (même niveau) : rareté décroissante, puis
## score décroissant (maquette : b.rar - a.rar || b.score - a.score), puis
## nom et ordre d'arrivée (stable).
static func weapon_before(a: OwnedWeapon, b: OwnedWeapon) -> bool:
	if int(a.rarity) != int(b.rarity):
		return int(a.rarity) > int(b.rarity)
	if a.score() != b.score():
		return a.score() > b.score()
	var na := HubGear.weapon_name(a.weapon_id)
	var nb := HubGear.weapon_name(b.weapon_id)
	if na != nb:
		return na < nb
	return _num(a.uid) < _num(b.uid)


## Ordre des pièces d'une colonne : qualité décroissante, total net
## décroissant, la plus récente d'abord.
static func part_before(a: WeaponPart, b: WeaponPart) -> bool:
	var qa := part_quality(a)
	var qb := part_quality(b)
	if qa != qb:
		return qa > qb
	var ta := net_total(a)
	var tb := net_total(b)
	if not is_equal_approx(ta, tb):
		return ta > tb
	return _num(a.uid) > _num(b.uid)


static func _num(uid: String) -> int:
	var digits := ""
	for c in uid:
		if c >= "0" and c <= "9":
			digits += c
	return digits.to_int()


## Filtre suivant (cycle).
static func next_filter(list: Array, f: String) -> String:
	return list[(list.find(f) + 1) % list.size()]


static func filter_name(f: String, part_tab := false) -> String:
	var n: Array = (PART_FILTER_NAMES if part_tab else FILTER_NAMES).get(f, [f, f])
	return Lang.t(n[0], n[1])


## « NIV. 20 » / « LVL 20 ».
static func level_text(lvl: int) -> String:
	return Lang.t("NIV. %d", "LVL %d") % lvl


## « NIV. 24 REQUIS » / « LVL 24 REQUIRED ».
static func required_text(lvl: int) -> String:
	return Lang.t("NIV. %d REQUIS", "LVL %d REQUIRED") % lvl


## Famille de l'arme en capitales (« REVOLVER », « CORPS À CORPS »).
static func class_name_of(id: String) -> String:
	if WeaponDB.exists(id):
		return WeaponDB.family_name(id)
	return Lang.t("CORPS À CORPS", "MELEE") if HubGear.is_melee(id) else Lang.t("ARME", "WEAPON")


# --------------------------------------------------------------------------
# Statistiques de la fiche
# --------------------------------------------------------------------------

## Valeur numérique d'une statistique de la fiche dans `s` (GameWeapon.stats).
static func stat_number(key: String, s: Dictionary) -> float:
	match key:
		"accuracy":
			return float(HubGear.accuracy(s))
	return float(s.get(key, 0.0))


## La statistique a-t-elle un sens pour cette arme ? (corps à corps :
## ni chargeur ni recharge -> « — » ; arme inconnue : rien.)
static func has_stat(key: String, id: String, s: Dictionary) -> bool:
	if s.is_empty():
		return false
	if HubGear.is_melee(id) and key in ["mag", "reload"]:
		return false
	return s.has(key) or key == "accuracy"


## Valeur affichée : « 184 », « 400/min », « 70 % », « 25 m », « 8 »,
## « 1,6 s » (unités de la maquette ; anglais : « 70% », « 1.6 s »).
static func format_value(key: String, v: float) -> String:
	match key:
		"rpm":
			return Hub2Style.num(roundi(v)) + "/min"
		"accuracy":
			return str(roundi(v)) + Lang.t(String.chr(0xA0) + "%", "%")
		"range":
			return Hub2Style.num(roundi(v)) + String.chr(0xA0) + "m"
		"reload":
			return decimal(v) + String.chr(0xA0) + "s"
	return Hub2Style.num(roundi(v))


## Nombre à une décimale dans la langue (« 0,3 » / « 0.3 »).
static func decimal(v: float) -> String:
	var t := "%.1f" % v
	return t if Lang.is_en() else t.replace(".", ",")


## Modificateur des pièces (écart `d` = avec pièces − sans), SANS unité :
## « + 15 », « − 0,3 » ; "" s'il est nul une fois arrondi (rien affiché).
static func format_mod(key: String, d: float) -> String:
	var mag := ""
	if key == "reload":
		mag = decimal(absf(d))
		if mag == decimal(0.0):
			return ""
	else:
		var n := roundi(absf(d))
		if n == 0:
			return ""
		mag = Hub2Style.num(n)
	return ("+ " if d > 0.0 else "− ") + mag


## Le modificateur aide-t-il ? (plus = mieux, sauf le temps de recharge).
static func mod_good(key: String, d: float) -> bool:
	return d < 0.0 if key in LOWER_IS_BETTER else d > 0.0


static func mod_color(key: String, d: float) -> Color:
	return GOOD if mod_good(key, d) else HARMFUL


## Les six statistiques de la fiche de `w` :
## [{key, label, icon, value, mod, good, base, eff, none}] ; `value` = valeur
## de BASE (niveau compris, sans les pièces), `mod` = apport des pièces.
static func stat_lines(w: OwnedWeapon) -> Array:
	var out := []
	if w == null:
		return out
	var known := WeaponDB.exists(w.weapon_id)
	var raw: Dictionary = HubGear.fire_stats(w, false) if known else {}
	var eff: Dictionary = HubGear.fire_stats(w, true) if known else {}
	for key in STATS:
		var lbl: Array = STAT_LABELS[key]
		var line := {"key": key, "label": Lang.t(lbl[0], lbl[1]), "icon": ICONS[key], "value": "—", "mod": "",
			"good": true, "base": 0.0, "eff": 0.0, "none": true}
		if has_stat(key, w.weapon_id, raw):
			var b := stat_number(key, raw)
			var e := stat_number(key, eff)
			line.base = b
			line.eff = e
			line.none = false
			line.value = format_value(key, b)
			line.mod = format_mod(key, e - b)
			line.good = mod_good(key, e - b)
		out.append(line)
	return out


## Aperçu d'une pièce sur une arme (fenêtre d'installation, onglet PIÈCES) :
## [{key, label, before, after, good}] pour chaque statistique de la fiche
## qui change (valeurs effectives avant / après).
static func preview_lines(w: OwnedWeapon, p: WeaponPart) -> Array:
	var out := []
	if w == null or p == null or not WeaponDB.exists(w.weapon_id):
		return out
	var before_s := HubGear.fire_stats(w)
	var after_w := OwnedWeapon.create(w.weapon_id, w.level, w.rarity)
	after_w.parts = w.parts.duplicate()
	after_w.parts.append(p)
	var after_s := HubGear.fire_stats(after_w)
	for key in STATS:
		if not has_stat(key, w.weapon_id, before_s):
			continue
		var b := stat_number(key, before_s)
		var a := stat_number(key, after_s)
		var tb := format_value(key, b)
		var ta := format_value(key, a)
		if tb == ta:
			continue
		var lbl: Array = STAT_LABELS[key]
		out.append({"key": key, "label": Lang.t(lbl[0], lbl[1]), "before": tb, "after": ta, "good": mod_good(key, a - b)})
	return out


# --------------------------------------------------------------------------
# Pièces
# --------------------------------------------------------------------------

## Total net des modificateurs (bonus − malus).
static func net_total(p: WeaponPart) -> float:
	var t := 0.0
	for k in p.mods:
		t += float(p.mods[k])
	return t


## Qualité affichée (0 ordinaire, 1 solide, 2 excellente).
static func part_quality(p: WeaponPart) -> int:
	var t := net_total(p)
	if t >= QUALITY_STEPS[1] - 0.0001:
		return 2
	if t >= QUALITY_STEPS[0] - 0.0001:
		return 1
	return 0


static func quality_name(q: int) -> String:
	var n: Array = QUALITY_NAMES[clampi(q, 0, QUALITY_NAMES.size() - 1)]
	return Lang.t(n[0], n[1])


static func quality_color(q: int) -> Color:
	return Hub2Style.rarity_color(clampi(q, 0, 2))


## Effet d'un modificateur en clair : [texte, bonus ?] (« +8 % dégâts »,
## « −17 % temps de recharge » pour un rechargement +20 %).
static func effect(key: String, v: float) -> Array:
	key = GameWeapon.MOD_ALIASES.get(key, key)
	var pct := v
	var spec: Array = GameWeapon.MODS.get(key, [[], "mul"])
	if spec[1] == "div":
		pct = 1.0 / maxf(1.0 + v, GameWeapon.MIN_FACTOR) - 1.0
	var n := roundi(absf(pct) * 100.0)
	var nm: Array = EFFECT_NAMES.get(key, [key, key])
	var t := "%s%d%s%% %s" % ["+" if pct >= 0.0 else "−", n, Lang.t(String.chr(0xA0), ""), Lang.t(nm[0], nm[1])]
	return [t, v >= 0.0]


## Effets d'une pièce dans l'ordre d'affichage (principal d'abord).
static func effects(p: WeaponPart) -> Array:
	var out := []
	if p == null:
		return out
	var om := HubGear.ordered_mods(p)
	for k in om:
		out.append(effect(String(k), float(om[k])))
	return out


## Nom de la ligne d'une pièce installée : « Renfort · niv. 7 ».
static func part_line_name(p: WeaponPart) -> String:
	return "%s · %s" % [HubGear.part_name(p), Lang.t("niv. %d", "lvl %d") % p.level]


## Armes de l'arsenal qui peuvent recevoir `p` (règle OwnedWeapon.can_mount)
## et les autres avec la raison : {"ok": [OwnedWeapon], "ko": [[OwnedWeapon, raison]]}.
static func compatible(pr: PlayerProfile, p: WeaponPart) -> Dictionary:
	var ok := []
	var ko := []
	if pr == null or p == null:
		return {"ok": ok, "ko": ko}
	var all := pr.weapons.duplicate()
	all.sort_custom(func(a, b):
		if a.level != b.level:
			return a.level > b.level
		return weapon_before(a, b))
	for w in all:
		var why := HubGear.mount_refusal(w, p, pr.level())
		if why == "":
			ok.append(w)
		else:
			ko.append([w, why])
	return {"ok": ok, "ko": ko}
