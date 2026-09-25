extends MapDef
## BUNKER K-7 — installation militaire et laboratoire abandonnés.
##
## Zones : a Salle de garde (départ) · b Couloir des cellules (piège)
##         c Laboratoire · d Dortoir · e Générateur · f Quai du téléporteur
##         p Salle du Pack-a-Punch (accessible par téléporteur uniquement)
## Marqueurs : voir MapDef. Généré à partir de rectangles puis retouché.

func _init() -> void:
	id = "bunker_k7"
	display_name = "BUNKER K-7"
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
	wall_buys = {"R": "carbine", "U": "smg", "V": "shotgun"}
	perks = {"Q": "lazarus", "J": "titan", "S": "rapid", "D": "twin", "M": "stride"}
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
		" #ZddddddVddddddZd#ZffffffffffDfffffffffffffffffZ# ###########  ",
		" #dddddddddddddddd#fOffffffffffffffffffffffffffff# #ppppKpppp#  ",
		" #ddIddddddddIdddd#fffffffffffffffffffffffffTTfff# #ppppppppp#  ",
		" #ddIdLdddddLIdddd#ffffLfffffffLfffffffLffffTTfff# #ppLpppLpp#  ",
		" #dddddddddddddddd5ffffffff,fffffffffffffffffffff# #ppppppppp#  ",
		" #dddddddddddddddd5ffffffffffffffffCCffffffffffff# #ppppFpppp#  ",
		" #Xddddddddddddddd#ffffffffffffffffCffffffffffLff# #ppppppppp#  ",
		" #ddIddddddddIdddd#ffffffffffffffffffffffffffffOf# #ppppppppp#  ",
		" #ddIddddddddIdddd#fffffXffffffffZffffffffffffffZ# ###########  ",
		" #ddddLdddddLddddd######################66########              ",
		" #dddddddddddddddJ#                    #cc#                     ",
		" #dddddddddddddddd#                    #Lc#                     ",
		" #ddddddZddddddddd#                    #cc#                     ",
		" ########11########                    #cc#                     ",
		" ########11########              #######cc#############         ",
		" #aaaaaaaaaaaaaaZa#              #ZccccccccccccccccccZ#         ",
		" #aaaaaaaaaaaaaaaa#              #cccccccccccccccccccc#         ",
		" #aaaaa,aaaaaaaCCa#              #ccccLccccccccccLcccc#         ",
		" #QaaLaaaaaaaLaCaa#              #cccccccccccccccccccc##########",
		" #aaaaaaaaaaaaaaaa################ccccNNNNccccNNNNcccc#eeeSeeeZ#",
		" #aOaaaaaaaaaaaaaa#bbbHbEEEb,bbbb#cccccccccccccccccccc#eeeeeeOe#",
		" #aaaaaaaaaaaaaaaa2bbLbbEEEbbbbbb3cccccccccccccccccccc#eLeeeeee#",
		" #aaaaaaPaPaaaaaaa2bbbbbEEEbbLbbb3ccccccccccLccccccccc4ee,eeeee#",
		" #aaaaaaaaaaaaaaaa#bZbbbEEEbbUbbb#cccccccccccccccccccc4eeeeeeeG#",
		" #aaaaaaPaPaaaaaaa################cccccccccccccccccccc#eeeYYeee#",
		" #aaaLaaaaaaaLaaaa#              #ccccNNNNccccNNNNcccc#eeeYYeee#",
		" #aaaaaaaaaaaa,aaa#              #cccccccccccccccccccc#eeeeeCLe#",
		" #aaaaaaaaaaaaaaaa#              #ccccLccccccccccLcccc#Zeeeeeee#",
		" #aZaaaaaaaaRaaaZa#              #ccccccccc,cccccccccM##########",
		" ##################              #cccccccccccccccccccc#         ",
		"                                 #ZcccccccccXcccccZccc#         ",
		"                                 ######################         ",
	])
