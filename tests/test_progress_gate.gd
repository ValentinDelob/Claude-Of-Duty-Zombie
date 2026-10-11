extends TestCase
## Cartes personnalisées : aucune progression (GAME_CONCEPT §4.20,
## ProgressGate) : cartes perso du joueur et cartes reçues d'un hôte
## reconnues, chemins de Game fermés (XP, codex, contrats, défi), rapport de
## fin « carte perso », record par carte du dossier de combat (jamais le
## fichier du joueur).

const CAREER_TMP := "user://career_unittest_%d.cfg"

var _lang := ""


func before_each() -> void:
	_lang = Settings.language
	Settings.language = "fr"
	CareerStats.path_override = CAREER_TMP % OS.get_process_id()


func after_each() -> void:
	Settings.language = _lang
	var p := CareerStats.path_override
	CareerStats.path_override = ""
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func test_custom_maps_detected() -> void:
	assert_true(ProgressGate.is_custom_map(EditorMapDef.CUSTOM_PREFIX + "ma_carte"), "carte perso du joueur")
	assert_true(ProgressGate.is_custom_map(EditorMapDef.SHARED_PREFIX + "abcdef"), "carte perso reçue d'un hôte")
	assert_false(ProgressGate.is_custom_map("bunker_k7"), "carte du jeu")
	assert_false(ProgressGate.is_custom_map("test_arena"))
	assert_true(ProgressGate.allows("bunker_k7"), "carte du jeu : progression")
	assert_false(ProgressGate.allows(EditorMapDef.CUSTOM_PREFIX + "x"), "carte perso : aucune progression")
	assert_eq(ProgressGate.rule_text(), "Créées avec l’éditeur. Aucune progression : ni XP, ni butin, ni contrat.",
			"texte de la maquette (Partie.dc.html)")
	Settings.language = "en"
	assert_true(ProgressGate.rule_text().begins_with("Made with the editor."), "anglais")


## Game : sur une carte perso, l'XP n'est jamais ajoutée (ni le codex), une
## seule fois comptée comme faite ; le tableau des contrats ne tourne pas.
## (Aucun accès au profil du joueur : la porte se ferme avant.)
func test_game_paths_closed() -> void:
	var g: Game = (load("res://scripts/game/game.gd") as GDScript).new()
	g.progress = false
	var l := XpRules.new_ledger()
	XpRules.add_kill(l, XpRules.WALKER, 3)
	XpRules.add_round(l, 3)
	assert_true(XpRules.total(l) > 0, "relevé non vide")
	assert_eq(g._record_xp(l), {}, "carte perso : MatchXp jamais appelé")
	assert_true(g._xp_recorded, "compté comme fait (une fois par partie)")
	g._rotate_contracts(5)
	assert_true(g._contracts_rotated, "contrats : rien ne tourne, chemin fermé")
	g.free()


func test_match_result_custom_text() -> void:
	var r := MatchResult.new()
	r.evacuated = true
	r.loot = ProfileLoot.report(ProfileLoot.carried(null, [], {"dog_fang": 3}), false)
	r.loot["custom"] = true
	var back := MatchResult.from_dict(r.to_dict())
	assert_eq(back.loot_text(), "CARTE PERSO : aucune progression (ni XP, ni butin, ni contrat)")


## Rapport du butin : arme neuve (butin, arme de base améliorée) ou version
## de l'arsenal mise à jour.
func test_report_marks_new_weapons() -> void:
	var pd := PlayerData.new(1)
	pd.weapons = [GameWeapon.make("mp40", 9, 1, [], "loot:4"), GameWeapon.make("python", 12, 2, [], "w3")]
	var rep := ProfileLoot.report(ProfileLoot.carried(pd, [], {}), true)
	assert_eq(rep.weapons.size(), 2)
	assert_eq(rep.weapons[0][3], true, "butin : neuve")
	assert_eq(rep.weapons[1][3], false, "exemplaire de l'arsenal : mise à jour")


func test_map_best_record() -> void:
	assert_eq(CareerStats.map_best("bunker_k7"), 0, "jamais jouée")
	CareerStats.record_map_best("bunker_k7", 12)
	CareerStats.record_map_best("bunker_k7", 9)
	assert_eq(CareerStats.map_best("bunker_k7"), 12, "meilleure manche gardée")
	CareerStats.record_map_best(EditorMapDef.CUSTOM_PREFIX + "ma_carte", 4)
	assert_eq(CareerStats.map_best(EditorMapDef.CUSTOM_PREFIX + "ma_carte"), 4, "carte perso : record gardé (pas une progression)")
	assert_false(CareerStats.map_key("perso:x").contains(":"), "clé sans « : »")
	# Une partie enregistrée ensuite garde les records par carte.
	CareerStats.record_game(PlayerData.new(1), 3, true, 10.0)
	assert_eq(CareerStats.map_best("bunker_k7"), 12, "record_game garde les autres sections")
	assert_eq(int(CareerStats.load_stats().games), 1)
