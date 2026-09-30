extends TestCase
## Effets locaux des atouts, testés seuls (sans partie) : onde de NOVA FLOP
## (NovaFx.play via PerkSystem._cl_nova_blast) sur un nœud Fx seul sous
## `host`, et choix de cible de DEADEYE DRAM (DeadeyeAim._pick) sans partie,
## sans zombies, puis avec une liste de zombies vide.

var _saved_instance: Game


func before_each() -> void:
	_saved_instance = Game.instance


func after_each() -> void:
	Game.instance = _saved_instance


## Partie factice hors de l'arbre (aucun _ready) dont seul fx_root est rempli.
func _fake_game(fx: Fx) -> Game:
	var g := Game.new()
	g.fx_root = fx
	return g


func _rings(fx: Fx) -> int:
	var n := 0
	for c in fx.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh is TorusMesh:
			n += 1
	return n


func test_nova_blast_fx_creates_and_frees_rings() -> void:
	var fx := Fx.new()
	host.add_child(fx)
	var g := _fake_game(fx)
	var ps := PerkSystem.new()
	ps.game = g
	var before := fx.get_child_count()
	ps._cl_nova_blast(Vector3(2, 0, 3))
	assert_eq(_rings(fx), 2, "deux anneaux d'onde de choc")
	assert_eq(fx.get_child_count(), before + 2, "seulement les anneaux ajoutés (le reste est en pool)")
	for c in fx.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh is TorusMesh:
			assert_near((c as Node3D).global_position.y, 0.08, 0.001, "anneau au ras du sol")
	# Les anneaux se libèrent seuls à la fin de leur animation (≈ 0,6 s).
	var t0 := Time.get_ticks_msec()
	while _rings(fx) > 0 and Time.get_ticks_msec() - t0 < 1500:
		await host.get_tree().process_frame
	assert_eq(_rings(fx), 0, "anneaux libérés après l'animation")
	ps.free()
	g.free()
	fx.queue_free()


func test_nova_fx_repeated_blasts() -> void:
	var fx := Fx.new()
	host.add_child(fx)
	var g := _fake_game(fx)
	for i in 5:
		NovaFx.play(g, Vector3(i, 0, 0))
	assert_eq(_rings(fx), 10, "deux anneaux par explosion")
	g.free()
	fx.free()


func test_deadeye_pick_without_game() -> void:
	var aim := DeadeyeAim.new()
	Game.instance = null
	assert_eq(aim._pick(null), null, "pas de partie : aucune cible")
	var g := Game.new()
	Game.instance = g
	assert_eq(aim._pick(null), null, "partie sans gestionnaire de zombies : aucune cible")
	Game.instance = _saved_instance
	g.free()


func test_deadeye_pick_no_zombies() -> void:
	var g := Game.new()
	var zm := ZombieManager.new()
	g.zombies = zm
	Game.instance = g
	var root := Node3D.new()
	host.add_child(root)
	var p := Player.new()
	p.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(p)
	var aim := DeadeyeAim.new()
	assert_eq(aim._pick(p), null, "aucun zombie vivant : aucune cible")
	assert_eq(aim.last_target_id, -1)
	Game.instance = _saved_instance
	root.free()
	zm.free()
	g.free()
