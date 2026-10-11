class_name ProgressGate
extends RefCounted
## Règle des cartes personnalisées (GAME_CONCEPT §4.20, décision du
## 2026-10-11) : une partie sur une carte faite avec l'éditeur (carte perso
## « perso:<id> » du joueur, ou carte perso reçue d'un hôte « partagee:<hash> »)
## est POUR LE FUN : AUCUNE progression. Ni XP (ni niveau), ni butin gardé
## (armes, pièces, échantillons), ni avancée des contrats (tableau qui tourne,
## histoire), ni codex, ni défi de la semaine. Le dossier de combat (records)
## reste compté : ce n'est pas une progression.
##
## Seul point de décision : Game le lit une fois au chargement de la carte
## (Game.progress) et ferme chaque chemin du profil (MatchXp, ProfileLoot,
## MatchContracts, WeeklyChallenge, ContractWatch, compteur d'XP en partie).
## Pur, testé par tests/test_progress_gate.gd.


## La carte `map_id` est-elle une carte personnalisée (éditeur) ?
static func is_custom_map(map_id: String) -> bool:
	return map_id.begins_with(EditorMapDef.CUSTOM_PREFIX) or map_id.begins_with(EditorMapDef.SHARED_PREFIX)


## Une partie sur `map_id` fait-elle progresser le profil ?
static func allows(map_id: String) -> bool:
	return not is_custom_map(map_id)


## Ligne de l'interface (JOUER, récapitulatif) : la règle en une phrase.
static func rule_text() -> String:
	return Lang.t("Créées avec l’éditeur. Aucune progression : ni XP, ni butin, ni contrat.",
			"Made with the editor. No progression: no XP, no loot, no contract.")
