class_name CubeFont
extends RefCounted
## Police « en cubes » propre au jeu (GAME_CONCEPT §4.19 : l'interface reste
## libre mais en harmonie avec le style cubique). Chaque lettre est une grille
## de 5 x 7 cubes (accents sur 2 rangées au-dessus, détachés d'une rangée
## vide ; cédille et virgule sur une rangée en dessous) ; chaque cube est
## cuit avec une arête claire en haut à
## gauche, une ombre en bas à droite et un liseré noir autour de la lettre.
##
## Deux usages :
##   * font() : FontFile bitmap générée au premier appel (aucun fichier),
##     glyphes en niveaux de gris teintés par la couleur du Label ; repli sur
##     une police système pour les caractères absents ;
##   * draw_cube() / glyph() : dessin direct cube par cube (compteur de manche,
##     animations par cube).

## Rangées des glyphes : 3 d'accent (2 + 1 vide), 7 de lettre, 1 de jambage.
const ACCENT_ROWS := 3
const CAP_ROWS := 7
const DESC_ROWS := 1
## Taille d'un cube dans la police cuite (px) et liseré noir (px).
const BAKE_CUBE := 12
const BAKE_OUTLINE := 3
## Taille nominale de la police : 10 cubes = font_size (la ligne entière en
## fait 11). À 72 px, une capitale fait ~50 px, comme une police système.
const FIXED_SIZE := (CAP_ROWS + 3) * BAKE_CUBE

const GLYPHS := {
	"A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
	"C": [".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."],
	"D": ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
	"E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
	"F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
	"G": [".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".####"],
	"H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"I": ["###", ".#.", ".#.", ".#.", ".#.", ".#.", "###"],
	"J": ["..###", "...#.", "...#.", "...#.", "#..#.", "#..#.", ".##.."],
	"K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
	"L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
	"M": ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"],
	"N": ["#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#", "#...#"],
	"O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"P": ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
	"Q": [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"],
	"R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
	"S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
	"T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
	"U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"V": ["#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
	"W": ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "##.##", "#...#"],
	"X": ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"],
	"Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
	"Z": ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"],
	"0": [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],
	"1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
	"2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
	"3": ["#####", "...#.", "..#..", "...#.", "....#", "#...#", ".###."],
	"4": ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
	"5": ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
	"6": ["..##.", ".#...", "#....", "####.", "#...#", "#...#", ".###."],
	"7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
	"8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
	"9": [".###.", "#...#", "#...#", ".####", "....#", "...#.", ".##.."],
	" ": ["...", "...", "...", "...", "...", "...", "..."],
	"-": ["....", "....", "....", "####", "....", "....", "...."],
	"—": [".....", ".....", ".....", "#####", ".....", ".....", "....."],
	".": [".", ".", ".", ".", ".", ".", "#"],
	",": [".", ".", ".", ".", ".", ".", "#"],
	":": [".", ".", "#", ".", ".", "#", "."],
	";": [".", ".", "#", ".", ".", "#", "#"],
	"!": ["#", "#", "#", "#", "#", ".", "#"],
	"?": [".###.", "#...#", "....#", "...#.", "..#..", ".....", "..#.."],
	"'": ["#", "#", ".", ".", ".", ".", "."],
	"/": ["....#", "...#.", "...#.", "..#..", ".#...", ".#...", "#...."],
	"%": ["##..#", "##..#", "...#.", "..#..", ".#...", "#..##", "#..##"],
	"(": [".#", "#.", "#.", "#.", "#.", "#.", ".#"],
	")": ["#.", ".#", ".#", ".#", ".#", ".#", "#."],
	"[": ["##", "#.", "#.", "#.", "#.", "#.", "##"],
	"]": ["##", ".#", ".#", ".#", ".#", ".#", "##"],
	"+": [".....", "..#..", "..#..", "#####", "..#..", "..#..", "....."],
	"×": [".....", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "....."],
	"«": [".....", "..#.#", ".#.#.", "#.#..", ".#.#.", "..#.#", "....."],
	"»": [".....", "#.#..", ".#.#.", "..#.#", ".#.#.", "#.#..", "....."],
	"·": [".", ".", ".", "#", ".", ".", "."],
	# Croix médicale (« ✚ À TERRE » au-dessus d'un coéquipier, Tag3D).
	"✚": ["..###..", "..###..", "#######", "#######", "#######", "..###..", "..###.."],
}
## Signes diacritiques (2 rangées au-dessus de la lettre, largeur 5 ; centrés
## sur les lettres plus étroites).
const ACCENTS := {
	"acute": ["...#.", "..#.."],
	"grave": [".#...", "..#.."],
	"circ": ["..#..", ".#.#."],
	"trema": [".....", ".#.#."],
}
## Lettres accentuées : [lettre de base, accent ("cedilla" : sous la lettre)].
const ACCENTED := {
	"É": ["E", "acute"], "È": ["E", "grave"], "Ê": ["E", "circ"], "Ë": ["E", "trema"],
	"À": ["A", "grave"], "Â": ["A", "circ"], "Ä": ["A", "trema"],
	"Ù": ["U", "grave"], "Û": ["U", "circ"], "Ü": ["U", "trema"],
	"Ô": ["O", "circ"], "Ö": ["O", "trema"], "Î": ["I", "circ"], "Ï": ["I", "trema"],
	"Ç": ["C", "cedilla"],
}
## Signes qui descendent sous la ligne (rangée de jambage) : [colonne].
const DESCENDERS := {",": 0, ";": 0}

static var _font: FontFile


## Glyphe d'un caractère : 11 rangées (3 d'accent, 7 de lettre, 1 de
## jambage) de même largeur ; [] si le caractère n'existe pas. Les minuscules
## prennent le dessin des capitales (police de titres).
static func glyph(ch: String) -> PackedStringArray:
	var up := ch.to_upper()
	if ch == " " or ch == " ":
		up = " "
	if ch == "’":
		up = "'"
	var base := up
	var accent := ""
	if ACCENTED.has(up):
		base = ACCENTED[up][0]
		accent = ACCENTED[up][1]
	if not GLYPHS.has(base):
		return PackedStringArray()
	var rows: Array = GLYPHS[base]
	var w: int = String(rows[0]).length()
	var empty := ".".repeat(w)
	var out := PackedStringArray()
	# Accent sur 2 rangées, puis une rangée vide qui le détache de la lettre.
	if accent != "" and accent != "cedilla":
		for r: String in ACCENTS[accent]:
			out.append(_fit(r, w))
	else:
		out.append(empty)
		out.append(empty)
	out.append(empty)
	for r: String in rows:
		out.append(r)
	if accent == "cedilla":
		out.append(_fit("..#..", w))
	elif DESCENDERS.has(base):
		var d := empty
		d[DESCENDERS[base]] = "#"
		out.append(d)
	else:
		out.append(empty)
	return out


## Recentre une rangée de 5 sur une largeur `w` (lettres étroites).
static func _fit(r: String, w: int) -> String:
	if r.length() == w:
		return r
	var cut := floori((r.length() - w) / 2.0)
	return r.substr(cut, w)


## Caractères disponibles (capitales, minuscules, accents, chiffres, signes).
static func chars() -> PackedStringArray:
	var out := PackedStringArray()
	for k: String in GLYPHS:
		out.append(k)
		if k.to_lower() != k:
			out.append(k.to_lower())
	for k: String in ACCENTED:
		out.append(k)
		out.append(k.to_lower())
	for k in [" ", " ", "’"]:
		out.append(k)
	return out


## Un cube dessiné dans `ci` : face teinte `col`, arête claire en haut à
## gauche, ombre en bas à droite (même rendu que la police cuite).
static func draw_cube(ci: CanvasItem, r: Rect2, col: Color) -> void:
	var e := maxf(r.size.x * 0.16, 1.0)
	ci.draw_rect(r, col)
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, e)), col.lightened(0.35))
	ci.draw_rect(Rect2(r.position + Vector2(0, e), Vector2(e, r.size.y - e)), col.lightened(0.18))
	ci.draw_rect(Rect2(r.position + Vector2(0, r.size.y - e), Vector2(r.size.x, e)), col.darkened(0.42))
	ci.draw_rect(Rect2(r.position + Vector2(r.size.x - e, e), Vector2(e, r.size.y - 2.0 * e)), col.darkened(0.28))


## Police de titres en cubes (FontFile bitmap, générée une fois).
static func font() -> FontFile:
	if _font:
		return _font
	var c := BAKE_CUBE
	var o := BAKE_OUTLINE
	var rows := ACCENT_ROWS + CAP_ROWS + DESC_ROWS
	var cell_h := rows * c + 2 * o
	var list := chars()
	# Atlas : une rangée de cellules par 16 glyphes.
	var max_w := 0
	for ch in list:
		max_w = maxi(max_w, glyph(ch)[0].length())
	var cell_w := max_w * c + 2 * o
	var per_row := 16
	var atlas_rows := int(ceil(float(list.size()) / per_row))
	var img := Image.create(per_row * cell_w, atlas_rows * cell_h, false, Image.FORMAT_LA8)
	img.fill(Color(0, 0, 0, 0))
	var f := FontFile.new()
	var sz := Vector2i(FIXED_SIZE, 0)
	f.fixed_size = FIXED_SIZE
	f.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
	f.generate_mipmaps = true
	f.set_cache_ascent(0, FIXED_SIZE, float((ACCENT_ROWS + CAP_ROWS) * c))
	f.set_cache_descent(0, FIXED_SIZE, float(DESC_ROWS * c))
	for i in list.size():
		var ch: String = list[i]
		var g := glyph(ch)
		var w := g[0].length()
		var origin := Vector2i((i % per_row) * cell_w, floori(float(i) / per_row) * cell_h)
		_bake(img, origin, g, c, o)
		var code := ch.unicode_at(0)
		f.set_glyph_advance(0, FIXED_SIZE, code, Vector2((w + 1) * c, 0))
		f.set_glyph_offset(0, sz, code, Vector2(-o, -(ACCENT_ROWS + CAP_ROWS) * c - o))
		f.set_glyph_size(0, sz, code, Vector2(w * c + 2 * o, cell_h))
		f.set_glyph_uv_rect(0, sz, code, Rect2(origin.x, origin.y, w * c + 2 * o, cell_h))
		f.set_glyph_texture_idx(0, sz, code, 0)
	f.set_texture_image(0, sz, 0, img)
	var fallback := SystemFont.new()
	fallback.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial", "sans-serif"])
	fallback.font_weight = 700
	f.fallbacks = [fallback]
	_font = f
	return f


## Cuit un glyphe dans l'atlas : liseré noir (dilatation du masque), puis
## cubes en niveaux de gris (teintés ensuite par la couleur du texte).
static func _bake(img: Image, origin: Vector2i, g: PackedStringArray, c: int, o: int) -> void:
	var black := Color(0, 0, 0, 1)
	for y in g.size():
		for x in g[y].length():
			if g[y][x] == "#":
				img.fill_rect(Rect2i(origin + Vector2i(x * c, y * c), Vector2i(c + 2 * o, c + 2 * o)), black)
	var e := maxi(int(c * 0.16), 1)
	for y in g.size():
		for x in g[y].length():
			if g[y][x] != "#":
				continue
			var p := origin + Vector2i(o + x * c, o + y * c)
			img.fill_rect(Rect2i(p, Vector2i(c, c)), Color(0.94, 0.94, 0.94, 1))
			img.fill_rect(Rect2i(p, Vector2i(c, e)), Color(1, 1, 1, 1))
			img.fill_rect(Rect2i(p + Vector2i(0, e), Vector2i(e, c - e)), Color(1, 1, 1, 1))
			img.fill_rect(Rect2i(p + Vector2i(0, c - e), Vector2i(c, e)), Color(0.66, 0.66, 0.66, 1))
			img.fill_rect(Rect2i(p + Vector2i(c - e, e), Vector2i(e, c - 2 * e)), Color(0.78, 0.78, 0.78, 1))
