class_name Hub2ShadowRender
extends Control
## Rendu Blender (HubRenders) d'une maquette du hub v2 : <img> avec
## `object-fit: contain` (ou hauteur imposée, largeur auto), ombre portée
## `filter: drop-shadow(0 Ypx Bpx rgba(0, 0, 0, A))` et silhouette d'un objet
## inconnu `filter: brightness(0) opacity(A)` (même image, noire).
## L'ombre floue est approchée par 9 copies noires décalées autour de
## l'ombre (le flou CSS sans shader) ; valeurs en px de la maquette.

var texture: Texture2D:
	set(v):
		texture = v
		queue_redraw()
## Silhouette noire d'opacité `silhouette` (0 : rendu normal).
var silhouette := 0.0:
	set(v):
		silhouette = v
		queue_redraw()
## drop-shadow : décalage vertical, rayon du flou, opacité (0 : sans ombre).
var shadow_y := 0.0
var shadow_blur := 0.0
var shadow_alpha := 0.0
## Hauteur imposée (px de la maquette, largeur auto, centré en bas : flex-end) ;
## 0 : contain dans le nœud, centré.
var fixed_height := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = HubRenders.FILTER


## Réglage en une ligne : drop-shadow(0 y blur rgba(0, 0, 0, a)).
func drop_shadow(y: float, blur: float, a: float) -> void:
	shadow_y = y
	shadow_blur = blur
	shadow_alpha = a
	queue_redraw()


## Rectangle de l'image dans le nœud.
func image_rect() -> Rect2:
	if texture == null:
		return Rect2()
	var ts := texture.get_size()
	if ts.x <= 0.0 or ts.y <= 0.0:
		return Rect2()
	if fixed_height > 0.0:
		var h := Hub2Style.px(fixed_height)
		var w := h * ts.x / ts.y
		return Rect2((size.x - w) * 0.5, size.y - h, w, h)
	var k := minf(size.x / ts.x, size.y / ts.y)
	var s := ts * k
	return Rect2((size - s) * 0.5, s)


func _draw() -> void:
	var r := image_rect()
	if r.size == Vector2.ZERO:
		return
	if silhouette > 0.0:
		draw_texture_rect(texture, r, false, Color(0, 0, 0, silhouette))
		return
	if shadow_alpha > 0.0:
		var off := Vector2(0, Hub2Style.px(shadow_y))
		var rad := Hub2Style.px(shadow_blur) * 0.5
		# 9 copies : centre + 8 directions ; opacité de chacune telle que leur
		# superposition au centre donne `shadow_alpha`.
		var a := 1.0 - pow(1.0 - shadow_alpha, 1.0 / 9.0)
		draw_texture_rect(texture, Rect2(r.position + off, r.size), false, Color(0, 0, 0, a))
		for i in 8:
			var d := Vector2.from_angle(TAU * i / 8.0) * rad
			draw_texture_rect(texture, Rect2(r.position + off + d, r.size), false, Color(0, 0, 0, a))
	draw_texture_rect(texture, r, false)
