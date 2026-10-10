class_name ThrowableIcons
extends Control
## HUD : petites icônes de l'emplacement de grenade à gauche du compteur de
## munitions : grenades ou peluches leurres (une sorte à la fois). Lit la
## réserve répliquée du joueur local.

const SLOT := 22.0
const ICON_SCALE := 1.35

var game: Game
var _count := -1
var _kind := -1


func _init(g: Game = null) -> void:
	game = g
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(SLOT * ThrowableRules.SLOT_MAX + 12, 46)
	size_flags_vertical = Control.SIZE_SHRINK_END


func _process(_delta: float) -> void:
	if game == null:
		return
	var pd := game.session.local_data()
	if pd == null:
		return
	if pd.grenades != _count or pd.throwable != _kind:
		_count = pd.grenades
		_kind = pd.throwable
		queue_redraw()


func _draw() -> void:
	var y := size.y - 16.0
	var x := size.x - 16.0
	# De droite à gauche, en partant des munitions.
	for i in maxi(_count, 0):
		if _kind == ThrowableRules.Kind.DECOY:
			_draw_decoy(Vector2(x - i * SLOT, y))
		else:
			_draw_frag(Vector2(x - i * SLOT, y))


func _draw_frag(at_pos: Vector2) -> void:
	draw_set_transform(at_pos, 0.0, Vector2.ONE * ICON_SCALE)
	var c := Vector2.ZERO
	var body := Color(0.52, 0.58, 0.36, 0.95)
	var dark := Color(0.08, 0.09, 0.05, 0.9)
	draw_circle(c + Vector2(0, 2), 6.6, dark)
	draw_circle(c + Vector2(0, 2), 5.6, body)
	draw_rect(Rect2(c + Vector2(-2.5, -7), Vector2(5, 4)), body)
	# Cuillère et anneau.
	draw_line(c + Vector2(2.5, -6), c + Vector2(6, 3), Color(0.8, 0.8, 0.75, 0.9), 1.6)
	draw_arc(c + Vector2(-4.5, -6.5), 2.4, 0.0, TAU, 10, Color(0.8, 0.8, 0.75, 0.9), 1.2)


## Tête d'ours en peluche : oreilles, museau clair, nœud rouge.
func _draw_decoy(at_pos: Vector2) -> void:
	draw_set_transform(at_pos, 0.0, Vector2.ONE * ICON_SCALE)
	var c := Vector2.ZERO
	var fur := Color(0.55, 0.34, 0.16, 0.95)
	var dark := Color(0.05, 0.04, 0.03, 0.9)
	for s in [-1.0, 1.0]:
		draw_circle(c + Vector2(s * 4.6, -4.2), 2.9, dark)
		draw_circle(c + Vector2(s * 4.6, -4.2), 2.2, fur)
	draw_circle(c + Vector2(0, 1), 6.0, dark)
	draw_circle(c + Vector2(0, 1), 5.0, fur)
	draw_circle(c + Vector2(0, 3), 2.4, Color(0.85, 0.7, 0.5, 0.95))
	draw_rect(Rect2(c + Vector2(-3.5, 6.2), Vector2(7, 2)), Color(0.8, 0.1, 0.06, 0.95))
