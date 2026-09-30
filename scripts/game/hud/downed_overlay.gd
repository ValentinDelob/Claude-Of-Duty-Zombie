class_name DownedOverlay
extends Control
## État « À TERRE » du joueur local, façon BO1 : vision floue, délavée, bords
## rouges qui pulsent (downed_blur.gdshader, sous le reste du HUD), texte
## discret et barres de réanimation.
##
##   À TERRE
##   Réanimation : ████████░░░░
##   Temps restant : 12s

const BLUR := preload("res://assets/shaders/downed_blur.gdshader")

var game: Game
var _title: Label
var _revive: Label
var _time: Label
## Flou plein écran : ajouté par le HUD tout en dessous des autres éléments.
var blur: ColorRect
var _blur_mat: ShaderMaterial
var _amount := 0.0
var _beat := 0.0
var _assist: Label


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
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_title = HudStyle.label("", 44, HudStyle.CHALK, "title", 6)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_revive = HudStyle.label("", 22, HudStyle.TEXT, "text", 3)
	_revive.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_revive)
	_time = HudStyle.label("", 20, HudStyle.TEXT_DIM, "text", 3)
	_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_time)
	_assist = HudStyle.label("", 22, HudStyle.TEXT, "text", 3)
	_assist.anchor_left = 0.5
	_assist.anchor_right = 0.5
	_assist.anchor_top = 0.5
	_assist.anchor_bottom = 0.5
	_assist.offset_left = -400
	_assist.offset_right = 400
	_assist.offset_top = 150
	_assist.offset_bottom = 190
	_assist.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_assist)


static func bar(progress: float, width := 12) -> String:
	var n := int(round(clampf(progress, 0.0, 1.0) * width))
	return "█".repeat(n) + "░".repeat(width - n)


## Intensité courante de la vision « à terre » (0 : normale).
func amount() -> float:
	return _amount


func _process(delta: float) -> void:
	if game == null or game.local_player == null:
		return
	var me := multiplayer.get_unique_id()
	var d := game.downed
	var target := 0.0
	var over := GameState.state == GameState.State.GAME_OVER
	if d.is_downed(me) and over:
		# Fin de partie : la vision reste floue, les textes laissent la place.
		target = 1.0
		_title.text = ""
		_revive.text = ""
		_time.text = ""
	elif d.is_downed(me):
		target = 1.0
		_title.text = Lang.t("À TERRE", "DOWNED")
		var rp := d.revive_progress(me)
		var solo := Net.mode == Net.Mode.SOLO
		# Solo avec LAZARUS TONIC : la barre se remplit pendant qu'on se relève
		# seul (BO1), au lieu d'un compte à rebours de saignement trompeur.
		var sp := d.self_revive_progress(me)
		var reviving := Lang.t("Réanimation : ", "Reviving: ")
		if sp > 0.0:
			_revive.text = reviving + bar(sp)
		elif rp > 0.0:
			_revive.text = reviving + bar(rp)
		else:
			_revive.text = reviving + bar(0.0) if not solo else ""
		var left := d.bleed_left(me)
		_time.text = "" if sp > 0.0 else Lang.t("Temps restant : %ds", "Time left: %ds") % int(ceil(left))
		# Cœur de plus en plus rapide, rouge de plus en plus présent.
		var bleed := 1.0 - clampf(left / DownedSystem.BLEEDOUT_TIME, 0.0, 1.0)
		_beat += delta * (1.1 + bleed * 1.2)
		_blur_mat.set_shader_parameter("bleed", bleed)
		_blur_mat.set_shader_parameter("pulse", absf(sin(_beat * PI)))
		_title.modulate.a = 0.75 + 0.25 * absf(sin(_beat * PI))
	else:
		_title.text = ""
		_revive.text = ""
		_time.text = ""
	_amount = move_toward(_amount, target, delta * (1.4 if target > _amount else 2.5))
	blur.visible = _amount > 0.001
	_blur_mat.set_shader_parameter("amount", _amount)
	# Je réanime quelqu'un : barre de progression au centre.
	_assist.text = ""
	for pid in d.downed:
		if d.reviver_of(pid) == me:
			_assist.text = Lang.t("Réanimation de %s : %s", "Reviving %s: %s") % [Net.player_name(pid), bar(d.revive_progress(pid))]
