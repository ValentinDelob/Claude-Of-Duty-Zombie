class_name Lang
extends RefCounted
## Textes de l'interface en français ou en anglais, selon Settings.language
## (OPTIONS > JEU > LANGUE / LANGUAGE). Usage : Lang.t("REPRENDRE", "RESUME").
## Traduits : écran d'options et menu pause ; le reste du jeu est en français.


static func t(fr: String, en: String) -> String:
	return en if is_en() else fr


static func is_en() -> bool:
	# Fil de travail : jamais l'autoload Settings (état partagé), la langue
	# figée par le fil principal au lancement du calcul (ThreadGuard.enter).
	if ThreadGuard.worker():
		return ThreadGuard.worker_lang_en()
	return Settings.language == "en"
