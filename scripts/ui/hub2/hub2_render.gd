class_name Hub2Render
extends Control
## Image du hub v2 (<img> des maquettes) : un rendu Blender (HubRenders), un
## aperçu de carte ou un plan, posé comme `object-fit` (contain : entier,
## centré ; cover : remplit, recadré ; bottom : collé en bas, centré, hauteur
## pleine, comme le joueur des cartes du salon), avec en option :
##   - une ombre portée (filter: drop-shadow(x y flou couleur)) : la
##     silhouette de l'image, décalée, floutée (shader, alpha seulement) ;
##   - une couche teintée par-dessus (`overlay`, modulée par `overlay_color`) :
##     masque de la zone d'équipe du joueur (HubRenders.PLAYER_TEAM_MASK) ;
##   - une teinte de l'image (`tint`, modulate).
## Les images réduites prennent HubRenders.FILTER (mipmaps).

const FIT_CONTAIN := "contain"
const FIT_COVER := "cover"
const FIT_BOTTOM := "bottom"

const SHADOW_SHADER := preload("res://assets/shaders/hub2_drop_shadow.gdshader")

var texture: Texture2D:
	set(v):
		texture = v
		queue_redraw()
var overlay: Texture2D:
	set(v):
		overlay = v
		queue_redraw()
var overlay_color := Color.WHITE:
	set(v):
		overlay_color = v
		queue_redraw()
var tint := Color.WHITE:
	set(v):
		tint = v
		queue_redraw()
var fit := FIT_CONTAIN:
	set(v):
		fit = v
		queue_redraw()
## Ombre portée (px de la maquette) : décalage x, y et flou ; z = 0 : aucune.
var shadow := Vector3.ZERO:
	set(v):
		shadow = v
		_setup_shadow()
var shadow_color := Color(0, 0, 0, 0.5):
	set(v):
		shadow_color = v
		_setup_shadow()

var _shadow_node: Control
var _shadow_mat: ShaderMaterial


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = HubRenders.FILTER
	clip_contents = false


## Rectangle où l'image est dessinée (pixels du nœud).
func image_rect() -> Rect2:
	if texture == null:
		return Rect2()
	var ts := Vector2(texture.get_size())
	if ts.x <= 0.0 or ts.y <= 0.0 or size.x <= 0.0 or size.y <= 0.0:
		return Rect2()
	var k := 1.0
	match fit:
		FIT_COVER:
			k = maxf(size.x / ts.x, size.y / ts.y)
		FIT_BOTTOM:
			k = size.y / ts.y
		_:
			k = minf(size.x / ts.x, size.y / ts.y)
	var d := ts * k
	var pos := (size - d) * 0.5
	if fit == FIT_BOTTOM:
		pos.y = size.y - d.y
	return Rect2(pos, d)


func _draw() -> void:
	if texture == null:
		return
	var r := image_rect()
	if fit == FIT_COVER:
		# Recadrage : seule la partie visible de l'image est dessinée.
		var ts := Vector2(texture.get_size())
		var k := r.size.x / ts.x
		var src := Rect2((Vector2.ZERO - r.position) / k, size / k)
		draw_texture_rect_region(texture, Rect2(Vector2.ZERO, size), src, tint)
		if overlay:
			draw_texture_rect_region(overlay, Rect2(Vector2.ZERO, size), src, overlay_color)
		return
	draw_texture_rect(texture, r, false, tint)
	if overlay:
		draw_texture_rect(overlay, r, false, overlay_color)
	if _shadow_node:
		_shadow_node.queue_redraw()


func _setup_shadow() -> void:
	if shadow.z <= 0.0 and shadow.x == 0.0 and shadow.y == 0.0:
		if _shadow_node:
			_shadow_node.queue_free()
			_shadow_node = null
		return
	if _shadow_node == null:
		_shadow_node = Control.new()
		_shadow_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_shadow_node.show_behind_parent = true
		_shadow_node.set_anchors_preset(Control.PRESET_FULL_RECT)
		_shadow_mat = ShaderMaterial.new()
		_shadow_mat.shader = SHADOW_SHADER
		_shadow_node.material = _shadow_mat
		_shadow_node.texture_filter = HubRenders.FILTER
		_shadow_node.draw.connect(_draw_shadow)
		add_child(_shadow_node)
	_shadow_mat.set_shader_parameter("shadow_color", shadow_color)
	_shadow_node.queue_redraw()


func _draw_shadow() -> void:
	if texture == null or fit == FIT_COVER:
		return
	var r := image_rect()
	# CSS : écart type = flou / 2 ; l'ombre déborde de 2 écarts types.
	var sigma := Hub2Style.px(shadow.z) * 0.5
	var grow := ceilf(sigma * 2.0)
	var off := Vector2(Hub2Style.px(shadow.x), Hub2Style.px(shadow.y))
	var dst := Rect2(r.position + off - Vector2(grow, grow), r.size + Vector2(grow, grow) * 2.0)
	_shadow_mat.set_shader_parameter("sigma_uv", Vector2(sigma / maxf(dst.size.x, 1.0), sigma / maxf(dst.size.y, 1.0)))
	_shadow_mat.set_shader_parameter("inset_uv", Vector2(grow / maxf(dst.size.x, 1.0), grow / maxf(dst.size.y, 1.0)))
	_shadow_node.draw_texture_rect(texture, dst, false)
