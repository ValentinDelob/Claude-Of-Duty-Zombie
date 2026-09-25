class_name AutotestScenario
extends RefCounted
## Base des scénarios automatisés. Surcharger run() (coroutine).

var at: Node  # l'autoload Autotest
var timeout_sec := 60


func run() -> void:
	pass


func tree() -> SceneTree:
	return at.get_tree()


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
