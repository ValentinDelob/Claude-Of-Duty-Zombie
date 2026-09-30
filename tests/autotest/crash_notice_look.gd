extends AutotestScenario
## @rendu : message discret du menu principal après un plantage (CrashGuard,
## docs/ARCHITECTURE.md « Journaux et plantages »). Un rapport (fictif, rien
## n'est écrit dans les données du joueur) est donné à CrashGuard : le message
## apparaît au menu principal, en français puis en anglais, avec le chemin du
## rapport et le bouton « Ouvrir le dossier » ; il se ferme avec « × ».

const REPORT := "C:/Users/joueur/AppData/Roaming/Godot/app_userdata/Call of Claude Zombie/crashes/plantage_2026-09-30T15.07.21.txt"


func run() -> void:
	timeout_sec = 30
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	var lang0 := String(Settings.language)
	for lang in ["fr", "en"]:
		Settings.language = lang
		CrashGuard.reports = PackedStringArray([REPORT])
		CrashGuard._notice_shown = false
		CrashGuard._screen = ""   # le menu est « revu » au prochain relevé
		if not await until(func(): return CrashGuard.get_node_or_null("CrashNotice") != null, 3.0, "message affiché (%s)" % lang):
			break
		var layer: CanvasLayer = CrashGuard.get_node("CrashNotice")
		var label: Label = layer.find_children("*", "Label", true, false)[0]
		at.check(label.text.contains(REPORT.replace("/", "\\")), "chemin du rapport dans le message (%s)" % lang)
		at.check(label.text.contains("rapport" if lang == "fr" else "report"), "message en %s" % lang)
		var buttons := layer.find_children("*", "Button", true, false)
		at.check(buttons.size() == 2 and (buttons[0] as Button).text == Lang.t("Ouvrir le dossier", "Open folder"), "bouton « Ouvrir le dossier »")
		await seconds(2.6)   # fondu d'ouverture du menu
		await at.screenshot("notice_" + lang)
		(buttons[1] as Button).pressed.emit()
		await frames(2)
		at.check(CrashGuard.get_node_or_null("CrashNotice") == null, "fermé par « × » (%s)" % lang)
	Settings.language = lang0
	CrashGuard.reports = PackedStringArray()
