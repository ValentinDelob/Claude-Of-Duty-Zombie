class_name MenuLogo
extends Control
## Logo du menu titre : le nom du jeu (GameName, en attente du nom définitif)
## en lettres de cubes (glyphes de CubeFont, 5 x 7 cubes), chaque cube en
## relief (CubeFont.draw_cube) avec un liseré noir et une ombre franche.
## Mise en page automatique, pour qu'un nouveau nom s'y place seul :
##   * un mot : une grande ligne ;
##   * deux mots : deux grandes lignes ;
##   * trois mots ou plus : premier mot en grand, mots du milieu en petit
##     (jaune des bandes de danger), dernier mot en grand (vert toxique des
##     moniteurs) ;
## chaque ligne est réduite au besoin pour tenir dans WIDTH.
## Animation discrète : de temps en temps une rangée de cubes s'allume en
## balayant le logo de haut en bas (comme un écran qui se rafraîchit), et un
## cube au hasard grésille.

const WIDTH := 430.0
## Taille d'un cube des grandes lignes et des petites (px, au plus).
const BIG := 12.0
const SMALL := 6.0
## Espace entre deux lignes (en cubes de la ligne du dessous).
const GAP := 1.5
const OUTLINE := 3.0
const SHADOW := Vector2(5, 5)
const COL_FIRST := Color(0.93, 0.92, 0.86)
const COL_MID := UiStyle.ACCENT
const COL_LAST := UiStyle.MINT

## Lignes : [{text, cube, color}] (calculées une fois).
var lines: Array = []
var _cells: Array = []  # [Rect2, Color, rangée globale]
var _rows := 1
var _t := 0.0
var _sweep := -1.0
var _next_sweep := 2.5
var _flicker := -1
var _flicker_left := 0.0
var _next_flicker := 4.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 1971
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layout(GameName.words())


## Mise en page du nom `words` (public pour les tests).
func _layout(words: PackedStringArray) -> void:
	lines.clear()
	if words.size() <= 2:
		for i in words.size():
			lines.append({"text": words[i], "cube": BIG, "color": COL_FIRST if i == 0 else COL_LAST})
	else:
		lines.append({"text": words[0], "cube": BIG, "color": COL_FIRST})
		lines.append({"text": " ".join(words.slice(1, words.size() - 1)), "cube": SMALL, "color": COL_MID})
		lines.append({"text": words[words.size() - 1], "cube": BIG, "color": COL_LAST})
	_cells.clear()
	var y := OUTLINE
	var row := 0
	for i in lines.size():
		var l: Dictionary = lines[i]
		var c := minf(float(l.cube), floorf((WIDTH - OUTLINE * 2.0) / maxf(text_cubes(l.text), 1.0)))
		l.cube = c
		if i > 0:
			y += GAP * c
		var x := OUTLINE
		for ch in String(l.text):
			var g := CubeFont.glyph(ch)
			if g.is_empty():
				x += 4.0 * c
				continue
			# Rangées de la lettre seulement (ni accent ni jambage : capitales).
			for r in CubeFont.CAP_ROWS:
				var line_str: String = g[CubeFont.ACCENT_ROWS + r]
				for k in line_str.length():
					if line_str[k] == "#":
						_cells.append([Rect2(x + k * c, y + r * c, c, c), l.color, row + r])
			x += (g[0].length() + 1) * c
		y += CubeFont.CAP_ROWS * c
		row += CubeFont.CAP_ROWS
	_rows = row
	custom_minimum_size = Vector2(WIDTH, y + OUTLINE + SHADOW.y)
	queue_redraw()


## Largeur d'un texte en cubes (lettre + une colonne d'espace).
static func text_cubes(text: String) -> float:
	var n := 0.0
	for ch in text:
		var g := CubeFont.glyph(ch)
		n += 4.0 if g.is_empty() else g[0].length() + 1.0
	return n - 1.0


func _process(delta: float) -> void:
	_t += delta
	var dirty := false
	_next_sweep -= delta
	if _next_sweep <= 0.0 and _sweep < 0.0:
		_sweep = 0.0
		_next_sweep = _rng.randf_range(6.0, 11.0)
	if _sweep >= 0.0:
		_sweep += delta * 34.0  # rangées par seconde
		if _sweep > _rows + 4.0:
			_sweep = -1.0
		dirty = true
	_next_flicker -= delta
	if _next_flicker <= 0.0 and not _cells.is_empty():
		_flicker = _rng.randi_range(0, _cells.size() - 1)
		_flicker_left = _rng.randf_range(0.15, 0.5)
		_next_flicker = _rng.randf_range(2.5, 6.0)
		dirty = true
	if _flicker_left > 0.0:
		_flicker_left -= delta
		if _flicker_left <= 0.0:
			_flicker = -1
		dirty = true
	if dirty:
		queue_redraw()


func _draw() -> void:
	# Ombre franche puis liseré noir (cubes agrandis), puis les cubes.
	for cell in _cells:
		var r: Rect2 = cell[0]
		draw_rect(Rect2(r.position + SHADOW - Vector2(OUTLINE, OUTLINE), r.size + Vector2(OUTLINE, OUTLINE) * 2.0), Color(0.01, 0.03, 0.04, 0.75))
	for cell in _cells:
		var r: Rect2 = cell[0]
		draw_rect(Rect2(r.position - Vector2(OUTLINE, OUTLINE), r.size + Vector2(OUTLINE, OUTLINE) * 2.0), Color.BLACK)
	for i in _cells.size():
		var cell: Array = _cells[i]
		var col: Color = cell[1]
		if _sweep >= 0.0:
			var d := absf(float(cell[2]) - _sweep)
			if d < 3.0:
				col = col.lerp(Color.WHITE, (1.0 - d / 3.0) * 0.55)
		if i == _flicker and fmod(_t * 18.0, 2.0) < 1.0:
			col = col.darkened(0.55)
		CubeFont.draw_cube(self, cell[0], col)
