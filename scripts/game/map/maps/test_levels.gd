extends MapDef
## Carte de test à plusieurs niveaux (hors menus) : rez-de-chaussée, escalier
## vers une mezzanine à garde-corps, porte payante vers une salle, fenêtre
## barricadée donnant sur une cour, salle en pente par une arcade. Décrite par
## assets/maps/test_levels/layout.json ; architecture en cubes de 5 cm construite
## par le jeu (MeshMapGeometry, mêmes règles que les cartes de l'éditeur).

const DIR := "res://assets/maps/test_levels/"


func _init() -> void:
	id = "test_levels"
	display_name = Lang.t("Étages (test)", "Levels (test)")
	description = Lang.t("Carte de test des cartes en maillage à plusieurs niveaux.", "Test map for multi-level mesh maps.")
	zone_names = {"a": Lang.t("Rez-de-chaussée", "Ground floor"), "b": Lang.t("Mezzanine", "Mezzanine"),
		"c": Lang.t("Salle est", "East room"), "d": Lang.t("Salle en pente", "Sloped room")}
	doors = {"1": {"cost": 500}}
	open_links = {"a": ["b", "d"]}
	music = "ambience_bunker"


func create_layout() -> MapLayout:
	return MeshMapLayout.new(self, DIR + "layout.json")
