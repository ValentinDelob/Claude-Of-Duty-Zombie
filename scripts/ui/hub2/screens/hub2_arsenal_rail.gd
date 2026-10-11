class_name Hub2ArsenalRail
extends RefCounted
## Rail horizontal des niveaux de l'ARSENAL du hub v2 (docs/hub_v2/Arsenal.dc.html,
## partie script) : les objets (armes ou pièces) sont groupés par niveau, une
## colonne par niveau (niveaux croissants de gauche à droite), objets d'une
## colonne empilés verticalement dans l'ordre donné par `before`.
##   - `visible` colonnes affichées à partir de `start` (5 dans la maquette) ;
##   - ◄ ► : colonne voisine (même rang, borné) ; ▲ ▼ : même colonne ;
##   - ‹ › : fenêtre décalée d'une colonne ; vue d'ensemble : saut à un niveau
##     (fenêtre centrée dessus : `start = i - 2` dans la maquette).
## Données et règles pures (testées par tests/test_hub2_arsenal.gd), sans
## interface ; les objets ont `level` et `uid`.

## Colonnes visibles de la maquette (grid-template-columns: repeat(5, …)).
const VISIBLE := 5

## Niveaux présents, croissants.
var levels: Array[int] = []
## Niveau -> objets de la colonne (triés).
var columns: Dictionary = {}
## Première colonne affichée.
var start := 0
## Colonnes affichées.
var visible := VISIBLE
## Colonne et rang de l'objet choisi (-1 : rien).
var sel_col := -1
var sel_row := 0


## Range `items` par niveau ; `before(a, b)` : ordre dans une colonne.
func setup(items: Array, before: Callable) -> void:
	columns.clear()
	levels.clear()
	for it in items:
		var lvl := int(it.level)
		if not columns.has(lvl):
			columns[lvl] = []
			levels.append(lvl)
		(columns[lvl] as Array).append(it)
	levels.sort()
	for lvl in levels:
		(columns[lvl] as Array).sort_custom(before)
	sel_col = 0 if not levels.is_empty() else -1
	sel_row = 0
	start = clampi(start, 0, max_start())


func is_empty() -> bool:
	return levels.is_empty()


func count() -> int:
	var n := 0
	for lvl in levels:
		n += (columns[lvl] as Array).size()
	return n


func column(i: int) -> Array:
	if i < 0 or i >= levels.size():
		return []
	return columns[levels[i]]


## Dernière valeur possible de `start` (la fenêtre reste pleine).
func max_start() -> int:
	return maxi(0, levels.size() - visible)


## Objet choisi (null : rail vide).
func selected() -> Variant:
	var col := column(sel_col)
	if col.is_empty():
		return null
	return col[clampi(sel_row, 0, col.size() - 1)]


func selected_level() -> int:
	return levels[sel_col] if sel_col >= 0 and sel_col < levels.size() else -1


## Choisit l'objet d'identifiant `uid` ; faux s'il n'est pas dans le rail.
func select_uid(uid: String) -> bool:
	for i in levels.size():
		var col := column(i)
		for r in col.size():
			if String(col[r].uid) == uid:
				sel_col = i
				sel_row = r
				return true
	return false


## Choisit la colonne `i`, rang `row` (bornés).
func select_at(i: int, row: int) -> void:
	if levels.is_empty():
		sel_col = -1
		return
	sel_col = clampi(i, 0, levels.size() - 1)
	sel_row = clampi(row, 0, column(sel_col).size() - 1)


## ◄ (-1) / ► (+1) : colonne voisine, même rang (borné) ; fenêtre suivie.
## Faux au bord (rien ne change).
func move_col(dir: int) -> bool:
	var i := sel_col + dir
	if sel_col < 0 or i < 0 or i >= levels.size():
		return false
	select_at(i, sel_row)
	ensure_visible()
	return true


## ▲ (-1) / ▼ (+1) dans la même colonne ; faux au bord.
func move_row(dir: int) -> bool:
	var r := sel_row + dir
	if sel_col < 0 or r < 0 or r >= column(sel_col).size():
		return false
	sel_row = r
	return true


## Fenêtre déplacée au minimum pour montrer la colonne choisie.
func ensure_visible() -> void:
	if sel_col < 0:
		return
	if sel_col < start:
		start = sel_col
	elif sel_col >= start + visible:
		start = sel_col - visible + 1
	start = clampi(start, 0, max_start())


## Fenêtre centrée sur la colonne choisie (ouverture de l'écran).
func center_on_selection() -> void:
	if sel_col >= 0:
		start = clampi(sel_col - visible / 2, 0, max_start())


## ‹ (-1) / › (+1) : fenêtre décalée d'une colonne ; faux au bord.
func shift(dir: int) -> bool:
	var s := clampi(start + dir, 0, max_start())
	if s == start:
		return false
	start = s
	return true


## Clic sur le niveau `i` de la vue d'ensemble : fenêtre centrée dessus
## (Math.min(Math.max(0, i - 2), maxStart) dans la maquette).
func jump(i: int) -> void:
	start = clampi(i - visible / 2, 0, max_start())


func can_shift(dir: int) -> bool:
	return start + dir >= 0 and start + dir <= max_start() and max_start() > 0


## La colonne `i` est-elle dans la fenêtre ?
func is_visible_col(i: int) -> bool:
	return i >= start and i < start + visible


## Indices des colonnes affichées.
func visible_cols() -> Array[int]:
	var out: Array[int] = []
	for i in range(start, mini(start + visible, levels.size())):
		out.append(i)
	return out


## Nombre de colonnes qui tiennent dans `width` px (colonnes d'au moins
## `col_w` px séparées de `gap` px, déjà à l'échelle) : 5 au plus (la
## maquette), 1 au moins. À 100 % la maquette en montre 5 ; à 130 % moins
## de colonnes tiennent, chacune garde la largeur lisible de la maquette.
static func fit_visible(width: float, col_w: float, gap: float) -> int:
	if col_w <= 0.0:
		return VISIBLE
	return clampi(floori((width + gap + 0.5) / (col_w + gap)), 1, VISIBLE)
