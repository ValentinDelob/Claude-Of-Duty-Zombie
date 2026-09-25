class_name PerkDB
extends RefCounted
## Atouts (boissons). Effets lus par le serveur (santé, cadence, dégâts,
## rechargement, régénération) et par le client (vitesse, sprint, affichage).

const MAX_PERKS := 4

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
		"desc": "Cadence +33 %, dégâts +25 %", "needs_power": true,
	},
	"lazarus": {
		"name": "LAZARUS TONIC", "cost": 1500, "solo_cost": 500, "color": Color(0.3, 0.7, 1.0),
		"desc": "Réanimation rapide, régénération accélérée", "needs_power": false,
	},
	"stride": {
		"name": "STRIDE SODA", "cost": 2000, "color": Color(0.8, 0.45, 1.0),
		"desc": "Sprint plus long et plus rapide", "needs_power": true,
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


static func needs_power(id: String) -> bool:
	return PERKS.get(id, {}).get("needs_power", true)


# ---- effets (lus partout à partir de PlayerData.perks répliqués)

static func reload_mult(pd: PlayerData) -> float:
	return 0.5 if pd and pd.has_perk("rapid") else 1.0


static func fire_rate_mult(pd: PlayerData) -> float:
	return 1.33 if pd and pd.has_perk("twin") else 1.0


static func damage_mult(pd: PlayerData) -> float:
	return 1.25 if pd and pd.has_perk("twin") else 1.0


static func regen_delay_mult(pd: PlayerData) -> float:
	return 0.5 if pd and pd.has_perk("lazarus") else 1.0


static func max_health(pd: PlayerData) -> int:
	return TITAN_HEALTH if pd and pd.has_perk("titan") else PlayerData.BASE_HEALTH


static func speed_mult(pd: PlayerData) -> float:
	return 1.07 if pd and pd.has_perk("stride") else 1.0


static func sprint_bonus(pd: PlayerData) -> float:
	return 4.0 if pd and pd.has_perk("stride") else 0.0
