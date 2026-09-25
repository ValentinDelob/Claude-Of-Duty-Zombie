class_name TestCase
extends RefCounted
## Classe de base des tests. Chaque méthode `test_*` est exécutée par le runner.
## Une méthode de test peut être une coroutine (utiliser `await`).

var failures: PackedStringArray = []
## Nœud hôte fourni par le runner (accès à l'arbre de scène).
var host: Node


func assert_true(cond: bool, msg := "") -> void:
	if not cond:
		failures.append("assert_true a échoué %s" % msg)


func assert_false(cond: bool, msg := "") -> void:
	if cond:
		failures.append("assert_false a échoué %s" % msg)


func assert_eq(a: Variant, b: Variant, msg := "") -> void:
	if typeof(a) != typeof(b) or a != b:
		failures.append("attendu %s, obtenu %s %s" % [var_to_str(b), var_to_str(a), msg])


func assert_near(a: float, b: float, eps := 0.001, msg := "") -> void:
	if absf(a - b) > eps:
		failures.append("attendu ~%f, obtenu %f %s" % [b, a, msg])


func wait_frames(n: int) -> void:
	for i in n:
		await host.get_tree().process_frame


func wait_seconds(s: float) -> void:
	await host.get_tree().create_timer(s).timeout


func before_each() -> void:
	pass


func after_each() -> void:
	pass
