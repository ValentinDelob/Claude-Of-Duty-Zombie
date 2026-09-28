extends MapDef
## KINO V2 — Kino der Toten (Black Ops, 2010) à l'échelle 1, à plusieurs
## niveaux (docs/KINO_V2.md). Décrite par assets/maps/kino/layout.json, généré
## par tools/blender/kino/make_layout.py d'après les relevés de la carte
## d'origine, et construite par tools/blender/mesh_map.py.
##
## Zones : a Hall d'entrée (départ, balcon) · b Salle basse (fosse à feu)
##         c Ruelle · d Arrière-salle (zone grillagée, escalier)
##         e Salle haute (galerie, salle des portraits) · f Foyer (mezzanine)
##         g Loges · h Scène / coulisses · t Salle de théâtre (couloir, parterre,
##         avant-scène) · p Salle de projection (Pack-a-Punch, téléporteur seulement)
## Boucle comme dans BO1 : hall -(750)- salle basse -(1000)- ruelle -(1250)-
## arrière-salle -(1250)- coulisses ; hall -(750)- salle haute -(1000)- Foyer
## -(1250)- loges -(1250)- coulisses. Le courant ouvre le rideau de scène et
## les portes du couloir hall <-> salle de théâtre.

const DIR := "res://assets/maps/kino/"


func _init() -> void:
	id = "kino_v2"
	display_name = "KINO"
	description = "Le théâtre abandonné, à l'identique : hall à double escalier, salle en ruines, scène, loges, Foyer et ruelle."
	zone_names = {
		"a": "Hall d'entrée", "b": "Salle basse", "c": "Ruelle", "d": "Arrière-salle",
		"e": "Salle haute", "f": "Foyer", "g": "Loges", "h": "Coulisses",
		"t": "Salle de théâtre", "p": "Salle de projection",
	}
	# Départ de la boîte : au hasard, jamais le balcon du hall (index 1).
	box_start = 0
	box_starts = [0, 2, 3, 4, 5, 6, 7, 8]
	music = "ambience_kino"
	teleport_banner = "SALLE DE PROJECTION"
	teleporter_link = true
	look = {
		"ambient_color": Color(0.42, 0.3, 0.24),
		"ambient_energy": 0.52,
		"fog_color": Color(0.11, 0.085, 0.07),
		"fog_density": 0.012,
		"saturation": 0.85,
		"grade": TheaterLook.GRADE,
		"volumetric_albedo": TheaterLook.DUST_ALBEDO,
		"volumetric_density": TheaterLook.DUST_DENSITY,
	}


func create_layout() -> MapLayout:
	return MeshMapLayout.new(self, DIR + "layout.json", DIR + "kino.glb")
