class_name WeaponDB
extends RefCounted
## Arsenal de Black Ops 1 Zombies (Kino der Toten / Five). Données pures, lues
## par le client (prédiction, visuel) ET par le serveur (validation, dégâts) :
## une seule source de vérité.
##
## Unités : dégâts en PV (zombie de manche 1 : 150 PV), cadence en coups/min,
## dispersion en degrés, portée en m, vitesse de projectile en m/s.
## Chaque arme hérite des valeurs de sa famille (CLASSES), puis surcharge ce
## qu'elle veut ; la clé "pap" contient les valeurs remplacées après
## Pack-a-Punch. Clés facultatives :
##   wall_cost   prix au mur (Kino / Five)      box        poids dans la boîte
##   burst       tir en rafale (coups)           burst_delay pause après la rafale (s)
##   splash_radius / splash_damage / self_damage  explosion au point d'impact
##   projectile_speed  projectile visible, explosion à l'arrivée (m/s)
##   burn_dps / burn_time  balles incendiaires (dégâts par seconde, durée)
##   move_mult   vitesse de déplacement          reload_kind mag|shells|break|bolt|cylinder|belt|rocket

## Valeurs communes par famille d'arme.
const CLASSES := {
	"pistol": {"head_mult": 3.0, "auto": false, "pellets": 1, "spread_hip": 1.4, "spread_ads": 0.25,
		"range": 25.0, "penetration": 1, "recoil": 1.8, "ads_zoom": 0.85, "move_mult": 1.0,
		"sound": "pistol_fire", "reload_kind": "mag"},
	"revolver": {"head_mult": 2.0, "auto": false, "pellets": 1, "spread_hip": 1.8, "spread_ads": 0.15,
		"range": 30.0, "penetration": 3, "recoil": 4.5, "ads_zoom": 0.8, "move_mult": 1.0,
		"sound": "revolver_fire", "reload_kind": "cylinder"},
	"smg": {"head_mult": 2.0, "auto": true, "pellets": 1, "spread_hip": 3.0, "spread_ads": 0.7,
		"range": 18.0, "penetration": 1, "recoil": 0.9, "ads_zoom": 0.85, "move_mult": 1.0,
		"sound": "smg_fire", "reload_kind": "mag"},
	"rifle": {"head_mult": 2.5, "auto": true, "pellets": 1, "spread_hip": 2.6, "spread_ads": 0.3,
		"range": 35.0, "penetration": 2, "recoil": 1.2, "ads_zoom": 0.75, "move_mult": 0.95,
		"sound": "rifle_fire", "reload_kind": "mag"},
	"lmg": {"head_mult": 2.0, "auto": true, "pellets": 1, "spread_hip": 3.8, "spread_ads": 0.7,
		"range": 35.0, "penetration": 3, "recoil": 1.3, "ads_zoom": 0.8, "move_mult": 0.875,
		"sound": "lmg_fire", "reload_kind": "belt"},
	"shotgun": {"head_mult": 1.5, "auto": false, "pellets": 8, "spread_hip": 6.5, "spread_ads": 4.0,
		"range": 8.0, "penetration": 1, "recoil": 5.0, "ads_zoom": 0.9, "move_mult": 1.0,
		"sound": "shotgun_fire", "reload_kind": "shells"},
	"sniper": {"head_mult": 3.0, "auto": false, "pellets": 1, "spread_hip": 7.0, "spread_ads": 0.0,
		"range": 80.0, "penetration": 5, "recoil": 6.0, "ads_zoom": 0.35, "move_mult": 0.95,
		"sound": "sniper_fire", "reload_kind": "bolt"},
	"launcher": {"head_mult": 1.0, "auto": false, "pellets": 1, "spread_hip": 1.5, "spread_ads": 0.3,
		"range": 60.0, "penetration": 1, "recoil": 4.5, "ads_zoom": 0.8, "move_mult": 0.95,
		"sound": "launcher_fire", "reload_kind": "shells", "tracer": "grenade"},
	"rocket": {"head_mult": 1.0, "auto": false, "pellets": 1, "spread_hip": 1.2, "spread_ads": 0.2,
		"range": 80.0, "penetration": 1, "recoil": 6.0, "ads_zoom": 0.75, "move_mult": 0.9,
		"sound": "rocket_fire", "reload_kind": "rocket", "tracer": "rocket"},
	"wonder": {"head_mult": 1.0, "auto": false, "pellets": 1, "spread_hip": 0.8, "spread_ads": 0.2,
		"range": 60.0, "penetration": 1, "recoil": 1.5, "ads_zoom": 0.85, "move_mult": 1.0,
		"sound": "ray_fire", "reload_kind": "mag", "tracer": "ray"},
}

const WEAPONS := {
	# ------------------------------------------------------------ départ
	"m1911": {"name": "M1911", "pap_name": "CASTOR & POLLUX", "class": "pistol",
		"damage": 25, "rpm": 400, "mag": 8, "reserve": 80, "reload": 1.6,
		# Amélioré : balles explosives (façon lance-grenades de poing), 6 coups.
		"pap": {"damage": 150, "mag": 6, "reserve": 50, "rpm": 450, "splash_radius": 2.4, "splash_damage": 900,
			"self_damage": 25, "projectile_speed": 60.0, "sound": "launcher_fire", "tracer": "grenade", "sound_pitch": 1.25}},
	# ------------------------------------------------------------ murs (Kino / Five)
	"olympia": {"name": "OLYMPIA", "pap_name": "OLYMPIA PHLÉGÉTHON", "class": "shotgun",
		"damage": 60, "rpm": 200, "mag": 2, "reserve": 38, "reload": 2.8, "reload_kind": "break",
		"spread_hip": 7.0, "spread_ads": 5.0, "wall_cost": 500,
		# Amélioré : cartouches incendiaires.
		"pap": {"damage": 130, "reserve": 60, "burn_dps": 250, "burn_time": 2.0, "penetration": 2}},
	"m14": {"name": "M14", "pap_name": "M14 VIEILLE GARDE", "class": "rifle",
		"damage": 105, "rpm": 380, "auto": false, "mag": 8, "reserve": 96, "reload": 1.9,
		"spread_hip": 2.2, "spread_ads": 0.1, "range": 45.0, "recoil": 2.2, "wall_cost": 500,
		"pap": {"damage": 250, "mag": 15, "reserve": 150, "auto": true, "rpm": 450, "penetration": 3}},
	"mp5k": {"name": "MP5K", "pap_name": "MP5K FRELON", "class": "smg",
		"damage": 70, "rpm": 800, "mag": 30, "reserve": 120, "reload": 2.1, "wall_cost": 1000,
		"pap": {"damage": 140, "mag": 40, "reserve": 200, "rpm": 850, "penetration": 2}},
	"mpl": {"name": "MPL", "pap_name": "MPL MANTICORE", "class": "smg",
		"damage": 75, "rpm": 900, "mag": 24, "reserve": 192, "reload": 2.0, "wall_cost": 1000,
		"pap": {"damage": 150, "mag": 32, "reserve": 256, "penetration": 2}},
	"pm63": {"name": "PM63", "pap_name": "PM63 CHIENS JUMEAUX", "class": "smg",
		"damage": 70, "rpm": 1000, "mag": 20, "reserve": 100, "reload": 1.9,
		"spread_hip": 3.5, "spread_ads": 1.0, "range": 15.0, "wall_cost": 1000,
		# Amélioré : une arme dans chaque main (chargeur doublé).
		"pap": {"damage": 140, "mag": 40, "reserve": 200, "rpm": 1050, "penetration": 2}},
	"mp40": {"name": "MP40", "pap_name": "MP40 VIEUX LOUP", "class": "smg",
		"damage": 90, "rpm": 550, "mag": 32, "reserve": 192, "reload": 2.3,
		"spread_hip": 2.6, "spread_ads": 0.5, "range": 20.0, "wall_cost": 1000,
		"pap": {"damage": 180, "mag": 64, "reserve": 192, "rpm": 600, "penetration": 2}},
	"ak74u": {"name": "AK74u", "pap_name": "AK74u TOUNDRA", "class": "smg",
		"damage": 100, "rpm": 780, "mag": 20, "reserve": 160, "reload": 2.2,
		"spread_hip": 2.6, "spread_ads": 0.5, "range": 25.0, "penetration": 2, "recoil": 1.1, "wall_cost": 1200,
		"pap": {"damage": 180, "mag": 40, "reserve": 280, "penetration": 3}},
	"m16": {"name": "M16", "pap_name": "M16 CENTURION", "class": "rifle",
		"damage": 110, "rpm": 900, "auto": false, "burst": 3, "burst_delay": 0.22,
		"mag": 30, "reserve": 120, "reload": 2.2, "spread_hip": 2.0, "spread_ads": 0.2, "range": 40.0,
		"sound": "burst_fire", "wall_cost": 1200,
		"pap": {"damage": 220, "reserve": 270, "rpm": 1000, "penetration": 3}},
	"stakeout": {"name": "STAKEOUT", "pap_name": "STAKEOUT EMBUSCADE", "class": "shotgun",
		"damage": 70, "rpm": 70, "mag": 6, "reserve": 54, "reload": 3.0, "range": 9.0, "wall_cost": 1500, "cycle": "pump",
		"pap": {"damage": 170, "mag": 10, "reserve": 60, "rpm": 90, "penetration": 2}},
	# ------------------------------------------------------------ boîte mystère
	"cz75": {"name": "CZ75", "pap_name": "CZ75 FLÉAU", "class": "pistol",
		"damage": 120, "rpm": 500, "mag": 15, "reserve": 105, "reload": 1.6, "box": 1.0,
		"pap": {"damage": 240, "mag": 20, "reserve": 200, "auto": true, "rpm": 700, "penetration": 2}},
	"python": {"name": "PYTHON", "pap_name": "PYTHON MAMBA NOIR", "class": "revolver",
		"damage": 400, "rpm": 180, "mag": 6, "reserve": 60, "reload": 3.0, "box": 1.0,
		"pap": {"damage": 1200, "mag": 12, "reserve": 72, "penetration": 5}},
	"spectre": {"name": "SPECTRE", "pap_name": "SPECTRE ÂME DAMNÉE", "class": "smg",
		"damage": 80, "rpm": 950, "mag": 30, "reserve": 120, "reload": 2.2, "box": 1.0,
		"pap": {"damage": 160, "mag": 60, "reserve": 240, "penetration": 2}},
	"galil": {"name": "GALIL", "pap_name": "GALIL SIROCCO", "class": "rifle",
		"damage": 110, "rpm": 750, "mag": 35, "reserve": 315, "reload": 2.8, "box": 1.0,
		"pap": {"damage": 220, "reserve": 490, "penetration": 3}},
	"famas": {"name": "FAMAS", "pap_name": "FAMAS FULGURANT", "class": "rifle",
		"damage": 100, "rpm": 900, "mag": 30, "reserve": 150, "reload": 2.6, "box": 1.0,
		"pap": {"damage": 200, "mag": 45, "reserve": 225, "penetration": 3}},
	"commando": {"name": "COMMANDO", "pap_name": "COMMANDO TRAQUEUR", "class": "rifle",
		"damage": 120, "rpm": 800, "mag": 30, "reserve": 270, "reload": 2.4, "box": 1.0,
		"pap": {"damage": 240, "mag": 40, "reserve": 360, "penetration": 3}},
	"aug": {"name": "AUG", "pap_name": "AUG SENTINELLE", "class": "rifle",
		"damage": 130, "rpm": 700, "mag": 30, "reserve": 270, "reload": 2.8,
		"spread_ads": 0.1, "ads_zoom": 0.6, "box": 1.0,
		"pap": {"damage": 260, "mag": 60, "reserve": 360, "penetration": 3}},
	"g11": {"name": "G11", "pap_name": "G11 DYNAMO", "class": "rifle",
		"damage": 110, "rpm": 1800, "auto": false, "burst": 3, "burst_delay": 0.3,
		"mag": 48, "reserve": 192, "reload": 2.6, "spread_ads": 0.1, "ads_zoom": 0.6,
		"sound": "burst_fire", "box": 1.0,
		"pap": {"damage": 220, "mag": 64, "reserve": 384, "penetration": 3}},
	"fnfal": {"name": "FN FAL", "pap_name": "FN FAL ÉCLIPSE", "class": "rifle",
		"damage": 150, "rpm": 400, "auto": false, "mag": 20, "reserve": 120, "reload": 2.6,
		"penetration": 3, "recoil": 2.4, "range": 45.0, "box": 1.0,
		"pap": {"damage": 300, "mag": 30, "reserve": 180, "burst": 3, "burst_delay": 0.2, "rpm": 700, "penetration": 4}},
	"hk21": {"name": "HK21", "pap_name": "HK21 SÉISME", "class": "lmg",
		"damage": 130, "rpm": 750, "mag": 125, "reserve": 500, "reload": 4.5, "box": 1.0,
		"pap": {"damage": 260, "mag": 150, "reserve": 750, "penetration": 4}},
	"rpk": {"name": "RPK", "pap_name": "RPK TONNERRE ROUGE", "class": "lmg",
		"damage": 120, "rpm": 700, "mag": 100, "reserve": 400, "reload": 4.0, "box": 1.0,
		"pap": {"damage": 240, "mag": 125, "reserve": 500, "penetration": 4}},
	"spas12": {"name": "SPAS-12", "pap_name": "SPAS-12 CARNAGE", "class": "shotgun",
		"damage": 70, "rpm": 90, "mag": 8, "reserve": 32, "reload": 3.0, "box": 1.0, "cycle": "pump",
		"pap": {"damage": 170, "mag": 24, "reserve": 120, "rpm": 110, "penetration": 2}},
	"hs10": {"name": "HS10", "pap_name": "HS10 OURAGANS JUMEAUX", "class": "shotgun",
		"damage": 60, "rpm": 240, "mag": 6, "reserve": 36, "reload": 2.8, "box": 1.0,
		"pap": {"damage": 140, "mag": 12, "reserve": 72, "penetration": 2}},
	"dragunov": {"name": "DRAGUNOV", "pap_name": "DRAGUNOV TSAR", "class": "sniper",
		"damage": 800, "head_mult": 2.5, "rpm": 200, "mag": 10, "reserve": 40, "reload": 3.2,
		"reload_kind": "mag", "recoil": 4.0, "box": 1.0,
		"pap": {"damage": 2000, "mag": 15, "reserve": 60, "penetration": 8}},
	"l96a1": {"name": "L96A1", "pap_name": "L96A1 VEUVE NOIRE", "class": "sniper",
		"damage": 1000, "rpm": 45, "mag": 5, "reserve": 50, "reload": 3.6, "penetration": 6,
		"ads_zoom": 0.3, "box": 1.0, "cycle": "bolt",
		"pap": {"damage": 3000, "mag": 8, "reserve": 64, "rpm": 60, "penetration": 10}},
	"china_lake": {"name": "CHINA LAKE", "pap_name": "CHINA LAKE DRAGON DE JADE", "class": "launcher",
		"damage": 150, "rpm": 60, "mag": 2, "reserve": 20, "reload": 3.2,
		"splash_radius": 3.0, "splash_damage": 1000, "self_damage": 60, "projectile_speed": 38.0, "box": 1.0, "cycle": "pump",
		"pap": {"mag": 5, "reserve": 40, "splash_radius": 3.8, "splash_damage": 1800}},
	"law": {"name": "M72 LAW", "pap_name": "M72 LAW CATACLYSME", "class": "rocket",
		"damage": 800, "rpm": 60, "mag": 1, "reserve": 20, "reload": 2.8,
		"splash_radius": 3.5, "splash_damage": 1500, "self_damage": 75, "projectile_speed": 45.0, "box": 1.0,
		"pap": {"mag": 5, "reserve": 40, "rpm": 150, "splash_radius": 4.5, "splash_damage": 3000}},
	# ------------------------------------------------------------ arme merveille
	"ray": {"name": "CLAUDE-RAY", "pap_name": "CLAUDE-RAY SUPERNOVA", "class": "wonder",
		"damage": 1000, "rpm": 180, "mag": 20, "reserve": 160, "reload": 2.6,
		"splash_radius": 2.2, "splash_damage": 700, "self_damage": 40, "box": 0.35,
		"pap": {"damage": 2000, "splash_damage": 1500, "mag": 40, "reserve": 200, "rpm": 220}},
}

## Champs obligatoires de chaque arme (après fusion avec sa famille).
const REQUIRED := ["name", "pap_name", "class", "damage", "head_mult", "rpm", "auto", "mag", "reserve",
	"reload", "pellets", "spread_hip", "spread_ads", "range", "penetration", "recoil", "ads_zoom",
	"move_mult", "sound", "reload_kind", "model"]

## Arme de départ de chaque joueur.
const STARTING_WEAPON := "m1911"
## Nombre d'emplacements d'armes (hors couteau).
const MAX_SLOTS := 2
## Prix des munitions d'une arme améliorée au mur.
const PAP_AMMO_COST := 4500

## Mêlée (couteau) : tue un zombie de manche 1 en un coup.
const MELEE_DAMAGE := 150
const MELEE_RANGE := 1.9
const MELEE_COOLDOWN := 0.7

static var _cache: Dictionary = {}


static func exists(id: String) -> bool:
	return WEAPONS.has(id)


## Statistiques effectives (famille + arme, puis valeurs Pack-a-Punch si `pap`).
## Le résultat est partagé (lecture seule).
static func stats(id: String, pap := false) -> Dictionary:
	if not WEAPONS.has(id):
		id = STARTING_WEAPON
	var key := id + ("+" if pap else "")
	var cached: Dictionary = _cache.get(key, {})
	if not cached.is_empty():
		return cached
	var base: Dictionary = WEAPONS[id]
	var s: Dictionary = CLASSES.get(base.get("class", "pistol"), {}).duplicate()
	s.merge(base, true)
	s["model"] = base.get("model", id)
	s.erase("pap")
	if pap:
		s.merge(base.get("pap", {}), true)
		s["name"] = base.get("pap_name", base.name)
	s.make_read_only()
	_cache[key] = s
	return s


static func display_name(id: String, pap := false) -> String:
	return stats(id, pap).name


static func fire_interval(id: String, pap := false) -> float:
	return 60.0 / float(stats(id, pap).rpm)


## Multiplicateur de dégâts selon la distance (plein jusqu'à `range`, puis
## décroissance linéaire jusqu'à 50 % à 2x la portée).
static func falloff(id: String, pap: bool, distance: float) -> float:
	var r: float = stats(id, pap).range
	if distance <= r:
		return 1.0
	return clampf(1.0 - 0.5 * (distance - r) / r, 0.5, 1.0)


## Nouvelle instance d'arme (état d'inventaire sérialisable).
static func new_instance(id: String, pap := false) -> Dictionary:
	var s := stats(id, pap)
	return {"id": id, "pap": pap, "mag": s.mag, "reserve": s.reserve}


## Prix d'achat mural (0 si l'arme ne s'achète pas au mur).
static func wall_cost(id: String) -> int:
	return int(WEAPONS.get(id, {}).get("wall_cost", 0))


## Prix des munitions au mur : moitié prix, 4500 si l'arme est améliorée.
static func ammo_cost(id: String, pap: bool) -> int:
	return PAP_AMMO_COST if pap else wall_cost(id) / 2


## Armes de la boîte mystère et leur poids (l'arme merveille est plus rare).
static func box_pool() -> Dictionary:
	var out := {}
	for id in WEAPONS:
		var w: float = WEAPONS[id].get("box", 0.0)
		if w > 0.0:
			out[id] = w
	return out


## Délai d'arrivée d'un projectile (0 = arme à balles, effet immédiat).
static func projectile_delay(id: String, pap: bool, origin: Vector3, impact: Vector3) -> float:
	var v: float = stats(id, pap).get("projectile_speed", 0.0)
	if v <= 0.0 or impact == Vector3.INF:
		return 0.0
	return origin.distance_to(impact) / v


## Serveur : donne une arme à un joueur (remplace l'arme en main si les
## emplacements sont pleins). Retourne l'emplacement de la nouvelle arme.
static func give(pd: PlayerData, id: String, pap := false) -> int:
	var existing := pd.has_weapon(id)
	if existing >= 0:
		pd.weapons[existing] = new_instance(id, pap)
		pd.slot = existing
		return existing
	if pd.weapons.size() < MAX_SLOTS:
		pd.weapons.append(new_instance(id, pap))
		pd.slot = pd.weapons.size() - 1
	else:
		pd.weapons[pd.slot] = new_instance(id, pap)
	return pd.slot


## Serveur : remplit chargeur et réserve de l'arme `slot`.
static func refill(pd: PlayerData, slot: int) -> void:
	var w: Dictionary = pd.weapons[slot]
	var s := stats(w.id, w.pap)
	w.mag = s.mag
	w.reserve = s.reserve


static func is_full(w: Dictionary) -> bool:
	var s := stats(w.id, w.pap)
	return w.mag >= s.mag and w.reserve >= s.reserve
