class_name IllustratedPost
extends CanvasLayer
## Post-traitement du style ILLUSTRÉ (IllustratedStyle) : deux passes plein
## écran sur l'image finale (après tonemap), affichées seulement en ILLUSTRÉ :
##   1. assets/shaders/illustrated_kuwahara.gdshader : filtre de Kuwahara
##      (bruit des textures pixel art -> aplats peints, bords gardés) ; rayon
##      par préréglage de qualité (RenderQuality « illustrated_radius » ; 0 en
##      BASSE : passe sautée) ;
##   2. assets/shaders/illustrated_grade.gdshader : étalonnage mesuré sur la
##      planche cible (courbe de valeurs, carte de couleurs, paliers doux,
##      netteté locale, grain de papier).
## Chaque passe relit l'écran (BackBufferCopy avant elle).
##
## Couche : juste sous le grain de film (FilmPost) et le HUD en partie ; sous
## l'interface du menu titre (couche -1 : seul le fond 3D est traité).
## Créé par attach() à côté du contour noir (ScreenOutline : partie et fond
## du menu), sans rien changer d'autre.

const KUWAHARA := preload("res://assets/shaders/illustrated_kuwahara.gdshader")
const GRADE := preload("res://assets/shaders/illustrated_grade.gdshader")
## Couche en partie (sous FilmPost.LAYER) et dans le menu (sous l'interface).
const GAME_LAYER := FilmPost.LAYER - 1
const MENU_LAYER := -1
## Halo des sources lumineuses (illustrated_grade.gdshader, `glow`).
const GLOW := 0.6

var kuwahara: ShaderMaterial
var grade: ShaderMaterial
var _kuwahara_rect: ColorRect
var _kuwahara_copy: BackBufferCopy


## Ajoute le post-traitement à côté de `node` (même parent).
static func attach(node: Node) -> IllustratedPost:
	var p := node.get_parent()
	if p == null:
		return null
	var post := IllustratedPost.new()
	post.name = "IllustratedPost"
	var in_game := false
	for c in p.get_children():
		if c is FilmPost:
			in_game = true
	post.layer = GAME_LAYER if in_game else MENU_LAYER
	p.add_child.call_deferred(post)
	return post


func _ready() -> void:
	kuwahara = ShaderMaterial.new()
	kuwahara.shader = KUWAHARA
	grade = ShaderMaterial.new()
	grade.shader = GRADE
	_kuwahara_copy = _copy()
	_kuwahara_rect = _rect(kuwahara)
	_copy()
	_rect(grade)
	Settings.changed.connect(refresh)
	refresh()


func _copy() -> BackBufferCopy:
	var b := BackBufferCopy.new()
	b.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(b)
	return b


func _rect(m: ShaderMaterial) -> ColorRect:
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.material = m
	add_child(r)
	return r


## Rayon du filtre de Kuwahara (pixels à 1080p) du préréglage courant.
static func radius_for(q: Dictionary) -> float:
	return float(q.get("illustrated_radius", 0.0))


func refresh() -> void:
	visible = IllustratedStyle.active()
	var r := radius_for(RenderQuality.current())
	kuwahara.set_shader_parameter("radius", r)
	_kuwahara_rect.visible = r > 0.0
	_kuwahara_copy.visible = r > 0.0
	# BASSE : ni filtre de Kuwahara ni halo (8 lectures de moins par pixel).
	grade.set_shader_parameter("glow", GLOW if r > 0.0 else 0.0)
