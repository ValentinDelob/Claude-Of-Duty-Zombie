class_name MapPanelsScale
extends RefCounted
## Onglet Propriétés de l'éditeur de cartes, sections ÉCHELLE et ROTATION
## d'un décor (format 14, docs/EDITOR_SCALE_ROTATE.md § 2.5, maquette
## docs/editor_scale_rotate_mockup, écrans 1 à 3) :
##   - Échelle : facteur uniforme et cadenas (fermé : les trois axes ensemble,
##     préférence de l'interface), X / Y / Z (lettres aux couleurs des axes),
##     dimensions finales et d'origine, bouton « ↺ ×1 » ; prefab qui contient
##     un objet de jeu : encadré d'avertissement qui le nomme, champs grisés ;
##   - Rotation : X / Y / Z en degrés (X, Y grisés pour ce qui ne s'incline
##     pas, raison en bulle), « Rester posé », « ↺ Remettre droit » ;
##   - Collision (solide, barrière ; pavés à l'échelle ou inclinés) ;
##   - Parties d'un prefab groupe (objets de jeu en tête, « taille fixe »).
## Un champ validé = une étape d'annulation ; valeur refusée remise, raison
## dans la barre d'état (MapScale.check).

const COL_FIELD := Color("121214")
const COL_FIELD_B := Color("4D4D54")
const COL_LIVE := Color("FFD94D")
const COL_FOCUS := Color("D99940")
const COL_BTN := Color("333338")
const COL_WARN_BG := Color("2e2412")
const COL_WARN := Color("FFD9A0")
const COL_WARN_B := Color("FFE7B8")
const COL_RULE := Color("38383D")
## Largeur du libellé d'une ligne : celle de la ligne Position (le panneau
## de l'éditeur est plus étroit que celui de la maquette : 104 px sur 340).
const KEY_W := 76.0
## Préférences de l'interface (_editeur.cfg) : cadenas de l'échelle, « Rester posé ».
const PREF_LOCK := "echelle_cadenas"
const PREF_REST := "rester_pose"
## Premiers mots (FR) des noms de décor féminins (« pavés inclinés avec elle »).
const _FEM_WORDS := ["pile", "poutre", "table", "chaise", "rangée", "étagère", "épave", "bobine", "flaque", "petite", "torche", "planches", "bûches"]


# ------------------------------------------------------------------ petits contrôles

## Titre de section : trait, puis le nom en petites capitales grises.
static func section(p: MapPanels, text: String) -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	var line := ColorRect.new()
	line.color = COL_RULE
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(line)
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", UiStyle.DIM)
	v.add_child(l)
	p._props.add_child(v)


## Ligne : libellé (104 px) puis le contenu.
static func row(p: MapPanels, key: String, content: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var l := Label.new()
	l.text = key
	l.custom_minimum_size = Vector2(KEY_W, 0)
	h.add_child(l)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(content)
	p._props.add_child(h)
	return h


static func _sb(bg: Color, border: Color, bw := 1, radius := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 5
	sb.content_margin_right = 4
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	return sb


## Champ (cadre sombre) : lettre d'axe facultative, texte ; `commit(texte)`
## à Entrée ou en quittant le champ. `live` : bord jaune (geste en cours).
static func field(axis: String, text: String, commit: Callable, disabled := false, live := false) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _sb(COL_FIELD, COL_LIVE if live else COL_FIELD_B))
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 3)
	pc.add_child(hb)
	if axis != "":
		var lab := Label.new()
		lab.text = axis
		lab.add_theme_color_override("font_color", MapView.axis_color(axis))
		lab.add_theme_font_override("font", MapView.bold_font())
		hb.add_child(lab)
	var e := LineEdit.new()
	e.flat = true
	e.text = text
	e.custom_minimum_size = Vector2(16, 0)
	e.add_theme_constant_override("minimum_character_width", 1)
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	e.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	e.add_theme_stylebox_override("read_only", StyleBoxEmpty.new())
	e.alignment = HORIZONTAL_ALIGNMENT_RIGHT if axis != "" else HORIZONTAL_ALIGNMENT_LEFT
	e.select_all_on_focus = true
	e.editable = not disabled
	e.set_meta("applied", text)
	if not disabled:
		var go := func(_t := ""):
			if e.text == String(e.get_meta("applied")):
				return
			var t := e.text
			e.text = String(e.get_meta("applied"))
			commit.call(t)
		e.text_submitted.connect(go)
		e.focus_exited.connect(go)
	hb.add_child(e)
	if disabled:
		pc.modulate = Color(1, 1, 1, 0.42)
	return pc


## Petit bouton de la maquette (« ↺ ×1 », « ↺ Remettre droit »).
static func small_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 13)
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := _sb(COL_BTN if st != "hover" else Color("4D4233"), COL_BTN, 0, 3)
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		b.add_theme_stylebox_override(st, sb)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.pressed.connect(cb)
	return b


## Cadenas dessiné (fermé ou ouvert), comme celui de la maquette.
class LockIcon extends Control:
	var closed := true
	var col := Color("FFD9A0")

	func _init() -> void:
		custom_minimum_size = Vector2(12, 14)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var s := minf(size.x / 12.0, size.y / 14.0)
		var o := (size - Vector2(12, 14) * s) * 0.5
		var arc_c := o + Vector2(6, 4.1) * s + (Vector2(3, 0) * s if not closed else Vector2.ZERO)
		draw_arc(arc_c, 3.0 * s, PI, TAU, 10, col, 1.5 * s, true)
		var leg_y := 6.5 if closed else 3.6
		draw_line(arc_c + Vector2(-3, 0) * s, arc_c + Vector2(-3, leg_y - 4.1 + 2.0) * s if closed else arc_c + Vector2(-3, 0.6) * s, col, 1.5 * s)
		draw_line(arc_c + Vector2(3, 0) * s, arc_c + Vector2(3, 2.4) * s, col, 1.5 * s)
		draw_rect(Rect2(o + Vector2(1, 6) * s, Vector2(10, 7.5) * s), col)
		draw_rect(Rect2(o + Vector2(5.3, 8.5) * s, Vector2(1.4, 2.6) * s), Color("1A1B1D"))


## Bouton cadenas (26 × 24) : fermé = doré, ouvert = gris ; grisé si `disabled`.
static func lock_button(closed: bool, disabled: bool, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(26, 24)
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	b.focus_mode = Control.FOCUS_NONE
	var bg := Color("262629") if disabled else (Color("3a2f22") if closed else COL_BTN)
	for st in ["normal", "hover", "pressed", "disabled"]:
		var sb := _sb(bg, COL_FOCUS if (closed and not disabled) else bg, 1, 3)
		b.add_theme_stylebox_override(st, sb)
	b.disabled = disabled
	b.tooltip_text = tip
	var ic := LockIcon.new()
	ic.closed = closed or disabled
	ic.col = Color("8C8575") if disabled else (Color("FFD9A0") if closed else Color("E0DBCC"))
	ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ic.offset_left = 7
	ic.offset_right = -7
	ic.offset_top = 5
	ic.offset_bottom = -5
	b.add_child(ic)
	if not disabled:
		b.pressed.connect(cb)
	return b


# ------------------------------------------------------------------ nombres

## Facteur affiché « ×1,50 ».
static func factor_text(v: float) -> String:
	return "×" + MapView.num(v, 2)


## Angle affiché : « 0° », « +30° », « −12,5° » (signe pour X et Y), Z de 0 à 359.
static func angle_text(v: float, signed := true) -> String:
	var r := snappedf(v, 0.1)
	var s := MapView.num(r, 0 if is_equal_approx(r, roundf(r)) else 1)
	if signed and r > 0.0:
		s = "+" + s
	return s + "°"


## Nombre tapé (« 1,5 », « ×1.5 », « x2 », « +30° ») ; NAN s'il est illisible.
static func parse(t: String) -> float:
	var s := t.strip_edges().replace(",", ".").replace("×", "").replace("°", "").replace("−", "-").replace(" ", "")
	if s.begins_with("x") or s.begins_with("X"):
		s = s.substr(1)
	if s.begins_with("+"):
		s = s.substr(1)
	return float(s) if s.is_valid_float() else NAN


## Longueur « 3,75 m » (cotes).
static func _m2(v: float) -> String:
	return MapView.num(v, 2) + " m"


static func _dims_text(d: Vector3) -> String:
	return "%s × %s × %s" % [MapView.num(d.x, 2), MapView.num(d.y, 2), MapView.num(d.z, 2)]


# ------------------------------------------------------------------ sections

## Sections Échelle, Rotation, Collision (et Parties d'un prefab groupe) du
## décor `o`, dans l'onglet Propriétés `p`.
static func build(p: MapPanels, o: Dictionary) -> void:
	var oid := String(o.id)
	p._scale_fields = {}
	_scale_section(p, o, oid)
	_rotation_section(p, o, oid)
	_collision_row(p, o)
	_parts_section(p, o)


static func _scale_section(p: MapPanels, o: Dictionary, oid: String) -> void:
	section(p, Lang.t("Échelle", "Scale"))
	var blockers := MapScale.blockers_of(o)
	var blocked := not blockers.is_empty()
	if blocked:
		var nt := MapScale.names_text(blockers)
		var w := PanelContainer.new()
		var sb := _sb(COL_WARN_BG, COL_FOCUS)
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		w.add_theme_stylebox_override("panel", sb)
		var rt := RichTextLabel.new()
		rt.bbcode_enabled = true
		rt.fit_content = true
		rt.scroll_active = false
		rt.add_theme_font_size_override("normal_font_size", 12)
		rt.add_theme_font_size_override("bold_font_size", 12)
		rt.add_theme_color_override("default_color", COL_WARN)
		var bold := func(x: String) -> String: return "[b][color=#%s]%s[/color][/b]" % [COL_WARN_B.to_html(false), x]
		# « il contient un Pack-a-Punch » : l'article, puis le nom en gras.
		var what := ""
		if blockers.size() == 1:
			var b0: Array = blockers[0]
			var art := Lang.t(String(b0[0]).trim_suffix(String(b0[2])), String(b0[1]).trim_suffix(String(b0[3])))
			what = art + bold.call(Lang.t(String(b0[2]), String(b0[3])))
		else:
			what = bold.call(Lang.t(nt[0], nt[1]))
		rt.text = Lang.t("%s il contient %s. Les objets de jeu (atouts, armes murales, boîte, Pack-a-Punch, portes, fenêtres…) gardent leur taille.",
			"%s it contains %s. Game objects (perks, wall weapons, box, Pack-a-Punch, doors, windows…) keep their size.") % [
			bold.call(Lang.t("⚠ Ce prefab ne peut pas changer d'échelle :", "⚠ This prefab cannot be scaled:")), what]
		rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		w.add_child(rt)
		p._props.add_child(w)
	var s := MapScale.scale_of(o)
	var forced := MapScale.uniform_only(o)
	var locked := forced or bool(MapEditor.pref(PREF_LOCK, true))
	var uni := HBoxContainer.new()
	uni.add_theme_constant_override("separation", 6)
	var u_text := factor_text(s.x) if MapScale.is_uniform(s) else "—"
	var uf := field("", u_text, func(t: String): _apply_uniform(p, oid, parse(t)), blocked)
	uni.add_child(uf)
	var tip := Lang.t("Cadenas fermé : les trois axes ensemble ; ouvert : par axe", "Closed lock: the three axes together; open: per axis")
	if forced:
		tip = Lang.t("Parties tournées en biais : échelle uniforme seulement", "Parts turned at an angle: uniform scale only")
	if blocked:
		tip = Lang.t("Échelle bloquée par : %s", "Scale blocked by: %s") % Lang.t(MapScale.names_text(blockers, true)[0], MapScale.names_text(blockers, true)[1])
	uni.add_child(lock_button(locked, blocked or forced, tip, func():
		MapEditor.set_pref(PREF_LOCK, not locked)
		p.refresh()))
	row(p, Lang.t("Uniforme", "Uniform"), uni)
	p._scale_fields["U"] = uf
	var xyz := HBoxContainer.new()
	xyz.add_theme_constant_override("separation", 4)
	for i in 3:
		var ax: String = ["X", "Y", "Z"][i]
		var f := field(ax, MapView.num(s[i], 2), func(t: String): _apply_axis(p, oid, i, parse(t)), blocked)
		xyz.add_child(f)
		p._scale_fields["S" + ax] = f
	row(p, "X · Y · Z", xyz)
	if blocked:
		return
	var d := MapScale.dims(o)
	var note := ""
	if MapScale.is_scaled(o):
		note = Lang.t("%s m (d'origine %s).", "%s m (originally %s).") % [_dims_text(d), _dims_text(MapScale.base_dims(o))]
	else:
		note = "%s m." % _dims_text(d)
	if MapScale.is_tilted(o):
		note += Lang.t(" Objet incliné : poignées de coin seulement dans les vues ; par axe ici.", " Tilted object: corner handles only in the views; per axis here.")
	else:
		note += Lang.t(" De 0,25 à 4 par axe.", " From 0.25 to 4 per axis.")
	p._scale_fields["note"] = p._note(p._props, note)
	if MapScale.is_scaled(o):
		var h := HBoxContainer.new()
		h.add_child(small_button("↺ ×1", func(): _apply(p, oid, func(c: Dictionary): MapScale.set_scale(c, Vector3.ONE))))
		row(p, "", h)


static func _rotation_section(p: MapPanels, o: Dictionary, oid: String) -> void:
	section(p, Lang.t("Rotation", "Rotation"))
	var mount := MapScale.mount_of(o)
	var tiltable := MapScale.tiltable(o)
	var why := MapScale.tilt_refusal(o)
	var inc := MapScale.incl_of(o)
	var xyz := HBoxContainer.new()
	xyz.add_theme_constant_override("separation", 4)
	for i in 2:
		var ax: String = ["X", "Y"][i]
		var f := field(ax, angle_text(inc[i]) if tiltable else "—", func(t: String): _apply_tilt(p, oid, i, parse(t)), not tiltable)
		if not why.is_empty():
			f.tooltip_text = Lang.t(why[0], why[1])
		xyz.add_child(f)
		p._scale_fields["R" + ax] = f
	var zf := field("Z", angle_text(float(MapGeom.rot_of(o)), false) if mount != "mur" else "—", func(t: String): _apply_yaw(p, oid, parse(t)), mount == "mur")
	zf.tooltip_text = Lang.t("Degrés, sens horaire vu de dessus (anneau : crans de 15°, Maj : au degré près ; R : 90°)",
		"Degrees, clockwise seen from above (ring: 15° steps, Shift: to the degree; R: 90°)")
	xyz.add_child(zf)
	p._scale_fields["RZ"] = zf
	row(p, "X · Y · Z", xyz)
	if tiltable:
		var h := HBoxContainer.new()
		var c := CheckBox.new()
		c.text = Lang.t("Rester posé", "Stay grounded")
		c.button_pressed = rest_on_support()
		c.tooltip_text = Lang.t("Coché : le point le plus bas reste sur son support ; décoché : le décor tourne autour du centre de sa boîte",
			"Checked: the lowest point stays on its support; unchecked: the prop turns around the centre of its box")
		c.toggled.connect(func(on): MapEditor.set_pref(PREF_REST, on))
		h.add_child(c)
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(sp)
		h.add_child(small_button(Lang.t("↺ Remettre droit", "↺ Set upright"), func(): _apply(p, oid, func(cand: Dictionary): set_tilt(cand, Vector2.ZERO))))
		# Toute la largeur (sans colonne de libellé) : la case et le bouton tiennent.
		p._props.add_child(h)
	var note := ""
	if not blockers_empty(o):
		note = Lang.t("Inclinaison X / Y : objet de jeu, reste droit. Rotation Z : le prefab tourne en entier autour de son centre.",
			"Tilt X / Y: game object, stays upright. Rotation Z: the whole prefab turns around its centre.")
	elif mount == "mur":
		note = Lang.t("Décor mural : il suit son mur (ni rotation ni inclinaison).", "Wall prop: it follows its wall (no rotation, no tilt).")
	elif mount == "plafond":
		note = Lang.t("Z : lacet, sens horaire vu de dessus. Un décor du plafond pend droit (pas d'inclinaison).",
			"Z: yaw, clockwise seen from above. A ceiling prop hangs straight (no tilt).")
	elif MapScale.is_tilted(o):
		var v := p.ed.raster().v
		var top := MapVertical.decor_z(o) + MapScale.height(o)
		var room := MapRules.room_at(p.ed.doc, int(o.get("etage", 0)), MapVertical.anchor_of(o))
		var fem := String(MapScale.label_of(o)[0]).get_slice(" ", 0).to_lower() in _FEM_WORDS
		note = Lang.t("Point le plus bas gardé sur %s : le haut %s monte à %s m", "Lowest point kept on %s: the top of %s rises to %s m") % [
			Lang.t("le sol" if MapVertical.decor_z(o) < 0.005 else "son support", "the floor" if MapVertical.decor_z(o) < 0.005 else "its support"),
			Lang.t(("de la " if fem else "du ") + String(MapScale.label_of(o)[0]).get_slice(" ", 0).to_lower(), "the " + String(MapScale.label_of(o)[1]).to_lower()),
			MapView.num(top, 2)]
		if not room.is_empty() and v != null:
			note += Lang.t(" (plafond de « %s » : %s m).", " (\"%s\" ceiling: %s m).") % [String(room.get("nom", "")), MapView.num(MapVertical.room_h(v, o), 2)]
		else:
			note += "."
	else:
		note = Lang.t("Z : lacet, sens horaire vu de dessus. X, Y : inclinaison (décor au sol) ; le point le plus bas reste sur son support.",
			"Z: yaw, clockwise seen from above. X, Y: tilt (floor props); the lowest point stays on its support.")
	p._scale_fields["rnote"] = p._note(p._props, note)


static func blockers_empty(o: Dictionary) -> bool:
	return MapScale.blockers_of(o).is_empty()


static func _collision_row(p: MapPanels, o: Dictionary) -> void:
	var block := MapCatalog.blocking(o)
	var txt := ""
	match block:
		"solide":
			txt = Lang.t("solide", "solid")
		"barriere":
			txt = Lang.t("barrière", "barrier")
		_:
			txt = Lang.t("aucune : on marche dessus", "none: can be walked over")
	if block != "non":
		if MapScale.is_tilted(o):
			var fem := String(MapScale.label_of(o)[0]).get_slice(" ", 0).to_lower() in _FEM_WORDS
			txt += Lang.t(" · pavés inclinés avec %s" % ("elle" if fem else "lui"), " · boxes tilted with it")
		elif MapScale.is_scaled(o):
			txt += Lang.t(" · pavés à l'échelle", " · scaled boxes")
		else:
			txt += Lang.t(" · pavés du décor", " · prop boxes")
	var f := field("", txt, func(_t): pass, true)
	f.modulate = Color(1, 1, 1, 1)
	var le := f.get_child(0).get_child(0) as LineEdit
	if le != null:
		le.add_theme_color_override("font_uneditable_color", UiStyle.DIM)
	f.tooltip_text = {"solide": Lang.t("Bloque joueurs, zombies et balles.", "Blocks players, zombies and bullets."),
		"barriere": Lang.t("Bloque joueurs et zombies ; les balles passent.", "Blocks players and zombies; bullets go through."),
		"non": Lang.t("Décor : on marche dessus (aucune collision).", "Decoration: can be walked over (no collision).")}[block]
	row(p, Lang.t("Collision", "Collision"), f)


## Parties d'un prefab groupe : objets non redimensionnables en tête
## (« taille fixe »), puis chaque décor et son nombre.
static func _parts_section(p: MapPanels, o: Dictionary) -> void:
	var d := MapScale.def_of(o)
	var parts: Array = d.get("parties", [])
	if parts.is_empty():
		return
	section(p, Lang.t("Parties (%d)", "Parts (%d)") % parts.size())
	var counts := {}
	var order := []
	for part in parts:
		var id := String(part.get("decor", part.get("type", "?")))
		if not counts.has(id):
			counts[id] = 0
			order.append(id)
		counts[id] += 1
	var fixed := func(id: String) -> bool: return not MapCatalog.PREFABS.has(id)
	order.sort_custom(func(a, b): return fixed.call(a) and not fixed.call(b))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	for id in order:
		var bad: bool = fixed.call(id)
		var it := MapCatalog.item("prefab:" + id) if not bad else MapCatalog.item(id)
		var pc := PanelContainer.new()
		var sb := _sb(COL_WARN_BG if bad else Color(0, 0, 0, 0), Color("2C2D31"), 0)
		sb.border_width_bottom = 1
		sb.content_margin_top = 3
		sb.content_margin_bottom = 3
		pc.add_theme_stylebox_override("panel", sb)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		var sw := ColorRect.new()
		sw.color = it.get("color", Color(0.6, 0.6, 0.6)) if not it.is_empty() else Color(0.6, 0.6, 0.6)
		sw.custom_minimum_size = Vector2(10, 10)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(sw)
		var nm := Label.new()
		nm.text = MapCatalog.name_of(it) if not it.is_empty() else id
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.add_theme_font_size_override("font_size", 13)
		if bad:
			nm.add_theme_color_override("font_color", COL_WARN_B)
		h.add_child(nm)
		if bad:
			var ic := LockIcon.new()
			ic.col = COL_WARN
			ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(ic)
		var st := Label.new()
		st.text = Lang.t("taille fixe", "fixed size") if bad else "× %d" % int(counts[id])
		st.add_theme_font_size_override("font_size", 13)
		st.add_theme_color_override("font_color", COL_WARN if bad else UiStyle.DIM)
		h.add_child(st)
		pc.add_child(h)
		box.add_child(pc)
	p._props.add_child(box)


# ------------------------------------------------------------------ application

## « Rester posé » (préférence de l'interface, coché par défaut).
static func rest_on_support() -> bool:
	return bool(MapEditor.pref(PREF_REST, true))


## Inclinaison `v` écrite dans `c` ; « Rester posé » décoché : la boîte tourne
## autour de son centre (« z », hauteur du point le plus bas, suit).
static func set_tilt(c: Dictionary, v: Vector2) -> void:
	var hz0 := MapScale.half_z(c)
	MapScale.set_incl(c, v)
	if not rest_on_support():
		var z := MapVertical.decor_z(c) + hz0 - MapScale.half_z(c)
		if z < 0.005:
			c.erase("z")
			if z < -0.011:
				c["_sous_sol"] = true
		else:
			c["z"] = snappedf(z, 0.01)


## Change l'élément `oid` par `mut(copie)` : vérifié (MapScale.check), une
## étape d'annulation s'il est accepté, sinon la raison dans la barre d'état.
static func _apply(p: MapPanels, oid: String, mut: Callable) -> void:
	var r := apply(p.ed, oid, mut)
	if not r.get("ok", false):
		p.ed.canvas.show_refusal(r)
	p.refresh()


## Même chose sans panneau (raccourcis, MCP, tests) : -> {ok} ou le refus.
static func apply(ed: MapEditor, oid: String, mut: Callable) -> Dictionary:
	var doc := ed.doc
	var o := doc.find(oid)
	if o.is_empty():
		return MapRules.refuse("élément introuvable", "element not found")
	var before := o.duplicate(true)
	var cand := o.duplicate(true)
	mut.call(cand)
	if cand.has("_sous_sol"):
		return MapRules.refuse("le décor traverserait le sol : cochez « Rester posé »", "the prop would go through the floor: tick \"Stay grounded\"")
	if cand == before:
		return {"ok": true}
	var res := MapScale.check(doc, ed.raster().v, cand, before)
	if not res.get("ok", false):
		return res
	var snap := doc.snapshot()
	MapTransform.replace(doc, cand)
	ed.push_undo_snapshot(snap)
	ed.changed()
	return {"ok": true}


static func _apply_uniform(p: MapPanels, oid: String, v: float) -> void:
	if is_nan(v):
		return
	_apply(p, oid, func(c: Dictionary):
		var s := MapScale.scale_of(c)
		if MapScale.is_uniform(s) or s.x <= 0.0:
			MapScale.set_scale(c, Vector3(v, v, v))
		else:
			MapScale.set_scale(c, Vector3(v, v, v)))


static func _apply_axis(p: MapPanels, oid: String, axis: int, v: float) -> void:
	if is_nan(v):
		return
	var locked := MapScale.uniform_only(p.ed.doc.find(oid)) or bool(MapEditor.pref(PREF_LOCK, true))
	_apply(p, oid, func(c: Dictionary):
		var s := MapScale.scale_of(c)
		if locked:
			# Cadenas fermé : les trois axes en proportion.
			var k := v / maxf(s[axis], 0.0001)
			MapScale.set_scale(c, s * k)
		else:
			s[axis] = v
			MapScale.set_scale(c, s))


static func _apply_tilt(p: MapPanels, oid: String, axis: int, v: float) -> void:
	if is_nan(v):
		return
	_apply(p, oid, func(c: Dictionary):
		var i := MapScale.incl_of(c)
		i[axis] = clampf(v, -MapScale.INCL_MAX, MapScale.INCL_MAX)
		set_tilt(c, i))


static func _apply_yaw(p: MapPanels, oid: String, v: float) -> void:
	if is_nan(v):
		return
	_apply(p, oid, func(c: Dictionary):
		var r := MapGeom.norm_deg(v)
		if r == 0:
			c.erase("rot")
		else:
			c["rot"] = r)


## Pendant un geste (poignée, anneau) : les champs suivent l'élément, bord jaune.
static func live(p: MapPanels, o: Dictionary, on: bool) -> void:
	if p._scale_fields.is_empty() or o.is_empty():
		return
	var s := MapScale.scale_of(o)
	var inc := MapScale.incl_of(o)
	var vals := {"U": factor_text(s.x) if MapScale.is_uniform(s) else "—", "SX": MapView.num(s.x, 2), "SY": MapView.num(s.y, 2), "SZ": MapView.num(s.z, 2),
		"RX": angle_text(inc.x), "RY": angle_text(inc.y), "RZ": angle_text(float(MapGeom.rot_of(o)), false)}
	for k in vals:
		var c: Variant = p._scale_fields.get(k)
		if not (c is PanelContainer and is_instance_valid(c)):
			continue
		var le := (c as PanelContainer).get_child(0).get_child((c as PanelContainer).get_child(0).get_child_count() - 1) as LineEdit
		if le == null or not le.editable:
			continue
		var changed := le.text != String(vals[k])
		if not le.has_focus():
			le.text = String(vals[k])
			le.set_meta("applied", le.text)
		var sb := (c as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat
		if sb != null:
			sb.border_color = COL_LIVE if (on and (changed or String(sb.get_meta("live", "")) == "1")) else COL_FIELD_B
			sb.set_meta("live", "1" if on and (changed or String(sb.get_meta("live", "")) == "1") else "0")
