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
