extends MapDef
## BUNKER K-7 — installation militaire et laboratoire abandonnés.
##
## Zones : a Salle de garde (départ) · b Couloir des cellules (piège)
##         c Laboratoire · d Dortoir · e Générateur · f Quai du téléporteur
##         p Salle du Pack-a-Punch (accessible par téléporteur uniquement)
## Marqueurs : voir MapDef. Généré à partir de rectangles puis retouché.
## Fenêtres barricadées (W) : 4 dans la salle de garde, 1 au dortoir, 2 au
## quai, 2 au couloir, 4 au laboratoire, 2 au générateur ; derrière chacune,
## une poche fermée avec son apparition Z. Quelques Z « sortie du sol »
## subsistent dans les salles (comme à Kino der Toten).

func _init() -> void:
	id = "bunker_k7"
	display_name = "BUNKER K-7"
	description = "Installation militaire et laboratoire abandonnés. Le générateur est mort, les expériences non."
	zone_names = {
		"a": "Salle de garde", "b": "Couloir des cellules", "c": "Laboratoire",
		"d": "Dortoir", "e": "Générateur", "f": "Quai", "p": "Salle du rituel",
	}
	doors = {
		"1": {"cost": 750},
		"2": {"cost": 750},
		"3": {"cost": 1000},
		"4": {"cost": 1250},
		"5": {"cost": 1000},
		"6": {"cost": 1250},
	}
	# Arsenal mural de Kino der Toten (+ MP40 de Five) : contour à la craie.
	wall_buys = {
		"A": "olympia", "R": "m14",           # salle de garde (départ)
		"U": "mp5k",                          # couloir des cellules
		"V": "stakeout", "+": "mp40",         # dortoir
		"B": "pm63", "!": "mpl",              # laboratoire
		"$": "ak74u",                         # générateur
		"&": "m16",                           # quai
		"%": "bowie",                         # quai : couteau de chasse (KnifeDB)
	}
	perks = {"Q": "lazarus", "J": "titan", "S": "rapid", "D": "twin", "M": "stride",
		"(": "nova", ")": "deadeye"}  # laboratoire, générateur
	box_start = 1
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
		" #ZddddddVddddddZd#Zfffff%ffffDfffffff&fffffffffZ# ###########  ",
		" #ddddddddddddddd+#fOffffffffffffffffffffffffffff# #ppppKpppp#  ",
		" #ddIddddddddIdddd#fffffffffffffffffffffffffTTfff# #ppppppppp#  ",
		" #ddIdLdddddLIdddd#ffffLfffffffLfffffffLffffTTfff# #ppLpppLpp#  ",
		" #dddddddddddddddd5ffffffff,fffffffffffffffffffff# #ppppppppp#  ",
		" #dddddddddddddddd5ffffffffffffffffCCffffffffffff# #ppppFpppp#  ",
		" #Xddddddddddddddd#ffffffffffffffffCffffffffffLff# #ppppppppp#  ",
		" #ddIddddddddIdddd#ffffffffffffffffffffffffffffOf# #ppppppppp#  ",
		" #ddIddddddddIdddd#fffffXfffffffffffffffffffffffZ# ###########  ",
		" #ddddLdddddLddddd###########W#####W####66########              ",
		" #dddddddddddddddJ####     #fff# #fff# #cc#                     ",
		" #dddddddddddddddd#dd#     #fZf# #fZf# #Lc#                     ",
		" #ddddddZdddddddddWdZ#     ##### ##### #cc#                     ",
		" ########11########dd#                 #cc#                     ",
		" ########11###########        ##########cc#############         ",
		" #aaaAaaaaaaaaaaaa#aa#        #cc#ccccccccccccBccccccZ#   ##### ",
		" #aaaaaaaaaaaaaaaaWaZ#    #####ZcWcccccccccccccccccccc#   #eZe# ",
		" #aaaaa,aaaaaaaCCa#aa#    #bZb#cc#ccccLccccccccccLcccc#   #eee# ",
		" #QaaLaaaaaaaLaCaa####    #bbb####cccccccccccccccccccc######W###",
		" #aaaaaaaaaaaaaaaa##########W#####ccccNNNNccccNNNNcccc#e$eSeeee#",
		" #aOaaaaaaaaaaaaaa#bbbHbEEEb,bbbb#!ccccccccccccccccccc#eeeeeeOe#",
		" #aaaaaaaaaaaaaaaa2bbLbbEEEbbbbbb3cccccccccccccccccccc#eLeeeeee#",
		" #aaaaaaPaPaaaaaaa2bbbbbEEEbbLbbb3ccccccccccLccccccccc4ee,eeeee#",
		" #aaaaaaaaaaaaaaaa#bbbbbEEEbbUbbb#cccccccccccccccccccc4eeeeeeeG#",
		" #aaaaaaPaPaaaaaaa#####W##########cccccccccccccccccccc#eeeYYeee#",
		" #aaaLaaaaaaaLaaaa#aa#bbb#    ####(cccNNNNccccNNNNcccc#)eeYYeee#",
		" #aaaaaaaaaaaa,aaaWaZ#bZb#    #cc#cccccccccccccccccccc#eeeeeCLe#",
		" #aaaaaaaaaaaaaaaa#aa#####    #ZcWccccLccccccccccLcccc#Zeeeeeee#",
		" #aZaaaaa*aaRaaaaa####        #cc#ccccccccc,cccccccccM####W#####",
		" #####W########W###           ####cccccccccccccccccccc# #eee#   ",
		"    #aaa#    #aaa#               #ZcccccccccXccccccccc# #eZe#   ",
		"    #aZa#    #aZa#               #######W########W##### #####   ",
		"    #####    #####                    #ccc#    #ccc#            ",
		"                                      #cZc#    #cZc#            ",
		"                                      #####    #####            ",
	])
