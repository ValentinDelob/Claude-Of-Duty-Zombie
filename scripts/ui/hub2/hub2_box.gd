class_name Hub2Box
extends MarginContainer
## Panneau du hub v2 : fond rgba, liseré par côté, coins biseautés
## (clip-path des maquettes) et, en verre, flou de ce qui est derrière
## (backdrop-filter: blur). Dessiné par un shader (hub2_box / hub2_glass),
## antialiasé à toute résolution. C'est un MarginContainer : `pad()` donne le
## padding CSS, les enfants sont posés dedans (un seul enfant conteneur, comme
## un <div> avec padding).
##
##   var b := Hub2Box.new()
##   b.glass(Hub2Style.GLASS, Hub2Style.LINE)        # panneau standard
##   b.pad(18, 20, 18, 22)                           # padding: 18px 20px 18px 22px
##
##   var play := Hub2Box.new()                       # bouton plein biseauté
##   play.flat(Hub2Style.YELLOW)
##   play.chamfer(12)
##
## Le verre lit la copie de l'écran faite avant le premier verre de l'image
## (voir hub2_glass.gdshader) : un verre ne floute pas un autre verre.

const SHADER_FLAT := preload("res://assets/shaders/hub2_box.gdshader")
const SHADER_GLASS := preload("res://assets/shaders/hub2_glass.gdshader")

var fill := Hub2Style.GLASS:
	set(v):
		fill = v
		_apply()
var border_color := Hub2Style.LINE:
	set(v):
		border_color = v
		_apply()
## Liseré (px de la maquette) : gauche, haut, droite, bas.
var border := Vector4(1, 1, 1, 1):
	set(v):
		border = v
		_apply()
## Biseaux (px de la maquette) : coin haut-droit, coin bas-gauche.
var chamfer_tr := 0.0:
	set(v):
		chamfer_tr = v
		_apply()
var chamfer_bl := 0.0:
	set(v):
		chamfer_bl = v
		_apply()
## Écart type du flou (px de la maquette) ; 0 : fond plat (aucune lecture de
## l'écran).
var blur := 0.0:
	set(v):
		blur = v
		_apply()

var _mat: ShaderMaterial


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	material = _mat
	resized.connect(_apply)
	for side in ["left", "top", "right", "bottom"]:
		add_theme_constant_override("margin_" + side, 0)
	_apply()


## Verre : fond `bg`, liseré `line` de `width` px sur les quatre côtés,
## flou `blur_px` (12 : panneaux ; 16 : barre du haut).
func glass(bg := Hub2Style.GLASS, line := Hub2Style.LINE, width := 1.0, blur_px := Hub2Style.BLUR) -> void:
	fill = bg
	border_color = line
	border = Vector4(width, width, width, width)
	blur = blur_px


## Fond plat (sans flou) ; liseré facultatif.
func flat(bg: Color, line := Color(0, 0, 0, 0), width := 0.0) -> void:
	fill = bg
	border_color = line
	border = Vector4(width, width, width, width)
	blur = 0.0


## Biseau des deux coins (polygon(0 0, calc(100% - N) 0, 100% N, 100% 100%,
## N 100%, 0 calc(100% - N))) ; `bottom_left` 0 : seul le coin haut-droit
## (variante « 100% 100%, 0 100% »).
func chamfer(n: float, bottom_left := -1.0) -> void:
	chamfer_tr = n
	chamfer_bl = n if bottom_left < 0.0 else bottom_left


## padding CSS (haut, droite, bas, gauche ; px de la maquette).
func pad(top: float, right := -1.0, bottom := -1.0, left := -1.0) -> void:
	if right < 0.0:
		right = top
	if bottom < 0.0:
		bottom = top
	if left < 0.0:
		left = right
	add_theme_constant_override("margin_top", int(Hub2Style.px(top)))
	add_theme_constant_override("margin_right", int(Hub2Style.px(right)))
	add_theme_constant_override("margin_bottom", int(Hub2Style.px(bottom)))
	add_theme_constant_override("margin_left", int(Hub2Style.px(left)))


func _apply() -> void:
	if _mat == null:
		return
	var sh: Shader = SHADER_GLASS if blur > 0.0 else SHADER_FLAT
	if _mat.shader != sh:
		_mat.shader = sh
	_mat.set_shader_parameter("rect_size", size)
	_mat.set_shader_parameter("fill", fill)
	_mat.set_shader_parameter("border_color", border_color)
	_mat.set_shader_parameter("border_widths", Vector4(Hub2Style.px(border.x), Hub2Style.px(border.y),
			Hub2Style.px(border.z), Hub2Style.px(border.w)))
	_mat.set_shader_parameter("chamfer_tr", Hub2Style.px(chamfer_tr))
	_mat.set_shader_parameter("chamfer_bl", Hub2Style.px(chamfer_bl))
	if blur > 0.0:
		_mat.set_shader_parameter("blur", Hub2Style.px(blur))
	queue_redraw()


func _draw() -> void:
	# Taille relue au dessin : une taille posée hors de l'arbre n'émet pas
	# `resized`.
	_mat.set_shader_parameter("rect_size", size)
	draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE)


## Point dans la forme biseautée (clics : un coin coupé ne répond pas, comme
## clip-path).
func _has_point(p: Vector2) -> bool:
	if not Rect2(Vector2.ZERO, size).has_point(p):
		return false
	var tr := Hub2Style.px(chamfer_tr)
	var bl := Hub2Style.px(chamfer_bl)
	if tr > 0.0 and (size.x - p.x) + p.y < tr:
		return false
	if bl > 0.0 and p.x + (size.y - p.y) < bl:
		return false
	return true
