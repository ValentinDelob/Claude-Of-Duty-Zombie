class_name EvacVotePanel
extends Control
## Cadre de vote d'évacuation (maquette validée docs/hub_v2/Evacuation.dc.html,
## GAME_CONCEPT §4.5), à gauche de l'écran pendant la fenêtre d'évacuation :
## verre compact (left 24 px, top 150 px, 300 px de large, liseré turquoise de
## 3 px à gauche) ; « ÉVACUATION » et le temps restant m:ss, barre turquoise
## qui se vide ; une ligne par joueur (carré à sa couleur, nom, « (toi) » pour
## le joueur local sur une ligne éclaircie, son choix en face : CONTINUER en
## jaune, ÉVACUER en turquoise, EN ATTENTE en gris = pas encore voté) ; en bas
## les deux choix avec leurs vraies touches (F1 / F2, croix gauche / droite à
## la manette, réaffectables : Settings.action_label) et le choix du joueur
## local allumé.
##
## Suit Game.evac à chaque image (ouverte, temps, votes reçus de l'hôte) ; le
## vote lui-même passe par PlayerInput.vote. Tailles de la maquette passées par
## Hub2Style.px / fs (taille des menus).

## Maquette (px) : position et largeur du contenu, liserés.
const LEFT := 24.0
const TOP := 150.0
const WIDTH := 300.0
const BORDER_LEFT := 3.0
const BORDER := 1.0
const FILL := Color(10 / 255.0, 11 / 255.0, 13 / 255.0, 0.72)
const BLUR := 10.0
## rgba(242, 240, 234, 0.5) : EN ATTENTE ; 0.75 : choix éteint.
const WAIT_ALPHA := 0.5
const OFF_ALPHA := 0.75

var game: Game
var _box: Hub2Box
var _ink: Control
## Modèle affiché (describe) : refait à chaque image où le cadre est visible.
var _rows: Array = []
var _clock := ""
var _frac := 1.0
var _mine := EvacRules.Vote.NONE
var _can_vote := false


func setup(g: Game) -> void:
	game = g
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	_box = Hub2Box.new()
	_box.glass(FILL, Hub2Style.white_a(0.1), BORDER, BLUR)
	# Liseré gauche turquoise de 3 px dessiné par-dessus (_draw_content).
	_box.border = Vector4(0, BORDER, BORDER, BORDER)
	add_child(_box)
	_ink = Control.new()
	_ink.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ink.draw.connect(_draw_content)
	add_child(_ink)
	visible = false


## Couleur d'un vote : CONTINUER jaune #F5C542, ÉVACUER turquoise #4FE3C1,
## EN ATTENTE gris.
static func vote_color(v: int) -> Color:
	match v:
		EvacRules.Vote.READY:
			return Hub2Style.YELLOW
		EvacRules.Vote.LEAVE:
			return Hub2Style.TEAL
	return Hub2Style.text_a(WAIT_ALPHA)


## Nom affiché d'une ligne : « Valentin (toi) » pour le joueur local.
static func row_name(player_name: String, me: bool) -> String:
	return player_name + Lang.t(" (toi)", " (you)") if me else player_name


func _process(_delta: float) -> void:
	var door: EvacDoor = game.evac if game else null
	var show := door != null and door.is_open and GameState.is_in_game() \
			and GameState.state != GameState.State.GAME_OVER
	if visible != show:
		visible = show
	if not show:
		return
	var life := {}
	for pid in game.session.data:
		life[pid] = (game.session.data[pid] as PlayerData).life
	var me := multiplayer.get_unique_id()
	_rows = EvacRules.vote_rows(door.votes, life, me, Net.sorted_peer_ids())
	_clock = EvacRules.clock_text(door.time_left)
	_frac = clampf(door.time_left / EvacRules.DURATION, 0.0, 1.0)
	_mine = door.local_vote()
	_can_vote = door.local_can_vote()
	_layout()
	_ink.queue_redraw()


## État affiché (tests) : {visible, clock, rows: [{name, vote, text, me}],
## keys: [CONTINUER, ÉVACUER], mine}.
func describe() -> Dictionary:
	var rows := []
	for r in _rows:
		rows.append({"name": row_name(Net.player_name(r.pid), r.me), "vote": r.vote,
			"text": EvacRules.vote_text(r.vote), "me": r.me})
	return {"visible": visible, "clock": _clock, "rows": rows, "mine": _mine,
		"keys": [Settings.action_label("vote_continue"), Settings.action_label("vote_evacuate")] if _can_vote else []}


# --- Mise en page (maquette) --------------------------------------------------

func _f(fam: String, w: int) -> Font:
	return Hub2Style.font(fam, w)


func _lh(fam: String, w: int, size: float) -> float:
	return Hub2Style.line_height(_f(fam, w), Hub2Style.fs(size))


## Hauteurs de la maquette : en-tête, ligne de joueur, bouton de choix.
func _header_metrics() -> Vector2:
	var tf := _f(Hub2Style.CHAKRA, 700)
	var cf := _f(Hub2Style.MONO, 700)
	var asc := maxf(tf.get_ascent(Hub2Style.fs(15)), cf.get_ascent(Hub2Style.fs(20)))
	var desc := maxf(tf.get_descent(Hub2Style.fs(15)), cf.get_descent(Hub2Style.fs(20)))
	return Vector2(asc, desc)


func _row_h() -> float:
	return Hub2Style.px(7) * 2.0 + maxf(maxf(_lh(Hub2Style.CHAKRA, 600, 14), _lh(Hub2Style.CHAKRA, 700, 12)), Hub2Style.px(8))


func _button_h() -> float:
	return Hub2Style.px(4) * 2.0 + maxf(Hub2Style.px(20), _lh(Hub2Style.CHAKRA, 700, 12))


func _layout() -> void:
	var hm := _header_metrics()
	var h := Hub2Style.px(BORDER) + Hub2Style.px(12) + hm.x + hm.y + Hub2Style.px(8) \
			+ Hub2Style.px(2) + Hub2Style.px(6) \
			+ Hub2Style.px(4) * 2.0 + _row_h() * _rows.size()
	if _can_vote:
		h += Hub2Style.px(1) + Hub2Style.px(8) + _button_h() * 2.0 + Hub2Style.px(4) + Hub2Style.px(12)
	h += Hub2Style.px(BORDER)
	var w := Hub2Style.px(BORDER_LEFT) + Hub2Style.px(WIDTH) + Hub2Style.px(BORDER)
	position = Hub2Style.pxv(LEFT, TOP)
	var sz := Vector2(w, h)
	if size != sz:
		size = sz
		_box.size = sz
		_ink.size = sz


func _draw_content() -> void:
	var ci := _ink
	var x0 := Hub2Style.px(BORDER_LEFT)
	var cw := Hub2Style.px(WIDTH)
	var pad := Hub2Style.px(14)
	# Liseré gauche turquoise (border-left: 3px solid #4FE3C1).
	ci.draw_rect(Rect2(0, 0, x0, size.y), Hub2Style.TEAL)
	# En-tête : ÉVACUATION (Chakra 15 / 700 / .14em) et temps (Mono 20 / 700),
	# alignés sur la ligne de base.
	var hm := _header_metrics()
	var y := Hub2Style.px(BORDER) + Hub2Style.px(12)
	var base := y + hm.x
	var tf := _f(Hub2Style.CHAKRA, 700)
	var ts := Hub2Style.fs(15)
	Hub2Style.draw_text(ci, tf, Vector2(x0 + pad, base), Lang.t("ÉVACUATION", "EVACUATION"), ts,
			Hub2Style.TEXT, Hub2Style.tracking_px(0.14, ts))
	var cf := _f(Hub2Style.MONO, 700)
	var cs := Hub2Style.fs(20)
	var clw := Hub2Style.text_width(_clock, cf, cs)
	Hub2Style.draw_text(ci, cf, Vector2(x0 + cw - pad - clw, base), _clock, cs, Hub2Style.TEXT)
	y += hm.x + hm.y + Hub2Style.px(8)
	# Barre de temps : 2 px, fond blanc 0.1, turquoise qui se vide.
	var bw := cw - pad * 2.0
	var bh := Hub2Style.px(2)
	ci.draw_rect(Rect2(x0 + pad, y, bw, bh), Hub2Style.white_a(0.1))
	ci.draw_rect(Rect2(x0 + pad, y, roundf(bw * _frac), bh), Hub2Style.TEAL)
	y += bh + Hub2Style.px(6) + Hub2Style.px(4)
	# Joueurs.
	var nf := _f(Hub2Style.CHAKRA, 600)
	var ns := Hub2Style.fs(14)
	var vf := _f(Hub2Style.CHAKRA, 700)
	var vs := Hub2Style.fs(12)
	var vt := Hub2Style.tracking_px(0.12, vs)
	var rh := _row_h()
	var sq := Hub2Style.px(8)
	var gap := Hub2Style.px(10)
	for r in _rows:
		if r.me:
			ci.draw_rect(Rect2(x0, y, cw, rh), Hub2Style.white_a(0.05))
		var slot := Net.player_slot(r.pid)
		ci.draw_rect(Rect2(x0 + pad, y + roundf((rh - sq) * 0.5), sq, sq), HudStyle.player_color(slot))
		var vtext := EvacRules.vote_text(r.vote)
		var vw := Hub2Style.text_width(vtext, vf, vs, vt)
		var vx := x0 + cw - pad - vw
		Hub2Style.draw_text(ci, vf, Vector2(vx, Hub2Style.baseline(vf, vs, y, rh)), vtext, vs, vote_color(r.vote), vt)
		var nx := x0 + pad + sq + gap
		var name := _fit(row_name(Net.player_name(r.pid), r.me), nf, ns, vx - gap - nx)
		Hub2Style.draw_text(ci, nf, Vector2(nx, Hub2Style.baseline(nf, ns, y, rh)), name, ns, Hub2Style.TEXT)
		y += rh
	y += Hub2Style.px(4)
	if not _can_vote:
		return
	# Choix : séparateur, puis CONTINUER et ÉVACUER avec leurs touches.
	ci.draw_rect(Rect2(x0, y, cw, Hub2Style.px(1)), Hub2Style.white_a(0.08))
	y += Hub2Style.px(1) + Hub2Style.px(8)
	var bh2 := _button_h()
	var choices := [["vote_continue", EvacRules.Vote.READY], ["vote_evacuate", EvacRules.Vote.LEAVE]]
	for c in choices:
		var on: bool = _mine == c[1]
		var col := vote_color(c[1])
		var bx := x0 + pad
		if on:
			ci.draw_rect(Rect2(bx, y, bw, bh2), Hub2Style.white_a(0.07))
			ci.draw_rect(Rect2(bx, y, Hub2Style.px(2), bh2), col)
		var kx := bx + Hub2Style.px(2) + Hub2Style.px(6)
		var kw := _draw_key(ci, c[0], kx, y + roundf((bh2 - Hub2Style.px(20)) * 0.5))
		var label := EvacRules.vote_text(c[1])
		Hub2Style.draw_text(ci, vf, Vector2(kx + kw + gap, Hub2Style.baseline(vf, vs, y, bh2)), label, vs,
				col if on else Hub2Style.text_a(OFF_ALPHA), vt)
		y += bh2 + Hub2Style.px(4)


## Touche de `action` (<kbd> de la maquette : 20 px de haut, 26 px de large au
## moins, padding 0 5 px, JetBrains Mono 10 / 700 #0B0B0C sur pavé clair) ;
## bouton de face PlayStation en symbole. Rend la largeur.
func _draw_key(ci: CanvasItem, action: String, x: float, y: float) -> float:
	var h := Hub2Style.px(20)
	var sym := _ps_symbol(action)
	var t := Settings.action_label(action)
	var f := _f(Hub2Style.MONO, 700)
	var s := Hub2Style.fs(10)
	var w := Hub2Style.px(26) if sym >= 0 else maxf(Hub2Style.px(26), ceilf(Hub2Style.text_width(t, f, s) + Hub2Style.px(5) * 2.0))
	var r := Rect2(x, y, w, h)
	ci.draw_rect(r, Hub2Style.KEYCAP_BG)
	if sym >= 0:
		Hub2Keycap._draw_symbol(ci, r, sym)
	else:
		Hub2Style.draw_text(ci, f, Vector2(x + roundf((w - Hub2Style.text_width(t, f, s)) * 0.5),
				Hub2Style.baseline(f, s, y, h)), t, s, Hub2Style.INK)
	return w


## Bouton de face PlayStation de la touche affichée de `action` (-1 : texte).
func _ps_symbol(action: String) -> int:
	if not Settings.using_pad:
		return -1
	var ev := Settings.event_from_code(Settings.binding(action, true))
	if ev is InputEventJoypadButton:
		return Hub2Input.ps_symbol([(ev as InputEventJoypadButton).button_index], true)
	return -1


## `t` coupé (…) pour tenir dans `w` px.
static func _fit(t: String, f: Font, s: int, w: float) -> String:
	if Hub2Style.text_width(t, f, s) <= w:
		return t
	var out := t
	while out.length() > 1 and Hub2Style.text_width(out + "…", f, s) > w:
		out = out.left(out.length() - 1)
	return out + "…"
