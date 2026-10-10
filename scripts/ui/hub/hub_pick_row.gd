class_name HubPickRow
extends HubRow
## Ligne de liste CHOISISSABLE du hub (classe .row de la maquette, avec
## .row.sel et .row.lock) : prend le focus au clavier, à la manette (croix)
## et au clic ; la ligne qui a le focus — ou la dernière choisie, quand le
## focus est passé à la fiche voisine — est dessinée sélectionnée (fond brun,
## barre jaune de 4 px). Entrée / A / double clic : `activated`.
## `locked` : objet verrouillé (texte grisé par l'appelant), toujours
## choisissable pour lire sa fiche.

## La ligne a reçu le focus (choix de l'élément affiché à côté).
signal chosen
## Entrée / A / double clic sur la ligne.
signal activated

## Donnée de l'appelant (identifiant d'exemplaire…).
var key := ""
var locked := false
## Sélection gardée quand le focus part ailleurs (fiche ouverte à côté).
var sticky := false:
	set(v):
		sticky = v
		_update_look()
## Aide affichée dans la barre d'invites quand la ligne a le focus.
var hint := ""


func _init(k := ROW, height := -1.0, vertical := false, sep := 10.0) -> void:
	super(k, height, vertical, sep)
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_entered.connect(func():
		Audio.play_ui(MenuStyle.SND_MOVE, MenuStyle.VOL_MOVE)
		_update_look()
		chosen.emit())
	focus_exited.connect(_update_look)


func _update_look() -> void:
	selected = has_focus() or sticky


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if not has_focus():
			grab_focus()
		if mb.double_click:
			activated.emit()
		return
	if event.is_action_pressed("ui_accept"):
		accept_event()
		Audio.play_ui(MenuStyle.SND_SELECT, MenuStyle.VOL_SELECT)
		activated.emit()
