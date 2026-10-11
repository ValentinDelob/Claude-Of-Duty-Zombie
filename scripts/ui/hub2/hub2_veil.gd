class_name Hub2Veil
extends Control
## Voile posé sur le fond 3D du menu (MenuBackdrop) sous le hub v2 : chaque
## maquette assombrit l'image du fond par un <div> plein cadre :
##   - plein : background: rgba(8, 9, 11, a) (0.35 onglets, 0.45 contrats et
##     salon, 0.62 récapitulatif) -> {"color": Hub2Style.shade(a)} ;
##   - dégradé horizontal (LABO) : linear-gradient(90deg, rgba(8,9,11,0) 35%,
##     rgba(8,9,11,0.75) 70%) -> {"stops": [[0.35, shade(0)], [0.7, shade(0.75)]]}.
## Le panneau affiché le choisit (Hub2Panel.veil()).

var spec: Dictionary = {}:
	set(v):
		spec = v
		_rebuild()

var _tex: GradientTexture2D


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _rebuild() -> void:
	_tex = null
	if spec.has("stops"):
		var g := Gradient.new()
		var stops: Array = spec.stops
		g.offsets = PackedFloat32Array(stops.map(func(s): return float(s[0])))
		g.colors = PackedColorArray(stops.map(func(s): return s[1] as Color))
		_tex = GradientTexture2D.new()
		_tex.gradient = g
		_tex.fill_from = Vector2(0, 0)
		_tex.fill_to = Vector2(1, 0)
		_tex.width = 512
		_tex.height = 4
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if _tex:
		draw_texture_rect(_tex, r, false)
	elif spec.has("color"):
		draw_rect(r, spec.color)
