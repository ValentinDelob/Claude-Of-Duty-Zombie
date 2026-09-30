class_name CareerStats
extends RefCounted
## Dossier de combat (« Combat Record » de Black Ops 1) : statistiques locales
## cumulées de toutes les parties du joueur, enregistrées à chaque GAME OVER
## dans user://career.cfg (pendant les tests : un fichier par processus,
## user://career_autotest_<pid>.cfg, effacé à la fin du scénario ; plusieurs
## scénarios tournent en parallèle et ne doivent pas se marcher dessus).

const PATH := "user://career.cfg"
const TEST_PATH_PREFIX := "user://career_autotest_"

## Clés dans l'ordre d'affichage : [clé, libellé].
const FIELDS := [
	["games", "Parties jouées"],
	["best_round_solo", "Meilleure manche (solo)"],
	["best_round_coop", "Meilleure manche (coop)"],
	["rounds", "Manches survécues"],
	["kills", "Zombies abattus"],
	["headshots", "Tirs à la tête"],
	["best_score", "Meilleur score"],
	["downs", "Fois à terre"],
	["revives", "Réanimations"],
	["time", "Temps de jeu"],
]


static func path() -> String:
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
	var cfg := ConfigFile.new()
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


## Réinitialise le dossier (tests).
static func reset() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path()))


static func format_value(key: String, v: int) -> String:
	if key == "time":
		@warning_ignore("integer_division")
		return "%d h %02d min" % [v / 3600, (v / 60) % 60]
	return str(v)
