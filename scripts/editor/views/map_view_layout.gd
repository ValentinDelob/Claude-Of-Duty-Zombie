class_name MapViewLayout
extends Control
## Zone des vues de l'éditeur de cartes (docs/EDITOR_VIEWS.md, § 5) : les
## fenêtres de vue (MapView), la barre rapide et l'inventaire.

var ed: MapEditor
## Vues de la zone, dans l'ordre.
var views: Array[MapView] = []


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Ajoute une vue, qui remplit la zone.
func add_view(v: MapView) -> void:
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(v)
	views.append(v)
