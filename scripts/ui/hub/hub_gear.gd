class_name HubGear
extends RefCounted
## Textes et règles d'affichage des armes et des pièces au hub (onglets
## ARSENAL, PIÈCES, DÉPART ; docs/HUB_PLAN.md §3.2, §3.3, §3.6). Fonctions
## pures (testées par tests/test_hub_arsenal.gd) : filtres et tris de
## l'arsenal, numéros de version, nom d'une pièce, modificateurs en clair,
## statistiques effectives d'une fiche (GameWeapon.stats), raison d'un refus
## de montage (OwnedWeapon.can_mount).

## Filtres de l'arsenal (Tab / Y : cycle).
const FILTERS := ["all", "firearm", "melee", "usable"]
const FILTER_NAMES := {
	"all": ["TOUTES", "ALL"], "firearm": ["À FEU", "FIREARMS"], "melee": ["CORPS À CORPS", "MELEE"],
	"usable": ["UTILISABLES", "USABLE"],
}
## Tris de l'arsenal (R / X : cycle) : décroissant sauf le nom.
const SORTS := ["score", "level", "rarity", "name"]
const SORT_NAMES := {
	"score": ["SCORE", "SCORE"], "level": ["NIVEAU", "LEVEL"], "rarity": ["RARETÉ", "RARITY"], "name": ["NOM", "NAME"],
}
## Filtres et tris de l'onglet PIÈCES.
const PART_FILTERS := ["all", "mountable"]
const PART_FILTER_NAMES := {"all": ["TOUTES", "ALL"], "mountable": ["MONTABLES", "MOUNTABLE"]}
const PART_SORTS := ["level", "mod"]
const PART_SORT_NAMES := {"level": ["NIVEAU", "LEVEL"], "mod": ["MODIFICATEUR", "MODIFIER"]}

## Nom d'une pièce d'après son premier modificateur (provisoire, HUB_PLAN
## §3.3 : pas encore de catalogue de pièces) [FR, EN].
const PART_NAMES := {
	"damage": ["Renfort", "Reinforcement"], "fire_rate": ["Ressort", "Spring"], "reload": ["Guide", "Guide rail"],
	"recoil": ["Amortisseur", "Damper"], "accuracy": ["Mire", "Sight"], "mag": ["Rallonge", "Mag extension"],
	"reserve": ["Cartouchière", "Bandolier"],
}
## Noms courts des modificateurs (lignes de liste à deux modificateurs).
const MOD_SHORT := {
	"damage": ["dég.", "dmg"], "fire_rate": ["cad.", "rate"], "reload": ["rech.", "reload"], "recoil": ["recul", "recoil"],
	"accuracy": ["préc.", "acc."], "mag": ["charg.", "mag"], "reserve": ["rés.", "res."],
}
## Précision des modificateurs « div » (plus petit = mieux) [bonus FR, EN,
## malus FR, EN].
const MOD_MEANING := {
	"reload": ["rechargement plus rapide", "faster reload", "rechargement plus lent", "slower reload"],
	"recoil": ["moins de recul", "less recoil", "plus de recul", "more recoil"],
	"accuracy": ["moins de dispersion", "tighter spread", "plus de dispersion", "wider spread"],
}

## Familles d'armes (WeaponDB.CLASSES) : nom [FR, EN] (les mots de
## WeaponDB.FAMILIES en casse de phrase, vérifié par tests/test_hub_arsenal.gd)
## et icône (HubIcon, une par famille ; la batte pour le corps à corps).
const CLASS_NAMES := {
	"pistol": ["Pistolet", "Pistol"], "revolver": ["Revolver", "Revolver"],
	"smg": ["Mitraillette", "SMG"], "rifle": ["Fusil d'assaut", "Assault rifle"],
	"lmg": ["Mitrailleuse", "Machine gun"], "shotgun": ["Fusil à pompe", "Shotgun"],
	"sniper": ["Fusil de précision", "Sniper rifle"], "launcher": ["Lance-grenades", "Grenade launcher"],
	"rocket": ["Lance-roquettes", "Rocket launcher"], "melee": ["Corps à corps", "Melee"],
}
const CLASS_ART := {
	"pistol": "pistol", "revolver": "revolver", "smg": "smg", "rifle": "rifle", "lmg": "lmg", "shotgun": "shotgun",
	"sniper": "sniper", "launcher": "launcher", "rocket": "rocket", "melee": "bat",
}

## Statistiques d'une arme à feu sur la fiche, dans l'ordre de la maquette :
## clé -> [nom FR, EN, plus grand = mieux ?, valeur de la barre pleine].
const FIRE_STATS := [
	["damage", "Dégâts", "Damage"], ["rpm", "Cadence", "Fire rate"], ["reload", "Rechargement", "Reload"],
	["recoil", "Recul", "Recoil"], ["accuracy", "Précision", "Accuracy"], ["mag", "Chargeur", "Magazine"],
	["reserve", "Réserve", "Reserve"],
]
## Barres pleines (provisoire : de quoi comparer les armes entre elles).
const BAR_FULL := {"damage": 300.0, "rpm": 1200.0, "mag": 100.0, "reserve": 500.0}
## Rechargement : barre vide à 5 s et plus ; recul : vide à 6° par coup.
const RELOAD_EMPTY := 5.0
const RECOIL_EMPTY := 6.0
## Précision (0 à 100) = 100 − 12 × dispersion à la hanche (°), provisoire.
const ACCURACY_PER_DEG := 12.0
## Mots du recul (montée par coup, °) : < 1 faible, < 2,5 moyen, sinon fort.
const RECOIL_STEPS := [1.0, 2.5]

## Modificateur de pièce -> statistique de la fiche qu'il change.
const MOD_STAT := {
	"damage": "damage", "fire_rate": "rpm", "reload": "reload", "recoil": "recoil", "accuracy": "accuracy",
	"mag": "mag", "reserve": "reserve",
}


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


## Icône (HubIcon) d'une arme : sa famille, la batte, le couteau ; arme
## inconnue : pistolet.
static func weapon_art(id: String) -> String:
	if not WeaponDB.exists(id):
		return "knife" if KnifeDB.exists(id) or id.contains("knife") else "pistol"
	return CLASS_ART.get(String(WeaponDB.stats(id).get("class", "")), "pistol")


## Rareté et niveau : « niv. 7 ».
static func level_text(lvl: int) -> String:
	return Lang.t("niv. %d", "lvl %d") % lvl


## L'arme passe-t-elle le filtre `filter` (FILTERS) pour un joueur de niveau
## `player_level` ?
static func passes(w: OwnedWeapon, filter: String, player_level: int) -> bool:
	match filter:
		"firearm":
			return not is_melee(w.weapon_id)
		"melee":
			return is_melee(w.weapon_id)
		"usable":
			return w.level <= player_level
	return true


## `a` avant `b` pour le tri `sort` (SORTS) ; à égalité : score, niveau,
## nom, puis identifiant d'exemplaire (ordre stable).
static func before(a: OwnedWeapon, b: OwnedWeapon, sort: String) -> bool:
	var ka := _key(a, sort)
	var kb := _key(b, sort)
	for i in ka.size():
		if ka[i] != kb[i]:
			return ka[i] < kb[i]
	return false


static func _key(w: OwnedWeapon, sort: String) -> Array:
	var n := weapon_name(w.weapon_id)
	var num := w.uid.trim_prefix("w").to_int() if w.uid.begins_with("w") else 0
	match sort:
		"level":
			return [-w.level, -w.score(), -int(w.rarity), n, num]
		"rarity":
			return [-int(w.rarity), -w.score(), -w.level, n, num]
		"name":
			return [n, -w.score(), -w.level, num]
	return [-w.score(), -w.level, -int(w.rarity), n, num]


## Arsenal groupé par arme (HUB_PLAN §3.2) : [{"id", "versions": [OwnedWeapon]}],
## versions filtrées et triées, groupes rangés selon leur première version.
static func arsenal_groups(pr: PlayerProfile, filter: String, sort: String) -> Array:
	var by_id := {}
	var order := []
	for w in pr.weapons:
		if not passes(w, filter, pr.level()):
			continue
		if not by_id.has(w.weapon_id):
			by_id[w.weapon_id] = []
			order.append(w.weapon_id)
		by_id[w.weapon_id].append(w)
	var groups := []
	for id in order:
		var vs: Array = by_id[id]
		vs.sort_custom(func(a, b): return before(a, b, sort))
		groups.append({"id": id, "versions": vs})
	groups.sort_custom(func(a, b): return before(a.versions[0], b.versions[0], sort))
	return groups


## Armes de base qui passent le filtre (toujours en tête, ordre fixe).
static func base_rows(pr: PlayerProfile, filter: String) -> Array[OwnedWeapon]:
	var out: Array[OwnedWeapon] = []
	for w in BaseWeapons.all():
		if passes(w, filter, pr.level()):
			out.append(w)
	return out


## Numéro de version d'un exemplaire (ordre d'arrivée dans l'arsenal, stable
## quel que soit le tri) et nombre de versions de cette arme.
static func version_of(pr: PlayerProfile, w: OwnedWeapon) -> Vector2i:
	var vs := pr.versions_of(w.weapon_id)
	return Vector2i(maxi(vs.find(w) + 1, 1), maxi(vs.size(), 1))


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


static func mod_name(key: String, short := false) -> String:
	key = GameWeapon.MOD_ALIASES.get(key, key)
	var n: Array = (MOD_SHORT if short else LootRules.MOD_NAMES).get(key, [key, key])
	return Lang.t(n[0], n[1])


## « +15 % » (espace insécable en français) / « +15% ».
static func percent(v: float) -> String:
	var n := roundi(absf(v) * 100.0)
	return "%s%d%s%%" % ["+" if v >= 0.0 else "−", n, "" if Lang.is_en() else String.chr(0xA0)]


## Modificateurs d'une pièce : [[texte, bonus ?], …] (« dégâts +15 % »).
static func mod_items(mods: Dictionary, short := false) -> Array:
	var out := []
	for k in mods:
		var v := float(mods[k])
		out.append(["%s %s" % [mod_name(String(k), short), percent(v)], v >= 0.0])
	return out


## Modificateurs en un seul texte : « précision +12 % · rech. −8 % ».
static func mods_plain(mods: Dictionary, short := false) -> String:
	var out := PackedStringArray()
	for it in mod_items(mods, short):
		out.append(String(it[0]))
	return " · ".join(out)


## Modificateur avec son sens en clair : « recul +18 % (moins de recul) ».
static func mod_long(key: String, v: float) -> String:
	key = GameWeapon.MOD_ALIASES.get(key, key)
	var t := "%s %s" % [mod_name(key), percent(v)]
	if MOD_MEANING.has(key):
		var m: Array = MOD_MEANING[key]
		t += " (%s)" % (Lang.t(m[0], m[1]) if v >= 0.0 else Lang.t(m[2], m[3]))
	return t


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


## Tri des pièces (PART_SORTS) : niveau décroissant, ou par modificateur
## (ordre de LootRules.PART_MODS) puis niveau ; à égalité, la plus récente.
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
# Statistiques de la fiche
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


## Valeur numérique d'une statistique de la fiche (pour comparer).
static func stat_number(key: String, s: Dictionary) -> float:
	match key:
		"accuracy":
			return float(accuracy(s))
		"reload", "recoil":
			return float(s.get(key, 0.0))
	return float(s.get(key, 0))


## Remplissage de la barre (0..1, plus = mieux).
static func stat_ratio(key: String, s: Dictionary) -> float:
	var v := stat_number(key, s)
	match key:
		"reload":
			return clampf(1.0 - v / RELOAD_EMPTY, 0.0, 1.0)
		"recoil":
			return clampf(1.0 - v / RECOIL_EMPTY, 0.0, 1.0)
		"accuracy":
			return clampf(v / 100.0, 0.0, 1.0)
	return clampf(v / float(BAR_FULL.get(key, 1.0)), 0.0, 1.0)


static func recoil_word(r: float) -> String:
	if r < RECOIL_STEPS[0]:
		return Lang.t("faible", "low")
	if r < RECOIL_STEPS[1]:
		return Lang.t("moyen", "medium")
	return Lang.t("fort", "high")


## Nombre décimal à la langue : « 2,6 » / « 2.6 ».
static func decimal(v: float) -> String:
	var t := "%.1f" % v
	return t if Lang.is_en() else t.replace(".", ",")


## Texte d'une statistique : « 184 », « 825 /min », « 2,6 s », « moyen ».
static func stat_text(key: String, s: Dictionary) -> String:
	match key:
		"rpm":
			return "%s /min" % HubStyle.num(int(s.get("rpm", 0)))
		"reload":
			return "%s s" % decimal(float(s.get("reload", 0.0)))
		"recoil":
			return recoil_word(float(s.get("recoil", 0.0)))
		"accuracy":
			return str(accuracy(s))
	return HubStyle.num(int(stat_number(key, s)))


## Lignes de statistiques de la fiche d'une arme à feu :
## [{key, label, text, ratio, base_ratio, delta (texte, "" sans écart), good}].
## `base_ratio` : barre sans les pièces (part des pièces en vert ou rouge).
static func stat_lines(w: OwnedWeapon) -> Array:
	var eff := fire_stats(w)
	var raw := fire_stats(w, false)
	var out := []
	for st in FIRE_STATS:
		var key: String = st[0]
		var d := stat_number(key, eff) - stat_number(key, raw)
		var delta := ""
		# Écart écrit pour les valeurs entières (la barre montre les autres).
		if key in ["damage", "accuracy", "mag", "reserve"] and roundi(d) != 0:
			delta = ("+" if d > 0.0 else "−") + str(absi(roundi(d)))
		out.append({"key": key, "label": Lang.t(st[1], st[2]), "text": stat_text(key, eff),
			"ratio": stat_ratio(key, eff), "base_ratio": stat_ratio(key, raw), "delta": delta,
			"good": d > 0.0})
	return out


## Lignes d'une arme de corps à corps (§4.9) : dégâts, coups par seconde,
## énergie par coup ; la batte d'après WeaponDB (rpm = coups par minute,
## « energy »), un couteau d'après KnifeDB.
static func melee_lines(id: String) -> Array:
	var dmg: float
	var hits: float
	var energy: float
	if WeaponDB.exists(id):
		var s := WeaponDB.stats(id)
		dmg = float(s.damage)
		hits = float(s.rpm) / 60.0
		energy = float(s.get("energy", 0.0))
	else:
		dmg = float(KnifeDB.damage(id))
		hits = 1.0 / WeaponDB.MELEE_COOLDOWN
		energy = KnifeDB.energy_cost(id)
	return [
		{"key": "damage", "label": Lang.t("Dégâts", "Damage"), "text": HubStyle.num(roundi(dmg)), "ratio": clampf(dmg / BAR_FULL.damage, 0.0, 1.0),
			"base_ratio": clampf(dmg / BAR_FULL.damage, 0.0, 1.0), "delta": "", "good": true},
		{"key": "hits", "label": Lang.t("Coups / s", "Hits / s"), "text": decimal(hits), "ratio": clampf(hits / 3.0, 0.0, 1.0),
			"base_ratio": clampf(hits / 3.0, 0.0, 1.0), "delta": "", "good": true},
		{"key": "energy", "label": Lang.t("Énergie / coup", "Energy / hit"), "text": decimal(energy),
			"ratio": clampf(1.0 - energy / 30.0, 0.0, 1.0),
			"base_ratio": clampf(1.0 - energy / 30.0, 0.0, 1.0), "delta": "", "good": true},
	]


## Aperçu d'une pièce sur une arme (fenêtre d'installation, onglet PIÈCES) :
## [{label, before, after, good}] pour chaque statistique touchée.
static func part_preview(w: OwnedWeapon, p: WeaponPart) -> Array:
	var out := []
	if w == null or p == null or is_melee(w.weapon_id):
		return out
	var before_s := fire_stats(w)
	var after_w := OwnedWeapon.create(w.weapon_id, w.level, w.rarity)
	after_w.parts = w.parts.duplicate()
	after_w.parts.append(p)
	var after_s := fire_stats(after_w)
	var done := []
	for k in p.mods:
		var key: String = MOD_STAT.get(GameWeapon.MOD_ALIASES.get(String(k), String(k)), "")
		if key == "" or key in done:
			continue
		done.append(key)
		var label := ""
		for st in FIRE_STATS:
			if st[0] == key:
				label = Lang.t(st[1], st[2])
		var b := stat_text(key, before_s)
		var a := stat_text(key, after_s)
		if a == b and key in ["recoil", "reload"]:
			# Même mot (« faible → faible ») : la valeur précise montre l'effet.
			b = "%s%s" % [decimal(float(before_s.get(key, 0.0))), "°" if key == "recoil" else " s"]
			a = "%s%s" % [decimal(float(after_s.get(key, 0.0))), "°" if key == "recoil" else " s"]
		out.append({"label": label, "before": b, "after": a,
			"good": stat_ratio(key, after_s) >= stat_ratio(key, before_s)})
	return out


## Prix et durée à la station : « 2 090 ferraille · 2 manches » ; "" pour
## une arme de corps à corps (elle ne se construit pas).
static func station_text(w: OwnedWeapon) -> String:
	if is_melee(w.weapon_id):
		return ""
	var price := BuildRules.owned_price(w)
	return "%s %s · %s" % [HubStyle.num(price), Lang.t("ferraille", "scrap"), BuildRules.rounds_text(BuildRules.rounds(price))]
