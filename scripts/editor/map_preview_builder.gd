class_name MapPreviewBuilder
extends MeshMapBuilder
## Aperçu 3D de l'éditeur de cartes (MapPreviewWorld) : la carte construite
## par le CODE DU JEU (MeshMapBuilder, MeshMapGeometry, MapProps.add_lamp,
## EditorPrefabs), découpée en trois morceaux reconstruits séparément quand
## seule une partie de la carte change :
##   build_architecture : murs, sols, plafonds, escaliers, garde-corps (MeshMapGeometry)
##   build_decor        : décor posé, objets répétés, écrans, pavés de collision
##   build_lamps        : lampes automatiques et luminaires (courant, grésillement)
## Même enchaînement que MeshMapBuilder.build() (le test « même géométrie que
## le jeu » compare les deux sur DRAFT ARENA) ; chaque morceau a sa racine, son
## réseau électrique (PowerGrid) et son grésillement (LightFlicker).

## Clés de la description qui alimentent chaque morceau (reconstruit si
## l'une d'elles change).
const ARCH_KEYS := ["rooms", "walls", "blocks", "slabs", "stairs", "rails", "obliques", "prop_materials"]
const DECOR_KEYS := ["props", "instances", "screens", "beams", "shafts", "blockers", "prop_materials", "models_dir", "rooms"]


func _init(layout_data: Dictionary) -> void:
	super(layout_data, "")


func build_architecture(parent: Node3D) -> void:
	_make_root(parent, "Architecture")
	var scene: Node3D = MeshMapGeometry.build(layout)
	scene.name = "Architecture"
	root.add_child(scene)
	var floors := {}
	for r in layout.get("rooms", []):
		floors[r.id] = _room_floor(r)
	_prop_mats = layout.get("prop_materials", {})
	_setup_nodes(scene, func(room: String) -> float: return float(floors.get(room, 0.0)))


func build_decor(parent: Node3D) -> void:
	_make_root(parent, "Decor")
	_prop_mats = layout.get("prop_materials", {})
	_build_props()
	_build_instances()
	_build_screens()
	_build_blockers()


## Lampes : même boucle que MeshMapBuilder.build (une lampe automatique sur
## cinq grésille ; les luminaires de l'éditeur passent par _fixture_lamp).
func build_lamps(parent: Node3D) -> void:
	_make_root(parent, "Lamps")
	_prop_mats = layout.get("prop_materials", {})
	var lamps: Array = layout.get("markers", {}).get("lamps", [])
	for i in lamps.size():
		var l: Dictionary = lamps[i]
		if l.has("fixture"):
			_fixture_lamp(l)
			continue
		add_lamp(MeshMapLayout.vec(l.p), float(l.get("energy", 2.2)), float(l.get("range", 10.0)), i % 5 == 3)


## Empreinte des données d'un morceau (reconstruit seulement si elle change).
static func part_hash(layout_data: Dictionary, keys: Array) -> int:
	var parts := []
	for k in keys:
		parts.append(layout_data.get(k))
	return hash(parts)


static func lamps_hash(layout_data: Dictionary) -> int:
	return hash(layout_data.get("markers", {}).get("lamps", []))


## Objets de jeu (portes, fenêtres, atouts, armes, boîte...) : tous les
## marqueurs sauf les lampes, avec les réglages de la carte.
static func markers_hash(layout_data: Dictionary) -> int:
	var m: Dictionary = layout_data.get("markers", {}).duplicate()
	m.erase("lamps")
	return hash([m, layout_data.get("map_def", {}), layout_data.get("zones", {})])
