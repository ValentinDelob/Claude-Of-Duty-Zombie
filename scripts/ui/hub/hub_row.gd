class_name HubRow
extends MarginContainer
## Ligne de liste du hub (classes .row, .grp et .smp de la maquette) : fond
## (lignes paires un peu plus claires), liseré noir de 2 px en bas, sélection
## (fond brun et barre jaune de 4 px à gauche). Le contenu est dans `box`
## (HBoxContainer centré verticalement, ou VBoxContainer pour une ligne
## haute). Hauteur minimale à 100 % : 40 px (.row), 26 (.grp), 44 (.smp).

const ROW := "row"
## Intitulé de groupe (.grp : fond très sombre, Impact 13, gris).
const GROUP := "grp"
## Ligne d'échantillon (.smp : sans fond propre).
const SAMPLE := "smp"

var kind := ROW
var alt := false:
	set(v):
		alt = v
		queue_redraw()
var selected := false:
	set(v):
		selected = v
		queue_redraw()
## Liseré noir en bas (faux : dernière ligne d'un panneau).
var bottom_line := true:
	set(v):
		bottom_line = v
		queue_redraw()
var box: BoxContainer


## `vertical` : contenu en colonne (ligne haute, contrats actifs du LABO).
func _init(k := ROW, height := -1.0, vertical := false, sep := 10.0) -> void:
	kind = k
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := height if height >= 0.0 else (26.0 if k == GROUP else (44.0 if k == SAMPLE else 40.0))
	custom_minimum_size = Vector2(0, HubStyle.px(h))
	add_theme_constant_override("margin_left", int(HubStyle.px(10)))
	add_theme_constant_override("margin_right", int(HubStyle.px(10)))
	add_theme_constant_override("margin_top", 0)
	add_theme_constant_override("margin_bottom", int(HubStyle.px(2)))
	box = HubBox.vbox(sep) if vertical else HubBox.hbox(sep)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	if not vertical:
		box.size_flags_vertical = Control.SIZE_FILL
	add_child(box)


## Intitulé de groupe (.grp).
static func group(t: String) -> HubRow:
	var r := HubRow.new(GROUP)
	var l := HubStyle.label(t, 13, HubStyle.DIM, "impact", false, 0.08)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.box.add_child(l)
	return r


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var b := HubStyle.px(2)
	match kind:
		GROUP:
			draw_rect(r, HubStyle.GROUP_BG)
		SAMPLE:
			pass
		_:
			draw_rect(r, HubStyle.ROW_SEL if selected else (HubStyle.ROW_BG_ALT if alt else HubStyle.ROW_BG))
			if selected:
				draw_rect(Rect2(0, 0, HubStyle.px(4), r.size.y), HubStyle.YELLOW)
	if bottom_line:
		draw_rect(Rect2(0, r.size.y - b, r.size.x, b), HubStyle.BLACK)
