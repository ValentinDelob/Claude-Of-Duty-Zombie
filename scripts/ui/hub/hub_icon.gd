class_name HubIcon
extends Control
## Icône en pixel art du hub (un pixel = un cube, HUB_PLAN §4.4) : mêmes
## dessins et même palette que la maquette (docs/hub_mockup/index.html, script
## en bas de page), contour noir de 2 px autour des pixels pleins. `scale_px` :
## taille d'un pixel à 100 % (data-s de la maquette), mise à l'échelle par
## HubStyle.px.

## Palette : un caractère = une couleur ('.' = vide).
const PAL := {
	"k": "000000", "w": "E8E6DC", "W": "BDB9AC", "s": "C99B78", "S": "A87A5A", "g": "C9C9C2", "G": "7C7B76",
	"b": "8FB8C8", "r": "B81A1A", "y": "E0B31F", "m": "3D4042", "M": "8C9196", "n": "5C6064", "d": "54381F",
	"o": "855C38", "O": "A8784A", "c": "734024", "C": "8F5530", "l": "A88038", "f": "8A7A62", "F": "5E5240",
	"t": "EDE6CF", "T": "BFB49A", "e": "457366", "E": "8FAD9E", "p": "DBD6C2", "x": "2A2C2E", "h": "E0503A",
	"u": "365E94", "z": "66786B", "P": "B9B4A2",
}
const ART := {
	"doc": ["....gggggggg....", "..gggggggggggg..", ".ggggGGggGGgggg.", ".ggsssssssssssg.", ".gsssssssssssssg",
		"..skkkkssskkkks.", "..skbbkSSkbbks..", "..skkkksskkkks..", "..sssssSSsssss..", "..sssktttttkss..",
		"...sssskkksss...", "....ssssssss....", "..wwwwSssSwwww..", ".wwwwwwrrwwwwww.", "wwwwwwwrrwwwwwww",
		"wwwWwwwrrwwwlwww"],
	"fang": ["...tt...", "...ttt..", "...tTt..", "..ttTt..", "..tTT...", ".ttT....", ".tT.....", ".T......"],
	"fur": ["..f..f..", ".ff.ff.f", ".fFffFf.", "fFffFfF.", ".fFfFff.", "..fFFf..", "...ff...", "........"],
	"collar": ["..cccc..", ".cC..Cc.", "cC....Cc", "c......c", ".c....c.", "..cllc..", "...ll...", "...yy..."],
	"unk": ["..GGGG..", ".GG..GG.", ".....GG.", "....GG..", "...GG...", "...GG...", "........", "...GG..."],
	"part": ["...MM...", ".M.MM.M.", "..MMMM..", "MMMnnMMM", "MMMnnMMM", "..MMMM..", ".M.MM.M.", "...MM..."],
	"pistol": [".mmmmmmmmmmmmmm.", ".mMMMMMMMMMMMMm.", ".mmmmmmmmmmmmmm.", ".dddd.km........", ".dddd.kk........",
		".dddd...........", ".dddd..........."],
	"revolver": ["....mmmmmmmmmmmmmm", ".mmmmMMMMMMMMMMMMm", ".mmMMmmmmmmmmmmmm.", ".oooo.kmm.........",
		".oooo.kk..........", ".oooo.............", ".oooo............."],
	"smg": ["......mmmmmmmmmmmm......", "mmmmmmMMMMMMMMMMMMmmmmmm", "mmm...mmmmmmmmmmmm......",
		"mmm...mm.mmm..mm........", "......mm.mmm............", ".........mmm............", ".........mmm............"],
	"rifle": ["...........mmmm.............", "oooo.mmmmmmmmmmmmmmmmmmmmmmm", "oooommMMMMMMMMMMMMMMMMMmmmmm",
		"oooommmmmmmmmmmmmmmmmm......", "ooo....mm..mmm..............", ".......mm..mmm..............",
		"...........mm..............."],
	"shotgun": ["oooo..mmmmmmmmmmmmmmmmmmmm", "oooOmmmMMMMMMMMMMMMMMMMMMm", "oooommmmmmmmmmmmmmmmmmmmm.",
		"ooo....mm..oooooooo.......", ".......mm................."],
	"bat": ["..............oooooooooo", "kkkkooooooooooOOOOOOOOOo", "kkkkoooooooooooooooooooo", "..............oooooooooo"],
	"knife": [".........MMMM.", "ddddddkMMMMMMM", "ddddddkMMMMMM.", ".............."],
	"mapico": ["zzzzzzzz", "zppzppMz", "zppzppMz", "zzMzzMzz", "zppMppez", "zppzppez", "zzzzzzzz"],
	"map": ["mmmmmmmmmmmmmmmmmmmmmmmm", "mppppppmEEEEEEEEmppppppm", "mppppppmEEEEEEEEmppppppm",
		"mpppppp.EEEEEEEE.ppppppm", "mppppppmEEEyEEEEmppppppm", "mmmm.mmmmmmm.mmmmmmm.mmm", "mzzzzzzzzzm.....mpppppPm",
		"mzzzzzzzzzm.....mpppppPm", "mzzzzzzzzz......mppppprm", "mzzzzzzzzzm.....mpppppPm", "mmmmmmmmmmmmmmmmmmmmmmmm"],
}
## Icône de chaque sorte d'échantillon (LootRules.SAMPLES) ; autre : « unk ».
const SAMPLE_ART := {"dog_fang": "fang", "dog_fur": "fur", "dog_collar": "collar"}

var art := "unk":
	set(v):
		art = v
		_resize()
## Taille d'un pixel à 100 %.
var scale_px := 2.0:
	set(v):
		scale_px = v
		_resize()
## Opacité des couleurs (icône grisée d'un objet verrouillé : 0,5).
var dim := 1.0
## Contour noir (2 px à 100 %).
var outline := true


static func make(name: String, s := 2.0) -> HubIcon:
	var i := HubIcon.new()
	i.art = name
	i.scale_px = s
	return i


static func sample_art(kind: String) -> String:
	return SAMPLE_ART.get(kind, "unk")


## Taille du dessin en pixels de l'icône (colonnes, lignes).
static func grid_size(name: String) -> Vector2i:
	var rows: Array = ART.get(name, [])
	var w := 0
	for r in rows:
		w = maxi(w, String(r).length())
	return Vector2i(w, rows.size())


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_resize()


func _resize() -> void:
	var g := grid_size(art)
	custom_minimum_size = Vector2(g) * _cell()
	queue_redraw()


func _cell() -> float:
	return maxf(scale_px * HubStyle.factor(), 0.5)


func _draw() -> void:
	var rows: Array = ART.get(art, [])
	var c := _cell()
	# Centré dans la place donnée par le conteneur.
	var g := grid_size(art)
	var off := ((size - Vector2(g) * c) * 0.5).floor()
	if outline:
		var o := HubStyle.px(2)
		for y in rows.size():
			var row := String(rows[y])
			for x in row.length():
				if row[x] != "." and PAL.has(row[x]):
					draw_rect(Rect2(off + Vector2(x * c - o, y * c - o), Vector2(c + o * 2.0, c + o * 2.0)), Color(0, 0, 0, dim))
	for y in rows.size():
		var row := String(rows[y])
		for x in row.length():
			var ch := row[x]
			if ch != "." and PAL.has(ch):
				var col := Color(PAL[ch])
				col.a = dim
				draw_rect(Rect2(off + Vector2(x * c, y * c), Vector2(c, c)), col)
