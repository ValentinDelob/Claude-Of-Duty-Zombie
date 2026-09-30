class_name PowerupRules
extends RefCounted
## Règles des bonus (fonctions et petits états purs, testés unitairement).
## Reprises de _zombiemode_powerups de Black Ops 1.

const MAX_AMMO := "max_ammo"
const INSTA_KILL := "insta_kill"
const DOUBLE_POINTS := "double_points"
const NUKE := "nuke"
const CARPENTER := "carpenter"
const FIRE_SALE := "fire_sale"
## DEATH MACHINE de BO1 : minigun pour le seul joueur qui le ramasse.
const DEATH_MACHINE := "death_machine"
## Arme donnée (WeaponDB.POWERUP_WEAPONS).
const DEATH_MACHINE_WEAPON := "death_machine"

## Ordre de déclaration (le sac est mélangé à partir de cette liste).
const ALL := [MAX_AMMO, INSTA_KILL, DOUBLE_POINTS, NUKE, CARPENTER, FIRE_SALE, DEATH_MACHINE]
## Bonus à durée (icône dans le HUD).
const TIMED := [INSTA_KILL, DOUBLE_POINTS, FIRE_SALE]

const NAMES := {
	MAX_AMMO: "MUNITIONS MAX !",
	INSTA_KILL: "MORT INSTANTANÉE !",
	DOUBLE_POINTS: "POINTS DOUBLES !",
	NUKE: "BOMBE NUCLÉAIRE !",
	CARPENTER: "CHARPENTIER !",
	FIRE_SALE: "LIQUIDATION !",
	DEATH_MACHINE: "FAUCHEUSE !",
}

## Seuil de points d'équipe du premier bonus, puis multiplicateur de
## l'incrément à chaque bonus (zombie_powerup_drop_increment).
const START_INCREMENT := 2000.0
const INCREMENT_MULT := 1.14
## Tirage aléatoire par kill : randomint(100) <= 2 dans BO1 (~3 %).
const RANDOM_ROLL_MAX := 2
const MAX_PER_ROUND := 4

## Durée des bonus temporisés (s).
const DURATION := 30.0
const NUKE_POINTS := 400
const CARPENTER_POINTS := 200
const FIRE_SALE_COST := 10
## Nuke : les morts sont échelonnées sur cette durée (s), des plus proches
## aux plus éloignés.
const NUKE_SPREAD := 1.6
## Rayon de ramassage (BO1 : 64 unités, ~1,6 m), mesuré à plat.
const PICKUP_RADIUS := 1.5

## Durée de vie au sol (powerup_timeout de BO1) : 15 s visible, puis 40
## alternances de plus en plus rapides (15 x 0,5 s, 10 x 0,25 s, 15 x 0,1 s).
const SOLID_TIME := 15.0
const BLINKS := 40


static func blink_wait(i: int) -> float:
	if i < 15:
		return 0.5
	if i < 25:
		return 0.25
	return 0.1


## Durée totale au sol (26,5 s).
static func lifetime() -> float:
	var t := SOLID_TIME
	for i in BLINKS:
		t += blink_wait(i)
	return t


## Visibilité du bonus au sol `age` secondes après son apparition.
static func drop_visible(age: float) -> bool:
	if age < SOLID_TIME:
		return true
	var t := SOLID_TIME
	for i in BLINKS:
		t += blink_wait(i)
		if age < t:
			return i % 2 == 1  # i pair : caché
	return false


## Icône du HUD : clignote pendant les dernières secondes, de plus en plus vite.
static func hud_icon_visible(time_left: float) -> bool:
	if time_left > 10.0:
		return true
	var period := 0.5 if time_left > 5.0 else 0.2
	return fmod(time_left, period) > period * 0.4


static func is_timed(type: String) -> bool:
	return type in TIMED


static func display_name(type: String) -> String:
	return NAMES.get(type, type.to_upper())


# --------------------------------------------------------------------------
# Déclenchement des apparitions (watch_for_drop + powerup_drop)
# --------------------------------------------------------------------------

class DropTracker extends RefCounted:
	var increment := START_INCREMENT
	var score_to_drop := START_INCREMENT
	## Le prochain kill d'un joueur fera tomber un bonus.
	var drop_pending := false
	var drops_this_round := 0

	## Total des points GAGNÉS par toute l'équipe depuis le début.
	func on_team_total(total: float) -> void:
		if total > score_to_drop:
			increment *= INCREMENT_MULT
			score_to_drop = total + increment
			drop_pending = true

	func new_round() -> void:
		drops_this_round = 0

	## Kill d'un joueur : `roll` = entier aléatoire dans [0, 99].
	## Retourne true si un bonus doit tomber (et le comptabilise).
	func try_drop(roll: int, in_playable_area: bool) -> bool:
		if drops_this_round >= MAX_PER_ROUND:
			return false
		if roll > RANDOM_ROLL_MAX and not drop_pending:
			return false
		# Hors zone jouable : rien, mais le bonus « dû » reste en attente.
		if not in_playable_area:
			return false
		drops_this_round += 1
		drop_pending = false
		return true


# --------------------------------------------------------------------------
# Ordre des bonus : sac mélangé rejoué en boucle
# --------------------------------------------------------------------------

class Bag extends RefCounted:
	var items: Array = []
	var index := 0
	var rng := RandomNumberGenerator.new()

	func _init(list: Array = ALL, seed_value := -1) -> void:
		items = list.duplicate()
		if seed_value >= 0:
			rng.seed = seed_value
		else:
			rng.randomize()
		shuffle()

	func shuffle() -> void:
		# Fisher-Yates avec le générateur du sac (reproductible dans les tests).
		for i in range(items.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var t: Variant = items[i]
			items[i] = items[j]
			items[j] = t
		index = 0

	func next_item() -> String:
		if index >= items.size():
			shuffle()
		var v: String = items[index]
		index += 1
		return v

	## Prochain bonus autorisé par `valid` (Callable(type) -> bool). Les bonus
	## refusés sont consommés (get_valid_powerup de BO1). "" si aucun.
	func next_valid(valid: Callable) -> String:
		for k in items.size() * 2:
			var v := next_item()
			if valid.call(v):
				return v
		return ""
