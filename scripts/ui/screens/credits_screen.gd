extends MenuScreen
## Crédits : générique qui défile lentement (en boucle). ↑ / ↓ ou la molette
## accélèrent / inversent le défilement.

const SPEED := 34.0  # px/s
const WIDTH := 700.0
const CLIP_TOP := 112.0
const CLIP_H := 500.0
const EDGE := 70.0  # hauteur des fondus haut / bas

const LINES := [
	["h1", "CALL OF CLAUDE ZOMBIE"],
	["p", "Survie coopérative en bunker, de 1 à 4 joueurs."],
	["gap"],
	["role", "CONÇU ET DÉVELOPPÉ PAR"],
	["name", "Claude (Anthropic)"],
	["p", "pour Valentin"],
	["gap"],
	["role", "PROGRAMMATION · CONCEPTION DE JEU"],
	["name", "Claude"],
	["role", "DIRECTION ARTISTIQUE · ÉCLAIRAGE"],
	["name", "Claude"],
	["role", "CONCEPTION SONORE · MUSIQUE"],
	["name", "Claude"],
	["gap"],
	["role", "MOTEUR"],
	["name", "Godot Engine 4"],
	["p", "Moteur libre et open source (licence MIT) — godotengine.org"],
	["gap"],
	["role", "SONS"],
	["p", "100 % procéduraux : chaque tir, grognement, cloche et nappe est synthétisé par du code. Aucun échantillon enregistré."],
	["role", "GRAPHISMES"],
	["p", "100 % procéduraux : maillages, matériaux, textures et effets générés par des shaders et des scripts. Aucune image externe."],
	["role", "POLICES"],
	["p", "Polices système de la machine du joueur."],
	["gap"],
	["role", "REMERCIEMENTS"],
	["name", "Valentin"],
	["p", "pour l'idée, les parties de test et la patience."],
	["name", "La communauté Godot"],
	["p", "pour un moteur qui se laisse tout construire en code."],
	["name", "Les survivants"],
	["p", "qui tiendront jusqu'à la manche 100. Ou presque."],
	["gap"],
	["gap"],
	["p", "Aucun zombie n'a été maltraité pendant le développement."],
	["p", "Les autres, si."],
	["gap"],
	["gap"],
]

var _clip: Control
var _roll: VBoxContainer
var _boost := 1.0


func enter(_args := {}) -> void:
	var t := title("CRÉDITS", 46)
	t.position = Vector2(96, 34)
	add_child(t)
	_clip = Control.new()
	_clip.clip_contents = true
	_clip.position = Vector2(96, CLIP_TOP)
	_clip.size = Vector2(WIDTH, CLIP_H)
	_clip.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_clip)
	_roll = vbox(6)
	_roll.custom_minimum_size = Vector2(WIDTH, 0)
	_roll.size.x = WIDTH
	_clip.add_child(_roll)
	for l in LINES:
		_roll.add_child(_line(l))
	_roll.position.y = CLIP_H * 0.45
	var back_btn := button("RETOUR", back, "↑ ↓ : faire défiler.")
	back_btn.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	back_btn.offset_left = 96
	back_btn.offset_top = -120
	back_btn.offset_bottom = -76
	add_child(back_btn)
	focus_later(back_btn)


func _line(l: Array) -> Control:
	match l[0]:
		"h1":
			var h := MenuStyle.title(l[1], 40)
			h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			return h
		"role":
			var r := UiStyle.label(l[1], 16, Color(0.66, 0.16, 0.1), "impact")
			r.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			return r
		"name":
			var n := UiStyle.label(l[1], 28, UiStyle.BONE, "impact")
			n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			return n
		"p":
			var p := UiStyle.label(l[1], 18, UiStyle.DIM)
			p.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			p.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			p.custom_minimum_size = Vector2(WIDTH, 0)
			return p
	var g := Control.new()
	g.custom_minimum_size = Vector2(0, 34)
	return g


func _process(delta: float) -> void:
	var dir := 1.0
	if Input.is_action_pressed("ui_down"):
		_boost = 7.0
	elif Input.is_action_pressed("ui_up"):
		_boost = 7.0
		dir = -1.0
	else:
		_boost = move_toward(_boost, 1.0, delta * 8.0)
	_roll.position.y -= SPEED * _boost * dir * delta
	var h := _roll.size.y
	if _roll.position.y < -h:
		_roll.position.y = CLIP_H
	elif _roll.position.y > CLIP_H:
		_roll.position.y = -h
	# Fondu des lignes près des bords haut et bas.
	for c in _roll.get_children():
		var ci := c as Control
		var y := _roll.position.y + ci.position.y + ci.size.y * 0.5
		var a := clampf(y / EDGE, 0.0, 1.0) * clampf((CLIP_H - y) / EDGE, 0.0, 1.0)
		ci.modulate.a = a * a * (3.0 - 2.0 * a)


func _input(event: InputEvent) -> void:
	_wheel(event)


func _wheel(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_roll.position.y -= 40.0
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_roll.position.y += 40.0


## Position de défilement (pour les tests).
func scroll_y() -> float:
	return _roll.position.y


func back() -> void:
	menu.go_back()
