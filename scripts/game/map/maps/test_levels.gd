extends MapDef
## Carte de test à plusieurs niveaux (hors menus) : rez-de-chaussée, escalier
## vers une mezzanine à garde-corps, porte payante vers une salle, fenêtre
## barricadée donnant sur une cour, salle en pente par une arcade. Décrite par
## assets/maps/test_levels/layout.json, construite par tools/blender/mesh_map.py.

const DIR := "res://assets/maps/test_levels/"


func _init() -> void:
	id = "test_levels"
	display_name = "Étages (test)"
	description = "Carte de test des cartes en maillage à plusieurs niveaux."
	zone_names = {"a": "Rez-de-chaussée", "b": "Mezzanine", "c": "Salle est", "d": "Salle en pente"}
	doors = {"1": {"cost": 500}}
	open_links = {"a": ["b", "d"]}
	music = "ambience_bunker"


func create_layout() -> MapLayout:
	return MeshMapLayout.new(self, DIR + "layout.json", DIR + "test_levels.glb")
