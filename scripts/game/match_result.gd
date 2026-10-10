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
## Butin du joueur local, gardé ou perdu (ProfileLoot.report, rempli par
## chaque client dans Game._show_match_end, comme `xp`).
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


## Rapport du butin du joueur local (§4.16 ; `loot` : ProfileLoot.report,
## rempli par chaque client) : ce qui est gardé après une évacuation, ou
## perdu si l'équipe est morte (l'XP, elle, est toujours gardée). "" : rien.
func loot_text() -> String:
	if loot.is_empty():
		return ""
	var kept: bool = loot.get("kept", false) == true
	var items := PackedStringArray()
	var ws: Variant = loot.get("weapons", [])
	if ws is Array:
		for w in ws:
			if w is Array and w.size() >= 3:
				items.append("%s (%s, %s)" % [WeaponDB.display_name(String(w[0])),
					Lang.t("niv. %d", "lvl %d") % _int(w[1], 1, PlayerProfile.MAX_LEVEL),
					GameWeapon.rarity_name(_int(w[2], 0, 4)).to_lower()])
	var n_parts := _int(loot.get("parts", 0), 0, 1 << 30)
	if n_parts > 0:
		items.append(Lang.t("%d pièce(s)", "%d part(s)") % n_parts)
	var ss: Variant = loot.get("samples", {})
	if ss is Dictionary:
		var keys: Array = ss.keys()
		keys.sort()
		for k in keys:
			var n := _int(ss[k], 0, 1 << 30)
			if n > 0:
				items.append("%d %s" % [n, LootRules.sample_name(String(k)).to_lower()])
	var xp_t := Lang.t("+%d XP", "+%d XP") % xp
	if items.is_empty():
		return Lang.t("Aucun butin rapporté · %s", "No loot brought back · %s") % xp_t
	if kept:
		return Lang.t("BUTIN GARDÉ : %s · %s", "LOOT KEPT: %s · %s") % [", ".join(items), xp_t]
	return Lang.t("BUTIN PERDU : %s · seule l'XP est gardée (%s)", "LOOT LOST: %s · only XP is kept (%s)") % [", ".join(items), xp_t]


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
