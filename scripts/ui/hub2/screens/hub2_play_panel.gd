class_name Hub2PlayPanel
extends Hub2Panel
## JOUER (docs/hub_v2/Partie.dc.html en solo, PartieCoop.dc.html en coop) :
## SOLO / COOP, défi de la semaine, CARTES DU JEU / CARTES PERSONNALISÉES,
## aperçu, vagues, ÉQUIPEMENT, LANCER ; en coop le salon (4 cartes de
## joueurs ; voile 0.45 au lieu de 0.35, invites LANCER / CHANGER DE CARTE /
## QUITTER LE SALON). Bouton JOUER de la barre du haut en blanc sur cet écran.
## PROVISOIRE (cadre du hub v2) : titre sur un panneau de verre ; le contenu
## de la maquette reste à faire (docs/HUB_PLAN.md §9).


func build() -> void:
	add_placeholder(Hub2Screen.title_of(screen_id), Lang.t("Écran à venir (maquette validée).", "Screen coming soon (approved mockup)."))


func prompts() -> Array:
	return [[Hub2Input.ACCEPT, Lang.t("Lancer", "Launch")], [Hub2Input.SECONDARY, Lang.t("Armes de départ", "Starting weapons")],
		[Hub2Input.BACK, Lang.t("Retour", "Back")]]


func help() -> String:
	return Lang.t("Les armes de ton arsenal se construisent en partie, à la station, contre de la ferraille.",
			"Your arsenal weapons are built in a game, at the station, for scrap.")
