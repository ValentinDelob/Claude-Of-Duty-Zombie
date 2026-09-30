extends MapDef
## KINO — Kino der Toten (Black Ops, 2010) à l'échelle 1, à plusieurs
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
	id = "kino"
	display_name = "KINO"
	description = Lang.t("Un théâtre abandonné où l'on projetait autrefois les films du Reich. Les rideaux sont rouges ; la moquette aussi, désormais.",
			"An abandoned theater that once screened the Reich's films. The curtains are red; so is the carpet, now.")
	zone_names = {
		"a": Lang.t("Hall d'entrée", "Lobby"), "b": Lang.t("Salle basse", "Lower Hall"),
		"c": Lang.t("Ruelle", "Alley"), "d": Lang.t("Arrière-salle", "Back Room"),
		"e": Lang.t("Salle haute", "Upper Hall"), "f": Lang.t("Foyer", "Foyer"),
		"g": Lang.t("Loges", "Dressing Rooms"), "h": Lang.t("Coulisses", "Backstage"),
		"t": Lang.t("Salle de théâtre", "Theater"), "p": Lang.t("Salle de projection", "Projection Room"),
	}
	# Départ de la boîte : au hasard, jamais le balcon du hall (index 1).
	box_start = 0
	box_starts = [0, 2, 3, 4, 5, 6, 7, 8]
	music = "ambience_kino"
	teleport_banner = Lang.t("SALLE DE PROJECTION", "PROJECTION ROOM")
	teleporter_link = true
	# Téléporteur de Kino der Toten : gratuit, charge 1,8 s, zombies foudroyés
	# à 300 u (7,6 m) du pad, 30 s dans la salle de projection, 90 s de
	# recharge avant de pouvoir relier à nouveau.
	teleporter_cost = 0
	teleporter_charge = 1.8
	teleporter_stay = 30.0
	teleporter_link_cooldown = 90.0
	teleporter_kill_radius = 7.62
	look = {
		"ambient_color": Color(0.34, 0.36, 0.35),
		"ambient_energy": 0.8,
		"fog_color": Color(0.085, 0.095, 0.11),
		"fog_density": 0.007,
		"saturation": 0.85,
		"grade": TheaterLook.GRADE,
		"volumetric_albedo": TheaterLook.DUST_ALBEDO,
		"volumetric_density": TheaterLook.DUST_DENSITY,
	}


func create_layout() -> MapLayout:
	return MeshMapLayout.new(self, DIR + "layout.json", DIR + "kino.glb")
