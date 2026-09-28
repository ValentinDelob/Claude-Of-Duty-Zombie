extends AutotestScenario
## @rendu : a besoin du rendu (lancé avec fenêtre hors écran par check.sh).
## KINO, salle de théâtre et salle de projection : captures depuis les
## points de vue des références de BO1 (docs/reference/kino/images/theater_*),
## courant rétabli, pour comparer le décor à la carte d'origine.

var game: Game
var p: Player
const K := 0.0254


## Point en unités CoD (x Est, y Nord, z haut) -> monde (voir make_layout.py).
static func cod(x: float, y: float, z: float) -> Vector3:
	return Vector3(x * K + 75.0, z * K, -y * K + 72.0)


func view(label: String, eye: Vector3, target: Vector3) -> void:
	p.teleport_to(eye)
	await seconds(0.2)
	AutotestHelpers.aim_at(p, target)
	await seconds(0.8)
	await at.screenshot(label)


func run() -> void:
	timeout_sec = 90
	p = await AutotestHelpers.start_solo_game(self, "kino")
	if p == null:
		return
	game = Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	for zid in game.zombies.zombies.keys():
		game.zombies.despawn(zid)
	(game.interact.get_obj("power") as PowerSwitch).srv_use(1)
	await until(func(): return game.power_on, 3.0, "courant")
	await seconds(5.0)  # bandeau « le courant est rétabli »
	# Depuis la scène (estrade de la tourelle) vers la salle et le fond.
	await view("depuis_scene", cod(330, 960, 0), cod(-150, -300, 200))
	# Depuis l'allée centrale vers la scène et l'écran.
	await view("depuis_allee", cod(0, 250, -20), cod(0, 1300, 250))
	# Coin de Juggernog, sous la galerie.
	await view("coin_juggernog", cod(-230, -200, 5), cod(-330, -480, 60))
	# Boîte au milieu des sièges et flanc ouest (arcades, balcon).
	await view("boite_flanc_ouest", cod(140, 100, -10), cod(-770, 300, 250))
	# Points de vue des photos de référence : depuis le balcon du fond vers la scène,
	# depuis la scène vers le fond (voûte, balcons, baie de la cabine).
	await view("photo_balcon_fond", cod(450, -350, 190), cod(0, 1150, 120))
	await view("photo_scene_vers_fond", cod(150, 1100, 0), cod(-100, -300, 420))
	# Coulisses : passage de 3 m autour du bloc de l'écran, boîte contre le mur du fond.
	await view("coulisses_boite", cod(-440, 1850, 0), cod(1, 1842, 40))
	# Tour du téléporteur sur l'avant-scène.
	await view("teleporteur", cod(-60, 1000, 0), cod(-306, 1160, 200))
	# Salle de projection : la machine d'amélioration et le projecteur.
	await view("salle_projection", cod(60, -250, 322), cod(6, -487, 360))
	await view("salle_projection_projecteur", cod(80, -400, 322), cod(-62, -103, 360))
	# Baie de la cabine : fente de 1 m à hauteur des yeux sur 85 % du mur. On voit
	# la scène et on tire au milieu de la salle (seul un pavé barrière ferme le
	# passage) ; le mur arrête les tirs au-dessus et au-dessous de la fente.
	await view("depuis_baie", cod(95, -120, 322), cod(60, 1000, 150))
	await view("depuis_baie_parterre", cod(-40, -120, 322), cod(-40, 650, -30))
	var space := p.get_world_3d().direct_space_state
	var eye := 322.0 + 1.62 / K
	for pair in [[cod(-62, -120, eye), cod(-40, 700, -30)], [cod(120, -120, eye), cod(150, 600, -25)],
			[cod(-140, -120, eye), cod(-300, 1000, 20)]]:
		at.check(_clear(space, pair[0], pair[1]), "tir depuis la baie jusqu'à la salle et la scène")
	at.check(not _clear(space, cod(0, -120, eye + 45), cod(0, 700, eye + 45)), "mur au-dessus de la fente")
	at.check(not _clear(space, cod(0, -120, 340), cod(0, 700, 340)), "mur au-dessous de la fente")


## Aucun décor (couche 1, celle des balles) entre a et b, à 1,5 m près du but.
func _clear(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> bool:
	var r := space.intersect_ray(PhysicsRayQueryParameters3D.create(a, b, 1, [p.get_rid()]))
	return r.is_empty() or a.distance_to(r.position) > a.distance_to(b) - 1.5
