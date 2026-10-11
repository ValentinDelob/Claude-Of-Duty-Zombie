class_name MatchXp
extends RefCounted
## Ajout au profil de l'XP d'une partie (GAME_CONCEPT §4.15) : seule voie
## d'entrée de l'XP de partie dans le profil. Le relevé (XpRules) est compté
## pendant la partie par le serveur (XpSystem) ; il est ajouté UNE fois, à la
## fin de la partie, que l'équipe s'évacue ou non (§4.6 : l'XP est toujours
## gardée), ou quand le joueur quitte la partie en cours
## (Game.keep_match_xp). Barème et calibrage : docs/XP_RULES.md.
##
## Le même relevé remplit le CODEX du profil (§4.17, CodexState) : ennemis
## rencontrés (« met ») et éliminations par type. Seul point d'entrée du codex
## (une fois par partie et par client : en coop, chacun le sien).


## Ajoute au profil enregistré (chargé, modifié, enregistré) l'XP du relevé
## `ledger` et ses rencontres (codex). Rend {xp, level_before, level_after,
## total_xp (XP du profil après), levels (niveaux gagnés), codex_new (types
## d'ennemis découverts)}.
static func apply(ledger: Dictionary, profile_path := "") -> Dictionary:
	var gained := XpRules.total(ledger)
	var pr := ProfileStore.load_profile(profile_path)
	var before := pr.level()
	var levels := pr.add_xp(gained)
	var codex_before := JSON.stringify(pr.codex.to_dict())
	var fresh := pr.codex.record_ledger(ledger)
	if gained > 0 or JSON.stringify(pr.codex.to_dict()) != codex_before:
		ProfileStore.save_profile(pr, profile_path)
	return {"xp": gained, "level_before": before, "level_after": pr.level(), "total_xp": pr.xp, "levels": levels,
		"codex_new": fresh}
