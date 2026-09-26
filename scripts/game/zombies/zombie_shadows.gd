class_name ZombieShadows
extends RefCounted
## Ombres portées des zombies (lampes de la carte) limitées aux plus proches.
##
## Un zombie animé qui projette une ombre force chaque image le rendu complet
## de la carte cubique d'ombre des lampes proches (6 faces, décor compris).
## Seuls les `zombie_shadows` zombies les plus proches de la caméra (à moins de
## `zombie_shadow_dist` m, préréglage RenderQuality) projettent donc une ombre :
## ce sont les seules visibles au sol à l'écran ; au loin, dans la pénombre,
## l'absence d'ombre ne se voit pas. Appelé par ZombieManager (toutes les
## UPDATE_FRAMES images) ; choix avec hystérésis pour éviter le clignotement.

const UPDATE_FRAMES := 6
## Avantage (m) d'un zombie qui projette déjà une ombre dans le classement.
const HYSTERESIS := 1.5
## Mesures : impose le nombre de zombies à ombre (-1 : préréglage).
static var debug_count := -1


## Met à jour `cast_shadow` des zombies `alive` pour une caméra en `cam_pos`.
static func update(alive: Array[Zombie], cam_pos: Vector3, q: Dictionary) -> void:
	var count := int(q.get("zombie_shadows", 24)) if debug_count < 0 else debug_count
	var max_d := float(q.get("zombie_shadow_dist", 30.0)) if debug_count < 0 else INF
	var ranked := []
	for z: Zombie in alive:
		if z.mesh == null:
			continue
		var d := z.global_position.distance_to(cam_pos)
		if z.mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			d -= HYSTERESIS
		ranked.append([d, z])
	ranked.sort_custom(func(a, b): return a[0] < b[0])
	for i in ranked.size():
		var z: Zombie = ranked[i][1]
		var on := i < count and float(ranked[i][0]) < max_d
		var want := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if z.mesh.cast_shadow != want:
			z.mesh.cast_shadow = want


## Nombre de zombies qui projettent une ombre (tests).
static func casting(alive: Array[Zombie]) -> int:
	var n := 0
	for z: Zombie in alive:
		if z.mesh and z.mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			n += 1
	return n
