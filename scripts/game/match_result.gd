class_name MatchResult
extends RefCounted
## Résultat d'une partie (GAME_CONCEPT.md §4.6, §4.16) : une des deux issues,
## évacuation réussie ou toute l'équipe morte, la manche atteinte et la durée.
## Construit par le serveur (Game.srv_end_match), envoyé à tous en
## dictionnaire (to_dict / from_dict) et affiché par l'écran de fin
## (Hud.show_match_end).
##
## Structure prévue pour s'étendre : le butin gardé ou perdu, l'XP et
## l'arsenal (lots suivants) iront dans `loot` et `xp`, sans changer le
## message réseau (clés inconnues ignorées, clés absentes : valeurs par défaut).

var evacuated := false
## Manche en cours à la fin de la partie.
var round_reached := 0
## Durée de la partie (s de jeu, GameClock).
var duration_sec := 0.0
## Zombies abattus par toute l'équipe.
var kills := 0
## À venir (rapport de fin de partie) : butin gardé / perdu par joueur, XP.
var loot: Dictionary = {}
var xp := 0


func to_dict() -> Dictionary:
	return {"evacuated": evacuated, "round": round_reached, "duration": duration_sec, "kills": kills,
		"loot": loot, "xp": xp}


## Lecture tolérante (message du serveur) : types vérifiés, valeurs bornées.
static func from_dict(d: Variant) -> MatchResult:
	var r := MatchResult.new()
	if not d is Dictionary:
		return r
	var e: Variant = d.get("evacuated", false)
	r.evacuated = e is bool and e
	r.round_reached = _int(d.get("round", 0), 0, 1000000)
	r.kills = _int(d.get("kills", 0), 0, 1 << 30)
	r.xp = _int(d.get("xp", 0), 0, 1 << 30)
	var t: Variant = d.get("duration", 0.0)
	r.duration_sec = clampf(float(t), 0.0, 1e7) if (t is float or t is int) and is_finite(float(t)) else 0.0
	var l: Variant = d.get("loot", {})
	r.loot = l if l is Dictionary else {}
	return r


static func _int(v: Variant, lo: int, hi: int) -> int:
	return clampi(int(v), lo, hi) if (v is int or v is float) and is_finite(float(v)) else lo


## Titre de l'écran de fin.
func title() -> String:
	return Lang.t("ÉVACUATION RÉUSSIE", "EVACUATED") if evacuated else "GAME OVER"


## Ligne sous le titre : zombies abattus.
func summary() -> String:
	return Lang.t("%d zombies abattus", "%d zombies killed") % kills


## Manche atteinte et durée (au-dessus du tableau des scores).
func details() -> String:
	return Lang.t("MANCHE %d ATTEINTE — TEMPS %s", "REACHED ROUND %d — TIME %s") % [round_reached, time_text(duration_sec)]


## Durée « h:mm:ss » ou « m:ss ».
static func time_text(seconds: float) -> String:
	var s := maxi(int(seconds), 0)
	@warning_ignore("integer_division")
	var h := s / 3600
	@warning_ignore("integer_division")
	var m := (s / 60) % 60
	if h > 0:
		return "%d:%02d:%02d" % [h, m, s % 60]
	return "%d:%02d" % [m, s % 60]
