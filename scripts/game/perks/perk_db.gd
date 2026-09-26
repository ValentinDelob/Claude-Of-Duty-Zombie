class_name PerkDB
extends RefCounted
## Atouts (boissons). Effets lus par le serveur (santé, cadence, dégâts,
## rechargement, régénération) et par le client (vitesse, sprint, affichage).

## Solo : LAZARUS TONIC ne peut être acheté que 3 fois, puis la machine disparaît.
const SOLO_REVIVE_LIMIT := 3

const PERKS := {
	"titan": {
		"name": "TITAN BREW", "cost": 2500, "color": Color(0.9, 0.12, 0.08),
		"desc": "Santé maximale 250", "needs_power": true,
	},
	"rapid": {
		"name": "RAPID FIZZ", "cost": 3000, "color": Color(0.25, 0.9, 0.35),
		"desc": "Rechargement 2x plus rapide", "needs_power": true,
	},
	"twin": {
		"name": "TWIN SHOT", "cost": 2000, "color": Color(1.0, 0.72, 0.18),
		"desc": "Cadence de tir +33 %", "needs_power": true,
	},
	"lazarus": {
		"name": "LAZARUS TONIC", "cost": 1500, "solo_cost": 500, "color": Color(0.3, 0.7, 1.0),
		"desc": "Réanimation 2x plus rapide (solo : se relève seul)", "needs_power": true, "solo_needs_power": false,
	},
	"stride": {
		"name": "STRIDE SODA", "cost": 2000, "color": Color(0.8, 0.45, 1.0),
		"desc": "Sprint plus long et plus rapide", "needs_power": true,
	},
	# Five / Ascension (BO1).
	"nova": {
		"name": "NOVA FLOP", "cost": 2000, "color": Color(0.58, 0.16, 0.98),
		"desc": "Aucun dégât de vos explosions ; plongeon explosif", "needs_power": true,
	},
	"deadeye": {
		"name": "DEADEYE DRAM", "cost": 1500, "color": Color(0.8, 0.76, 0.6),
		"desc": "Visée auto vers la tête, tir plus précis", "needs_power": true,
	},
}

const TITAN_HEALTH := 250


static func exists(id: String) -> bool:
	return PERKS.has(id)


static func display_name(id: String) -> String:
	return PERKS.get(id, {}).get("name", id.to_upper())


static func color(id: String) -> Color:
	return PERKS.get(id, {}).get("color", Color.WHITE)


static func cost(id: String, solo: bool) -> int:
	var p: Dictionary = PERKS.get(id, {})
	return int(p.get("solo_cost", p.get("cost", 0))) if solo else int(p.get("cost", 0))


static func needs_power(id: String, solo := false) -> bool:
	var p: Dictionary = PERKS.get(id, {})
	if solo and p.has("solo_needs_power"):
		return p.solo_needs_power
	return p.get("needs_power", true)


# ---- effets (lus partout à partir de PlayerData.perks répliqués)

static func reload_mult(pd: PlayerData) -> float:
	return 0.5 if pd and pd.has_perk("rapid") else 1.0


static func fire_rate_mult(pd: PlayerData) -> float:
	return 1.33 if pd and pd.has_perk("twin") else 1.0


## TWIN SHOT (Double Tap de BO1) n'augmente que la cadence.
static func damage_mult(_pd: PlayerData) -> float:
	return 1.0


## BO1 : aucun atout n'accélère la régénération.
static func regen_delay_mult(_pd: PlayerData) -> float:
	return 1.0


static func max_health(pd: PlayerData) -> int:
	return TITAN_HEALTH if pd and pd.has_perk("titan") else PlayerData.BASE_HEALTH


static func speed_mult(pd: PlayerData) -> float:
	return 1.07 if pd and pd.has_perk("stride") else 1.0


static func sprint_bonus(pd: PlayerData) -> float:
	return 4.0 if pd and pd.has_perk("stride") else 0.0


# ---- NOVA FLOP (PhD Flopper de BO1)

## Plongeon explosif : hauteur minimale de la chute depuis le sommet du
## plongeon (m). BO1 demande une chute ; sur nos cartes plates, le saut rasant
## d'un plongeon en sprint (~0,36 m) suffit, pas un simple accroupi.
const NOVA_MIN_HEIGHT := 0.25
## Rayon et dégâts au centre (50 % au bord, ThrowableRules.splash) : tue en un
## coup jusqu'aux manches 10-12 selon la distance.
const NOVA_RADIUS := 4.0
const NOVA_DAMAGE := 1800
## Délai minimal entre deux explosions d'un même joueur (s).
const NOVA_COOLDOWN := 0.8


## Part des dégâts de ses propres explosions subie par le joueur (grenades,
## lance-grenades, roquettes, grenade gardée en main...).
static func explosive_self_mult(pd: PlayerData) -> float:
	return 0.0 if pd and pd.has_perk("nova") else 1.0


## Le plongeon de `height` m déclenche-t-il l'explosion ?
static func nova_triggers(pd: PlayerData, height: float) -> bool:
	return pd != null and pd.has_perk("nova") and height >= NOVA_MIN_HEIGHT


# ---- DEADEYE DRAM (Deadshot Daiquiri de BO1)

## Cône (demi-angle, degrés) et portée de l'aimantation vers la tête au
## passage en visée.
const DEADEYE_CONE_DEG := 14.0
const DEADEYE_RANGE := 40.0
## Durée du glissement de la visée vers la tête (s).
const DEADEYE_SNAP_TIME := 0.1


static func aim_assist(pd: PlayerData) -> bool:
	return pd != null and pd.has_perk("deadeye")


## Dispersion du tir à la hanche (la visée n'est pas modifiée).
static func hip_spread_mult(pd: PlayerData) -> float:
	return 0.55 if pd and pd.has_perk("deadeye") else 1.0


static func recoil_mult(pd: PlayerData) -> float:
	return 0.5 if pd and pd.has_perk("deadeye") else 1.0


## Index de la tête visée par l'aimantation : la plus proche du centre de
## l'écran (angle avec `fwd`) dans le cône et à portée, -1 si aucune.
static func deadeye_pick(eye: Vector3, fwd: Vector3, heads: Array) -> int:
	var best := -1
	var best_a := deg_to_rad(DEADEYE_CONE_DEG)
	for i in heads.size():
		var to: Vector3 = heads[i] - eye
		var d := to.length()
		if d < 0.3 or d > DEADEYE_RANGE:
			continue
		var a := fwd.angle_to(to)
		if a <= best_a:
			best_a = a
			best = i
	return best


## Lacet et tangage (conventions de Player) qui visent `target` depuis `eye`.
static func look_angles(eye: Vector3, target: Vector3) -> Vector2:
	var dir := target - eye
	return Vector2(atan2(-dir.x, -dir.z), atan2(dir.y, Vector2(dir.x, dir.z).length()))
