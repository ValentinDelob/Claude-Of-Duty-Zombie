extends AutotestScenario
## @rendu : a besoin du rendu (lancé avec fenêtre hors écran par check.sh).
## KINO V2, salle de théâtre et salle de projection : captures depuis les
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
	p = await AutotestHelpers.start_solo_game(self, "kino_v2")
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
	await view("depuis_scene", cod(260, 1000, 0), cod(-150, -300, 200))
	# Depuis l'allée centrale vers la scène et l'écran.
	await view("depuis_allee", cod(0, 250, -20), cod(0, 1300, 250))
	# Coin de Juggernog, sous la galerie.
	await view("coin_juggernog", cod(-230, -200, 5), cod(-330, -480, 60))
	# Boîte au milieu des sièges et flanc ouest (arcades, balcon).
	await view("boite_flanc_ouest", cod(140, 100, -10), cod(-770, 300, 250))
	# Tour du téléporteur sur l'avant-scène.
	await view("teleporteur", cod(-60, 1000, 0), cod(-306, 1160, 200))
	# Salle de projection : la machine d'amélioration et le projecteur.
	await view("salle_projection", cod(60, -250, 322), cod(6, -487, 360))
	await view("salle_projection_projecteur", cod(80, -400, 322), cod(-62, -103, 360))
	# Baies de la cabine ouvertes : on voit la salle d'en haut et les balles y
	# arrivent (seuls les pavés barrières ferment le passage aux joueurs).
	await view("depuis_baie", cod(95, -120, 322), cod(120, 350, -20))
	var space := p.get_world_3d().direct_space_state
	for pair in [[cod(-62, -120, 385), cod(-40, 300, -15)], [cod(95, -120, 385), cod(150, 250, -10)]]:
		var q := PhysicsRayQueryParameters3D.create(pair[0], pair[1], 1, [p.get_rid()])
		var r := space.intersect_ray(q)
		var reach: float = pair[0].distance_to(r.position) if not r.is_empty() else INF
		at.check(reach > pair[0].distance_to(pair[1]) - 1.5, "tir depuis la baie jusqu'au parterre (%.1f m)" % reach)
