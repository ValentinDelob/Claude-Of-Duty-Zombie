class_name AutotestScenario
extends RefCounted
## Base des scénarios automatisés. Surcharger run() (coroutine).

var at: Node  # l'autoload Autotest
var timeout_sec := 60


func run() -> void:
	pass


func tree() -> SceneTree:
	return at.get_tree()


# --------------------------------------------------------------------------
# Découpage en parties parallèles : un scénario long déclare « ## @parts N »
# (ligne en tête de fichier) ; check.sh le lance N fois avec --part=k/N et
# chaque partie ne traite que sa part (mine(i)) : même couverture, N fois
# plus vite. Sans --part, le scénario complet tourne en une fois.
# --------------------------------------------------------------------------

func _part_arg() -> Vector2i:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--part="):
			var kn := a.substr(7).split("/")
			if kn.size() == 2:
				return Vector2i(kn[0].to_int(), maxi(kn[1].to_int(), 1))
	return Vector2i(0, 1)


## Numéro de cette partie (0..parts()-1).
func part() -> int:
	return _part_arg().x


func parts() -> int:
	return _part_arg().y


## L'élément d'indice `i` d'une liste revient-il à cette partie ?
func mine(i: int) -> bool:
	return i % parts() == part()


## Cette partie est-elle chargée de la section numéro `section` ?
## (sections réparties à la suite des éléments de liste : section k -> partie k % N)
func owns(section: int) -> bool:
	return section % parts() == part()


func frames(n: int) -> void:
	for i in n:
		await at.get_tree().process_frame


func seconds(s: float) -> void:
	await at.get_tree().create_timer(s).timeout


## Attend qu'une condition devienne vraie (ou échoue après `limit` secondes).
func until(cond: Callable, limit: float, what: String) -> bool:
	var t := 0.0
	while not cond.call():
		if t >= limit:
			at.fail("attente trop longue : " + what)
			return false
		await at.get_tree().process_frame
		t += at.get_process_delta_time()
	return true
