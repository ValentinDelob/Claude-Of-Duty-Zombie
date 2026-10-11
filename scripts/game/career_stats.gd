class_name CareerStats
extends RefCounted
## Dossier de combat (« Combat Record » de Black Ops 1) : statistiques locales
## cumulées de toutes les parties du joueur, enregistrées à chaque GAME OVER
## dans user://career.cfg (pendant les tests : un fichier par processus,
## user://career_autotest_<pid>.cfg, effacé à la fin du scénario ; plusieurs
## scénarios tournent en parallèle et ne doivent pas se marcher dessus).

const PATH := "user://career.cfg"
const TEST_PATH_PREFIX := "user://career_autotest_"

## Clés dans l'ordre d'affichage : [clé, libellé français, libellé anglais].
const FIELDS := [
	["games", "Parties jouées", "Games played"],
	["best_round_solo", "Meilleure manche (solo)", "Best round (solo)"],
	["best_round_coop", "Meilleure manche (coop)", "Best round (co-op)"],
	["rounds", "Manches survécues", "Rounds survived"],
	["kills", "Zombies abattus", "Zombies killed"],
	["headshots", "Tirs à la tête", "Headshots"],
	["best_score", "Meilleur score", "Best score"],
	["downs", "Fois à terre", "Downs"],
	["revives", "Réanimations", "Revives"],
	["time", "Temps de jeu", "Time played"],
]


## Fichier imposé (tests unitaires : jamais le dossier du joueur) ; "" : aucun.
static var path_override := ""


static func path() -> String:
	if path_override != "":
		return path_override
	return "%s%d.cfg" % [TEST_PATH_PREFIX, OS.get_process_id()] if Autotest.active else PATH


static func load_stats() -> Dictionary:
	var out := {}
	for f in FIELDS:
		out[f[0]] = 0
	# SafeConfig : aucun objet ni ressource décodés depuis le fichier.
	var cfg := SafeConfig.load_file(path())
	if cfg != null:
		for f in FIELDS:
			out[f[0]] = SafeConfig.get_int(cfg, "career", f[0], 0, 0)
	return out


## Ajoute une partie terminée. `seconds` : durée de la partie.
static func record_game(pd: PlayerData, round_n: int, solo: bool, seconds: float) -> Dictionary:
	var s := accumulate(load_stats(), pd, round_n, solo, seconds)
	# Fichier relu : les autres sections (records par carte) restent.
	var cfg := SafeConfig.load_file(path())
	if cfg == null:
		cfg = ConfigFile.new()
	for k in s:
		cfg.set_value("career", k, s[k])
	var err := cfg.save(path())
	if err != OK:
		push_warning("[Career] dossier de combat non enregistré (%s)" % error_string(err))
	return s


## Règle pure : ajoute une partie aux statistiques `s` (modifiées et retournées).
static func accumulate(s: Dictionary, pd: PlayerData, round_n: int, solo: bool, seconds: float) -> Dictionary:
	s.games += 1
	var best_key := "best_round_solo" if solo else "best_round_coop"
	s[best_key] = maxi(s[best_key], round_n)
	# Manches survécues : la manche en cours au GAME OVER ne compte pas.
	s.rounds += maxi(round_n - 1, 0)
	if pd:
		s.kills += pd.kills
		s.headshots += pd.headshots
		s.downs += pd.downs
		s.revives += pd.revives
		s.best_score = maxi(s.best_score, pd.points)
	s.time += int(seconds)
	return s


## Section des records par carte (meilleure manche atteinte, solo et coop
## confondus ; cartes perso comprises : un record n'est pas une progression).
const MAP_SECTION := "best_round_map"


## Clé d'une carte dans MAP_SECTION (« perso:ma_carte » -> « perso__ma_carte » :
## jamais de « : » dans une clé de ConfigFile).
static func map_key(map_id: String) -> String:
	return map_id.replace(":", "__").validate_filename()


## Meilleure manche atteinte sur la carte `map_id` (0 : jamais jouée).
static func map_best(map_id: String) -> int:
	if map_id == "":
		return 0
	var cfg := SafeConfig.load_file(path())
	if cfg == null:
		return 0
	return SafeConfig.get_int(cfg, MAP_SECTION, map_key(map_id), 0, 0, 1000000)


## Note la manche `round_n` atteinte sur `map_id` (garde la meilleure).
static func record_map_best(map_id: String, round_n: int) -> void:
	if map_id == "" or round_n <= 0:
		return
	var cfg := SafeConfig.load_file(path())
	if cfg == null:
		cfg = ConfigFile.new()
	var k := map_key(map_id)
	if SafeConfig.get_int(cfg, MAP_SECTION, k, 0, 0, 1000000) >= round_n:
		return
	cfg.set_value(MAP_SECTION, k, round_n)
	var err := cfg.save(path())
	if err != OK:
		push_warning("[Career] record de la carte non enregistré (%s)" % error_string(err))


## Réinitialise le dossier (tests).
static func reset() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path()))


static func format_value(key: String, v: int) -> String:
	if key == "time":
		@warning_ignore("integer_division")
		return "%d h %02d min" % [v / 3600, (v / 60) % 60]
	return str(v)
