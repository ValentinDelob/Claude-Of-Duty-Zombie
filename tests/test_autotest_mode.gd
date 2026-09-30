extends TestCase
## AutotestMode : détection unique du mode test (ligne de commande), d'accord
## avec l'autoload Autotest ; hors autotest, les dossiers du joueur.


func test_off_in_the_unit_runner() -> void:
	assert_false(AutotestMode.is_running(), "le runner unitaire n'est pas un autotest")
	assert_true(AutotestMode.batch().is_empty(), "aucun scénario demandé")
	assert_eq(AutotestMode.scenario_name(), "")


func test_agrees_with_the_autoload() -> void:
	var at: Node = host.get_tree().root.get_node_or_null("Autotest")
	assert_true(at != null, "autoload Autotest présent")
	assert_eq(bool(at.get("active")), AutotestMode.is_running())


func test_paths_outside_autotest() -> void:
	var saved_maps := EditorMap.root_override
	var saved_cache := CustomMapGuard.cache_override
	EditorMap.root_override = ""
	CustomMapGuard.cache_override = ""
	assert_eq(EditorMap.maps_root(), "user://maps")
	assert_eq(CustomMapGuard.cache_root(), "user://maps_cache")
	EditorMap.root_override = saved_maps
	CustomMapGuard.cache_override = saved_cache
