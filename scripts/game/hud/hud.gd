class_name Hud
extends CanvasLayer
## Interface en jeu. Aucune logique de gameplay : elle affiche l'état du joueur
## local (données serveur via Session, prédiction d'armes via WeaponController).

var player: Player
var game: Game
var _crosshair: Crosshair
## Écran de lunette (L96A1, Dragunov, AUG, G11).
var scope: ScopeOverlay
var _hitmarker: HitMarker
var _debug: Label
var _ammo: Label
var _reserve: Label
var _weapon_name: Label
## Niveau, rareté et score de l'arme en main (texte écrit seulement s'il change).
var _weapon_info: Label
var _weapon_info_key := ""
## Panneau d'inventaire de partie ([I]).
var inventory: InventoryPanel
## Interface de la station de construction ([F] à la station).
var station_panel: StationPanel
var _hint: Label
var _vignette: ColorRect
var _vignette_mat: ShaderMaterial
var _hurt_flash := 0.0
var _damage_dir: DamageIndicator
var _center_msg: Label
var _center_sub: Label
var _fade: ColorRect
var _heart_t := 0.0
var _scores: ScorePanel
var _prompt: Label
var _prompt_view: Label
## Touche INTERAGIR affichée dans l'invite (change avec le périphérique : F / X / CARRÉ).
var _prompt_key := ""
var _banner_tw: Tween
var _flash: Label
## Nom de l'arme : affiché au changement d'arme puis estompé (BO1).
var _weapon_shown := ""
var _weapon_name_t := 0.0
const WEAPON_NAME_TIME := 3.0
var _flash_t := 0.0
var _round: RoundCounter
var _downed: DownedOverlay
var scoreboard: Scoreboard
var pause_menu: PauseMenu
## Dernières valeurs écrites (_process n'écrit que ce qui change).
## AMMO_UNSET : rien d'écrit encore ; AMMO_HIDDEN : compteur masqué.
const AMMO_UNSET := -2
const AMMO_HIDDEN := -1
var _shown_fps := -1.0
var _shown_mag := AMMO_UNSET
var _shown_reserve := AMMO_UNSET
var _ammo_col: Variant = null
var _reserve_col: Variant = null
var _drawn_spread := -1.0
var _drawn_size := Vector2(-1, -1)


func _ready() -> void:
	layer = 10
	game = get_parent()
	_build_pause_menu.call_deferred()

	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette_mat = ShaderMaterial.new()
	_vignette_mat.shader = preload("res://assets/shaders/hurt_vignette.gdshader")
	_vignette.material = _vignette_mat
	add_child(_vignette)

	# Écran de lunette (sous le reste du HUD).
	scope = ScopeOverlay.new()
	scope.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scope)
	move_child(scope, _vignette.get_index())

	_damage_dir = DamageIndicator.new()
	_damage_dir.set_anchors_preset(Control.PRESET_FULL_RECT)
	_damage_dir.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_damage_dir)

	_crosshair = Crosshair.new()
	_crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_crosshair)
	_hitmarker = HitMarker.new()
	_hitmarker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hitmarker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hitmarker)

	_debug = UiStyle.label("", 13, Color(1, 1, 1, 0.5), "mono")
	_debug.position = Vector2(8, 6)
	add_child(_debug)

	# Compteur de manche en bas à gauche.
	_round = RoundCounter.new()
	_round.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	# Bas collé à 14 px du bord : la taille minimale grandit vers le haut.
	_round.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_round.offset_left = 30
	_round.offset_top = -14
	_round.offset_bottom = -14
	add_child(_round)

	_scores = ScorePanel.new()
	_scores.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_scores.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_scores.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_scores.offset_right = -34
	_scores.offset_bottom = -112
	add_child(_scores)

	# Munitions BO1 : nom de l'arme (s'efface après le changement d'arme),
	# grenades à gauche, chargeur en gros, réserve plus petite.
	var ammo_box := VBoxContainer.new()
	ammo_box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ammo_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ammo_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ammo_box.offset_right = -34
	ammo_box.offset_bottom = -22
	ammo_box.alignment = BoxContainer.ALIGNMENT_END
	ammo_box.add_theme_constant_override("separation", -6)
	ammo_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ammo_box)
	_weapon_name = HudStyle.label("", 22, HudStyle.TEXT, "condensed", 3)
	_weapon_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ammo_box.add_child(_weapon_name)
	# Niveau, rareté (couleur) et score de l'arme en main, discrets (§4.9).
	_weapon_info = HudStyle.label("", 15, HudStyle.TEXT_DIM, "text", 2)
	_weapon_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_weapon_info.modulate.a = 0.8
	ammo_box.add_child(_weapon_info)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ammo_box.add_child(row)
	# Emplacement de grenade (grenades ou peluches leurres), à gauche des munitions.
	row.add_child(ThrowableIcons.new(game))
	_ammo = HudStyle.label("0", 52, HudStyle.TEXT, "condensed", 5)
	row.add_child(_ammo)
	_reserve = HudStyle.label("/ 0", 30, HudStyle.TEXT_DIM, "condensed", 4)
	_reserve.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(_reserve)

	_hint = HudStyle.label("", 24, HudStyle.TEXT, "text", 4)
	_hint.set_anchors_preset(Control.PRESET_CENTER)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.position = Vector2(-300, 56)
	_hint.size = Vector2(600, 40)
	add_child(_hint)

	# Invite d'interaction : `_prompt` garde le texte brut de l'objet visé
	# (tests), `_prompt_view` l'affiche au format BO1 (bo1_prompt).
	_prompt = UiStyle.label("", 24, UiStyle.BONE)
	_prompt.visible = false
	add_child(_prompt)
	_prompt_view = HudStyle.label("", 25, HudStyle.TEXT, "text", 5)
	_prompt_view.set_anchors_preset(Control.PRESET_CENTER)
	_prompt_view.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_view.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt_view.position = Vector2(-460, 96)
	_prompt_view.size = Vector2(920, 40)
	add_child(_prompt_view)
	_flash = HudStyle.label("", 23, HudStyle.POINTS_LOSS, "text", 4)
	_flash.set_anchors_preset(Control.PRESET_CENTER)
	_flash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flash.position = Vector2(-400, 170)
	_flash.size = Vector2(800, 40)
	add_child(_flash)

	_downed = DownedOverlay.new()
	# Ancrages posés AVANT l'ajout : sous un CanvasLayer, les poser après
	# conserve une taille nulle.
	_downed.setup(game)
	add_child(_downed)
	# Vision floue « à terre » : sous tout le HUD (qui reste net).
	add_child(_downed.blur)
	move_child(_downed.blur, 0)

	scoreboard = Scoreboard.new()
	scoreboard.setup(game)
	add_child(scoreboard)

	inventory = InventoryPanel.new()
	inventory.setup(game)
	add_child(inventory)

	station_panel = StationPanel.new()
	station_panel.setup(game)
	add_child(station_panel)

	_fade = ColorRect.new()
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	var center := VBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center.grow_vertical = Control.GROW_DIRECTION_BOTH
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_center_msg = HudStyle.label("", 72, HudStyle.CHALK, "title", 10)
	_center_msg.add_theme_color_override("font_outline_color", Color(0.35, 0.0, 0.0, 0.85))
	_center_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_center_msg)
	_center_sub = HudStyle.label("", 28, HudStyle.TEXT, "text", 5)
	_center_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_center_sub)


func bind_player(p: Player) -> void:
	player = p
	_scores.bind(game.session)


## Marqueur de touche : blanc = touché (prédit localement), rouge = tué (serveur).
func hit_marker(killed: bool, headshot: bool) -> void:
	_hitmarker.show_marker(killed, headshot)
	if not killed:
		Audio.play_2d("hitmarker", -10.0, 0.05)


## Coup reçu : flash rouge et indicateur de direction.
func damage_flash(from: Vector3) -> void:
	_hurt_flash = 1.0
	if player:
		var to := from - player.global_position
		var local := player.global_transform.basis.inverse() * to
		_damage_dir.show_from(atan2(local.x, -local.z))


func show_center(title: String, sub := "", fade_alpha := 0.0) -> void:
	# Un bandeau en cours (« RÉANIMÉ »...) ne doit pas effacer ce message.
	if _banner_tw and _banner_tw.is_valid():
		_banner_tw.kill()
	_center_msg.modulate.a = 1.0
	_center_msg.add_theme_font_size_override("font_size", 72)
	_center_msg.text = title
	_center_sub.text = sub
	create_tween().tween_property(_fade, "color:a", fade_alpha, 1.2)


func _process(delta: float) -> void:
	_scoreboard_tick()
	# Chaque écriture ci-dessous n'a lieu que si la valeur change (textes,
	# couleurs du thème, paramètres de shader, dessin du réticule) : même
	# affichage, sans reformatage ni propagation du thème à chaque image.
	var fps := Engine.get_frames_per_second()
	if fps != _shown_fps:
		_shown_fps = fps
		_debug.text = "%d FPS" % fps
	if player == null:
		return
	var pd := game.session.local_data()
	# Vignette de santé
	var hurt := 0.0
	if pd:
		hurt = 1.0 - float(pd.health) / maxf(pd.max_health, 1)
	_hurt_flash = maxf(_hurt_flash - delta * 1.6, 0.0)
	var intensity := clampf(maxf(hurt * 1.1, _hurt_flash * 0.8), 0.0, 1.0)
	# À terre : la vision floue (DownedOverlay) porte déjà le rouge.
	if pd and pd.life != PlayerData.Life.ALIVE:
		intensity = minf(intensity, 0.3)
	var beat_rate := 1.0 + hurt * 1.5
	var prev_beat := _heart_t
	_heart_t += delta * beat_rate
	# Plein écran avec bruit : masqué quand il n'y a rien à montrer (perf).
	_vignette.visible = intensity > 0.001
	# Masquée, elle n'est pas dessinée : ses paramètres sont écrits dès
	# qu'elle réapparaît (même image), inutile de les écrire avant.
	if _vignette.visible:
		_vignette_mat.set_shader_parameter("intensity", intensity)
		_vignette_mat.set_shader_parameter("pulse", absf(sin(_heart_t * PI)))
		_vignette_mat.set_shader_parameter("flash", clampf(_hurt_flash * 1.6 - 0.6, 0.0, 1.0))
	if hurt > 0.45 and pd.life == PlayerData.Life.ALIVE and floorf(_heart_t) != floorf(prev_beat):
		Audio.play_2d("heartbeat", -6.0, 0.0)
		# Respiration haletante (un souffle tous les trois battements).
		if int(floorf(_heart_t)) % 3 == 0:
			Audio.play_2d("player_breath_%d" % (1 + int(floorf(_heart_t) / 3.0) % 2), -8.0, 0.05)

	# Réticule dynamique : son écart est la dispersion réelle du prochain tir.
	var wcx := player.weapons
	_crosshair.spread = maxf(WeaponDB.spread_to_px(wcx.spread_deg(), player.camera.fov, _crosshair.size.y), 3.0) if wcx else 10.0
	# En visée, les organes de visée remplacent le réticule (sauf arme sans
	# organes de visée, info « no_sights »).
	var sights: bool = wcx == null or wcx.view == null or wcx.view.model_id == "" or not WeaponModels.info(wcx.view.model_id, "no_sights", false)
	_crosshair.visible = not player.sprinting and not (player.aiming and sights) and (pd == null or pd.life != PlayerData.Life.DEAD)
	scope.refresh(player, delta)
	# Le dessin ne dépend que de l'écart et de la taille du réticule.
	if _crosshair.spread != _drawn_spread or _crosshair.size != _drawn_size:
		_drawn_spread = _crosshair.spread
		_drawn_size = _crosshair.size
		_crosshair.queue_redraw()
	var focus := game.interact.focused
	var raw := focus.prompt(player.peer_id) if focus else ""
	# Recalculée aussi quand la touche change (clavier <-> manette, réaffectation).
	var key := Settings.action_label("interact") if raw != "" else _prompt_key
	if raw != _prompt.text or key != _prompt_key:
		_prompt.text = raw
		_prompt_key = key
		_prompt_view.text = bo1_prompt(raw, key)
	if _flash_t > 0.0:
		_flash_t -= delta
		_flash.modulate.a = clampf(_flash_t, 0.0, 1.0)
		if _flash_t <= 0.0:
			_flash.text = ""
	var wc := player.weapons
	if wc:
		var w := wc.current()
		if not w.is_empty():
			var s := wc.current_stats()
			if s.name != _weapon_shown:
				_weapon_shown = s.name
				_weapon_name.text = WeaponDB.localized(s.name)
				_weapon_name_t = WEAPON_NAME_TIME
			var info_key := "%d|%d|%d|%s" % [GameWeapon.level_of(w), GameWeapon.rarity_of(w), GameWeapon.score(w), Settings.language]
			if info_key != _weapon_info_key:
				_weapon_info_key = info_key
				_weapon_info.text = weapon_info_text(w)
				_weapon_info.add_theme_color_override("font_color", GameWeapon.rarity_color(GameWeapon.rarity_of(w)))
			_weapon_name_t = maxf(_weapon_name_t - delta, 0.0)
			_weapon_name.modulate.a = clampf(_weapon_name_t / 0.8, 0.0, 1.0)
			@warning_ignore("integer_division")
			var low: bool = w.mag <= int(s.mag) / 4
			var infinite: bool = s.get("infinite", false)
			var mag: int = w.mag
			var reserve: int = w.reserve
			if infinite:
				# Arme à munitions illimitées (`infinite`) : pas de compteur.
				low = false
				if _shown_mag != AMMO_HIDDEN:
					_shown_mag = AMMO_HIDDEN
					_shown_reserve = AMMO_HIDDEN
					_ammo.text = ""
					_reserve.text = ""
			else:
				if mag != _shown_mag:
					_shown_mag = mag
					_ammo.text = str(mag)
				if reserve != _shown_reserve:
					_shown_reserve = reserve
					_reserve.text = " / %d" % reserve
			var ammo_col := HudStyle.POINTS_LOSS if low else HudStyle.TEXT
			if ammo_col != _ammo_col:
				_ammo_col = ammo_col
				_ammo.add_theme_color_override("font_color", ammo_col)
			var reserve_col := HudStyle.POINTS_LOSS if reserve == 0 and not infinite else HudStyle.TEXT_DIM
			if reserve_col != _reserve_col:
				_reserve_col = reserve_col
				_reserve.add_theme_color_override("font_color", reserve_col)
			var hint := ""
			if infinite:
				hint = ""
			elif mag == 0 and reserve == 0:
				hint = Lang.t("PLUS DE MUNITIONS", "NO AMMO")
			elif wc.is_reloading():
				hint = Lang.t("RECHARGEMENT...", "RELOADING...")
			elif low and reserve > 0:
				hint = Lang.t("Appuyer sur %s pour recharger", "Press %s to reload") % Settings.action_label("reload")
			if hint != _hint.text:
				_hint.text = hint
		elif _weapon_info_key != "":
			# Mains vides : ni nom, ni niveau, ni munitions.
			_weapon_info_key = ""
			_weapon_info.text = ""
			_weapon_name.text = ""
			_weapon_shown = ""
			_shown_mag = AMMO_HIDDEN
			_shown_reserve = AMMO_HIDDEN
			_ammo.text = ""
			_reserve.text = ""
	# Compte à rebours dans la salle du rituel (prioritaire).
	var tp := game.teleporter
	if tp and tp.state == Teleporter.State.ACTIVE and game.layout.zone_at(player.global_position) == game.layout.teleporter_exit_zone():
		_hint.text = Lang.t("RETOUR DANS %d s", "RETURNING IN %d s") % tp.seconds_left()


class Crosshair extends Control:
	var spread := 10.0

	## BO1 : quatre traits fins blancs, liseré sombre pour rester lisibles sur
	## les lampes et le grain ; pas de point central.
	func _draw() -> void:
		var c := size * 0.5
		var col := Color(0.95, 0.95, 0.9, 0.8)
		var dark := Color(0, 0, 0, 0.45)
		var l := 8.0
		for d: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
			var a := c + d * spread
			var b := c + d * (spread + l)
			draw_line(a - d, b + d, dark, 3.5)
			draw_line(a, b, col, 1.6)


class HitMarker extends Control:
	var _t := 0.0
	var _kill := false
	var _head := false

	func show_marker(killed: bool, headshot: bool) -> void:
		if killed:
			_kill = true
			_t = 0.45
		elif not _kill:
			_t = 0.25
		_head = headshot
		queue_redraw()

	func _process(delta: float) -> void:
		if _t > 0.0:
			_t -= delta
			if _t <= 0.0:
				_kill = false
			queue_redraw()

	func _draw() -> void:
		if _t <= 0.0:
			return
		var c := size * 0.5
		var col := Color(0.9, 0.1, 0.05, minf(_t * 6.0, 1.0)) if _kill else Color(1, 1, 1, minf(_t * 6.0, 0.9))
		var a := 6.0
		var b := 14.0 if not _head else 17.0
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(c + d.normalized() * a, c + d.normalized() * b, col, 2.5 if _kill else 2.0)


class DamageIndicator extends Control:
	var _angle := 0.0
	var _t := 0.0

	func show_from(angle: float) -> void:
		_angle = angle
		_t = 1.2
		queue_redraw()

	func _process(delta: float) -> void:
		if _t > 0.0:
			_t -= delta
			queue_redraw()

	func _draw() -> void:
		if _t <= 0.0:
			return
		var c := size * 0.5
		var dir := Vector2(sin(_angle), -cos(_angle))
		var r := minf(size.x, size.y) * 0.22
		var tip := c + dir * (r + 26.0)
		var side := dir.orthogonal() * 22.0
		var base := c + dir * r
		var col := Color(0.75, 0.05, 0.03, clampf(_t, 0.0, 0.8))
		draw_colored_polygon(PackedVector2Array([tip, base + side, base - side]), col)


func round_changed(n: int, starting: bool) -> void:
	_round.set_round(n, starting)


## Manche de chiens : le compteur de manche clignote.
func set_special_round(on: bool) -> void:
	_round.set_special(on)


func round_counter() -> RoundCounter:
	return _round


## Grand bandeau temporaire au centre (événement de la partie).
func show_banner(text: String, duration := 3.5) -> void:
	_center_msg.text = text
	_center_msg.add_theme_font_size_override("font_size", 46)
	_center_msg.modulate.a = 0.0
	if _banner_tw and _banner_tw.is_valid():
		_banner_tw.kill()
	var tw := create_tween()
	_banner_tw = tw
	tw.tween_property(_center_msg, "modulate:a", 1.0, 0.6)
	tw.tween_interval(duration)
	tw.tween_property(_center_msg, "modulate:a", 0.0, 1.2)
	tw.tween_callback(func():
		_center_msg.text = ""
		_center_msg.modulate.a = 1.0
		_center_msg.add_theme_font_size_override("font_size", 72))


## Invite au format BO1 (« Press F to buy M14 [Cost: 500] ») à partir du texte
## des objets (« [F] Acheter M14 [500] » / « [F] Buy M14 [500] ») :
##   « Appuyer sur F pour acheter M14 [Coût : 500] » / « Press F to buy M14 [Cost: 500] ».
## Le texte des objets est déjà dans la langue du joueur (Lang.t) ; seuls les
## mots ajoutés ici (« Appuyer sur... pour », « Coût ») suivent Lang.
## `key` : nom de la touche INTERAGIR (réaffectable dans les options).
## Pure : testée dans tests/test_hud.gd.
const PROMPT_NOUNS := {
	"Caisse": "ouvrir la caisse",
	"Crate": "open the crate",
}
## Préfixes « maintenir » des deux langues (« Maintenir [F] ... », « [F] Hold ... »).
const HOLD_WORDS := ["Maintenir", "Hold"]


static func bo1_prompt(raw: String, key := "F") -> String:
	if raw == "":
		return ""
	var t := raw
	# Coûts : « [500] » -> « [Coût : 500] ».
	var re := RegEx.create_from_string("\\[(\\d+)\\]")
	t = re.sub(t, Lang.t("[Coût : $1]", "[Cost: $1]"), true)
	for hold: String in HOLD_WORDS:
		if t.begins_with(hold + " [F]"):
			return hold + " " + key + t.substr(hold.length() + 4)
	if not t.begins_with("[F] "):
		return t
	var rest := t.substr(4)
	for hold: String in HOLD_WORDS:
		if rest.begins_with(hold + " "):
			return "%s %s %s" % [hold, key, rest.substr(hold.length() + 1)]
	var press := Lang.t("Appuyer sur %s pour %s%s", "Press %s to %s%s")
	for noun: String in PROMPT_NOUNS:
		if rest.begins_with(noun):
			return press % [key, PROMPT_NOUNS[noun], rest.substr(noun.length())]
	return press % [key, rest.substr(0, 1).to_lower(), rest.substr(1)]


## Message bref (refus d'achat...).
func flash_message(text: String) -> void:
	_flash.text = text
	_flash_t = 1.8


# --------------------------------------------------------------------------
# Écran de chargement
# --------------------------------------------------------------------------

var _loading: Control


func show_loading(map_name: String) -> void:
	if _loading:
		return
	_loading = Control.new()
	_loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_loading)
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_loading.add_child(box)
	var title := UiStyle.label(map_name, 64, UiStyle.BLOOD, "title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := UiStyle.label(Lang.t("CHARGEMENT...", "LOADING..."), 20, UiStyle.DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)


func hide_loading() -> void:
	if _loading == null:
		return
	var l := _loading
	_loading = null
	var tw := create_tween()
	tw.tween_property(l, "modulate:a", 0.0, 1.2)
	tw.tween_callback(l.queue_free)


## Éclair blanc de téléportation.
func teleport_flash() -> void:
	var r := ColorRect.new()
	r.color = Color(1.0, 0.92, 0.8, 0.95)
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	var tw := r.create_tween()
	tw.tween_property(r, "color:a", 0.0, 0.9).set_ease(Tween.EASE_OUT)
	tw.tween_callback(r.queue_free)


## Niveau, rareté et score d'une arme de partie, pour le HUD (« NIV. 3 ·
## RARE · SCORE 5 »). Pure (tests).
static func weapon_info_text(w: Dictionary) -> String:
	if w.is_empty():
		return ""
	return Lang.t("NIV. %d · %s · SCORE %d", "LVL %d · %s · SCORE %d") % [GameWeapon.level_of(w),
		GameWeapon.rarity_name(GameWeapon.rarity_of(w)), GameWeapon.score(w)]


func _unhandled_input(event: InputEvent) -> void:
	# Station de construction ouverte : Échap, B ou [I] la ferment (avant le
	# menu pause et l'inventaire).
	if station_panel and station_panel.visible and GameState.is_in_game():
		if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("inventory"):
			station_panel.close()
			get_viewport().set_input_as_handled()
			return
	# Panneau d'inventaire : [I] l'ouvre et le ferme ; ouvert, Échap ou B le
	# ferment (avant le menu pause).
	if inventory and GameState.is_in_game() and pause_menu and not pause_menu.visible:
		if event.is_action_pressed("inventory") and GameState.state != GameState.State.GAME_OVER:
			inventory.toggle()
			get_viewport().set_input_as_handled()
			return
		if inventory.visible and (event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")):
			inventory.close()
			get_viewport().set_input_as_handled()
			return
	# Ouverture seulement : une fois ouvert (partie suspendue en solo), le
	# menu pause gère lui-même Échap (retour des options, reprise).
	if event.is_action_pressed("pause") and GameState.is_in_game() and pause_menu and not pause_menu.visible:
		pause_menu.open()
		get_viewport().set_input_as_handled()


## Toujours au premier plan : créé en dernier.
func _build_pause_menu() -> void:
	pause_menu = PauseMenu.new()
	pause_menu.setup(game)
	add_child(pause_menu)


func _scoreboard_tick() -> void:
	if GameState.state == GameState.State.GAME_OVER:
		return
	var show_board := Input.is_action_pressed("scoreboard") and not pause_menu.visible
	if show_board and not scoreboard.visible:
		scoreboard.refresh()
	scoreboard.visible = show_board


## Fin de partie (Game._cl_game_over) : « GAME OVER » + résumé sur voile
## sombre, manches survécues, tableau des scores, battement de cœur. Textes
## déjà dans la langue du joueur (Game.game_over_summary / survived_text).
func show_game_over(summary: String, survived: String) -> void:
	show_center("GAME OVER", summary, 0.6)
	show_game_over_table(survived)
	Audio.play_2d("heartbeat", 0.0, 0.0)


## Fin de partie (Game._show_match_end), une des deux issues : « ÉVACUATION
## RÉUSSIE » ou « GAME OVER », zombies abattus, manche atteinte et durée,
## tableau des scores. Le rapport complet (butin gardé ou perdu, XP) viendra
## ici avec les lots suivants (MatchResult.loot, xp).
func show_match_end(r: MatchResult) -> void:
	set_evac_status("")
	if inventory:
		inventory.close()
	if station_panel:
		station_panel.close()
	show_center(r.title(), r.summary(), 0.6)
	show_game_over_table(r.details())
	if not r.evacuated:
		Audio.play_2d("heartbeat", 0.0, 0.0)


var _evac_label: Label


## Fenêtre d'évacuation (EvacDoor) : compte à rebours et votes ("" : masqué).
func set_evac_status(text: String) -> void:
	if _evac_label == null:
		if text == "":
			return
		_evac_label = UiStyle.label("", 22, Color(0.55, 1.0, 0.6))
		_evac_label.anchor_left = 0.5
		_evac_label.anchor_right = 0.5
		_evac_label.offset_left = -500
		_evac_label.offset_right = 500
		_evac_label.offset_top = 110
		_evac_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(_evac_label)
	_evac_label.text = text
	_evac_label.visible = text != ""


## Texte du bandeau d'évacuation affiché ("" : aucun ; tests).
func evac_status() -> String:
	return _evac_label.text if _evac_label and _evac_label.visible else ""


## Fin de partie : tableau récapitulatif.
## BO1 : « GAME OVER » en haut, « Vous avez survécu N manches » dessous, puis
## le tableau des scores.
func show_game_over_table(title_text: String) -> void:
	_center_sub.text = title_text.substr(0, 1) + title_text.substr(1).to_lower()
	_center_msg.add_theme_font_size_override("font_size", 84)
	scoreboard.refresh("")
	scoreboard._title.text = "SCORES"
	scoreboard.visible = true
	scoreboard.offset_top = 70
	scoreboard.offset_bottom = 80  # la hauteur minimale du contenu l'emporte
	# Au-dessus du voile sombre de fin de partie (le menu pause reste devant).
	move_child(scoreboard, _fade.get_index())
	# Le bloc central remonte au-dessus du tableau.
	var center := _center_msg.get_parent() as Control
	center.offset_top = -250
	center.offset_bottom = -110
	_center_msg.modulate.a = 0.0
	_center_sub.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_center_msg, "modulate:a", 1.0, 0.8)
	tw.tween_property(_center_sub, "modulate:a", 1.0, 0.8)


var _spectate_label: Label


func set_spectating(player_name: String) -> void:
	if _spectate_label == null:
		_spectate_label = UiStyle.label("", 22, UiStyle.BONE)
		_spectate_label.anchor_left = 0.5
		_spectate_label.anchor_right = 0.5
		_spectate_label.offset_left = -400
		_spectate_label.offset_right = 400
		_spectate_label.offset_top = 70
		_spectate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(_spectate_label)
	_spectate_label.text = (Lang.t("SPECTATEUR — %s   ([Tir] joueur suivant — retour à la prochaine manche)", "SPECTATING — %s   ([Fire] next player — back next round)") % player_name) if player_name != "" else ""
	if player_name != "":
		show_center("", "", 0.0)
