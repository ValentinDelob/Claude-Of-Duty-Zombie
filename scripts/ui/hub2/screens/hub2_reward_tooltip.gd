class_name Hub2RewardTooltip
extends PanelContainer
## Infobulle d'une tuile de récompense (docs/hub_v2/Contrats.dc.html,
## role="tooltip") : 260 px de large, padding 14 16, écart 8, fond
## rgba(8, 9, 11, 0.94), liseré 1 px à la couleur de la récompense, ombre
## 0 12px 30px rgba(0, 0, 0, 0.6) ; sorte (Chakra Petch 11 px 700 0.16em, à
## la couleur), nom (Chakra Petch 20 px 700), statistiques en grille de deux
## colonnes (écarts 6 / 12 ; libellé Barlow 13 px à 70 %, valeur JetBrains
## Mono 700), note (12 px à 55 %). Posée 10 px au-dessus de la tuile, bord
## gauche (histoire) ou droit (contrats temporaires) aligné sur elle ; en
## dessous s'il n'y a pas la place. Un seul exemplaire par écran (enfant du
## panneau, au premier plan, ignore la souris).

const WIDTH := 260.0
const OFFSET := 10.0

## Tuile montrée (null : cachée).
var tile: Hub2RewardTile
var kind_text: Hub2Text
var name_text: Hub2Text
var grid: GridContainer
var note: Label
var _style: StyleBoxFlat


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	z_index = 10
	_style = StyleBoxFlat.new()
	_style.bg_color = Hub2Style.TOOLTIP_BG
	_style.set_border_width_all(int(maxf(Hub2Style.px(1), 1.0)))
	_style.shadow_color = Color(0, 0, 0, 0.6)
	_style.shadow_size = int(Hub2Style.px(15))
	_style.shadow_offset = Hub2Style.pxv(0, 12)
	_style.content_margin_top = Hub2Style.px(14)
	_style.content_margin_bottom = Hub2Style.px(14)
	_style.content_margin_left = Hub2Style.px(16)
	_style.content_margin_right = Hub2Style.px(16)
	add_theme_stylebox_override("panel", _style)
	custom_minimum_size.x = Hub2Style.px(WIDTH)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(Hub2Style.px(8)))
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	kind_text = Hub2Text.new()
	v.add_child(kind_text)
	name_text = Hub2Text.new()
	v.add_child(name_text)
	grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", int(Hub2Style.px(12)))
	grid.add_theme_constant_override("v_separation", int(Hub2Style.px(6)))
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(grid)
	note = Hub2Style.label("", Hub2Style.BARLOW, 400, 12, Hub2Style.text_a(0.55))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Largeur intérieure fixe : la hauteur du texte replié est juste tout de
	# suite (pas d'infobulle géante le temps d'une mise en page).
	note.custom_minimum_size.x = Hub2Style.px(WIDTH - 32.0)
	v.add_child(note)
	minimum_size_changed.connect(func(): _place.call_deferred())


## Montre l'infobulle de `t` (null : cache).
func show_for(t: Hub2RewardTile) -> void:
	tile = t
	if t == null or t.spec.is_empty() or not t.is_visible_in_tree():
		visible = false
		return
	var s := t.spec
	var col := t.color()
	_style.border_color = col
	kind_text.setup(String(s.get("kind", "")), Hub2Style.CHAKRA, 700, 11, col, 0.16)
	name_text.setup(String(s.get("name", "")), Hub2Style.CHAKRA, 700, 20, Hub2Style.TEXT)
	for c in grid.get_children():
		grid.remove_child(c)
		c.queue_free()
	for st in s.get("stats", []):
		var h := HBoxContainer.new()
		h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := Hub2Style.label(String(st[0]), Hub2Style.BARLOW, 400, 13, Hub2Style.text_a(0.7))
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		h.add_child(Hub2Style.label(String(st[1]), Hub2Style.MONO, 700, 13, Hub2Style.TEXT))
		grid.add_child(h)
	grid.visible = grid.get_child_count() > 0
	note.text = String(s.get("note", ""))
	note.visible = note.text != ""
	visible = true
	note.size.x = Hub2Style.px(WIDTH - 32.0)
	reset_size()
	_place()
	_place.call_deferred()


## Position au-dessus de la tuile (ou dessous), dans l'écran.
func _place() -> void:
	if tile == null or not is_instance_valid(tile) or not visible:
		return
	var parent := get_parent() as Control
	if parent == null:
		return
	reset_size()
	size = get_combined_minimum_size()
	var inv := parent.get_global_transform().affine_inverse()
	var tr := inv * tile.get_global_rect()
	var off := Hub2Style.px(OFFSET)
	var x := tr.end.x - size.x if tile.tip_right else tr.position.x
	var y := tr.position.y - off - size.y
	var screen := Rect2(Vector2.ZERO, parent.size)
	if y < Hub2Style.px(Hub2Style.TOP_BAR_H):
		y = tr.end.y + off
	x = clampf(x, 0.0, maxf(screen.size.x - size.x, 0.0))
	y = clampf(y, 0.0, maxf(screen.size.y - size.y, 0.0))
	position = Vector2(roundf(x), roundf(y))
