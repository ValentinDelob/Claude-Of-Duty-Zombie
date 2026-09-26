extends MapDef
## KINO — théâtre abandonné (inspiré de Kino der Toten, Black Ops).
##
## Zones : a Hall d'entrée (départ, poste central du téléporteur, M14 et
##         Olympia au mur) · b Foyer (LAZARUS TONIC, MP5K, MPL)
##         c Loges (couloir piégé, coiffeuses, TWIN SHOT, PM63)
##         e Salle des machines / arrière-scène (courant, couteau de chasse)
##         d Allée (ruelle, passage étroit piégé, RAPID FIZZ, Stakeout)
##         g Scène (téléporteur, Pack-a-Punch après le premier voyage)
##         f Salle de théâtre (fauteuils, TITAN BREW, M16)
##         p Cabine de projection (arrivée du téléporteur uniquement)
## Parcours : hall -(1000)- foyer -(1000)- allée -(1250)- théâtre ;
##            hall -(750)- loges -(1000)- machines = scène = théâtre.
## Téléporteur (comme à Kino) : courant, puis activer la plateforme de la scène
## et la relier au poste central du hall ; chaque voyage (1500) mène à la
## cabine de projection puis ramène devant le poste central, et il faut
## relier à nouveau. Le premier voyage fait surgir le Pack-a-Punch sur scène.
## Grille générée à partir de rectangles (salles, poches des fenêtres) puis
## retouchée ; marqueurs : voir MapDef.

func _init() -> void:
	id = "kino"
	display_name = "KINO"
	description = "Un théâtre abandonné où l'on projetait autrefois les films du Reich. Les rideaux sont rouges ; la moquette aussi, désormais."
	zone_names = {
		"a": "Hall d'entrée", "b": "Foyer", "c": "Loges", "d": "Allée",
		"e": "Salle des machines", "f": "Salle de théâtre", "g": "Scène",
		"p": "Cabine de projection",
	}
	doors = {
		"1": {"cost": 1000},
		"2": {"cost": 750},
		"3": {"cost": 1000},
		"4": {"cost": 1000},
		"5": {"cost": 1250},
	}
	# Arsenal mural de Kino der Toten (contour à la craie).
	wall_buys = {
		"R": "m14", "V": "olympia",           # hall d'entrée (départ)
		"U": "mp5k", "B": "mpl",              # foyer
		"<": "pm63",                          # loges
		">": "stakeout",                      # allée
		"/": "m16",                           # salle de théâtre
		"%": "bowie",                         # salle des machines : couteau de chasse
	}
	perks = {"Q": "lazarus", "D": "twin", "S": "rapid", "J": "titan"}
	extra_blocking = "=$@|^"
	theater_props = true
	# Emplacements (ordre des X) : 0 cour de l'allée, 1 théâtre, 2 ruelle,
	# 3 loges, 4 foyer. Départ tiré au sort parmi foyer, loges, allée.
	box_start = 4
	box_starts = [0, 3, 4]
	zone_materials = {
		"a": ["marble", "wall_lobby", "ceiling_theater"],
		"b": ["parquet", "wall_foyer", "ceiling_theater"],
		"c": ["tiles", "wall_loges"],
		"d": ["cobble", "brick", "night_sky"],
		"e": ["metal", "wall_rust"],
		"f": ["carpet_red", "wall_theater", "ceiling_theater"],
		"g": ["stage_wood", "wall_theater", "ceiling_theater"],
		"p": ["wood", "wall_concrete"],
	}
	zone_heights = {"a": 5.2, "b": 4.2, "d": 7.0, "f": 6.5, "g": 6.5}
	# Galerie du hall : le foyer « à l'étage » vu d'en bas.
	balcony_zone = "a"
	stage_zone = "g"
	# Machines, scène et salle communiquent sans porte.
	open_links = {"e": ["g", "f"], "f": ["g", "e"]}
	pipe_zones = ["e"]
	music = "ambience_kino"
	teleport_banner = "CABINE DE PROJECTION"
	teleporter_link = true
	pap_revealed_by_teleporter = true
	look = {
		"ambient_color": Color(0.42, 0.3, 0.24),
		"ambient_energy": 0.27,
		"fog_color": Color(0.07, 0.045, 0.035),
		"fog_density": 0.04,
		"saturation": 0.85,
	}
	rows = PackedStringArray([
		"                                                                        ",
		"        ################################################################",
		"        #eeeeeGeeeeO#~~~ggg]]]]]]]]]]]]]]]]]]ggg~~~#+dddddddddddddddddd#",
		"     ####eeeeeeeeeZeggggTTgggggggggKggggggggggggggg#dOddddOddddddddddZd#",
		"     #ee#eeeeeeeeeeeggggTTggLggggggggggggggLggggggg#ddddddddddddddddddd#",
		"     #ZeWeeeLeeeeeeeggggggggggggggggggggggggggggggg#ddddLddddddd,dddddd#",
		"     #ee#eeeeeeeeee%#gggggggggggggggggggggggggggggg#ddddddddddddddddddX#",
		"     ####eeeeeeeeLee#ffffffffffffffffffffffffffffff#ddddddddddddddddddd#",
		"        #eeeeeeeeeee#ffffffffffffffffffffffffffffZf#!dddddddddddddLdddd#",
		"        #Ceeeeeeeeee#!fffffffffffffffffffffffffffff5ddddddddddddddddddd#",
		"        ####44#######fff===========ff===========fff5ddddddddddddddddCCd#",
		"          #ccc#     #Xfffffffffffffffffffffffffffff#ddCCddddddddddddddd#",
		"          #Hcc# #####fff===========ff===========ff/######W##ddd##W######",
		"          #cLc# #fff#ffffffff?ffffffffffff?ffffffff#   #dZd#dLd#dZd#    ",
		"          #EEE# #ZffWfff===========ff===========fff#   #ddd#ddd#ddd#    ",
		"          #EEE# #fff#ffffff,ffffffffffffffffffffff!#########EEE#####    ",
		"          #EEE# #####Jff===========ff===========fff#fff#   #EEE#####    ",
		"          #ccc#     #ffffffffffffff?fffffffffffffffWfZf#   #EEE#dZd#    ",
		"###########ccc#######fff===========ff===========fff#fff#   #ddd#ddd#    ",
		"#cc$c$c$ccccccc$c$cc#fZffffffffffffffffffffffffffZf#########ddd##W######",
		"#cZccccccccccccccccc#ffffffffffffffffffffffffffffff#ddddd,dHddddddOddOd#",
		"#ccccccccccccccccccc################################Odddddddddddddddddd#",
		"#ccc^ccc^ccccccccccc#       ##############         #ddddddddddddddddddS#",
		"#ccccLcccccccccccccc# ##### #ppp@ppppp@pp######    #ddddLdddddddddddddd#",
		"#Xcccccccccccc^ccccc# #aZa# #pppppLFppppp##aZa#    #Xddddddddddddddddd>#",
		"#cccccccccccccccccc<# #aaa# #pppppppppppp##aaa#    #ddddddddddddddLddZd#",
		"#ccccccccccccccccccc####W###################W##    #dZdddddddddddddddd!#",
		"#ccccccc,ccccccc^ccc#aaaaaaaaaaaa+aaaaaaaaaaaa#    #ddddddddddddCCddddd#",
		"#ccccccccccccccccccc#aaaaaaaaaaaaaaaaaaaaaaaaa##############33##########",
		"#DccccccccccccLccccc#aaZaaaaaaaaaaaaaaaaaaaaaa#bbbbbUbbbbbbbbb&bbbbBbbb#",
		"#ccccc^ccccccccccccc2aaaaaaaaaaaaaaaaaaaaaaaaV#bbbbbbbbbbbbbbbbbbbbbbb*#",
		"#&cccccccccccccccccc2aaaaa|aaaaaa?aaaaaa|aaaaa#bbbbbbbbbbbbbbbbbbbbbbZb#",
		"#cccccccccccccccccZc#aaaaaaaaaaaaaaaaaaaaaaaaa#!bbbbbbbb|bbbbb|bbbbbbbb#",
		"#ccccccccc+ccccccccc#!aaaaaaaaaaaaaaaa,aaaaaa*#bbbbbbbbbbbbbbbbbbbbbbb&#",
		"######W########W#####aaaaaaaaaaPaaaPaaaaaaaaaa#bbbbbbbbbbbbbbbbbbbbbbbb#",
		"    #ccc#    #ccc#  #aaaaaaaaaaaaaaaaaaaaaaaaa1bbbbbbbbbbbbbbbbbbbbbbbb#",
		"    #cZc#    #cZc#  #aaaaaaaaaaPaaaPaaaaaaaaaa1bbbbbb?bbbbbbbbbb?bbbbbX#",
		"    #####    #####  #aaaaaaaaaaaaaaaaaaaaaaaaa#bbbbbbbbbbbbbbbbbbbbbbbb#",
		"                    #Raaaaaaaaaaaaaaaaaaaaaaaa#bbbbbbbbbbbbbbbbbbbbbbbb#",
		"                    #aaaaa|aaaaaa?aaaaaa|aaaaa#Qbbbbbbbbbbbbbbbbbbbbbbb#",
		"                    #aaaaaaaaaaaaaaaaaaaaaaaa!#bbbbbbbbb|bbbbb|bbbbbbb!#",
		"                    #&aaaaaaaaaaaaaaaaaaaaaaZa#bbbbbbbbbbbbbbbbbbbbbbbb#",
		"                    #aaaaaaaaaaaaaaaaaaaaaaaaa#bZbbbbbbbbbbbbbbbbbbbbbb#",
		"                    #aaaa&aaaaaaaAaaaaaaa&aaaa#bbb&bbbbbbb+bbbbbbbbbbbb#",
		"                    ######W#############W##############W##########W#####",
		"                        #aaa#         #aaa#          #bbb#      #bbb#   ",
		"                        #aZa#         #aZa#          #bZb#      #bZb#   ",
		"                        #####         #####          #####      #####   ",
	])
