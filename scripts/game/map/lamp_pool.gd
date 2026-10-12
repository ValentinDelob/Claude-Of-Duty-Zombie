class_name LampPool
extends SpotLight3D
## Flaque de lumière d'une lampe sous abat-jour (LampStyle) : projecteur
## dirigé vers le bas, enfant de la lampe (OmniLight3D), qui recopie à
## chaque image sa couleur, son énergie (x `ratio`) et sa visibilité : le
## courant (PowerGrid) et le grésillement (LightFlicker) ne pilotent que la
## lampe. Ombre et distances de fondu : RenderQuality.apply_lamp.

## Énergie de la flaque / énergie de la lampe.
var ratio := 1.0
var _lamp: OmniLight3D


func _ready() -> void:
	_lamp = get_parent() as OmniLight3D
	sync()


func _process(_delta: float) -> void:
	sync()


func sync() -> void:
	if _lamp == null:
		return
	light_energy = _lamp.light_energy * ratio
	light_color = _lamp.light_color
