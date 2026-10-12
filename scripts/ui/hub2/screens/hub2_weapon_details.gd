class_name Hub2WeaponDetails
extends VBoxContainer
## Fiche complète repliable d'une arme (demande du 2026-10-12), sous les six
## statistiques : « DÉTAILS ▾ » (fermée) / « MASQUER ▴ » (ouverte), puis les
## autres statistiques (Hub2ArsenalView.detail_lines_of) dans la même grille
## 2 colonnes que les six (Hub2ArsenalStat sans carré d'icône : libellé
## Chakra Petch 10 px, valeur JetBrains Mono 15 px, modificateur 13 px
## turquoise / rouge sans unité) et la référence réelle pleine largeur
## (Barlow 13 px, 55 %). Le titre a le style des titres de section de la
## fiche (« PIÈCES · n / m » : Chakra Petch 12 px 600 0,18em, 55 %), flèche
## dessinée (les polices n'ont pas ▾ ▴).
##
## Composant réutilisable : ARSENAL du hub (Hub2ArsenalPanel), inventaire de
## partie (InventoryPanel), plus tard la station de construction :
##   var d := Hub2WeaponDetails.new()
##   d.setup("station", 16, 10)       # écran, écarts de la grille des six
##   stats_vbox.add_child(d)          # sous la grille des six statistiques
##   d.set_lines(Hub2ArsenalView.detail_lines_of(id, s, s_apres, s_avant))
##   # touche : Hub2Input.is_details(event) -> d.toggle() ; invite
##   # [Hub2Input.DETAILS, Hub2WeaponDetails.prompt_text(d.open)]
## Clic sur le titre, D ou R3 (Hub2Input.DETAILS, lus par l'écran) : ouvrir /
## fermer. L'état est retenu par écran pour la session (jamais enregistré
## dans le profil).

signal toggled(open: bool)

## Fiches ouvertes pendant la session : écran -> vrai.
static var _open_by_screen: Dictionary = {}

var screen := ""
var open := false
var title: Title
var body: VBoxContainer
var grid: GridContainer
var note: Hub2Text
## Cellules de la grille (Hub2ArsenalStat), lues par les tests.
var cells: Array = []
var lines: Array = []


static func is_open_for(screen_id: String) -> bool:
	return bool(_open_by_screen.get(screen_id, false))


static func set_open_for(screen_id: String, v: bool) -> void:
	_open_by_screen[screen_id] = v


## Oublie les fiches ouvertes (tests).
static func reset_session() -> void:
	_open_by_screen.clear()


## Titre du bouton : « DÉTAILS » fermée, « MASQUER » ouverte.
static func toggle_text(is_open: bool) -> String:
	return Lang.t("MASQUER", "HIDE") if is_open else Lang.t("DÉTAILS", "DETAILS")


## Libellé de l'invite (barre du bas).
static func prompt_text(is_open: bool) -> String:
	return Lang.t("Masquer", "Hide") if is_open else Lang.t("Détails", "Details")


## Prépare le composant pour l'écran `screen_id` ; `h_sep` / `v_sep` : écarts
## (px de la maquette) de la grille des six statistiques de cet écran.
func setup(screen_id: String, h_sep: float, v_sep: float) -> void:
	screen = screen_id
	open = is_open_for(screen)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", int(Hub2Style.px(v_sep)))
	title = Title.new()
	title.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	title.clicked.connect(toggle)
	add_child(title)
	body = VBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("separation", int(Hub2Style.px(v_sep)))
	add_child(body)
	grid = GridContainer.new()
	grid.columns = 2
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_theme_constant_override("h_separation", int(Hub2Style.px(h_sep)))
	grid.add_theme_constant_override("v_separation", int(Hub2Style.px(v_sep)))
	body.add_child(grid)
	note = Hub2Text.new()
	note.setup("", Hub2Style.BARLOW, 400, 13, Hub2Style.text_a(0.55))
	body.add_child(note)
	_apply()


## Lignes à montrer (Hub2ArsenalView.detail_lines_of) ; aucune : composant
## masqué.
func set_lines(new_lines: Array) -> void:
	lines = new_lines
	var cell_lines := []
	var wide := ""
	for l in lines:
		if bool(l.get("wide", false)):
			wide = String(l.get("value", ""))
		else:
			cell_lines.append(l)
	while cells.size() > cell_lines.size():
		var c: Control = cells.pop_back()
		grid.remove_child(c)
		c.queue_free()
	while cells.size() < cell_lines.size():
		var c := Hub2ArsenalStat.new()
		c.iconless = true
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(c)
		cells.append(c)
	for i in cells.size():
		cells[i].line = cell_lines[i]
	note.text = wide
	note.visible = wide != ""
	visible = not lines.is_empty()


## Ouvre ou ferme la fiche (retenu pour l'écran pendant la session) ;
## ouverte, la fiche qui défile la montre en entier si elle le peut.
func toggle() -> void:
	set_open(not open)
	if open:
		_reveal()


## Fait défiler la fiche (ScrollContainer parent) jusqu'à la fiche complète,
## une fois la mise en page refaite.
func _reveal() -> void:
	var n := get_parent()
	while n != null and not n is ScrollContainer:
		n = n.get_parent()
	if n == null or not is_inside_tree():
		return
	var sc := n as ScrollContainer
	await get_tree().process_frame
	if is_instance_valid(sc) and is_inside_tree() and open:
		sc.ensure_control_visible(self)


func set_open(v: bool) -> void:
	if v == open:
		return
	open = v
	set_open_for(screen, v)
	_apply()
	toggled.emit(open)


func _apply() -> void:
	body.visible = open
	title.text = toggle_text(open)
	title.up = open
	title.tooltip_text = Lang.t("%s : afficher ou masquer toutes les statistiques",
			"%s: show or hide every statistic") % Hub2Input.keycap_text(
			Hub2Input.keys_of(Hub2Input.DETAILS), Hub2Input.pads_of(Hub2Input.DETAILS), Settings.using_pad)


## Titre cliquable : texte (Chakra Petch 12 px 600 0,18em, 55 %) puis, à
## 6 px, la flèche ▾ (fermée) / ▴ (ouverte) de 7 × 4 px, même couleur.
class Title extends Control:
	signal clicked

	var text := "":
		set(v):
			text = v
			update_minimum_size()
			queue_redraw()
	var up := false:
		set(v):
			up = v
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _label_w() -> float:
		var s := Hub2Style.fs(12)
		return Hub2Style.text_width(text, Hub2Style.font(Hub2Style.CHAKRA, 600), s, Hub2Style.tracking_px(0.18, s))

	func _get_minimum_size() -> Vector2:
		return Vector2(ceilf(_label_w() + Hub2Style.px(6 + 7)),
				ceilf(Hub2ArsenalDraw.line_h(Hub2Style.CHAKRA, 600, 12)))

	func _draw() -> void:
		var col := Hub2Style.text_a(0.55)
		var lw := Hub2ArsenalDraw.text(self, text, Hub2Style.CHAKRA, 600, 12, col, 0.18, 0.0,
				Hub2ArsenalDraw.baseline(Hub2Style.CHAKRA, 600, 12, 0.0, size.y))
		var w := Hub2Style.px(7)
		var h := Hub2Style.px(4)
		var x := lw + Hub2Style.px(6)
		var cy := roundf(size.y * 0.5)
		var pts: PackedVector2Array
		if up:
			pts = [Vector2(x, cy + h * 0.5), Vector2(x + w, cy + h * 0.5), Vector2(x + w * 0.5, cy - h * 0.5)]
		else:
			pts = [Vector2(x, cy - h * 0.5), Vector2(x + w, cy - h * 0.5), Vector2(x + w * 0.5, cy + h * 0.5)]
		draw_colored_polygon(pts, col)

	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			clicked.emit()
