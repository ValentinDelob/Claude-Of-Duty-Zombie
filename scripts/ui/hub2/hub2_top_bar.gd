class_name Hub2TopBar
extends Control
## Barre du haut du hub v2 (TopBar.dc.html), 72 px : verre rgba(8, 9, 11,
## 0.72) flou 16 px, liseré bas 1 px rgba(255, 255, 255, 0.08) ; padding
## 0 28 px, écart 24 px entre les trois blocs :
##  - joueur (230 px) : pavé du niveau 40 × 40 biseauté 8 px (fond jaune 12 %,
##    liseré jaune, JetBrains Mono 17 px 700), nom (Chakra Petch 16 px 600,
##    0.04em) et XP (JetBrains Mono 11 px, 60 %) sur une ligne de base, barre
##    d'XP de 3 px (fond blanc 12 %, jaune) 6 px dessous ;
##  - onglets centrés (écart 4 px) entre « LB » et « RB » (JetBrains Mono 11 px
##    700, 45 %, à 10 px) : Chakra Petch 16 px, 0.08em, majuscules, padding
##    0 16 px ; actif 700 #F2F0EA, sinon 500 58 % ; pastille jaune 6 × 6 à
##    6 px, montée de 7 px ; actif : soulignement jaune de 2 px en bas ;
##  - bouton JOUER (START en anglais) 168 × 44 biseauté 12 px, jaune (blanc
##    #F2F0EA sur l'écran JOUER), Chakra Petch 18 px 700, 0.14em, #0B0B0C.
## Onglets et bouton se cliquent (`tab_clicked`, `play_clicked`) ; les
## indications LB / RB suivent le périphérique (Q / E au clavier).

const H := Hub2Style.TOP_BAR_H
const PROFILE_W := 230.0
const GAP := 24.0
const LVL := 40.0
const LVL_CHAMFER := 8.0
const PLAY_W := 168.0
const PLAY_H := 44.0
const PLAY_CHAMFER := 12.0
const TAB_PAD := 16.0
const TAB_GAP := 4.0
const HINT_PAD := 10.0
const TAB_SIZE := 16.0
const TAB_TRACKING := 0.08
const DOT := 6.0
const DOT_GAP := 6.0
const DOT_RISE := 7.0
const UNDERLINE := 2.0

## Onglets : [{id, label}] ; `current` : onglet actif ("" : aucun, écran
## JOUER) ; `play_active` : bouton JOUER en blanc (écran JOUER).
var tabs: Array = []
var current := ""
var play_active := false
var badges: Dictionary = {}  # id -> bool

var player_name := ""
var level := 1
var xp_in := 0
var xp_need := 0
var max_level := false

signal tab_clicked(id: String)
signal play_clicked

var bg: Hub2Box
var level_box: Hub2Box
var level_text: Hub2Text
var play_box: Hub2Box
var play_text: Hub2Text
var _fg: Control
## Rectangles des onglets (coordonnées de la barre) : id -> Rect2.
var tab_rects: Dictionary = {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	bg = Hub2Box.new()
	bg.glass(Hub2Style.TOP_BAR_BG, Hub2Style.LINE, 1.0, Hub2Style.BLUR_TOP_BAR)
	bg.border = Vector4(0, 0, 0, 1)
	add_child(bg)
	level_box = Hub2Box.new()
	level_box.flat(Hub2Style.YELLOW_TINT, Hub2Style.YELLOW, 1.0)
	level_box.chamfer(LVL_CHAMFER)
	add_child(level_box)
	level_text = Hub2Text.new()
	level_text.setup("1", Hub2Style.MONO, 700, 17, Hub2Style.YELLOW)
	level_text.align = HORIZONTAL_ALIGNMENT_CENTER
	add_child(level_text)
	_fg = Control.new()
	_fg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fg.draw.connect(_draw_fg)
	add_child(_fg)
	play_box = Hub2Box.new()
	play_box.flat(Hub2Style.YELLOW)
	play_box.chamfer(PLAY_CHAMFER)
	add_child(play_box)
	play_text = Hub2Text.new()
	play_text.setup(Lang.t("JOUER", "START"), Hub2Style.CHAKRA, 700, 18, Hub2Style.INK, 0.14)
	play_text.align = HORIZONTAL_ALIGNMENT_CENTER
	add_child(play_text)
	resized.connect(_layout)


func _ready() -> void:
	custom_minimum_size = Vector2(0, Hub2Style.px(H))
	Settings.input_device_changed.connect(_on_device)
	_layout()


func _exit_tree() -> void:
	if Settings.input_device_changed.is_connected(_on_device):
		Settings.input_device_changed.disconnect(_on_device)


func _on_device(_pad: bool) -> void:
	_fg.queue_redraw()


## Lit le niveau et l'XP d'un profil (nom : Settings.player_name).
func show_profile(pr: PlayerProfile) -> void:
	player_name = Settings.player_name if Settings.player_name != "" else Lang.t("Joueur", "Player")
	level = pr.level()
	max_level = pr.is_max_level()
	xp_in = pr.xp_in_level()
	xp_need = PlayerProfile.xp_to_next(level) if not max_level else 0
	level_text.text = str(level)
	_fg.queue_redraw()


## Texte de l'XP : « 8 420 / 13 100 » ; niveau maximum : « MAX ».
func xp_text() -> String:
	if max_level:
		return "MAX"
	return "%s / %s" % [Hub2Style.num(xp_in), Hub2Style.num(xp_need)]


func xp_ratio() -> float:
	if max_level:
		return 1.0
	return clampf(float(xp_in) / maxf(1.0, float(xp_need)), 0.0, 1.0)


## Onglets (identifiant, libellé déjà traduit) dans l'ordre.
func set_tabs(list: Array) -> void:
	tabs = list
	_layout()


## Onglet actif ("" : aucun) et bouton JOUER actif (écran JOUER).
func set_current(id: String, on_play := false) -> void:
	current = id
	play_active = on_play
	play_box.fill = Hub2Style.TEXT if on_play else Hub2Style.YELLOW
	_layout()


func set_badge(id: String, on: bool) -> void:
	badges[id] = on
	_fg.queue_redraw()


func _tab_font(id: String) -> Font:
	return Hub2Style.font(Hub2Style.CHAKRA, 700 if id == current else 500)


## Largeur d'un onglet (padding, libellé, pastille).
func tab_width(id: String, label: String) -> float:
	var s := Hub2Style.fs(TAB_SIZE)
	var w := Hub2Style.px(TAB_PAD) * 2.0 + Hub2Style.text_width(label, _tab_font(id), s, Hub2Style.tracking_px(TAB_TRACKING, s))
	if badges.get(id, false):
		w += Hub2Style.px(DOT_GAP) + Hub2Style.px(DOT)
	return w


func _hint_w(t: String) -> float:
	var f := Hub2Style.font(Hub2Style.MONO, 700)
	return Hub2Style.text_width(t, f, Hub2Style.fs(11)) + Hub2Style.px(HINT_PAD)


## Contenu centré verticalement dans la boîte de contenu (72 − 1 px de
## liseré : align-items: center du <header>).
func _center_y() -> float:
	return (Hub2Style.px(H) - Hub2Style.px(1)) * 0.5


func _layout() -> void:
	if bg == null:
		return
	var h := Hub2Style.px(H)
	bg.position = Vector2.ZERO
	bg.size = Vector2(size.x, h)
	var side := Hub2Style.px(Hub2Style.SIDE)
	var cy := _center_y()
	var lv := Hub2Style.px(LVL)
	level_box.position = Vector2(side, roundf(cy - lv * 0.5))
	level_box.size = Vector2(lv, lv)
	level_text.position = level_box.position
	level_text.size = level_box.size
	var pw := Hub2Style.px(PLAY_W)
	var ph := Hub2Style.px(PLAY_H)
	play_box.position = Vector2(size.x - side - pw, roundf(cy - ph * 0.5))
	play_box.size = Vector2(pw, ph)
	play_text.position = play_box.position
	play_text.size = play_box.size
	play_text.text = Lang.t("JOUER", "START")
	# Onglets : centrés dans la zone entre le joueur et JOUER.
	tab_rects.clear()
	var x0 := side + Hub2Style.px(PROFILE_W) + Hub2Style.px(GAP)
	var x1 := size.x - side - pw - Hub2Style.px(GAP)
	var gap := Hub2Style.px(TAB_GAP)
	var total := _hint_w(Hub2Input.tab_hint(-1)) + _hint_w(Hub2Input.tab_hint(1))
	for t in tabs:
		total += tab_width(t.id, t.label)
	total += gap * (tabs.size() + 1)  # LB, n onglets, RB : n + 1 écarts
	var x := x0 + maxf(0.0, (x1 - x0 - total) * 0.5)
	x += _hint_w(Hub2Input.tab_hint(-1)) + gap
	for t in tabs:
		var w := tab_width(t.id, t.label)
		tab_rects[t.id] = Rect2(x, 0, w, h)
		x += w + gap
	_fg.position = Vector2.ZERO
	_fg.size = Vector2(size.x, h)
	_fg.queue_redraw()


func _draw_fg() -> void:
	var h := Hub2Style.px(H)
	var side := Hub2Style.px(Hub2Style.SIDE)
	var cy := _center_y()
	# --- Joueur : nom, XP, barre.
	var cx := side + Hub2Style.px(LVL) + Hub2Style.px(12)
	var cw := Hub2Style.px(PROFILE_W) - Hub2Style.px(LVL) - Hub2Style.px(12)
	var nf := Hub2Style.font(Hub2Style.CHAKRA, 600)
	var ns := Hub2Style.fs(16)
	var xf := Hub2Style.font(Hub2Style.MONO, 400)
	var xs := Hub2Style.fs(11)
	var row_h := Hub2Style.line_height(nf, ns)
	var bar_h := Hub2Style.px(3)
	var col_h := row_h + Hub2Style.px(6) + bar_h
	var top := roundf(cy - col_h * 0.5)
	var base := Hub2Style.baseline(nf, ns, top, row_h)
	var name_room := cw - Hub2Style.text_width(xp_text(), xf, xs) - Hub2Style.px(8)
	Hub2Style.draw_text(_fg, nf, Vector2(cx, base), Hub2Prompts.ellipsis(player_name, nf, ns, name_room), ns,
			Hub2Style.TEXT, Hub2Style.tracking_px(0.04, ns))
	var xt := xp_text()
	var xw := Hub2Style.text_width(xt, xf, xs)
	Hub2Style.draw_text(_fg, xf, Vector2(cx + cw - xw, base), xt, xs, Hub2Style.text_a(0.6))
	var by := top + row_h + Hub2Style.px(6)
	_fg.draw_rect(Rect2(cx, by, cw, bar_h), Hub2Style.white_a(0.12))
	_fg.draw_rect(Rect2(cx, by, roundf(cw * xp_ratio()), bar_h), Hub2Style.YELLOW)
	# --- Indications LB / RB.
	var hf := Hub2Style.font(Hub2Style.MONO, 700)
	var hs := Hub2Style.fs(11)
	var hb := Hub2Style.baseline(hf, hs, 0.0, h)
	if not tabs.is_empty():
		var first: Rect2 = tab_rects[tabs[0].id]
		var last: Rect2 = tab_rects[tabs[tabs.size() - 1].id]
		var lt := Hub2Input.tab_hint(-1)
		var gap := Hub2Style.px(TAB_GAP)
		var lx := first.position.x - gap - _hint_w(lt)
		Hub2Style.draw_text(_fg, hf, Vector2(lx, hb), lt, hs, Hub2Style.text_a(0.45))
		Hub2Style.draw_text(_fg, hf, Vector2(last.end.x + gap + Hub2Style.px(HINT_PAD), hb), Hub2Input.tab_hint(1), hs,
				Hub2Style.text_a(0.45))
	# --- Onglets.
	var ts := Hub2Style.fs(TAB_SIZE)
	var ttrack := Hub2Style.tracking_px(TAB_TRACKING, ts)
	for t in tabs:
		var r: Rect2 = tab_rects[t.id]
		var on: bool = t.id == current
		var f := _tab_font(t.id)
		var x := r.position.x + Hub2Style.px(TAB_PAD)
		var tb := Hub2Style.baseline(f, ts, 0.0, h)
		var tw := Hub2Style.draw_text(_fg, f, Vector2(x, tb), String(t.label), ts,
				Hub2Style.TEXT if on else Hub2Style.text_a(0.58), ttrack)
		if badges.get(t.id, false):
			var d := Hub2Style.px(DOT)
			var dy := roundf(h * 0.5 - d * 0.5 - Hub2Style.px(DOT_RISE))
			_fg.draw_rect(Rect2(x + tw + Hub2Style.px(DOT_GAP), dy, d, d), Hub2Style.YELLOW)
		if on:
			var u := Hub2Style.px(UNDERLINE)
			_fg.draw_rect(Rect2(r.position.x + Hub2Style.px(TAB_PAD), h - u,
					r.size.x - Hub2Style.px(TAB_PAD) * 2.0, u), Hub2Style.YELLOW)


## Identifiant de l'onglet sous `p` ("" : aucun).
func tab_at(p: Vector2) -> String:
	for id in tab_rects:
		if (tab_rects[id] as Rect2).has_point(p):
			return id
	return ""


func play_rect() -> Rect2:
	return Rect2(play_box.position, play_box.size)


func _gui_input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm:
		var over := tab_at(mm.position) != "" or play_box._has_point(mm.position - play_box.position)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if over else Control.CURSOR_ARROW
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		var id := tab_at(mb.position)
		if id != "":
			accept_event()
			tab_clicked.emit(id)
		elif play_box._has_point(mb.position - play_box.position):
			accept_event()
			play_clicked.emit()
