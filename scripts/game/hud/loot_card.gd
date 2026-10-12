class_name LootCard
extends Control
## Fiche d'un BUTIN regardé (arme, pièce ou échantillon au sol) : petit
## panneau de verre au style du hub v2 (docs/hub_v2/README.md : verre
## sombre, liseré, coin biseauté, Chakra Petch / Barlow / JetBrains Mono),
## ancré à l'objet (à droite de sa projection à l'écran, donc près du
## réticule quand on le vise), bordé à gauche de la couleur de sa rareté.
##
## Arme : rareté et famille, nom, niveau (« NIV. 12 REQUIS » en rouge s'il
## dépasse celui du joueur), score et écart avec l'arme en main (vert /
## rouge), six statistiques en icône + valeur (comme la fiche de
## l'ARSENAL, Hub2ArsenalStat) avec l'écart à l'arme en main, touche
## INTERAGIR réelle (clavier ou manette) ; arme d'un coéquipier : « BUTIN
## DE ... ». Pièce : qualité, nom, niveau, modificateurs. Échantillon :
## rareté, nom, quantité de la partie.
##
## Données : weapon_info / part_info / sample_info (pures, tests/test_loot_fx.gd).
## LootSystem choisit l'objet regardé (pick) et appelle show_info / hide_card.

## Largeur et marges (px de la maquette 1280 × 720).
const W := 252.0
const PAD_X := 14.0
const PAD_Y := 12.0
const BAR := 3.0
const CHAMFER := 10.0
## Écart entre le point de l'objet à l'écran et la fiche.
const GAP := 34.0
const STAT_SQ := 22.0
const STAT_ICON := 13.0
const STAT_H := 30.0
const STAT_GAP := 8.0
## Fondu d'apparition (s).
const FADE := 0.12
const BG := Color(10 / 255.0, 11 / 255.0, 13 / 255.0, 0.82)

var info: Dictionary = {}
var anchor := Vector2.ZERO
var _shown := false
var _alpha := 0.0
var _key := ""
var _reach := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	modulate.a = 0.0


# --------------------------------------------------------------------------
# Données (pures)
# --------------------------------------------------------------------------

## Fiche d'une arme de partie `w`, comparée à l'arme en main `hand` (vide :
## aucune), pour un joueur de niveau `player_level` ; `owner_name` vide :
## c'est la sienne. `key` : nom de la touche INTERAGIR ; `bag_full`.
static func weapon_info(w: Dictionary, hand: Dictionary, player_level: int, owner_name := "", key := "F",
		bag_full := false) -> Dictionary:
	var id := String(w.get("id", ""))
	var r := GameWeapon.rarity_of(w)
	var lvl := GameWeapon.level_of(w)
	var too_high := lvl > player_level
	var score := GameWeapon.score(w)
	var out := {
		"kind": "weapon", "rarity": r, "color": LootFx.color(r),
		"eyebrow": "%s · %s" % [GameWeapon.rarity_name(r), Hub2ArsenalView.class_name_of(id)],
		"title": WeaponDB.display_name(id),
		"level": Hub2ArsenalView.required_text(lvl) if too_high else Hub2ArsenalView.level_text(lvl),
		"level_bad": too_high,
		"score": Lang.t("SCORE %s", "SCORE %s") % Hub2Style.num(score),
		"delta": "", "delta_good": true, "stats": [], "lines": [],
		"key": "" if owner_name != "" else key,
		"action": Lang.t("RAMASSER", "PICK UP") if owner_name == "" else Lang.t("BUTIN DE %s", "%s'S LOOT") % owner_name.to_upper(),
		"warn": Lang.t("INVENTAIRE PLEIN", "BACKPACK FULL") if bag_full and owner_name == "" else "",
	}
	if not hand.is_empty():
		var d := score - GameWeapon.score(hand)
		if d != 0:
			out.delta = ("▲ " if d > 0 else "▼ ") + Hub2Style.num(absi(d))
			out.delta_good = d > 0
	var s := GameWeapon.stats(w) if WeaponDB.exists(id) else {}
	var hs := GameWeapon.stats(hand) if not hand.is_empty() and WeaponDB.exists(String(hand.get("id", ""))) else {}
	for k in Hub2ArsenalView.STATS:
		var lbl: Array = Hub2ArsenalView.STAT_LABELS[k]
		var line := {"key": k, "label": Lang.t(lbl[0], lbl[1]), "icon": Hub2ArsenalView.ICONS[k], "value": "—", "mod": "", "good": true}
		if Hub2ArsenalView.has_stat(k, id, s):
			var v := Hub2ArsenalView.stat_number(k, s)
			line.value = Hub2ArsenalView.format_value(k, v)
			if Hub2ArsenalView.has_stat(k, String(hand.get("id", "")), hs):
				var dv := v - Hub2ArsenalView.stat_number(k, hs)
				line.mod = Hub2ArsenalView.format_mod(k, dv)
				line.good = Hub2ArsenalView.mod_good(k, dv)
		out.stats.append(line)
	return out


## Fiche d'une pièce (format LootRules.roll_part).
static func part_info(p: Dictionary) -> Dictionary:
	var wp := WeaponPart.create(String(p.get("id", "part")), int(p.get("level", 1)), p.get("mods", {}))
	var q := Hub2ArsenalView.part_quality(wp)
	var r := LootFx.part_rarity(p)
	var lines := []
	for e in Hub2ArsenalView.effects(wp):
		lines.append([String(e[0]), bool(e[1])])
	return {
		"kind": "part", "rarity": r, "color": LootFx.color(r),
		"eyebrow": "%s · %s" % [Lang.t("PIÈCE", "PART"), Hub2ArsenalView.quality_name(q)],
		"title": HubGear.part_name(wp).to_upper(), "level": Hub2ArsenalView.level_text(wp.level), "level_bad": false,
		"score": "", "delta": "", "delta_good": true, "stats": [], "lines": lines,
		"key": "", "action": Lang.t("PASSER DESSUS POUR RAMASSER", "WALK OVER TO PICK UP"), "warn": "",
	}


## Fiche d'un échantillon `id` ; `total` : quantité de la partie.
static func sample_info(id: String, total: int) -> Dictionary:
	var r := LootFx.sample_rarity(id)
	return {
		"kind": "sample", "rarity": r, "color": LootFx.color(r),
		"eyebrow": "%s · %s" % [Lang.t("ÉCHANTILLON", "SAMPLE"), GameWeapon.rarity_name(r)],
		"title": LootRules.sample_name(id), "level": "× 1", "level_bad": false,
		"score": Lang.t("DANS LE SAC : %d", "IN BAG: %d") % maxi(total, 1), "delta": "", "delta_good": true,
		"stats": [], "lines": [],
		"key": "", "action": Lang.t("PASSER DESSUS POUR RAMASSER", "WALK OVER TO PICK UP"), "warn": "",
	}


## Index de l'objet regardé parmi `points` (centres, m) depuis l'œil `eye`
## dans la direction `fwd` (unitaire) : le plus proche de l'axe du regard
## (écart au plus RADIUS + 3 % de la distance), devant, à moins de `max_d`
## m ; -1 : aucun. Pure.
const RADIUS := 0.4
static func pick(eye: Vector3, fwd: Vector3, points: Array, max_d: float) -> int:
	var best := -1
	var best_off := INF
	for i in points.size():
		var to: Vector3 = points[i] - eye
		var along := to.dot(fwd)
		if along <= 0.1 or to.length() > max_d:
			continue
		var off := (to - fwd * along).length()
		if off > RADIUS + along * 0.03:
			continue
		# Le plus proche de l'axe, à distance égale le plus près.
		var score := off + along * 0.02
		if score < best_off:
			best_off = score
			best = i
	return best


# --------------------------------------------------------------------------
# Affichage
# --------------------------------------------------------------------------

## Montre la fiche `data`, ancrée au point d'écran `at` ; `reach` : demi-
## taille de l'objet à l'écran (px), la fiche se pose au-delà.
func show_info(data: Dictionary, at: Vector2, reach := 0.0) -> void:
	_reach = clampf(reach, 0.0, 260.0)
	var key := "%s|%s|%s|%s|%s|%s" % [data.get("title", ""), data.get("level", ""), data.get("delta", ""),
		data.get("key", ""), data.get("warn", ""), Settings.language]
	if key != _key:
		_key = key
		info = data
		size = Vector2(Hub2Style.px(W), _height())
		queue_redraw()
	anchor = at
	_shown = true
	visible = true
	_place()


func hide_card() -> void:
	_shown = false


func shown() -> bool:
	return _shown and visible


func _process(delta: float) -> void:
	var target := 1.0 if _shown else 0.0
	_alpha = move_toward(_alpha, target, delta / FADE)
	modulate.a = _alpha
	if _alpha <= 0.0 and not _shown:
		visible = false
		_key = ""


func _place() -> void:
	var vp := get_viewport_rect().size
	var gap := _reach + Hub2Style.px(GAP)
	var p := anchor + Vector2(gap, -size.y * 0.5)
	# Bord droit : la fiche passe à gauche de l'objet.
	if p.x + size.x > vp.x - Hub2Style.px(16):
		p.x = anchor.x - gap - size.x
	p.y = clampf(p.y, Hub2Style.px(16), vp.y - size.y - Hub2Style.px(16))
	p.x = clampf(p.x, Hub2Style.px(16), maxf(vp.x - size.x - Hub2Style.px(16), Hub2Style.px(16)))
	# Glisse légèrement en apparaissant.
	position = (p + Vector2(Hub2Style.px(6) * (1.0 - _alpha), 0)).round()


func _row(family: String, weight: int, sz: float) -> float:
	return Hub2ArsenalDraw.line_h(family, weight, sz)


func _height() -> float:
	var h := Hub2Style.px(PAD_Y) * 2.0
	h += _row(Hub2Style.CHAKRA, 600, 10) + Hub2Style.px(2)
	h += _row(Hub2Style.CHAKRA, 700, 18) + Hub2Style.px(2)
	h += _row(Hub2Style.MONO, 700, 12)
	var stats: Array = info.get("stats", [])
	var lines: Array = info.get("lines", [])
	if not stats.is_empty():
		@warning_ignore("integer_division")
		var rows := (stats.size() + 1) / 2
		h += Hub2Style.px(10) * 2.0 + 1.0 + rows * Hub2Style.px(STAT_H) + (rows - 1) * Hub2Style.px(STAT_GAP)
	if not lines.is_empty():
		h += Hub2Style.px(10) + lines.size() * _row(Hub2Style.BARLOW, 600, 13)
	h += Hub2Style.px(10) * 2.0 + 1.0 + Hub2Style.px(Hub2Keycap.H)
	return ceilf(h)


func _draw() -> void:
	if info.is_empty():
		return
	var w := size.x
	var col: Color = info.get("color", Hub2Style.TEXT)
	var ch := Hub2Style.px(CHAMFER)
	# Verre sombre à coin biseauté (haut droit), liseré, barre de rareté.
	var poly := PackedVector2Array([Vector2(0, 0), Vector2(w - ch, 0), Vector2(w, ch), Vector2(w, size.y), Vector2(0, size.y)])
	draw_colored_polygon(poly, BG)
	var outline := poly.duplicate()
	outline.append(poly[0])
	draw_polyline(outline, Color(col, 0.35), 1.0)
	draw_rect(Rect2(0, 0, Hub2Style.px(BAR), size.y), col)
	# Lueur douce de la rareté en haut.
	draw_rect(Rect2(Hub2Style.px(BAR), 0, w - Hub2Style.px(BAR) - ch, 1.0), Color(col, 0.7))
	var x := Hub2Style.px(BAR) + Hub2Style.px(PAD_X) - Hub2Style.px(2)
	var iw := w - x - Hub2Style.px(PAD_X)
	var y := Hub2Style.px(PAD_Y)
	var lh := _row(Hub2Style.CHAKRA, 600, 10)
	Hub2ArsenalDraw.text(self, String(info.eyebrow), Hub2Style.CHAKRA, 600, 10, col, 0.14, x,
			Hub2ArsenalDraw.baseline(Hub2Style.CHAKRA, 600, 10, y, lh))
	y += lh + Hub2Style.px(2)
	lh = _row(Hub2Style.CHAKRA, 700, 18)
	Hub2ArsenalDraw.text(self, String(info.title), Hub2Style.CHAKRA, 700, 18, Hub2Style.TEXT, 0.02, x,
			Hub2ArsenalDraw.baseline(Hub2Style.CHAKRA, 700, 18, y, lh))
	y += lh + Hub2Style.px(2)
	lh = _row(Hub2Style.MONO, 700, 12)
	var base := Hub2ArsenalDraw.baseline(Hub2Style.MONO, 700, 12, y, lh)
	var lvl_col: Color = Hub2Style.BAD if info.get("level_bad", false) else Hub2Style.text_a(0.72)
	Hub2ArsenalDraw.text(self, String(info.level), Hub2Style.MONO, 700, 12, lvl_col, 0.0, x, base)
	var delta := String(info.get("delta", ""))
	var right := x + iw
	if delta != "":
		var dc: Color = Hub2ArsenalView.GOOD if info.get("delta_good", true) else Hub2ArsenalView.HARMFUL
		var dw := Hub2ArsenalDraw.text(self, delta, Hub2Style.MONO, 700, 12, dc, 0.0, x, base, iw, HORIZONTAL_ALIGNMENT_RIGHT)
		right -= dw + Hub2Style.px(8)
	if String(info.get("score", "")) != "":
		Hub2ArsenalDraw.text(self, String(info.score), Hub2Style.MONO, 700, 12, Hub2Style.TEXT, 0.0, x, base, right - x,
				HORIZONTAL_ALIGNMENT_RIGHT)
	y += lh
	var stats: Array = info.get("stats", [])
	if not stats.is_empty():
		y += Hub2Style.px(10)
		draw_rect(Rect2(x, y, iw, 1.0), Hub2Style.LINE)
		y += 1.0 + Hub2Style.px(10)
		var cw := (iw - Hub2Style.px(10)) * 0.5
		for i in stats.size():
			@warning_ignore("integer_division")
			var row := i / 2
			var cx := x + (i % 2) * (cw + Hub2Style.px(10))
			var cy := y + row * (Hub2Style.px(STAT_H) + Hub2Style.px(STAT_GAP))
			_draw_stat(stats[i], Rect2(cx, cy, cw, Hub2Style.px(STAT_H)))
		@warning_ignore("integer_division")
		var rows := (stats.size() + 1) / 2
		y += rows * Hub2Style.px(STAT_H) + (rows - 1) * Hub2Style.px(STAT_GAP)
	var lines: Array = info.get("lines", [])
	if not lines.is_empty():
		y += Hub2Style.px(10)
		lh = _row(Hub2Style.BARLOW, 600, 13)
		for l in lines:
			var lc: Color = Hub2ArsenalView.GOOD if l[1] else Hub2ArsenalView.HARMFUL
			Hub2ArsenalDraw.text(self, String(l[0]), Hub2Style.BARLOW, 600, 13, lc, 0.0, x,
					Hub2ArsenalDraw.baseline(Hub2Style.BARLOW, 600, 13, y, lh))
			y += lh
	# Pied : touche + action, avertissement à droite.
	y += Hub2Style.px(10)
	draw_rect(Rect2(x, y, iw, 1.0), Hub2Style.LINE)
	y += 1.0 + Hub2Style.px(10)
	var kh := Hub2Style.px(Hub2Keycap.H)
	var ax := x
	var key := String(info.get("key", ""))
	if key != "":
		var kw := Hub2Keycap.width_for(key)
		var sym := Hub2Input.ps_symbol(Settings.bindings_of("interact", true), Settings.using_pad)
		Hub2Keycap.draw_keycap(self, Rect2(x, y, Hub2Style.px(Hub2Keycap.MIN_W) if sym >= 0 else kw, kh), key, sym)
		ax += (Hub2Style.px(Hub2Keycap.MIN_W) if sym >= 0 else kw) + Hub2Style.px(8)
	var act_col: Color = info.get("action_color", Hub2Style.TEXT if key != "" else Hub2Style.text_a(0.55))
	Hub2ArsenalDraw.text(self, String(info.action), Hub2Style.CHAKRA, 600, 11, act_col, 0.12, ax,
			Hub2ArsenalDraw.baseline(Hub2Style.CHAKRA, 600, 11, y, kh))
	var warn := String(info.get("warn", ""))
	if warn != "":
		Hub2ArsenalDraw.text(self, warn, Hub2Style.CHAKRA, 600, 10, Hub2Style.BAD, 0.1, x,
				Hub2ArsenalDraw.baseline(Hub2Style.CHAKRA, 600, 10, y, kh), iw, HORIZONTAL_ALIGNMENT_RIGHT)


## Une statistique : carré d'icône, libellé au-dessus de la valeur et de
## l'écart à l'arme en main (style Hub2ArsenalStat, en plus compact).
func _draw_stat(line: Dictionary, r: Rect2) -> void:
	var sq := Hub2Style.px(STAT_SQ)
	var top := r.position.y + roundf((r.size.y - sq) * 0.5)
	draw_rect(Rect2(r.position.x, top, sq, sq), Hub2Style.white_a(0.06))
	var ic := Hub2Style.px(STAT_ICON)
	var tex := Hub2ArsenalDraw.svg_icon(String(line.get("icon", "")), ic, Hub2Style.TEXT)
	draw_texture_rect(tex, Rect2(r.position.x + roundf((sq - ic) * 0.5), top + roundf((sq - ic) * 0.5), ic, ic), false)
	var x := r.position.x + sq + Hub2Style.px(7)
	var lh := _row(Hub2Style.CHAKRA, 600, 9)
	var vh := _row(Hub2Style.MONO, 700, 13)
	var y := r.position.y + roundf((r.size.y - lh - vh) * 0.5)
	Hub2ArsenalDraw.text(self, String(line.get("label", "")), Hub2Style.CHAKRA, 600, 9, Hub2Style.text_a(0.5), 0.12, x,
			Hub2ArsenalDraw.baseline(Hub2Style.CHAKRA, 600, 9, y, lh))
	y += lh
	var base := Hub2ArsenalDraw.baseline(Hub2Style.MONO, 700, 13, y, vh)
	var vw := Hub2ArsenalDraw.text(self, String(line.get("value", "")), Hub2Style.MONO, 700, 13, Hub2Style.TEXT, 0.0, x, base)
	var mod := String(line.get("mod", ""))
	if mod != "":
		var mc: Color = Hub2ArsenalView.GOOD if line.get("good", true) else Hub2ArsenalView.HARMFUL
		Hub2ArsenalDraw.text(self, mod, Hub2Style.MONO, 700, 11, mc, 0.0, x + vw + Hub2Style.px(5), base)
