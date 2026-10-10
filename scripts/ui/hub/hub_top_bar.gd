class_name HubTopBar
extends Control
## Barre du haut du hub (classe .top de la maquette, 52 px + 2 px de liseré) :
## pavé du niveau, nom du joueur et niveau, barre d'XP en cubes (XP dans le
## niveau / XP du niveau ; niveau maximum signalé), titre LABORATOIRE au
## pochoir, à droite la touche du menu du hub (Échap ou Start), cliquable.

const HEIGHT := 52.0

var player_name := ""
var level := 1
var xp_in := 0
var xp_need := 0
var max_level := false

signal menu_clicked

var _menu_rect := Rect2()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# 52 px de barre + 2 px de liseré gris (box-shadow 0 2px).
	custom_minimum_size = Vector2(0, HubStyle.px(HEIGHT) + HubStyle.px(2))
	Settings.input_device_changed.connect(func(_p): queue_redraw())


## Lit le niveau et l'XP d'un profil.
func show_profile(pr: PlayerProfile) -> void:
	player_name = Settings.player_name.to_upper()
	level = pr.level()
	max_level = pr.is_max_level()
	xp_in = pr.xp_in_level()
	xp_need = PlayerProfile.xp_to_next(level) if not max_level else 0
	queue_redraw()


## Texte à droite de la barre d'XP : « 2 140 / 3 320 XP ».
func xp_text() -> String:
	if max_level:
		return Lang.t("NIVEAU MAXIMUM", "MAX LEVEL")
	return "%s / %s XP" % [HubStyle.num(xp_in), HubStyle.num(xp_need)]


func _draw() -> void:
	var h := HubStyle.px(HEIGHT)
	var b := HubStyle.px(2)
	draw_rect(Rect2(0, 0, size.x, h), HubStyle.BAR_BG)
	draw_rect(Rect2(0, h - b, size.x, b), HubStyle.BLACK)
	draw_rect(Rect2(0, h, size.x, b), HubStyle.BAR_EDGE)
	var inner_h := h - b
	var x := HubStyle.px(16)
	# Pavé du niveau (.lvl : 38 px, biseau, ombre 3 px).
	var lv := HubStyle.px(38)
	var lr := Rect2(x, (inner_h - lv) * 0.5, lv, lv)
	HubStyle.draw_box(self, lr, HubStyle.YELLOW, b, HubStyle.px(3), HubStyle.YELLOW_HI, HubStyle.YELLOW_LO, HubStyle.px(3))
	var fi := HubStyle.font("impact")
	var ls := HubStyle.fs(22)
	var lt := str(level)
	draw_string(fi, Vector2(lr.position.x + (lv - HubStyle.text_width(lt, fi, ls)) * 0.5, HubStyle.baseline(fi, ls, lr.position.y, lv)),
			lt, HORIZONTAL_ALIGNMENT_LEFT, -1, ls, HubStyle.INK)
	x += lv + HubStyle.px(14)
	# Nom (Impact 17, espacé) + « NIVEAU 7 » (13, gris) ; dessous la barre d'XP.
	var ns := HubStyle.fs(17)
	var fn := HubStyle.font("impact", HubStyle.em(0.04, ns))
	var top := (inner_h - (HubStyle.px(21) + HubStyle.px(3) + HubStyle.px(16))) * 0.5
	var name_base := HubStyle.baseline(fn, ns, top - HubStyle.px(2), HubStyle.px(21))
	HubStyle.draw_text(self, fn, Vector2(x, name_base), player_name, ns, HubStyle.PAPER, true)
	var nw := HubStyle.text_width(player_name, fn, ns)
	var fu := HubStyle.font("ui")
	var ss := HubStyle.fs(13)
	var lvl_t := Lang.t("NIVEAU %d", "LEVEL %d") % level
	draw_string(fu, Vector2(x + nw + HubStyle.px(8), name_base), lvl_t, HORIZONTAL_ALIGNMENT_LEFT, -1, ss, HubStyle.DIM)
	var by := top + HubStyle.px(21) + HubStyle.px(3)
	var bar := Rect2(x, by + HubStyle.px(2), HubStyle.px(240), HubStyle.px(12))
	HubStyle.draw_bar(self, bar, 1.0 if max_level else (float(xp_in) / maxf(xp_need, 1.0)))
	var xt := xp_text()
	draw_string(fu, Vector2(bar.end.x + HubStyle.px(8), HubStyle.baseline(fu, ss, by, HubStyle.px(16))), xt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, ss, HubStyle.PLASTER)
	var who_end := maxf(x + nw + HubStyle.px(8) + HubStyle.text_width(lvl_t, fu, ss),
			bar.end.x + HubStyle.px(8) + HubStyle.text_width(xt, fu, ss))
	# Titre au pochoir.
	var bs := HubStyle.fs(20)
	var fb := HubStyle.font("stencil", HubStyle.em(0.06, bs))
	HubStyle.draw_text(self, fb, Vector2(who_end + HubStyle.px(14) + HubStyle.px(18), HubStyle.baseline(fb, bs, 0, inner_h)),
			Lang.t("LABORATOIRE", "LABORATORY"), bs, HubStyle.RED_HI, true)
	# À droite : touche du menu + « Menu ».
	var ms := HubStyle.fs(14)
	var mt := "Menu"
	var mw := HubStyle.text_width(mt, fu, ms)
	var kx := size.x - HubStyle.px(16) - mw - HubStyle.px(10)
	var kh := HubStyle.px(22)
	var ky := (inner_h - kh) * 0.5
	var kw: float
	if Settings.using_pad:
		kw = HubKey.item_width("", JOY_BUTTON_START)
		HubKey.draw_item(self, Vector2(kx - kw, ky), "", JOY_BUTTON_START)
	else:
		var k := Lang.t("Échap", "Esc")
		kw = HubKey.item_width(k, -1)
		HubKey.draw_item(self, Vector2(kx - kw, ky), k, -1)
	draw_string(fu, Vector2(kx + HubStyle.px(10) - HubStyle.px(6) + HubStyle.px(6), HubStyle.baseline(fu, ms, 0, inner_h)), mt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, ms, HubStyle.PLASTER)
	_menu_rect = Rect2(kx - kw, 0, kw + HubStyle.px(10) + mw + HubStyle.px(4), inner_h)


func _gui_input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if _menu_rect.has_point(mm.position) else Control.CURSOR_ARROW
		return
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and _menu_rect.has_point(mb.position):
		accept_event()
		menu_clicked.emit()
