class_name AutotestMode
## La seule façon de savoir si le jeu tourne sous autotest
## (`-- --autotest=<nom>[,<nom>...]`, voir l'autoload Autotest).
##
## Lit la ligne de commande : utilisable avant le _ready des autoloads
## (Settings, chargé avant Autotest, choisit ainsi son fichier de test) et
## dans les fonctions statiques. `Autotest.active` vaut toujours
## `AutotestMode.is_running()` (même lecture des arguments).

const ARG_PREFIX := "--autotest="


## Scénarios demandés, dans l'ordre (vide hors autotest). Le dernier
## `--autotest=` de la ligne de commande l'emporte.
static func batch() -> PackedStringArray:
	var names: PackedStringArray = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with(ARG_PREFIX):
			names = a.substr(ARG_PREFIX.length()).split(",", false)
	return names


## Vrai si le jeu joue des scénarios d'autotest.
static func is_running() -> bool:
	return not batch().is_empty()


## Scénario en cours : celui que joue l'autoload Autotest (il change au fil
## d'une série) ; avant son _ready, le premier de la ligne de commande.
## Vide hors autotest.
static func scenario_name() -> String:
	if not is_running():
		return ""
	var ml := Engine.get_main_loop()
	var at: Node = (ml as SceneTree).root.get_node_or_null("Autotest") if ml is SceneTree else null
	if at != null:
		var current := String(at.get("scenario_name"))
		if current != "":
			return current
	return batch()[0]
