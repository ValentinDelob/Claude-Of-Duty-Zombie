class_name Hub2InventoryPanel
extends Hub2Panel
## INVENTAIRE (docs/hub_v2/Inventaire.dc.html) : échantillons groupés par
## ennemi (rendus 3D), fiche (où le trouver, demandé par).
## PROVISOIRE (cadre du hub v2) : titre sur un panneau de verre ; le contenu
## de la maquette reste à faire (docs/HUB_PLAN.md §9).


func build() -> void:
	add_placeholder(Hub2Screen.title_of(screen_id), Lang.t("Écran à venir (maquette validée).", "Screen coming soon (approved mockup)."))


func prompts() -> Array:
	return [[Hub2Input.ACCEPT, Lang.t("Voir le contrat", "View contract")], [Hub2Input.BACK, Lang.t("Retour", "Back")]]


func help() -> String:
	return Lang.t("Les échantillons se gagnent en partie et se gardent en évacuant.",
			"Samples are earned in a game and kept by evacuating.")
