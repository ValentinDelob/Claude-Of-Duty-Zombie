class_name BeaconSpin
extends Node3D
## Gyrophare (luminaire « gyrophare », LampStyle.BEACON) : deux faisceaux
## opposés (SpotLight3D sans ombre) qui tournent autour de l'axe vertical,
## enfants de la lampe (OmniLight3D) dont ils recopient couleur et énergie
## (x `beam`) à chaque image, comme LampPool : le courant et le grésillement
## ne pilotent que la lampe. Un seul script par gyrophare, aucun calcul
## lourd. Distances de fondu : RenderQuality.apply_lamp.

var beams: Array[SpotLight3D] = []
var ratio := 3.5
var period := 1.6
var _lamp: OmniLight3D
var _t := 0.0


static func make(style: Dictionary) -> BeaconSpin:
	var b := BeaconSpin.new()
	b.name = "Beacon"
	b.ratio = float(style.get("beam", 3.5))
	b.period = maxf(0.2, float(style.get("period", 1.6)))
	for k in 2:
		var sp := SpotLight3D.new()
		sp.name = "Beam%d" % k
		sp.spot_angle = float(style.get("beam_angle", 20.0))
		sp.spot_range = float(style.get("beam_range", 9.0))
		sp.spot_attenuation = 0.9
		sp.spot_angle_attenuation = 1.4
		sp.light_volumetric_fog_energy = float(style.get("beam_fog", 2.0))
		sp.shadow_enabled = false
		# Légèrement vers le bas : les faisceaux balaient murs et sol.
		sp.rotation = Vector3(-0.18, k * PI, 0.0)
		b.add_child(sp)
		b.beams.append(sp)
	return b


func _ready() -> void:
	_lamp = get_parent() as OmniLight3D
	# Départ décalé d'un gyrophare à l'autre (pas tous en phase).
	_t = fposmod(global_position.x * 0.37 + global_position.z * 0.61, period) if is_inside_tree() else 0.0
	sync()


func _process(delta: float) -> void:
	_t += delta
	rotation.y = fmod(_t * TAU / period, TAU)
	sync()


func sync() -> void:
	if _lamp == null:
		return
	for sp in beams:
		sp.light_energy = _lamp.light_energy * ratio
		sp.light_color = _lamp.light_color
