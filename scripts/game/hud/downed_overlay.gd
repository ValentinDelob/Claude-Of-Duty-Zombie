class_name DownedOverlay
extends Control
## Affichage « À TERRE » du joueur local et barres de réanimation.
##
##   PLAYER DOWN
##   Réanimation : ████████░░░░
##   Temps restant : 12s

var game: Game
var _title: Label
var _revive: Label
var _time: Label
var _tint: ColorRect
var _assist: Label


func setup(g: Game) -> void:
	game = g
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tint = ColorRect.new()
	_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tint.color = Color(0.35, 0.0, 0.0, 0.0)
	_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tint)
	var box := VBoxContainer.new()
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.offset_left = -350
	box.offset_right = 350
	box.offset_top = 110
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_title = UiStyle.label("", 56, UiStyle.BLOOD_BRIGHT, "title")
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_revive = UiStyle.label("", 26, UiStyle.BONE, "mono")
	_revive.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_revive)
	_time = UiStyle.label("", 24, UiStyle.BONE)
	_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_time)
	_assist = UiStyle.label("", 22, UiStyle.BONE, "mono")
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


func _process(_delta: float) -> void:
	if game == null or game.local_player == null:
		return
	var me := multiplayer.get_unique_id()
	var d := game.downed
	if d.is_downed(me):
		_title.text = "À TERRE"
		var rp := d.revive_progress(me)
		var solo := Net.mode == Net.Mode.SOLO
		if rp > 0.0:
			_revive.text = "Réanimation : " + bar(rp)
		else:
			_revive.text = "Réanimation : " + bar(0.0) if not solo else ""
		_time.text = "Temps restant : %ds" % int(ceil(d.bleed_left(me)))
		_tint.color.a = lerpf(_tint.color.a, 0.35, 0.1)
	else:
		_title.text = ""
		_revive.text = ""
		_time.text = ""
		_tint.color.a = lerpf(_tint.color.a, 0.0, 0.1)
	# Je réanime quelqu'un : barre de progression au centre.
	_assist.text = ""
	for pid in d.downed:
		if d.reviver_of(pid) == me:
			_assist.text = "Réanimation de %s : %s" % [Net.player_name(pid), bar(d.revive_progress(pid))]
