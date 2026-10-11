class_name HubPlayView
extends RefCounted
## Morceaux communs de l'onglet PARTIE (docs/HUB_PLAN.md §3.7, maquette
## écrans 9 et 10) : cartes jouables, faits d'une carte pour l'aperçu
## (vagues spéciales et de boss, porte d'évacuation, échantillons), lignes
## « VOUS PARTEZ AVEC » et « CONTRATS ACTIFS », ligne de carte cliquable,
## champ de saisie et aperçu encadré.

## Faits des cartes déjà calculés : identifiant -> Dictionary (map_facts).
static var _facts: Dictionary = {}


# --------------------------------------------------------------------------
# Cartes
# --------------------------------------------------------------------------

## Cartes jouables : cartes du jeu (Game.MENU_MAPS) puis cartes perso jouables
## de l'éditeur (user://maps) ; [{id, def, custom}].
static func playable_maps() -> Array:
	var out := []
	for id in Game.MENU_MAPS:
		var def: MapDef = _cached_def(id, 0)
		if def != null:
			out.append({"id": id, "def": def, "custom": false})
	for m in EditorMap.list_maps():
		var cid := EditorMapDef.CUSTOM_PREFIX + String(m.id)
		var cdef := _cached_def(cid, _stamp(String(m.dir))) as EditorMapDef
		if cdef != null and cdef.is_valid():
			out.append({"id": cid, "def": cdef, "custom": true})
	return out


## Définitions déjà lues : identifiant -> [date des fichiers, MapDef] (une
## carte perso n'est relue et contrôlée que si l'un de ses fichiers a changé :
## le hub se reconstruit souvent, la lecture d'une carte perso est lente).
static var _defs: Dictionary = {}


static func _cached_def(id: String, stamp: int) -> MapDef:
	var c: Array = _defs.get(id, [])
	if not c.is_empty() and int(c[0]) == stamp:
		return c[1]
	var def := MapPreview.map_def(id)
	if def != null:  # carte partagée pas encore reçue : relue plus tard
		_defs[id] = [stamp, def]
	return def


## Définition d'une carte (dernière lue par playable_maps si elle existe).
static func def_of(id: String) -> MapDef:
	var c: Array = _defs.get(id, [])
	if not c.is_empty():
		return c[1]
	return _cached_def(id, 0)


## Date de modification la plus récente des fichiers d'un dossier de carte.
static func _stamp(dir: String) -> int:
	var t := 0
	for f in DirAccess.get_files_at(dir):
		t = maxi(t, FileAccess.get_modified_time(dir.path_join(f)))
	return t


## Nom affiché d'une carte (carte perso : nettoyé, jamais du BBCode).
static func map_name(def: MapDef) -> String:
	return CustomMapGuard.clean_display(def.display_name) if def else "..."


## Faits d'une carte pour l'aperçu (calculés une fois par carte) :
## {special: {premiere, intervalle}, boss: types de boss ([] : aucun), boss_waves,
## evac: "start" (accessible dès le départ) / "door" (derrière une porte) /
## "none", samples: sortes d'échantillons qu'on y trouve}.
static func map_facts(id: String, def: MapDef) -> Dictionary:
	if def == null:
		return {"special": {"premiere": 0, "intervalle": 0}, "boss": [], "boss_waves": {}, "evac": "none", "samples": []}
	var key := "%s|%s|%d" % [id, def.display_name, def.get_instance_id()]
	if _facts.has(key):
		return _facts[key]
	var sched := WaveRules.parse(def.waves)
	var sp: Dictionary = sched[WaveRules.SPECIAL]
	var samples := []
	if int(sp.premiere) > 0:
		# Seule vague spéciale du jeu aujourd'hui : la meute de chiens.
		for s in LootRules.SAMPLES.get("dogs", []):
			samples.append(String(s[0]))
	# Boss de la carte (format 22 : types en rotation) et ses échantillons.
	var boss_names := []
	if WaveRules.has_boss(sched):
		for t in WaveRules.boss_types(sched):
			boss_names.append(String(t))
			if t == WaveRules.CHIRURGIEN:
				for s in LootRules.SAMPLES.get("surgeon", []):
					samples.append(String(s[0]))
	var evac := "none"
	var layout := def.create_layout()
	if layout != null:
		var door := layout.evac_door()
		if door != null:
			evac = "start"
			var spawns := layout.player_spawns()
			if not spawns.is_empty() and door.zone != "" and door.zone != layout.zone_at(spawns[0]):
				evac = "door"
	var f := {"special": sp, "boss": boss_names, "boss_waves": sched[WaveRules.BOSS], "evac": evac, "samples": samples}
	_facts[key] = f
	return f


## Rythme d'un type de vague {premiere, intervalle} : « toutes les 5 manches »,
## « à la manche 10 », « dès la manche 3, toutes les 5 manches » ; "" : jamais.
static func rhythm_text(e: Dictionary) -> String:
	var first := int(e.get("premiere", 0))
	var gap := int(e.get("intervalle", 0))
	if first <= 0:
		return ""
	if gap <= 0:
		return Lang.t("à la manche %d", "at round %d") % first
	if first == gap:
		return Lang.t("toutes les %d manches", "every %d rounds") % gap
	return Lang.t("dès la manche %d, toutes les %d manches", "from round %d, every %d rounds") % [first, gap]


## « Vagues spéciales : [b]meute de chiens[/b], toutes les 5 manches » (BBCode).
static func special_line(f: Dictionary) -> String:
	var r := rhythm_text(f.special)
	if r == "":
		return Lang.t("Vagues spéciales : [b]aucune[/b]", "Special waves: [b]none[/b]")
	return Lang.t("Vagues spéciales : [b]meute de chiens[/b], %s", "Special waves: [b]dog pack[/b], %s") % r


## Nom affiché d'un type de boss (WaveRules.BOSS_TYPES).
static func boss_name(t: String) -> String:
	match t:
		WaveRules.CHIRURGIEN:
			return Lang.t("le Chirurgien", "the Surgeon")
	return t


static func boss_line(f: Dictionary) -> String:
	var r := rhythm_text(f.boss_waves)
	var types: Array = f.boss if f.get("boss") is Array else []
	if types.is_empty() or r == "":
		return Lang.t("Vagues de boss : [b]aucune[/b]", "Boss waves: [b]none[/b]")
	var names := PackedStringArray()
	for t in types:
		names.append(boss_name(String(t)))
	return Lang.t("Vagues de boss : [b]%s[/b], %s", "Boss waves: [b]%s[/b], %s") % [HubSamplesColumn.esc(", ".join(names)), r]


static func evac_line(f: Dictionary) -> String:
	match String(f.evac):
		"start":
			return Lang.t("Porte d'évacuation : [b]oui[/b], accessible dès le départ", "Evacuation door: [b]yes[/b], reachable from the start")
		"door":
			return Lang.t("Porte d'évacuation : [b]oui[/b], derrière une porte", "Evacuation door: [b]yes[/b], behind a door")
	return Lang.t("Porte d'évacuation : [b]aucune[/b] (pas d'évacuation possible)", "Evacuation door: [b]none[/b] (no evacuation)")


## Mot court d'une sorte d'échantillon (« croc », « touffe » ; EN « fang »).
static func sample_word(kind: String) -> String:
	var w: Array = HubSamplesColumn.WORDS.get(kind, [])
	if w.is_empty():
		return LootRules.sample_name(kind).to_lower()
	return w[2] if Lang.is_en() else w[0]


## Texte court de la ligne d'une carte : « chiens » / « sans vague spéciale ».
static func list_note(f: Dictionary) -> String:
	if int((f.special as Dictionary).get("premiere", 0)) > 0:
		return Lang.t("chiens", "dogs")
	return Lang.t("sans vague spéciale", "no special wave")


## Coop (salon) : « Meute de chiens toutes les 5 manches ».
static func lobby_waves_line(f: Dictionary) -> String:
	var r := rhythm_text(f.special)
	if r == "":
		return Lang.t("Aucune vague spéciale", "No special wave")
	return Lang.t("Meute de chiens %s", "Dog pack %s") % r


# --------------------------------------------------------------------------
# Lignes communes
# --------------------------------------------------------------------------

## Icône en pixel art d'une arme de départ (famille, batte : HubGear).
static func weapon_art(id: String) -> String:
	return HubGear.weapon_art(id)


## Nom d'une arme de départ en casse de phrase (« Pétoire », « Batte »).
static func weapon_label(id: String) -> String:
	var n := HubGear.weapon_name(id)
	if n.to_upper() == n and n.length() > 1 and not n.left(1).is_valid_int():
		var has_digit := false
		for ch in n:
			if ch.is_valid_int():
				has_digit = true
		if not has_digit:
			return HubLabPanel.sentence_case(n)
	return n


## Ligne « VOUS PARTEZ AVEC » : armes de départ du profil (icône et nom), puis
## MODIFIER (ouvre l'onglet DÉPART). Rend [ligne, bouton].
static func loadout_row(pr: PlayerProfile, panel: HubPanel) -> Array:
	var row := HubRow.new()
	var first := true
	for id in pr.starting_weapons:
		if not first:
			row.box.add_child(HubBox.gap(4, 0))
		first = false
		var ic := HubIcon.make(weapon_art(String(id)), 2)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.box.add_child(ic)
		var l := HubStyle.label(weapon_label(String(id)), 15, HubStyle.PAPER)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.box.add_child(l)
	row.box.add_child(HubBox.spring(false))
	var b := panel.hub_button(Lang.t("MODIFIER", "CHANGE"), func():
		if panel.hub:
			panel.hub.select_tab("loadout"), HubButton.NORMAL,
		Lang.t("Choisir ses armes de départ (onglet DÉPART).", "Choose your starting weapons (LOADOUT tab)."))
	b.height = 28
	b.font_size = 13
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.box.add_child(b)
	return [row, b]


## Texte de ce qui manque à un contrat : « encore 1 touffe », « encore 2
## crocs, 1 collier » (EN « 1 tuft of fur to go ») ; `days` >= 0 : « · 12 j ».
static func missing_line(pr: PlayerProfile, samples: Dictionary, days := -1) -> String:
	var items := PackedStringArray()
	for k in samples:
		var miss := int(samples[k]) - pr.sample_count(String(k))
		if miss > 0:
			items.append(HubSamplesColumn.words(String(k), miss))
	var t := Lang.t("encore %s", "%s to go") % ", ".join(items)
	if days >= 0:
		t += Lang.t(" · %d j", " · %d d") % days
	return t


## Lignes des contrats actifs (« CONTRATS ACTIFS ») ; `facts` : carte choisie
## (« sur cette carte » quand elle donne un échantillon qui manque), {} : sans
## cette mention (salon, écran 10). Au moins une ligne.
static func contract_rows(pr: PlayerProfile, facts: Dictionary) -> Array:
	var out := []
	var act := HubContractsView.active(pr)
	if act.is_empty():
		var r := HubRow.new()
		var l := HubStyle.label(Lang.t("Aucun contrat actif", "No active contract"), 15, HubStyle.DIM)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		r.box.add_child(l)
		r.box.add_child(HubBox.spring(false))
		var s := HubStyle.label(Lang.t("le scientifique en propose dans CONTRATS", "the scientist offers some in CONTRACTS"), 13, HubStyle.DIM)
		s.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		r.box.add_child(s)
		out.append(r)
		return out
	for i in act.size():
		var c: Dictionary = act[i]
		var r := HubRow.new()
		r.alt = i % 2 == 1
		var name := HubStyle.label(String(c.title), 15, HubStyle.PAPER)
		name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		r.box.add_child(name)
		if c.ready:
			r.box.add_child(HubTag.make(Lang.t("PRÊT", "READY"), HubTag.READY))
		else:
			var m := HubStyle.label(missing_line(pr, c.samples, int(c.days)), 13, HubStyle.DIM)
			m.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			r.box.add_child(m)
		r.box.add_child(HubBox.spring(false))
		var right := ""
		var col := HubStyle.DIM
		if c.ready:
			right = Lang.t("à remettre au labo", "hand it in at the lab")
		elif not facts.is_empty():
			var here := false
			for k in c.samples:
				if pr.sample_count(String(k)) < int(c.samples[k]) and String(k) in facts.samples:
					here = true
			right = Lang.t("sur cette carte", "on this map") if here else Lang.t("pas sur cette carte", "not on this map")
			col = HubStyle.YELLOW if here else HubStyle.DIM
		if right != "":
			var rl := HubStyle.label(right, 13, col)
			rl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			r.box.add_child(rl)
		out.append(r)
	return out


## Pastille d'un échantillon qu'on trouve sur la carte (.need : icône et mot).
static func sample_chip(kind: String) -> MarginContainer:
	var m := MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var b := HubStyle.px(2)
	m.add_theme_constant_override("margin_left", int(HubStyle.px(3) + b))
	m.add_theme_constant_override("margin_right", int(HubStyle.px(7) + b))
	m.add_theme_constant_override("margin_top", int(HubStyle.px(2) + b))
	m.add_theme_constant_override("margin_bottom", int(HubStyle.px(2) + b))
	m.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	m.draw.connect(func():
		HubStyle.draw_box(m, Rect2(Vector2.ZERO, m.size), HubContractCard.INSET_BG, HubStyle.px(2), 0.0))
	var h := HubBox.hbox(5)
	m.add_child(h)
	h.add_child(HubIcon.make(HubIcon.sample_art(kind), 2))
	var l := HubStyle.label(sample_word(kind), 13, HubStyle.PAPER, "bold")
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	return m


## Aperçu encadré (fond très sombre, contour noir) de `w` × `h` à 100 % :
## [encadré, TextureRect du plan].
static func preview_box(w: float, h: float) -> Array:
	var box := Control.new()
	box.custom_minimum_size = HubStyle.pxv(w, h)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	box.draw.connect(func():
		HubStyle.draw_box(box, Rect2(Vector2.ZERO, box.size), HubStyle.TRACK, HubStyle.px(2), 0.0))
	var tex := TextureRect.new()
	tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	var m := HubStyle.px(10)
	tex.offset_left = m
	tex.offset_top = m
	tex.offset_right = -m
	tex.offset_bottom = -m
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(tex)
	return [box, tex]


## Liseré noir de 2 px sous un contrôle (border-bottom de la maquette).
static func underline(c: Control) -> Control:
	c.draw.connect(func():
		var b := HubStyle.px(2)
		c.draw_rect(Rect2(0, c.size.y - b, c.size.x, b), HubStyle.BLACK))
	return c


# --------------------------------------------------------------------------
# Ligne de carte (.row cliquable)
# --------------------------------------------------------------------------

## Ligne de la liste des cartes : icône, nom (gras si choisie), note à droite
## (« chiens »). Choisie : fond brun et barre jaune (.row.sel). Le focus du
## clavier ou de la manette choisit la carte ; un clic la choisit ; valider
## une carte déjà choisie (Entrée, A, second clic) déclenche `activated`.
class MapRow extends Button:
	var map_id := ""
	var selected := false:
		set(v):
			selected = v
			if _name:
				_name.add_theme_font_override("font", HubStyle.font("bold" if v else "ui"))
			queue_redraw()
	var alt := false
	var hint := ""
	var _name: Label
	signal chosen(id: String)
	signal activated(id: String)

	func _init(id: String, title: String, note: String, h := "") -> void:
		map_id = id
		hint = h
		text = ""
		flat = true
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		custom_minimum_size = Vector2(0, HubStyle.px(40))
		var empty := StyleBoxEmpty.new()
		for s in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			add_theme_stylebox_override(s, empty)
		var box := HubBox.hbox(10)
		box.set_anchors_preset(Control.PRESET_FULL_RECT)
		box.offset_left = HubStyle.px(10)
		box.offset_right = -HubStyle.px(10)
		box.offset_bottom = -HubStyle.px(2)
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		add_child(box)
		var ic := HubIcon.make("mapico", 2)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.add_child(ic)
		_name = HubStyle.label(title, 15, HubStyle.PAPER)
		_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_name.clip_text = true
		_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(_name)
		var n := HubStyle.label(note, 13, HubStyle.DIM)
		n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		box.add_child(n)

	func _ready() -> void:
		focus_entered.connect(func():
			Audio.play_ui(MenuStyle.SND_MOVE, MenuStyle.VOL_MOVE)
			chosen.emit(map_id))
		pressed.connect(func():
			if selected:
				Audio.play_ui(MenuStyle.SND_SELECT, MenuStyle.VOL_SELECT)
				activated.emit(map_id)
			else:
				chosen.emit(map_id))

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var b := HubStyle.px(2)
		draw_rect(r, HubStyle.ROW_SEL if selected else (HubStyle.ROW_BG_ALT if alt else HubStyle.ROW_BG))
		if selected:
			draw_rect(Rect2(0, 0, HubStyle.px(4), r.size.y), HubStyle.YELLOW)
		elif is_hovered():
			draw_rect(r, Color(1, 1, 1, 0.03))
		draw_rect(Rect2(0, r.size.y - b, r.size.x, b), HubStyle.BLACK)


# --------------------------------------------------------------------------
# Champ de saisie
# --------------------------------------------------------------------------

## Champ de saisie du hub : fond sombre enfoncé, contour noir, focus jaune.
static func line_edit(value: String, placeholder: String, max_len: int) -> LineEdit:
	var e := LineEdit.new()
	e.text = value
	e.placeholder_text = placeholder
	e.max_length = max_len
	e.custom_minimum_size = Vector2(0, HubStyle.px(30))
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	e.add_theme_font_override("font", HubStyle.font("ui"))
	e.add_theme_font_size_override("font_size", HubStyle.fs(15))
	e.add_theme_color_override("font_color", HubStyle.PAPER)
	e.add_theme_color_override("font_placeholder_color", HubStyle.DIM2)
	e.add_theme_color_override("caret_color", HubStyle.YELLOW)
	e.add_theme_color_override("selection_color", Color(HubStyle.YELLOW, 0.35))
	var n := StyleBoxFlat.new()
	n.bg_color = HubStyle.GROUP_BG
	n.border_color = HubStyle.BLACK
	n.set_border_width_all(int(HubStyle.px(2)))
	n.content_margin_left = HubStyle.px(8)
	n.content_margin_right = HubStyle.px(8)
	e.add_theme_stylebox_override("normal", n)
	var f := n.duplicate() as StyleBoxFlat
	f.border_color = HubStyle.YELLOW
	f.set_border_width_all(int(maxf(HubStyle.px(2), 2.0)))
	e.add_theme_stylebox_override("focus", f)
	e.add_theme_stylebox_override("read_only", n)
	return e
