extends AutotestScenario
## HUD : le compteur de munitions, sa couleur, l'aide sous le réticule et le
## compteur d'images montrent exactement ce qu'écrivait l'ancien HUD (tout
## réécrit à chaque image) alors qu'il n'écrit plus que ce qui change :
## pleine charge, chargeur bas, réserve vide, plus de munitions, retour.

var p: Player
var game: Game


## Ce que l'ancien Hud._process écrivait pour l'arme `w` (hors lunette,
## hors salle du rituel) : [munitions, réserve, couleur, couleur, aide].
func _expected(w: Dictionary) -> Array:
	var s := p.weapons.current_stats()
	var ammo := str(w.mag)
	var reserve := " / %d" % w.reserve
	@warning_ignore("integer_division")
	var low: bool = w.mag <= int(s.mag) / 4
	if s.get("infinite", false):
		ammo = ""
		reserve = ""
		low = false
	var ammo_col := HudStyle.POINTS_LOSS if low else HudStyle.TEXT
	var reserve_col := HudStyle.POINTS_LOSS if w.reserve == 0 and not s.get("infinite", false) else HudStyle.TEXT_DIM
	var hint := ""
	if s.get("infinite", false):
		hint = ""
	elif w.mag == 0 and w.reserve == 0:
		hint = Lang.t("PLUS DE MUNITIONS", "NO AMMO")
	elif p.weapons.is_reloading():
		hint = Lang.t("RECHARGEMENT...", "RELOADING...")
	elif low and w.reserve > 0:
		hint = Lang.t("Appuyer sur %s pour recharger", "Press %s to reload") % Settings.action_label("reload")
	return [ammo, reserve, ammo_col, reserve_col, hint]


func _shown() -> Array:
	var h := game.hud
	return [h._ammo.text, h._reserve.text, h._ammo.get_theme_color("font_color"),
		h._reserve.get_theme_color("font_color"), h._hint.text]


func _case(label: String, mag: int, reserve: int) -> void:
	var w := p.weapons.current()
	w.mag = mag
	w.reserve = reserve
	await frames(2)
	var want := _expected(w)
	var got := _shown()
	at.check(got == want, "%s : %s (attendu %s)" % [label, got, want])


func run() -> void:
	p = await AutotestHelpers.start_solo_game(self)
	if p == null:
		return
	game = Game.instance
	game.combat.debug_invulnerable = true
	await seconds(0.5)
	var mag := int(p.weapons.current_stats().mag)
	await _case("pleine charge", mag, 80)
	await _case("chargeur bas", 1, 80)
	await _case("chargeur bas, même valeur", 1, 80)
	await _case("réserve vide", mag, 0)
	await _case("plus de munitions", 0, 0)
	await _case("retour à la normale", mag, 40)
	await _case("chargeur vide, réserve pleine", 0, 40)
	await _case("retour à la normale (bis)", mag - 1, 39)
	# Compteur d'images : même texte que l'ancien formatage.
	await frames(2)
	at.check(game.hud._debug.text == "%d FPS" % Engine.get_frames_per_second(), "compteur d'images : %s" % game.hud._debug.text)
	# Réticule : redessiné dès que son écart change (tir).
	var ch := game.hud._crosshair
	at.check(game.hud._drawn_spread == ch.spread and game.hud._drawn_size == ch.size, "réticule dessiné avec l'écart courant (%.1f)" % ch.spread)
	var w := p.weapons.current()
	w.mag = mag
	w.reserve = 80
	await until(func(): return not p.weapons.is_reloading(), 4.0, "rechargement fini")
	var s0 := ch.spread
	p.input.fire = true
	await seconds(0.05)
	p.input.fire = false
	await frames(1)
	at.check(ch.spread != s0 and game.hud._drawn_spread == ch.spread, "réticule redessiné quand l'écart change (%.1f -> %.1f)" % [s0, ch.spread])
	await seconds(1.0)
	at.check(game.hud._drawn_spread == ch.spread, "réticule redessiné au retour (%.1f)" % ch.spread)
	# Vignette de blessure : paramètres écrits dès qu'elle est visible.
	game.combat.debug_invulnerable = false
	game.combat.damage_player(1, 60, p.global_position + Vector3(2, 1, 0))
	game.combat.debug_invulnerable = true
	await frames(3)
	var inten: Variant = game.hud._vignette_mat.get_shader_parameter("intensity")
	at.check(game.hud._vignette.visible and (inten == null or float(inten) > 0.1), "vignette visible et réglée après un coup (%s)" % inten)
