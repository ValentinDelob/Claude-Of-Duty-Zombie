class_name ScopeOverlay
extends Control
## Écran de lunette (L96A1, Dragunov : "sniper" ; AUG, G11 : "optic") affiché
## quand WeaponController.scoped est vrai. L'arme est alors masquée (ViewModel)
## et la caméra zoome (WeaponDB "scope_fov" ou "ads_zoom").
##
## * sniper : lentille ronde, noir autour, vignettage et légère aberration
##   chromatique (shader scope.gdshader), réticule fin à épaississement vers le
##   bord et graduations ; indication « [MAJ] RETENIR SA RESPIRATION » ;
## * optic : lentille plus large, bord assombri, anneau et point central.
## Le réticule reste au centre de l'écran : c'est là que partent les balles
## (le balancement déplace la caméra, donc le monde, pas le réticule).

var kind := ""
var _lens: ColorRect
var _mat: ShaderMaterial
var _hint: Label
var _reveal := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lens = ColorRect.new()
	_lens.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lens.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://assets/shaders/scope.gdshader")
	_lens.material = _mat
	add_child(_lens)
	_hint = UiStyle.label(Lang.t("[MAJ] RETENIR SA RESPIRATION", "[SHIFT] HOLD BREATH"), 15, Color(0.85, 0.85, 0.8, 0.55))
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.position = Vector2(-160, -150)
	_hint.size = Vector2(320, 24)
	add_child(_hint)
	visible = false


## Appelé par Hud._process.
func refresh(p: Player, delta: float) -> void:
	var wc := p.weapons if p else null
	var on := wc != null and wc.scoped
	if not on:
		visible = false
		_reveal = 0.0
		return
	kind = WeaponDB.scope_kind(wc.current_stats())
	visible = true
	# Mise en joue : bref passage au noir, puis la lentille s'ouvre.
	_reveal = move_toward(_reveal, 1.0, delta * 7.0)
	var sniper := kind == "sniper"
	_mat.set_shader_parameter("radius", 0.47 if sniper else 0.62)
	_mat.set_shader_parameter("aberration", 0.007 if sniper else 0.003)
	_mat.set_shader_parameter("vignette", 0.75 if sniper else 0.55)
	_mat.set_shader_parameter("mask", 1.0 if sniper else 0.8)
	_mat.set_shader_parameter("reveal", ease(_reveal, 0.6))
	var f := wc.feel
	_hint.visible = sniper and not f.holding and f.gasp <= 0.0
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var h := size.y
	var col := Color(0.02, 0.02, 0.02, 0.95 * _reveal)
	if kind == "sniper":
		var r := h * 0.47
		# Fils fins au centre, épais vers le bord (réticule « duplex »).
		for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
			draw_line(c + d * 2.0, c + d * r * 0.5, col, 1.2, true)
			draw_line(c + d * r * 0.5, c + d * r, col, 4.0, true)
		# Graduations (mil-dots) sur les fils fins.
		for k in range(1, 5):
			var o := r * 0.1 * k
			for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
				draw_circle(c + d * o, 1.6, col)
		draw_circle(c, 1.3, col)
	else:
		var r2 := h * 0.62
		var ring := Color(0.05, 0.05, 0.05, 0.9 * _reveal)
		draw_arc(c, h * 0.06, 0.0, TAU, 48, ring, 1.6, true)
		draw_circle(c, 2.0, Color(0.85, 0.12, 0.08, 0.95 * _reveal))
		for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN]:
			draw_line(c + d * r2 * 0.35, c + d * r2, ring, 3.0, true)
