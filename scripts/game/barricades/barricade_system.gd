class_name BarricadeSystem
extends Node
## Fenêtres barricadées de la carte (chemin réseau : /root/Game/Barricades).
##
## Construit les fenêtres (marqueurs W), rattache chaque zombie apparu dans
## une poche extérieure à sa fenêtre (serveur ET clients, d'après la position
## d'apparition : aucun champ réseau supplémentaire), tient le plafond de
## points de réparation par joueur et par manche (serveur), et envoie l'état
## complet des planches au lancement de la partie.

var game: Game
var windows: Array[Barricade] = []
## Apparitions derrière les fenêtres : [position, fenêtre].
var _spawns: Array = []
## Serveur : points de réparation gagnés pendant la manche, par joueur.
var repair_earned: Dictionary = {}


func setup(g: Game) -> void:
	game = g
	var root := Node3D.new()
	root.name = "Barricades"
	game.world.add_child(root)
	for w: BarricadeLayout.Opening in game.layout.windows():
		var b := Barricade.new()
		b.setup(w)
		game.interact.register(b)
		root.add_child(b)
		windows.append(b)
		for p in w.spawn_points:
			_spawns.append([p, b])
		game.layout.set_blocked("window_%d" % w.index, true)
	game.zombies.zombie_spawned.connect(_on_zombie_spawned)
	game.rounds.round_started.connect(_on_round_started)
	if multiplayer.is_server():
		Net.all_loaded.connect(_on_all_loaded)
	if not windows.is_empty():
		print("[Barricades] %d fenêtres, %d apparitions derrière les fenêtres" % [windows.size(), _spawns.size()])


## Fenêtre dont une apparition est en `pos` (à 0,5 m près), ou null.
func window_for_spawn(pos: Vector3) -> Barricade:
	for s in _spawns:
		if (s[0] as Vector3).distance_squared_to(pos) < 0.25:
			return s[1]
	return null


func window_at(index: int) -> Barricade:
	return windows[index] if index >= 0 and index < windows.size() else null


## Toutes les machines : un zombie apparu derrière une fenêtre ne sort pas du
## sol, il marche jusqu'à sa fenêtre.
func _on_zombie_spawned(z: Zombie) -> void:
	var b := window_for_spawn(z.global_position)
	if b:
		z.enter_barricade(b)


func _on_round_started(_n: int) -> void:
	repair_earned.clear()


## Serveur : points d'une planche reposée (double points, plafond par manche).
func srv_award_repair(pid: int) -> int:
	var earned: int = repair_earned.get(pid, 0)
	var pts := BarricadeRules.repair_points(earned, game.points.multiplier)
	if pts > 0:
		repair_earned[pid] = earned + pts
		game.session.add_points(pid, pts)
	return pts


## Serveur : toutes les fenêtres reconstruites (bonus CHARPENTIER).
func srv_repair_all() -> void:
	if not multiplayer.is_server():
		return
	for b in windows:
		b.srv_set_mask(BarricadeRules.FULL_MASK)


# --------------------------------------------------------------------------
# État complet (lancement de la partie)
# --------------------------------------------------------------------------

func _on_all_loaded() -> void:
	if windows.is_empty():
		return
	_cl_full_state.rpc(masks())


func masks() -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(windows.size())
	for i in windows.size():
		out[i] = windows[i].mask
	return out


@rpc("authority", "call_remote", "reliable")
func _cl_full_state(m: PackedByteArray) -> void:
	for i in mini(m.size(), windows.size()):
		windows[i].set_mask(m[i], false)
