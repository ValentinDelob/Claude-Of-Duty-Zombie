extends RefCounted
## Textes du lanceur en français et en anglais.

const T := {
	"subtitle": {"fr": "LANCEUR", "en": "LAUNCHER"},
	"versions": {"fr": "VERSIONS", "en": "VERSIONS"},
	"latest": {"fr": "Dernière version", "en": "Latest version"},
	"installed": {"fr": "installée", "en": "installed"},
	"play": {"fr": "JOUER", "en": "PLAY"},
	"delete": {"fr": "SUPPRIMER", "en": "DELETE"},
	"loading": {"fr": "Recherche des versions…", "en": "Looking for versions…"},
	"offline": {"fr": "Hors ligne : seules les versions installées sont disponibles.", "en": "Offline: only installed versions are available."},
	"ready": {"fr": "Prêt à jouer.", "en": "Ready to play."},
	"to_download": {"fr": "Cette version sera téléchargée au lancement (%s Mo).", "en": "This version will be downloaded when you play (%s MB)."},
	"updating": {"fr": "Mise à jour vers %s : %d %%", "en": "Updating to %s: %d%%"},
	"downloading": {"fr": "Téléchargement de %s : %d %%", "en": "Downloading %s: %d%%"},
	"download_failed": {"fr": "Échec du téléchargement de %s. Vérifiez votre connexion.", "en": "Could not download %s. Check your connection."},
	"launching": {"fr": "Lancement de %s…", "en": "Starting %s…"},
	"play_after": {"fr": "Le jeu démarrera à la fin du téléchargement.", "en": "The game will start when the download finishes."},
	"no_versions": {"fr": "Aucune version installée. Connectez-vous à Internet pour télécharger le jeu.", "en": "No version installed. Connect to the Internet to download the game."},
	"no_notes": {"fr": "Pas encore de notes pour cette version.", "en": "No notes for this version yet."},
	"self_update": {"fr": "Mise à jour du lanceur…", "en": "Updating the launcher…"},
	"deleted": {"fr": "%s supprimée.", "en": "%s deleted."},
	"click_zoom": {"fr": "Cliquez sur une capture pour l'agrandir.", "en": "Click a screenshot to enlarge it."},
	"integrity_failed": {"fr": "Fichier de %s refusé : il ne correspond pas à la version publiée (téléchargement abîmé ou modifié). Réessayez.",
		"en": "%s file rejected: it does not match the published version (damaged or altered download). Please try again."},
	"integrity_failed_launcher": {"fr": "Mise à jour du lanceur refusée : fichier non conforme. Le lanceur actuel reste en place.",
		"en": "Launcher update rejected: the file does not match. The current launcher is kept."},
	"no_checksum": {"fr": "%s ne peut pas être vérifiée (somme de contrôle absente) : téléchargement refusé.",
		"en": "%s cannot be verified (checksum missing): download refused."},
	"legacy": {"fr": "(version ancienne : taille vérifiée seulement)", "en": "(old version: size check only)"},
	"latest_snapshot": {"fr": "Dernière snapshot", "en": "Latest snapshot"},
	"settings": {"fr": "RÉGLAGES", "en": "SETTINGS"},
	"back": {"fr": "← RETOUR", "en": "← BACK"},
	"s_lang": {"fr": "Langue", "en": "Language"},
	"s_lang_help": {"fr": "Textes du lanceur. Le jeu garde sa propre langue (menu Options).",
		"en": "Launcher text. The game keeps its own language (Options menu)."},
	"s_folder": {"fr": "Dossier des versions", "en": "Versions folder"},
	"s_space": {"fr": "%d version(s) installée(s) · %s Mo", "en": "%d version(s) installed · %s MB"},
	"s_space_engine": {"fr": " (moteur partagé : %s Mo)", "en": " (shared engine: %s MB)"},
	"s_open": {"fr": "OUVRIR", "en": "OPEN"},
	"s_clean": {"fr": "Paquets inutilisés", "en": "Unused packages"},
	"s_clean_btn": {"fr": "NETTOYER · %s Mo", "en": "CLEAN UP · %s MB"},
	"s_clean_help": {"fr": "Supprime les paquets qu'aucune version installée n'utilise plus.",
		"en": "Removes packages no installed version uses any more."},
	"s_clean_done": {"fr": "Paquets inutilisés supprimés.", "en": "Unused packages removed."},
	"s_logs": {"fr": "Journaux et rapports", "en": "Logs and reports"},
	"s_logs_help": {"fr": "Gardés 14 jours (rapports de plantage : 30 jours). Joignez-les à un signalement.",
		"en": "Kept 14 days (crash reports: 30 days). Attach them to a bug report."},
	"s_about": {"fr": "À propos", "en": "About"},
	"s_about_txt": {"fr": "Lanceur version %d. Chaque fichier est vérifié avant d'être installé.",
		"en": "Launcher version %d. Every file is checked before it is installed."},
	"launcher_updated": {"fr": "Lanceur mis à jour.", "en": "Launcher updated."},
	"launcher_update_failed": {"fr": "La nouvelle version du lanceur n'a pas démarré : l'ancienne a été remise.",
		"en": "The new launcher did not start: the previous one was restored."},
	"channel_stable": {"fr": "STABLE", "en": "STABLE"},
	"channel_snapshot": {"fr": "SNAPSHOT", "en": "SNAPSHOT"},
	"snapshot_note": {"fr": "Canal snapshot : chaque nouveauté dès sa sortie, parfois moins stable.",
		"en": "Snapshot channel: every new feature as soon as it ships, sometimes less stable."},
	"to_download_parts": {"fr": "Cette version sera téléchargée au lancement (seules les parties qui ont changé).",
		"en": "This version will be downloaded when you play (only the parts that changed)."},
	"downloading_parts": {"fr": "Téléchargement de %s : %d %% (%s Mo)", "en": "Downloading %s: %d%% (%s MB)"},
	"crashed": {"fr": "Le lanceur s'est arrêté brutalement la dernière fois. Rapport : %s",
		"en": "The launcher stopped unexpectedly last time. Report: %s"},
}


static func t(key: String, lang: String) -> String:
	var e: Dictionary = T.get(key, {})
	return String(e.get(lang, e.get("fr", key)))


## Date ISO (2026-09-28) au format de la langue.
static func date(iso: String, lang: String) -> String:
	var p := iso.split("-")
	if p.size() != 3:
		return iso
	return "%s/%s/%s" % [p[2], p[1], p[0]] if lang == "fr" else "%s-%s-%s" % [p[0], p[1], p[2]]
