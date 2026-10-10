class_name XpCalibration
extends RefCounted
## Simulation du calibrage de l'XP (GAME_CONCEPT §4.15 : niveau 10 vers 3 h,
## 25 vers 25 h, 50 vers 120 h ; docs/XP_RULES.md §4). Pure et déterministe :
## estime l'XP et la durée d'une partie type à partir des vraies règles
## (RoundRules.zombie_count, DogRules.dog_count, WaveRules, XpRules), puis le
## temps de jeu pour atteindre chaque niveau (PlayerProfile).
##
## Lancement : tests/test_xp_rules.gd (vérifie les cibles et imprime le
## tableau, report()) :
## `godot --headless --path . res://tests/test_runner.tscn -- --files=test_xp_rules.gd`.
##
## Hypothèses (joueur « type », valeurs moyennes à re-mesurer en jeu) :
## * cadence d'élimination : KILL_PACE s par zombie et par joueur (approche,
##   tir, rechargement, déplacement ; les PV montent avec la manche mais les
##   armes du joueur aussi) ; chiens : DOG_PACE s chacun, plus l'annonce ;
## * chaque manche coûte en plus ROUND_OVERHEAD s (entracte de 10 s, trajet
##   jusqu'aux premiers zombies) ; l'évacuation EVAC_TIME s ; chaque partie
##   MATCH_OVERHEAD s (chargement, écran de fin, hub) ;
## * comportement : le joueur s'évacue après la vague spéciale de la manche
##   evac_round(niveau) : 5 pour ses toutes premières parties (premières
##   vagues spéciales, après le tutoriel de 3 manches), 10 puis 15 ensuite
##   (« vers la manche 10-15 »), puis plus loin quand son arsenal le permet
##   (20, puis 25) ;
## * aucune mort (une défaite garde l'XP mais perd le bonus d'évacuation : un
##   joueur qui meurt progresse un peu moins vite) ; aucun contrat.

const KILL_PACE := 3.0
const DOG_PACE := 4.0
const ROUND_OVERHEAD := 25.0
const EVAC_TIME := 30.0
const MATCH_OVERHEAD := 90.0
## Temps visés (heures) par niveau (§4.15) et tolérance du test.
const TARGET_HOURS := {10: 3.0, 25: 25.0, 50: 120.0}
const TOLERANCE := 0.2


## Manche d'évacuation type selon le niveau du joueur.
static func evac_round(level: int) -> int:
	if level < 5:
		return 5
	if level < 10:
		return 10
	if level < 25:
		return 15
	if level < 40:
		return 20
	return 25


## Une partie de `players` joueurs, évacuation à la manche `evac` (vague
## spéciale vaincue) : XP et éliminations d'UN joueur, durée en secondes.
## Schéma des vagues par défaut (WaveRules.DEFAULT, pas de boss défini).
static func simulate_match(evac: int, players := 1) -> Dictionary:
	var l := XpRules.new_ledger()
	var sec := MATCH_OVERHEAD
	var dog_rounds := 0
	for r in range(1, evac + 1):
		var kind := WaveRules.wave_kind(WaveRules.DEFAULT, r, false)
		if kind == WaveRules.SPECIAL:
			dog_rounds += 1
			var dogs := DogRules.dog_count(players, dog_rounds)
			# Meute partagée : chaque joueur en abat sa part.
			for i in roundi(float(dogs) / players):
				XpRules.add_kill(l, XpRules.DOG, r)
			sec += DogRules.START_DELAY + float(dogs) / players * DOG_PACE + ROUND_OVERHEAD
			XpRules.add_wave(l, kind, r)
		else:
			var n := RoundRules.zombie_count(r, players)
			var mine := roundi(float(n) / players)
			# Marcheurs puis coureurs : même barème (XpRules), le type ne
			# change pas l'XP d'un zombie commun.
			for i in mine:
				XpRules.add_kill(l, XpRules.WALKER, r)
			sec += float(n) / players * KILL_PACE + ROUND_OVERHEAD
		XpRules.add_round(l, r)
	XpRules.close(l, true)
	sec += EVAC_TIME
	return {"xp": XpRules.total(l), "kills": XpRules.kill_count(l), "sec": sec}


## Heures de jeu pour atteindre chaque niveau (2 à 50), en enchaînant des
## parties types (evac_round selon le niveau atteint).
static func hours_to_levels(players := 1) -> Dictionary:
	var out := {}
	var xp := 0
	var sec := 0.0
	var lvl := 1
	var guard := 0
	while lvl < PlayerProfile.MAX_LEVEL and guard < 100000:
		guard += 1
		var m := simulate_match(evac_round(lvl), players)
		xp += int(m.xp)
		sec += float(m.sec)
		while lvl < PlayerProfile.MAX_LEVEL and xp >= PlayerProfile.xp_for_level(lvl + 1):
			lvl += 1
			out[lvl] = sec / 3600.0
	return out


## Tableau lisible (outil, documentation).
static func report() -> String:
	var lines := PackedStringArray()
	lines.append("Parties types (solo) :")
	for e in [10, 15, 20, 25]:
		var m := simulate_match(e)
		lines.append("  évacuation manche %d : %d XP, %d éliminations, %.1f min, %d XP/h" % [e, m.xp, m.kills,
				m.sec / 60.0, roundi(m.xp / m.sec * 3600.0)])
	for p in [1, 4]:
		var h := hours_to_levels(p)
		lines.append("%d joueur(s) : niveau 10 en %.1f h, 25 en %.1f h, 50 en %.1f h" % [p, h[10], h[25], h[50]])
	return "\n".join(lines)
