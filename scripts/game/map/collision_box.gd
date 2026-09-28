class_name CollisionBox
extends StaticBody3D
## Pavé de collision plein et invisible (aucun maillage) : ruines
## infranchissables, rangées de fauteuils, collisions des objets du décor.
## Toujours créé par le jeu à partir de données (layout.json, fichiers
## <modèle>.collision.json), jamais exporté depuis Blender.
##
## barrier = true : couche BARRIER (arrête joueurs et zombies, les balles
## passent : fauteuils, gravats bas) ; false : couche du décor (arrête aussi
## les balles et les grenades).

var size := Vector3.ONE
var barrier := false
var surface := "concrete"


## `center` et `yaw` dans le repère du parent ; `size` en mètres.
static func make(center: Vector3, box_size: Vector3, yaw := 0.0, is_barrier := false, surf := "concrete") -> CollisionBox:
	var b := CollisionBox.new()
	b.size = box_size
	b.barrier = is_barrier
	b.surface = surf
	b.transform = Transform3D(Basis(Vector3.UP, yaw), center)
	return b


## D'après une entrée de données : {center, size, yaw, barrier, surface}.
static func from_dict(d: Dictionary) -> CollisionBox:
	return make(MeshMapLayout.vec(d.center), MeshMapLayout.vec(d.size), float(d.get("yaw", 0.0)),
			bool(d.get("barrier", false)), String(d.get("surface", "concrete")))


func _init() -> void:
	collision_mask = 0


func _ready() -> void:
	collision_layer = Barricade.BARRIER_LAYER if barrier else 1
	set_meta("surface", surface)  # effets d'impact (Fx.surface_of)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.set_meta("surface", surface)
	add_child(cs)
