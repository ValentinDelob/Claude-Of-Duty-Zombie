class_name WeaponDB
extends RefCounted
## Définition de toutes les armes. Données pures, lues par le client (prédiction,
## visuel) ET par le serveur (validation, dégâts) : une seule source de vérité.
##
## Unités : dégâts en PV, cadence en coups/min, dispersion en degrés, portée en m.
## La clé "pap" contient les valeurs remplacées après Pack-a-Punch.

const WEAPONS := {
	"pistol": {
		"name": "P-9 SERVICE", "pap_name": "P-9 CERBÈRE",
		"slot_class": "pistol", "damage": 30, "head_mult": 2.5, "rpm": 420, "auto": false,
		"mag": 8, "reserve": 64, "reload": 1.5, "pellets": 1, "spread_hip": 1.4, "spread_ads": 0.25,
		"range": 25.0, "penetration": 1, "recoil": 1.8, "ads_zoom": 0.85,
		"sound": "pistol_fire", "model": "pistol",
		"pap": {"damage": 110, "mag": 12, "reserve": 120, "rpm": 480, "penetration": 2, "sound_pitch": 0.85},
	},
	"carbine": {
		"name": "M-14 CARABINE", "pap_name": "M-14 SANS RETOUR",
		"slot_class": "rifle", "damage": 110, "head_mult": 2.5, "rpm": 360, "auto": false,
		"mag": 8, "reserve": 96, "reload": 1.8, "pellets": 1, "spread_hip": 2.2, "spread_ads": 0.1,
		"range": 45.0, "penetration": 2, "recoil": 2.2, "ads_zoom": 0.75,
		"wall_cost": 500,
		"sound": "rifle_fire", "model": "carbine",
		"pap": {"damage": 260, "mag": 15, "reserve": 150, "auto": true, "rpm": 420, "penetration": 3},
	},
	"smg": {
		"name": "KRAKEN-9", "pap_name": "KRAKEN DES ABYSSES",
		"slot_class": "smg", "damage": 55, "head_mult": 2.0, "rpm": 780, "auto": true,
		"mag": 30, "reserve": 150, "reload": 2.2, "pellets": 1, "spread_hip": 3.0, "spread_ads": 0.6,
		"range": 18.0, "penetration": 1, "recoil": 0.9, "ads_zoom": 0.85,
		"wall_cost": 1000,
		"sound": "smg_fire", "model": "smg",
		"pap": {"damage": 150, "mag": 45, "reserve": 270, "rpm": 850, "penetration": 2},
	},
	"shotgun": {
		"name": "BRUTE-12", "pap_name": "BRUTE-12 BOUCHER",
		"slot_class": "shotgun", "damage": 70, "head_mult": 1.5, "rpm": 75, "auto": false,
		"mag": 6, "reserve": 42, "reload": 2.8, "pellets": 8, "spread_hip": 6.5, "spread_ads": 4.0,
		"range": 8.0, "penetration": 1, "recoil": 5.0, "ads_zoom": 0.9,
		"wall_cost": 1500,
		"sound": "shotgun_fire", "model": "shotgun",
		"pap": {"damage": 180, "mag": 10, "reserve": 70, "rpm": 110, "penetration": 2},
	},
	"assault": {
		"name": "VANGUARD AR", "pap_name": "VANGUARD APOCALYPSE",
		"slot_class": "rifle", "damage": 100, "head_mult": 2.5, "rpm": 620, "auto": true,
		"mag": 30, "reserve": 240, "reload": 2.4, "pellets": 1, "spread_hip": 2.6, "spread_ads": 0.3,
		"range": 35.0, "penetration": 2, "recoil": 1.2, "ads_zoom": 0.75,
		"sound": "rifle_fire", "model": "assault",
		"pap": {"damage": 240, "mag": 45, "reserve": 360, "rpm": 680, "penetration": 3},
	},
	"lmg": {
		"name": "HAILSTORM LMG", "pap_name": "HAILSTORM DÉLUGE",
		"slot_class": "lmg", "damage": 130, "head_mult": 2.0, "rpm": 560, "auto": true,
		"mag": 100, "reserve": 300, "reload": 4.2, "pellets": 1, "spread_hip": 3.8, "spread_ads": 0.7,
		"range": 35.0, "penetration": 3, "recoil": 1.3, "ads_zoom": 0.8, "move_mult": 0.88,
		"sound": "lmg_fire", "model": "lmg",
		"pap": {"damage": 300, "mag": 150, "reserve": 600, "rpm": 620, "penetration": 4},
	},
	"sniper": {
		"name": "LONGSHOT .50", "pap_name": "LONGSHOT TRÉPAS",
		"slot_class": "sniper", "damage": 600, "head_mult": 3.0, "rpm": 45, "auto": false,
		"mag": 5, "reserve": 40, "reload": 3.2, "pellets": 1, "spread_hip": 7.0, "spread_ads": 0.0,
		"range": 80.0, "penetration": 5, "recoil": 6.0, "ads_zoom": 0.35, "move_mult": 0.9,
		"sound": "sniper_fire", "model": "sniper",
		"pap": {"damage": 1800, "mag": 8, "reserve": 64, "rpm": 60, "penetration": 8},
	},
	"ray": {
		"name": "CLAUDE-RAY", "pap_name": "CLAUDE-RAY SUPERNOVA",
		"slot_class": "wonder", "damage": 1000, "head_mult": 1.0, "rpm": 180, "auto": false,
		"mag": 20, "reserve": 160, "reload": 2.6, "pellets": 1, "spread_hip": 0.8, "spread_ads": 0.2,
		"range": 60.0, "penetration": 1, "recoil": 1.5, "ads_zoom": 0.85,
		"splash_radius": 2.2, "splash_damage": 700, "self_damage": 40,
		"sound": "ray_fire", "model": "ray", "tracer": "ray",
		"pap": {"damage": 2000, "splash_damage": 1500, "mag": 40, "reserve": 200, "rpm": 220},
	},
}

## Arme de départ de chaque joueur.
const STARTING_WEAPON := "pistol"
## Nombre d'emplacements d'armes (hors couteau).
const MAX_SLOTS := 2

## Mêlée (couteau).
const MELEE_DAMAGE := 150
const MELEE_RANGE := 1.9
const MELEE_COOLDOWN := 0.7


static func exists(id: String) -> bool:
	return WEAPONS.has(id)


## Statistiques effectives (avec les valeurs Pack-a-Punch si `pap`).
static func stats(id: String, pap := false) -> Dictionary:
	var base: Dictionary = WEAPONS.get(id, WEAPONS[STARTING_WEAPON])
	if not pap:
		return base
	var s := base.duplicate()
	s.merge(base.get("pap", {}), true)
	s["name"] = base.get("pap_name", base.name)
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
	return 4500 if pap else wall_cost(id) / 2


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
