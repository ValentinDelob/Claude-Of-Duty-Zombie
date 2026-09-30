class_name EditorOptions
extends MenuHost
## OPTIONS du jeu ouvertes depuis l'éditeur de cartes (bouton ⚙ de la barre
## du haut, Fichier > Options) : le même écran que le menu principal et le menu
## pause (MainMenu.SCREENS.options), sur un voile qui laisse voir l'éditeur,
## ouvert sur l'onglet JEU et la TAILLE DE L'INTERFACE DE L'ÉDITEUR, appliquée
## en direct derrière le voile. RETOUR ou Échap : retour à l'éditeur.
## Posé dans son propre CanvasLayer (open_in) : il garde le thème et la taille
## du menu du jeu, jamais ceux de l'éditeur (EditorUi.SKIP).

signal closed

var ed: MapEditor
var _layer: CanvasLayer
var _hint: Label


## Ouvre les options par-dessus l'éditeur `editor`.
static func open_in(editor: MapEditor) -> EditorOptions:
	var layer := CanvasLayer.new()
	layer.name = "OptionsLayer"
	layer.layer = 20
	layer.set_meta(EditorUi.SKIP, true)
	editor.add_child(layer)
	var o := EditorOptions.new()
	o.name = "EditorOptions"
	o.ed = editor
	o._layer = layer
	layer.add_child(o)
	o._open()
	return o


func _open() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.86)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	_hint = UiStyle.label("", 17, UiStyle.DIM)
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hint.offset_left = 112
	_hint.offset_top = -64
	_hint.offset_right = 1100
	_hint.offset_bottom = -36
	add_child(_hint)
	var s: MenuScreen = load(MainMenu.SCREENS.options).new()
	s.menu = self
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	current = s
	current_name = "options"
	add_child(s)
	s.enter({"tab": "game", "focus": "editor_ui_scale"})


func go_back() -> void:
	Audio.play_ui(MenuStyle.SND_BACK, -4.0)
	close()


func close() -> void:
	if current != null:
		var s := current
		current = null
		current_name = ""
		s.exit()
		var fo := get_viewport().gui_get_focus_owner()
		if fo != null and is_ancestor_of(fo):
			fo.release_focus()
	closed.emit()
	if _layer != null:
		_layer.queue_free()
	else:
		queue_free()


func set_hint(t: String) -> void:
	if _hint != null:
		_hint.text = t


## Échap (ou B / Retour) : l'écran d'options revient en arrière (annule une
## réaffectation de touche en cours, sinon ferme).
func _unhandled_input(event: InputEvent) -> void:
	if current == null:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		current.back()
		get_viewport().set_input_as_handled()
