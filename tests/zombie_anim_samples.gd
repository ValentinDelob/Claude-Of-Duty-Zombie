extends RefCounted
## Poses échantillonnées des animations des zombies (ZombieAnim, rampant de
## ZombieGibs) : met un zombie seul (hors partie) dans l'état voulu à
## l'instant `k` (0..1) de l'animation, sans simulation. Partagé par
## tests/test_zombie_voxel_anim.gd (interpénétrations) et le scénario avec
## rendu zombie_voxel_anims (planches d'images clés).

## [nom, classe de vitesse]
const ANIMS := [
	["marche", 0], ["course", 2], ["sprint", 3], ["sortie_du_sol", 0],
	["arrachage", 0], ["folie", 0], ["passage_fenetre", 0], ["attaque", 0],
	["attaque_fenetre", 0], ["rampant", 0], ["chute_rampant", 0],
	["mort_bascule", 0], ["mort_genoux", 0], ["mort_vrille", 0], ["mort_raide", 0],
]


static func speed_class(anim: String) -> int:
	for a in ANIMS:
		if a[0] == anim:
			return a[1]
	return 0


## Zombie seul (`parent` : nœud hôte), classe de vitesse de l'animation.
static func make(parent: Node, anim: String, variant := 7, zid := 95000) -> Zombie:
	var z := Zombie.new()
	z.setup(zid, variant, speed_class(anim), false)
	parent.add_child(z)
	z.set_process(false)
	z.set_physics_process(false)
	return z


## Pose de l'animation `anim` à l'instant `k` (0..1).
static func pose(z: Zombie, anim: String, k: float) -> void:
	var a := z.anim
	z.skel.position = Vector3.ZERO
	z.skel.rotation = Vector3.ZERO
	z.attack_t = -1.0
	z.attack_through = false
	z.tear_frenzy = false
	z.crawl_t = -1.0
	z.state = Zombie.State.CHASE
	z.anim_speed = 0.0
	match anim:
		"marche", "course", "sprint":
			z.anim_speed = Zombie.SPEEDS[z.speed_class]
			a.run_k = ZombieAnim._run_target(z.speed_class)
			a.sprint_k = 1.0 if z.speed_class >= 3 else 0.0
			z.gait_phase = k * TAU
			_step(z, 0.0)
		"sortie_du_sol":
			z.state = Zombie.State.EMERGE
			z._state_time = k * Zombie.EMERGE_TIME
			_step(z, 0.0)
		"arrachage", "folie":
			z.state = Zombie.State.BARRIER
			z.tear_frenzy = anim == "folie"
			z.tear_t = k * BarricadeRules.TEAR_PULL if anim == "arrachage" else 0.3 + k * 1.0
			_step(z, 0.0)
		"passage_fenetre":
			z.state = Zombie.State.VAULT
			z._state_time = k * BarricadeRules.VAULT_TIME
			_step(z, 0.0)
		"attaque", "attaque_fenetre":
			if anim == "attaque_fenetre":
				z.state = Zombie.State.BARRIER
				z.tear_frenzy = true
				z.tear_t = 1.0
				z.attack_through = true
			z.attack_t = clampf(k, 0.0, 0.999)
			_step(z, 0.0)
			z.attack_t = -1.0
		"rampant", "chute_rampant":
			z.anim_speed = ZombieGibs.CRAWL_SPEED if anim == "rampant" else 0.0
			z.crawl_t = 1.5 + k * 2.0 if anim == "rampant" else k * ZombieGibs.CRAWL_FALL_TIME
			z.gait_phase = k * TAU
			ZombieGibs.crawl_pose(z, 0.0)
			z.crawl_t = -1.0
		_:
			if anim.begins_with("mort"):
				var style := {"mort_bascule": ZombieAnim.Death.TOPPLE, "mort_genoux": ZombieAnim.Death.CRUMPLE,
						"mort_vrille": ZombieAnim.Death.SPIN, "mort_raide": ZombieAnim.Death.STIFF}[anim] as int
				_step(z, 0.0)
				a.start_death(false)
				a.death_style = style
				# Chute procédurale (qualité BASSE, plafond de ragdolls atteint) :
				# images successives jusqu'à l'instant voulu.
				var t := 0.0
				var dt := 1.0 / 30.0
				var end := k * Zombie.DEATH_SETTLE_TIME
				while t < end:
					t += dt
					a.death(dt, t, 1.0)


static func _step(z: Zombie, dt: float) -> void:
	z.anim.pose(dt)
