extends MapDef
## BUNKER K-7 — installation militaire et laboratoire abandonnés. Carte de
## TEST depuis l'abandon du clone de BO1 (GAME_CONCEPT §5) : plus d'atouts,
## d'armes murales, d'achat de grenades ni de Pack-a-Punch ; restent les
## portes, le courant, le piège, le téléporteur, les barricades et UNE caisse
## au hasard (X, sur le quai).
##
## Zones : a Salle de garde (départ) · b Couloir des cellules (piège)
##         c Laboratoire · d Dortoir · e Générateur · f Quai du téléporteur
##         (caisse) · p Salle du rituel (vide, accessible par téléporteur
##         uniquement)
## Marqueurs : voir MapDef. Généré à partir de rectangles puis retouché.
## Fenêtres barricadées (W) : 4 dans la salle de garde, 1 au dortoir, 2 au
## quai, 2 au couloir, 4 au laboratoire, 2 au générateur ; derrière chacune,
## une poche fermée avec son apparition Z. Quelques Z « sortie du sol »
## subsistent dans les salles (comme à Kino der Toten).
## Salle du générateur : la caisse est en (61, 27), à l'écart de la sortie de
## la fenêtre sud (en 60, 28 elle ne laissait qu'une file de zombies passer).
## Porte d'évacuation (@) : salle de garde (départ), contre le mur ouest.
## Station de construction (=) : salle de garde, contre le mur nord.
## Vagues spéciales et de boss : schéma par défaut (MapDef.waves).

func _init() -> void:
	id = "bunker_k7"
	display_name = "BUNKER K-7"
	description = Lang.t("Installation militaire et laboratoire abandonnés. Le générateur est mort, les expériences non.",
			"An abandoned military facility and laboratory. The generator is dead; the experiments are not.")
	zone_names = {
		"a": Lang.t("Salle de garde", "Guard Room"), "b": Lang.t("Couloir des cellules", "Cell Block"),
		"c": Lang.t("Laboratoire", "Laboratory"), "d": Lang.t("Dortoir", "Barracks"),
		"e": Lang.t("Générateur", "Generator"), "f": Lang.t("Quai", "Platform"),
		"p": Lang.t("Salle du rituel", "Ritual Room"),
	}
	doors = {
		"1": {"cost": 750},
		"2": {"cost": 750},
		"3": {"cost": 1000},
		"4": {"cost": 1250},
		"5": {"cost": 1000},
		"6": {"cost": 1250},
	}
	# Une seule caisse au hasard (seul X de la carte, sur le quai).
	box_start = 0
	zone_materials = {
		"a": ["concrete", "wall_green"], "b": ["concrete_dark", "wall_cell"],
		"c": ["tiles", "wall_lab"], "d": ["wood", "wall_green"],
		"e": ["metal", "wall_rust"], "f": ["concrete", "wall_concrete"],
		"p": ["stone", "wall_ritual"],
	}
	pipe_zones = ["b", "e", "f"]
	rows = PackedStringArray([
		"                                                                ",
		" #################################################              ",
		" #ZdddddddddddddZd#ZffffffffffffffffffffffffffffZ# ###########  ",
		" #dddddddddddddddd#fOffffffffffffffffffffffffffff# #ppppppppp#  ",
		" #ddIddddddddIdddd#fffffffffffffffffffffffffTTfff# #ppppppppp#  ",
		" #ddIdLdddddLIdddd#ffffLfffffffLfffffffLffffTTfff# #ppLpppLpp#  ",
		" #dddddddddddddddd5ffffffff,fffffffffffffffffffff# #ppppppppp#  ",
		" #dddddddddddddddd5ffffffffffffffffCCffffffffffff# #ppppFpppp#  ",
		" #dddddddddddddddd#ffffffffffffffffCffffffffffLff# #ppppppppp#  ",
		" #ddIddddddddIdddd#ffffffffffffffffffffffffffffOf# #ppppppppp#  ",
		" #ddIddddddddIdddd#fffffXfffffffffffffffffffffffZ# ###########  ",
		" #ddddLdddddLddddd###########W#####W####66########              ",
		" #dddddddddddddddd####     #fff# #fff# #cc#                     ",
		" #dddddddddddddddd#dd#     #fZf# #fZf# #Lc#                     ",
		" #ddddddZdddddddddWdZ#     ##### ##### #cc#                     ",
		" ########11########dd#                 #cc#                     ",
		" ########11###########        ##########cc#############         ",
		" #aaa=aaaaaaaaaaaa#aa#        #cc#cccccccccccccccccccZ#   ##### ",
		" #aaaaaaaaaaaaaaaaWaZ#    #####ZcWcccccccccccccccccccc#   #eZe# ",
		" #aaaaa,aaaaaaaCCa#aa#    #bZb#cc#ccccLccccccccccLcccc#   #eee# ",
		" #aaaLaaaaaaaLaCaa####    #bbb####cccccccccccccccccccc######W###",
		" #aaaaaaaaaaaaaaaa##########W#####ccccNNNNccccNNNNcccc#eeeeeeee#",
		" #aOaaaaaaaaaaaaaa#bbbHbEEEb,bbbb#cccccccccccccccccccc#eeeeeeOe#",
		" #aaaaaaaaaaaaaaaa2bbLbbEEEbbbbbb3cccccccccccccccccccc#eLeeeeee#",
		" #@aaaaaPaPaaaaaaa2bbbbbEEEbbLbbb3ccccccccccLccccccccc4ee,eeeee#",
		" #aaaaaaaaaaaaaaaa#bbbbbEEEbbbbbb#cccccccccccccccccccc4eeeeeeeG#",
		" #aaaaaaPaPaaaaaaa#####W##########cccccccccccccccccccc#eeeYYeee#",
		" #aaaLaaaaaaaLaaaa#aa#bbb#    ####ccccNNNNccccNNNNcccc#eeeYYeCe#",
		" #aaaaaaaaaaaa,aaaWaZ#bZb#    #cc#cccccccccccccccccccc#eeeeeeLe#",
		" #aaaaaaaaaaaaaaaa#aa#####    #ZcWccccLccccccccccLcccc#Zeeeeeee#",
		" #aZaaaaaaaaaaaaaa####        #cc#ccccccccc,cccccccccc####W#####",
		" #####W########W###           ####cccccccccccccccccccc# #eee#   ",
		"    #aaa#    #aaa#               #Zccccccccccccccccccc# #eZe#   ",
		"    #aZa#    #aZa#               #######W########W##### #####   ",
		"    #####    #####                    #ccc#    #ccc#            ",
		"                                      #cZc#    #cZc#            ",
		"                                      #####    #####            ",
	])
