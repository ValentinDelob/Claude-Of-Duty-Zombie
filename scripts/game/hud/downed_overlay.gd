class_name DownedOverlay
extends Control
## État « À TERRE » du joueur local, façon BO1 : vision floue, bords rouges
## qui pulsent (downed_blur.gdshader, sous le reste du HUD) et couleurs qui
## s'éteignent avec le saignement : l'écran est en noir et blanc complet à la
## mort (aucun compte à rebours affiché). Barre de réanimation fine sous le
## titre, pendant qu'on est réanimé.
##
##   À TERRE
##   RÉANIMATION
##   ━━━━━━━━━━━━━━━━──────────

const BLUR := preload("res://assets/shaders/downed_blur.gdshader")

var game: Game
var _title: Label
## Ma réanimation (par un coéquipier, ou LAZARUS en solo).
var _revive: ReviveBar
## Flou plein écran : ajouté par le HUD tout en dessous des autres éléments.
var blur: ColorRect
var _blur_mat: ShaderMaterial
var _amount := 0.0
var _gray := 0.0
var _beat := 0.0
## Je réanime quelqu'un : barre au centre de l'écran.
var _assist: ReviveBar


func setup(g: Game) -> void:
	game = g
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	blur = ColorRect.new()
	blur.set_anchors_preset(Control.PRESET_FULL_RECT)
	blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blur_mat = ShaderMaterial.new()
	_blur_mat.shader = BLUR
	blur.material = _blur_mat
	blur.visible = false
	var box := VBoxContainer.new()
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.offset_left = -350
	box.offset_right = 350
	box.offset_top = 96
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_title = HudStyle.label("", 44, HudStyle.CHALK, "title", 6)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_revive = ReviveBar.new()
	_revive.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_revive)
	_assist = ReviveBar.new()
	_assist.anchor_left = 0.5
	_assist.anchor_right = 0.5
	_assist.anchor_top = 0.5
	_assist.anchor_bottom = 0.5
	_assist.offset_left = -ReviveBar.WIDTH * 0.5
	_assist.offset_right = ReviveBar.WIDTH * 0.5
	_assist.offset_top = 140
	_assist.offset_bottom = 140 + ReviveBar.HEIGHT
	add_child(_assist)


## Intensité courante de la vision « à terre » (0 : normale).
func amount() -> float:
	return _amount


## Part de noir et blanc de la vision (1 : saignement terminé).
func grayness() -> float:
	return _gray


func _process(delta: float) -> void:
	if game == null or game.local_player == null:
		return
	var me := multiplayer.get_unique_id()
	var d := game.downed
	var target := 0.0
	var over := GameState.state == GameState.State.GAME_OVER
	var revive_caption := ""
	var revive_progress := 0.0
	if d.is_downed(me) and over:
		# Fin de partie : la vision reste floue, les textes laissent la place.
		target = 1.0
		_title.text = ""
	elif d.is_downed(me):
		target = 1.0
		_title.text = Lang.t("À TERRE", "DOWNED")
		# Solo avec LAZARUS TONIC : la barre se remplit pendant qu'on se relève
		# seul (BO1) ; sinon pendant qu'un coéquipier nous réanime.
		var sp := d.self_revive_progress(me)
		var rp := sp if sp > 0.0 else d.revive_progress(me)
		if rp > 0.0:
			revive_caption = Lang.t("RÉANIMATION", "REVIVING")
			revive_progress = rp
		# Les couleurs s'éteignent avec le saignement (sauf auto-réanimation :
		# on ne va pas mourir).
		var bleed := d.bleed_fraction(me)
		_gray = 0.0 if sp > 0.0 else bleed
		# Cœur de plus en plus rapide, rouge de plus en plus présent.
		_beat += delta * (1.1 + bleed * 1.2)
		_blur_mat.set_shader_parameter("bleed", bleed)
		_blur_mat.set_shader_parameter("pulse", absf(sin(_beat * PI)))
		_title.modulate.a = 0.75 + 0.25 * absf(sin(_beat * PI))
	else:
		_title.text = ""
	_revive.show_progress(revive_caption, revive_progress)
	_amount = move_toward(_amount, target, delta * (1.4 if target > _amount else 2.5))
	if _amount <= 0.001:
		_gray = 0.0
	blur.visible = _amount > 0.001
	_blur_mat.set_shader_parameter("amount", _amount)
	_blur_mat.set_shader_parameter("gray", _gray)
	# Je réanime quelqu'un : barre de progression au centre.
	var assist_caption := ""
	var assist_progress := 0.0
	for pid in d.downed:
		if d.reviver_of(pid) == me:
			assist_caption = Lang.t("RÉANIMATION DE %s", "REVIVING %s") % Net.player_name(pid).to_upper()
			assist_progress = d.revive_progress(pid)
	_assist.show_progress(assist_caption, assist_progress)


## Barre de réanimation : légende espacée, rail sombre fin, remplissage
## blanc cassé avec reflet et pointe lumineuse. Apparaît et disparaît en
## fondu ; le remplissage suit la progression en douceur.
class ReviveBar extends Control:
	const WIDTH := 300.0
	const HEIGHT := 34.0
	const BAR_H := 6.0
	const FADE_SPEED := 6.0

	## Progression visée (0..1) et légende ; vide = barre masquée.
	var progress := 0.0
	var caption := ""
	var _shown := 0.0
	var _alpha := 0.0
	var _font: Font

	func _init() -> void:
		custom_minimum_size = Vector2(WIDTH, HEIGHT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fv := FontVariation.new()
		fv.base_font = HudStyle.font("text")
		fv.spacing_glyph = 3
		_font = fv
		modulate.a = 0.0
		visible = false

	func show_progress(text: String, p: float) -> void:
		if text != "":
			caption = text
			# Réanimation reprise de zéro : la barre repart de zéro aussi.
			if p < _shown - 0.05:
				_shown = p
			progress = clampf(p, 0.0, 1.0)
		var want := 1.0 if text != "" else 0.0
		var delta := get_process_delta_time()
		_alpha = move_toward(_alpha, want, delta * FADE_SPEED)
		visible = _alpha > 0.001
		modulate.a = _alpha
		if want == 0.0 and not visible:
			progress = 0.0
			_shown = 0.0
		_shown = lerpf(_shown, progress, 1.0 - exp(-delta * 18.0))
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		# Légende : petites capitales espacées, centrées.
		var fs := 15
		var tw := _font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var base := Vector2((w - tw) * 0.5, 14.0)
		draw_string_outline(_font, base, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.55))
		draw_string(_font, base, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, HudStyle.TEXT)
		# Rail : fond sombre translucide, liseré clair discret.
		var y := HEIGHT - BAR_H - 6.0
		var rail := Rect2(0, y, w, BAR_H)
		draw_rect(rail.grow(2.0), Color(0, 0, 0, 0.55))
		draw_rect(rail.grow(2.0), Color(HudStyle.CHALK, 0.22), false, 1.0)
		draw_rect(rail, Color(1, 1, 1, 0.06))
		# Graduations au quart.
		for i in range(1, 4):
			var x := w * i / 4.0
			draw_line(Vector2(x, y), Vector2(x, y + BAR_H), Color(1, 1, 1, 0.12), 1.0)
		var fw := w * clampf(_shown, 0.0, 1.0)
		if fw < 1.0:
			return
		# Remplissage : blanc cassé, reflet en haut, ombre en bas.
		draw_rect(Rect2(0, y, fw, BAR_H), HudStyle.CHALK)
		draw_rect(Rect2(0, y, fw, BAR_H * 0.4), Color(1, 1, 1, 0.35))
		draw_rect(Rect2(0, y + BAR_H * 0.7, fw, BAR_H * 0.3), Color(0, 0, 0, 0.18))
		# Pointe lumineuse au bout du remplissage.
		var tip := Vector2(fw, y + BAR_H * 0.5)
		for k in 4:
			draw_circle(tip, BAR_H * (2.2 - k * 0.45), Color(1, 0.97, 0.9, 0.07 + k * 0.05))
		draw_rect(Rect2(fw - 2.0, y - 1.0, 2.0, BAR_H + 2.0), Color(1, 1, 1, 0.95))
