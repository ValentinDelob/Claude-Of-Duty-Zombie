class_name Hud
extends CanvasLayer
## Interface en jeu. Aucune logique de gameplay : elle affiche l'état du joueur
## local (données serveur via Session, prédiction d'armes via WeaponController).

var player: Player
var game: Game
var _crosshair: Crosshair
var _hitmarker: HitMarker
var _debug: Label
var _ammo: Label
var _reserve: Label
var _weapon_name: Label
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


func _ready() -> void:
	layer = 10
	game = get_parent()

	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette_mat = ShaderMaterial.new()
	_vignette_mat.shader = preload("res://assets/shaders/hurt_vignette.gdshader")
	_vignette.material = _vignette_mat
	add_child(_vignette)

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

	_scores = ScorePanel.new()
	_scores.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_scores.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_scores.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_scores.offset_right = -36
	_scores.offset_bottom = -118
	add_child(_scores)

	var ammo_box := VBoxContainer.new()
	ammo_box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ammo_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ammo_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ammo_box.offset_right = -36
	ammo_box.offset_bottom = -26
	ammo_box.alignment = BoxContainer.ALIGNMENT_END
	ammo_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ammo_box)
	_weapon_name = UiStyle.label("", 18, UiStyle.DIM, "impact")
	_weapon_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ammo_box.add_child(_weapon_name)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ammo_box.add_child(row)
	_ammo = UiStyle.label("0", 44, UiStyle.BONE, "impact")
	row.add_child(_ammo)
	_reserve = UiStyle.label("/ 0", 24, UiStyle.DIM, "impact")
	_reserve.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(_reserve)

	_hint = UiStyle.label("", 22, UiStyle.BONE)
	_hint.set_anchors_preset(Control.PRESET_CENTER)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.position = Vector2(-300, 60)
	_hint.size = Vector2(600, 40)
	add_child(_hint)

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
	_center_msg = UiStyle.label("", 72, UiStyle.BLOOD_BRIGHT, "title")
	_center_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_center_msg)
	_center_sub = UiStyle.label("", 24, UiStyle.BONE)
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
	_center_msg.text = title
	_center_sub.text = sub
	create_tween().tween_property(_fade, "color:a", fade_alpha, 1.2)


func _process(delta: float) -> void:
	_debug.text = "%d FPS" % Engine.get_frames_per_second()
	if player == null:
		return
	var pd := game.session.local_data()
	# Vignette de santé
	var hurt := 0.0
	if pd:
		hurt = 1.0 - float(pd.health) / maxf(pd.max_health, 1)
	_hurt_flash = maxf(_hurt_flash - delta * 1.6, 0.0)
	var intensity := clampf(maxf(hurt * 1.1, _hurt_flash * 0.8), 0.0, 1.0)
	var beat_rate := 1.0 + hurt * 1.5
	var prev_beat := _heart_t
	_heart_t += delta * beat_rate
	_vignette_mat.set_shader_parameter("intensity", intensity)
	_vignette_mat.set_shader_parameter("pulse", absf(sin(_heart_t * PI)))
	if hurt > 0.45 and pd.life == PlayerData.Life.ALIVE and floorf(_heart_t) != floorf(prev_beat):
		Audio.play_2d("heartbeat", -6.0, 0.0)

	_crosshair.spread = 0.0 if player.aiming else (18.0 if Vector2(player.velocity.x, player.velocity.z).length() > 1.0 else 10.0)
	_crosshair.visible = not player.sprinting and not player.aiming and (pd == null or pd.life != PlayerData.Life.DEAD)
	_crosshair.queue_redraw()
	var wc := player.weapons
	if wc:
		var w := wc.current()
		if not w.is_empty():
			var s := wc.current_stats()
			_weapon_name.text = s.name
			_ammo.text = str(w.mag)
			_reserve.text = " / %d" % w.reserve
			var low: bool = w.mag <= int(s.mag) / 4
			_ammo.add_theme_color_override("font_color", UiStyle.BLOOD_BRIGHT if low else UiStyle.BONE)
			if w.mag == 0 and w.reserve == 0:
				_hint.text = "PLUS DE MUNITIONS"
			elif wc.is_reloading():
				_hint.text = "RECHARGEMENT..."
			elif low and w.reserve > 0:
				_hint.text = "[R] RECHARGER"
			else:
				_hint.text = ""


class Crosshair extends Control:
	var spread := 10.0

	func _draw() -> void:
		var c := size * 0.5
		var col := Color(0.9, 0.9, 0.85, 0.75)
		var l := 7.0
		for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
			draw_line(c + d * spread, c + d * (spread + l), col, 2.0)
		draw_rect(Rect2(c - Vector2(1, 1), Vector2(2, 2)), col)


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
