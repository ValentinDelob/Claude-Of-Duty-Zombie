class_name HubMenu
extends Control
## Menu du hub (Échap au niveau des onglets, Start ; HUB_PLAN §2, D3) : voile
## sombre et panneau au centre, REPRENDRE, OPTIONS, DOSSIER DE COMBAT, ÉCRAN
## TITRE, QUITTER LE JEU. Retour (Échap / B / clic hors du panneau) : ferme.
## Pas de maquette dédiée : même style que les fenêtres de la maquette
## (voile .veil, panneau .pnl à en-tête rouge, boutons .btn).

var hub: Node
var buttons: Array[HubButton] = []
var resume_button: HubButton
var panel: HubBox

signal closed


func _init(owner_hub: Node) -> void:
	hub = owner_hub
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func _ready() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	panel = HubBox.new(Lang.t("MENU DU HUB", "HUB MENU"), "", true, false)
	panel.custom_minimum_size = Vector2(HubStyle.px(380), 0)
	center.add_child(panel)
	var v := HubBox.vbox(10)
	panel.content.add_child(HubBox.pad(v, 18, 18, 18, 18))
	resume_button = _add(v, Lang.t("REPRENDRE", "RESUME"), close, HubButton.PRIMARY,
			Lang.t("Revenir au hub.", "Back to the hub."))
	_add(v, "OPTIONS", func(): hub.open_screen("options"), HubButton.NORMAL,
			Lang.t("Commandes, affichage, son, taille des menus.", "Controls, display, sound, menu size."))
	_add(v, Lang.t("DOSSIER DE COMBAT", "COMBAT RECORD"), func(): hub.open_screen("career"), HubButton.NORMAL,
			Lang.t("Vos statistiques de survie, partie après partie.", "Your survival stats, game after game."))
	_add(v, Lang.t("ÉCRAN TITRE", "TITLE SCREEN"), func(): hub.to_title(), HubButton.NORMAL,
			Lang.t("Revenir au menu titre.", "Back to the title menu."))
	_add(v, Lang.t("QUITTER LE JEU", "QUIT GAME"), func(): hub.quit_game(), HubButton.DANGER,
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


func _add(v: VBoxContainer, t: String, cb: Callable, kind: String, hint: String) -> HubButton:
	var b := HubButton.make(t, cb, kind, hint)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_entered.connect(func(): hub.set_hint(hint))
	v.add_child(b)
	buttons.append(b)
	return b


func open() -> void:
	visible = true
	resume_button.grab_focus.call_deferred()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func is_open() -> bool:
	return visible


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.62))


func _gui_input(event: InputEvent) -> void:
	# Clic sur le voile, hors du panneau : fermer.
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and (mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT):
		if not panel.get_global_rect().has_point(mb.global_position):
			accept_event()
			close()
