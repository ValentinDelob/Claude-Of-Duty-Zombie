class_name Hub2Menu
extends Control
## Menu du hub (B / Échap au LABO, START dans le menu : fermer ; HUB_PLAN §2,
## D3) : voile sombre et panneau de verre au centre, REPRENDRE, OPTIONS,
## DOSSIER DE COMBAT, ÉCRAN TITRE, QUITTER LE JEU. Retour (Échap / B / clic
## hors du panneau) : ferme. Pas de maquette dédiée : style des fenêtres du
## hub (Hub2Modal : voile, verre, titre Chakra Petch ; boutons des maquettes).
## Gardé en vie par Hub2Screen (open / close), contrairement à Hub2Modal.

const WIDTH := 380.0

var hub: Node
var buttons: Array[Hub2Button] = []
var resume_button: Hub2Button
var title_button: Hub2Button
var panel: Hub2Box
var _title_armed := false

signal closed


func _init(owner_hub: Node) -> void:
	hub = owner_hub
	name = "HubMenu"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func _ready() -> void:
	var veil := ColorRect.new()
	veil.color = Hub2Style.shade(0.7)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)
	add_child(Hub2Style.blur_barrier())
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	panel = Hub2Box.new()
	panel.glass(Hub2Style.GLASS_STRONG, Hub2Style.white_a(0.12), 1.0)
	panel.pad(22, 24)
	panel.custom_minimum_size.x = Hub2Style.px(WIDTH)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(panel)
	var v := Hub2Ui.vbox(10)
	panel.add_child(v)
	var t := Hub2Text.new()
	t.setup(Lang.t("MENU DU HUB", "HUB MENU"), Hub2Style.CHAKRA, 700, 20, Hub2Style.TEXT, 0.08)
	var tm := MarginContainer.new()
	tm.add_theme_constant_override("margin_bottom", int(Hub2Style.px(4)))
	tm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tm.add_child(t)
	v.add_child(tm)
	resume_button = _add(v, Lang.t("REPRENDRE", "RESUME"), close, "primary",
			Lang.t("Revenir au hub.", "Back to the hub."))
	_add(v, "OPTIONS", func(): hub.open_screen("options"), "normal",
			Lang.t("Commandes, affichage, son, taille des menus.", "Controls, display, sound, menu size."))
	_add(v, Lang.t("DOSSIER DE COMBAT", "COMBAT RECORD"), func(): hub.open_screen("career"), "normal",
			Lang.t("Vos statistiques de survie, partie après partie.", "Your survival stats, game after game."))
	title_button = _add(v, Lang.t("ÉCRAN TITRE", "TITLE SCREEN"), _on_title, "normal",
			Lang.t("Revenir au menu titre.", "Back to the title menu."))
	_add(v, Lang.t("QUITTER LE JEU", "QUIT GAME"), func(): hub.quit_game(), "danger",
			Lang.t("Retour à la surface.", "Back to the surface."))
	# Le focus reste dans le menu (rien derrière le voile n'est atteignable).
	for i in buttons.size():
		var b := buttons[i]
		b.focus_neighbor_top = b.get_path_to(buttons[(i - 1 + buttons.size()) % buttons.size()])
		b.focus_neighbor_bottom = b.get_path_to(buttons[(i + 1) % buttons.size()])
		b.focus_neighbor_left = b.get_path_to(b)
		b.focus_neighbor_right = b.get_path_to(b)
		b.focus_previous = b.focus_neighbor_top
		b.focus_next = b.focus_neighbor_bottom


## Bouton du menu (hauteur 40) : « primary » jaune, « normal » liseré clair,
## « danger » liseré rouge.
func _add(v: VBoxContainer, text: String, cb: Callable, kind: String, hint_text: String) -> Hub2Button:
	var b := Hub2Button.new()
	b.hint = hint_text
	b.custom_minimum_size.y = Hub2Style.px(40)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.box.pad(0, 18)
	var t := Hub2Text.new()
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.align = HORIZONTAL_ALIGNMENT_CENTER
	b.add_content(t)
	b.set_meta("text", t)
	_style(b, text, kind)
	b.pressed.connect(cb)
	v.add_child(b)
	buttons.append(b)
	return b


func _style(b: Hub2Button, text: String, kind: String) -> void:
	var t: Hub2Text = b.get_meta("text")
	match kind:
		"primary":
			b.box.flat(Hub2Style.YELLOW)
			t.setup(text, Hub2Style.CHAKRA, 700, 14, Hub2Style.INK, 0.14)
		"danger":
			b.box.flat(Color(0, 0, 0, 0), Hub2Style.BAD, 1.0)
			t.setup(text, Hub2Style.CHAKRA, 700, 14, Hub2Style.BAD, 0.14)
		_:
			b.box.flat(Color(0, 0, 0, 0), Hub2Style.text_a(0.4), 1.0)
			t.setup(text, Hub2Style.CHAKRA, 700, 14, Hub2Style.TEXT, 0.14)
	b.set_meta("kind", kind)


## Texte affiché d'un bouton du menu.
static func button_label(b: Hub2Button) -> String:
	return (b.get_meta("text") as Hub2Text).text


## ÉCRAN TITRE : en coop (salon ouvert), deux appuis — le premier demande
## confirmation (la session sera quittée, HUB_PLAN §2).
func _on_title() -> void:
	if Net.is_online() and not _title_armed:
		_title_armed = true
		_style(title_button, Lang.t("CONFIRMER : QUITTER LE SALON", "CONFIRM: LEAVE THE LOBBY"), "danger")
		title_button.hint = Lang.t("Le groupe continue sans vous ; appuyez encore pour revenir au menu titre.",
				"The group goes on without you; press again to go back to the title menu.")
		hub.set_hint(title_button.hint)
		return
	hub.to_title()


func is_title_armed() -> bool:
	return _title_armed


func _disarm_title() -> void:
	_title_armed = false
	if title_button:
		_style(title_button, Lang.t("ÉCRAN TITRE", "TITLE SCREEN"), "normal")
		title_button.hint = Lang.t("Revenir au menu titre.", "Back to the title menu.")


func open() -> void:
	_disarm_title()
	visible = true
	(func():
		if is_instance_valid(resume_button) and resume_button.is_inside_tree() and visible:
			resume_button.grab_focus()).call_deferred()


func close() -> void:
	if not visible:
		return
	visible = false
	_disarm_title()
	closed.emit()


func is_open() -> bool:
	return visible


func _gui_input(event: InputEvent) -> void:
	# Clic sur le voile, hors du panneau : fermer.
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and (mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT):
		if not panel.get_global_rect().has_point(mb.global_position):
			accept_event()
			close()
