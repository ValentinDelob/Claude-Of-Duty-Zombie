class_name MapDef
extends RefCounted
## Description d'une carte (nom, musique, ambiance, prix, départs de la
## boîte, réglages du téléporteur...) et création de sa géométrie : grille
## ASCII par défaut (marqueurs ci-dessous, GridMapLayout : BUNKER K-7,
## test_arena), ou carte en maillage à plusieurs niveaux en surchargeant
## create_layout (MeshMapLayout : KINO, test_levels).
##
## Marqueurs communs (posés sur du sol, zone déduite des voisins) :
##   P apparition joueur      Z apparition zombie     L lampe
##   1-9 portes (payantes)    X emplacement de la boîte mystère
##   R U V % ... achats muraux, armes ou couteaux (voir wall_buys)   Q J S D M ( ) atouts (voir perks)
##   * achat mural de grenades (250, voir GrenadeBuy)
##   G interrupteur du courant   E zone du piège électrique   H levier du piège
##   T plateforme du téléporteur   F sortie du téléporteur   K Pack-a-Punch
##   Décor bloquant : C caisse  O baril  I lit  N paillasse  Y générateur
##   @ porte d'évacuation (EvacDoor, contre le mur le plus proche)
##   Décor : , flaque de sang
##   W fenêtre barricadée, posée dans un mur entre la zone et une petite poche
##     fermée (le dehors) dont les Z sont des apparitions « par la fenêtre »
##     (voir BarricadeLayout). Les Z hors poche sortent du sol.

const BLOCKING_PROPS := "COINY"
const WINDOW := "W"
const EVAC_MARKER := "@"

var id := "map"
var display_name := Lang.t("Carte", "Map")
var rows: PackedStringArray = []
var zone_names: Dictionary = {}
## "1" -> {"cost": 750}
var doors: Dictionary = {}
## marqueur -> id d'arme
var wall_buys: Dictionary = {}
## marqueur -> id d'atout
var perks: Dictionary = {}
## Index de l'emplacement de départ de la boîte mystère (ordre des X).
var box_start := 0
## zone -> [matériau du sol, matériau des murs]
var zone_materials: Dictionary = {}
## Zones dont les murs portent des tuyauteries.
var pipe_zones: Array = []
## Texte d'accroche (écran de sélection de carte).
var description := ""
## Départ aléatoire de la boîte parmi ces index d'emplacements (vide : box_start).
var box_starts: Array = []
## Zones ouvertes l'une sur l'autre sans porte : ouvrir l'accès à l'une
## active aussi les apparitions des autres (zone -> [zones]).
var open_links: Dictionary = {}
## Musique d'ambiance (assets/audio).
var music := "ambience_bunker"
## Bandeau affiché à l'arrivée du téléporteur.
var teleport_banner := Lang.t("SALLE DU RITUEL", "RITUAL ROOM")
## Téléporteur à relier au poste central (`mainframe` de la description en
## maillage) avant chaque voyage, comme à Kino der Toten ; retour dessus.
var teleporter_link := false
## Réglages du téléporteur (défauts : BUNKER K-7) ; KINO reprend ceux de
## Kino der Toten (gratuit, 1,8 s, 30 s, 90 s de recharge).
var teleporter_cost := 1500
var teleporter_charge := 3.0
var teleporter_stay := 25.0
var teleporter_cooldown := 60.0
## Recharge après chaque voyage en mode liaison (0 : relier aussitôt).
var teleporter_link_cooldown := 0.0
## Zombies tués autour de la plateforme au départ (0 : aucun).
var teleporter_kill_radius := 0.0
## Ambiance lumineuse : surcharges de WorldLook.setup_environment
## (ambient_color, ambient_energy, fog_color, fog_density, saturation...).
var look: Dictionary = {}
## Schéma des vagues spéciales et de boss (WaveRules ; défaut : spéciale
## toutes les 5 manches, boss toutes les 15). Cartes de l'éditeur : clé
## « vagues » de carte.json (format 18).
var waves: Dictionary = WaveRules.default_schedule()
## Boss de la carte ("" : aucun ; une vague de boss ne fait alors rien).
var boss := ""


func player_spawn_marker() -> String:
	return "P"


func zone_display_name(zone: String) -> String:
	return zone_names.get(zone, zone.to_upper())


## Cellules bloquantes au départ (décor + portes fermées + fenêtres, que les
## zombies ne franchissent que par l'enjambement scripté).
static func blocking_cells(data: MapData, def: MapDef) -> Array:
	var out := []
	for key in data.markers:
		if BLOCKING_PROPS.contains(key) or def.doors.has(key) or key == WINDOW:
			out.append_array(data.markers[key])
	return out


## Regroupe des cellules adjacentes (4-connexité) : une porte de 2 cases, une
## plateforme 2x2... Retourne Array[Array[Vector2i]].
static func group_cells(cells: Array) -> Array:
	var left := {}
	for c in cells:
		left[c] = true
	var groups := []
	while not left.is_empty():
		var start: Vector2i = left.keys()[0]
		var group := []
		var stack := [start]
		left.erase(start)
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			group.append(c)
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if left.has(c + d):
					left.erase(c + d)
					stack.append(c + d)
		groups.append(group)
	return groups


## Direction (unitaire, dans le plan) vers le mur le plus proche d'une cellule :
## les objets muraux (atouts, achats) sont plaqués contre ce mur.
static func wall_normal(data: MapData, c: Vector2i) -> Vector3:
	for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		if data.is_wall(c + d):
			return Vector3(d.x, 0, d.y)
	return Vector3(0, 0, -1)


## Géométrie de la carte pour les systèmes de jeu (grille ASCII par défaut ;
## les cartes en maillage surchargent cette méthode).
func create_layout() -> MapLayout:
	return GridMapLayout.new(self)
