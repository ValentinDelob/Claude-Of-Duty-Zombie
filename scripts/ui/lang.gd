class_name Lang
extends RefCounted
## Textes du jeu en français ou en anglais, selon Settings.language
## (OPTIONS > JEU > LANGUE / LANGUAGE).
##
## Mécanisme unique du jeu (et de l'éditeur de cartes) :
## * texte en ligne : Lang.t("REPRENDRE", "RESUME") ;
## * texte en table : {"fr": "...", "en": "..."} lu par Lang.pick(d).
## Le texte est choisi à l'affichage : changer de langue prend effet au
## prochain affichage. tests/test_lang.gd vérifie que chaque Lang.t() et
## chaque table a ses deux versions, et qu'aucun texte français en dur
## n'est affecté à un texte affiché.


static func t(fr: String, en: String) -> String:
	return en if is_en() else fr


## Texte bilingue d'une table : {"fr": ..., "en": ...} (ou une simple chaîne,
## rendue telle quelle). L'anglais manquant retombe sur le français.
static func pick(d: Variant, fallback := "") -> String:
	if d is Dictionary:
		var fr := String(d.get("fr", fallback))
		return String(d.get("en", fr)) if is_en() else fr
	if d == null:
		return fallback
	return String(d)


static func is_en() -> bool:
	# Fil de travail : jamais l'autoload Settings (état partagé), la langue
	# figée par le fil principal au lancement du calcul (ThreadGuard.enter).
	if ThreadGuard.worker():
		return ThreadGuard.worker_lang_en()
	return Settings.language == "en"
