class_name DrawnMapDef
extends MapDef
## Carte DESSINÉE (docs/MAP_AUTHORING.md) : dessin (une image par étage +
## carte.txt) converti par tools/maps/build_map.sh en
## assets/maps/<id>/layout.json (carte en maillage, MeshMapLayout) et <id>.glb.
## Les réglages de la carte (nom, zones, prix des portes, zones ouvertes l'une
## sur l'autre, départ de la boîte...) viennent de la section « map_def » de la
## description : un script de carte dessinée se réduit à son identifiant.

var dir := ""


func _init_drawn(map_id: String) -> void:
	id = map_id
	dir = "res://assets/maps/%s/" % map_id
	var data = JSON.parse_string(FileAccess.get_file_as_string(dir + "layout.json"))
	var md: Dictionary = data.get("map_def", {}) if data is Dictionary else {}
	display_name = String(md.get("display_name", map_id.to_upper()))
	description = String(md.get("description", ""))
	music = String(md.get("music", music))
	zone_names = md.get("zone_names", {})
	doors = md.get("doors", {})
	open_links = md.get("open_links", {})
	box_start = int(md.get("box_start", 0))
	box_starts = md.get("box_starts", [])
	# Poste central dessiné : téléporteur à relier avant chaque voyage (Kino).
	if bool(md.get("teleporter_link", false)):
		teleporter_link = true
		teleporter_cost = 0
		teleporter_charge = 1.8
		teleporter_stay = 30.0
		teleporter_link_cooldown = 90.0


func create_layout() -> MapLayout:
	return MeshMapLayout.new(self, dir + "layout.json", dir + id + ".glb")
