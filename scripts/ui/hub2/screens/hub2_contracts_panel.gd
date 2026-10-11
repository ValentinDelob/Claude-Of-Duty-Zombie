class_name Hub2ContractsPanel
extends Hub2Panel
## LABO › CONTRATS (docs/hub_v2/Contrats.dc.html) : contrat d'HISTOIRE
## (chapitres, étapes, turquoise) à gauche, CONTRATS TEMPORAIRES à droite,
## récompenses en tuiles avec infobulle au survol ; anneaux pulsés
## Hub2PulseRings (scale_to 1.1 × 1.5).
## PROVISOIRE (cadre du hub v2) : titre sur un panneau de verre ; le contenu
## de la maquette reste à faire (docs/HUB_PLAN.md §9).


func build() -> void:
	add_placeholder(Hub2Screen.title_of(screen_id), Lang.t("Écran à venir (maquette validée).", "Screen coming soon (approved mockup)."))


func veil() -> Dictionary:
	return {"color": Hub2Style.shade(0.45)}


func prompts() -> Array:
	return [[Hub2Input.ACCEPT, Lang.t("Remettre", "Hand in")], [Hub2Input.SECONDARY, Lang.t("Abandonner", "Abandon")],
		[Hub2Input.BACK, Lang.t("Labo", "Lab")]]


func help() -> String:
	return Lang.t("L’histoire avance d’un contrat à la fois ; les contrats temporaires donnent un bonus en attendant.",
			"The story moves on one contract at a time; timed contracts give a bonus in the meantime.")
