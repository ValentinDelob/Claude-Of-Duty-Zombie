extends TestCase
## Préréglages de qualité graphique (RenderQuality).

const KEYS := ["name", "lamp_shadows", "shadow_atlas", "shadow_filter", "light_fade_begin",
	"light_fade_length", "shadow_fade", "glow", "glow_bicubic", "ssao", "scale_3d", "msaa",
	"decal_fade", "decals", "particles"]


func test_one_preset_per_settings_quality() -> void:
	assert_eq(RenderQuality.PRESETS.size(), Settings.Quality.size())
	assert_eq(RenderQuality.preset(Settings.Quality.LOW).name, "low")
	assert_eq(RenderQuality.preset(Settings.Quality.MEDIUM).name, "medium")
	assert_eq(RenderQuality.preset(Settings.Quality.HIGH).name, "high")
	for q in RenderQuality.PRESETS:
		for k in KEYS:
			assert_true(q.has(k), "%s : clé %s" % [q.name, k])


func test_parse_names() -> void:
	assert_eq(RenderQuality.parse("LOW"), Settings.Quality.LOW)
	assert_eq(RenderQuality.parse("high"), Settings.Quality.HIGH)
	assert_eq(RenderQuality.parse("ultra"), -1)


func test_presets_are_ordered_by_cost() -> void:
	var low: Dictionary = RenderQuality.preset(Settings.Quality.LOW)
	var med: Dictionary = RenderQuality.preset(Settings.Quality.MEDIUM)
	var high: Dictionary = RenderQuality.preset(Settings.Quality.HIGH)
	assert_true(low.lamp_shadows <= med.lamp_shadows and med.lamp_shadows <= high.lamp_shadows, "ombres")
	assert_true(low.light_fade_begin <= med.light_fade_begin and med.light_fade_begin <= high.light_fade_begin, "fondu")
	assert_true(low.scale_3d <= med.scale_3d and med.scale_3d <= high.scale_3d, "résolution 3D")
	assert_true(low.particles <= med.particles, "particules")
	assert_eq(low.lamp_shadows, 0, "LOW : aucune ombre de lampe")


func test_lamp_shadow_selection() -> void:
	var counts := []
	for q in RenderQuality.PRESETS:
		var n := 0
		for i in 24:
			if RenderQuality.lamp_has_shadow(i, q):
				n += 1
		counts.append(n)
	assert_eq(counts, [0, 8, 16])
	# Les lampes à ombre de MEDIUM gardent leur ombre en HIGH (même ambiance).
	for i in 24:
		if RenderQuality.lamp_has_shadow(i, RenderQuality.preset(Settings.Quality.MEDIUM)):
			assert_true(RenderQuality.lamp_has_shadow(i, RenderQuality.preset(Settings.Quality.HIGH)), "lampe %d" % i)


## Éblouissement en HAUTE (MSAA 2x) : sur les bords d'un triangle, le MSAA
## évalue le shader avec des varyings extrapolés hors du triangle (et des
## dérivées dFdx/dFdy dégénérées) ; un pow() d'une base qui y devient
## négative, ou un normalize() d'un vecteur nul, donne NaN, que le glow étale
## en énorme tache blanche (colonne de la boîte mystère, en partie comme dans
## l'aperçu de l'éditeur). Tout pow() de shader doit avoir une base bornée à
## >= 0 ; dans un shader à dérivées, normalize() ne prend qu'un nom simple
## (un calcul sur les dérivées se protège à la main : longueur nulle -> repli).
func test_shader_pow_bases_are_guarded() -> void:
	var files: Array[String] = []
	for f in DirAccess.get_files_at("res://assets/shaders"):
		if f.ends_with(".gdshader"):
			files.append("res://assets/shaders/" + f)
	_gd_with_shaders("res://scripts", files)
	assert_true(files.size() > 10, "shaders trouvés (%d)" % files.size())
	for path in files:
		for problem in shader_nan_risks(FileAccess.get_file_as_string(path)):
			assert_true(false, "%s : %s" % [path, problem])


## La règle elle-même : bases sûres, et les anciens bogues refusés.
func test_shader_nan_rule() -> void:
	for base in ["2.0", "3", "max(1.0 - h01, 0.0)", "max(0.0, x)", "clamp(1.0 - dot(N, V), 0.0, 1.0)",
			"abs(dot(normalize(NORMAL), normalize(VIEW)))", " abs(x) "]:
		assert_true(pow_base_safe(base), "base sûre : " + base)
	for base in ["1.0 - h01", "1.0 - clamp(d, 0.0, 1.0)", "max(a, b)", "max(a, -1.0)", "max(a, 0.0) - 1.0",
			"abs(a) - b", "clamp(a, -1.0, 1.0)", "max(a, 0.0) * max(b, 0.0)", "-2.0", "x", "2.0 * x",
			"clamp(a, 0.0)", "abs(a, b)"]:
		assert_false(pow_base_safe(base), "base risquée refusée : " + base)
	# Ancien code de box_beam (tache blanche en HAUTE).
	var old_beam := "float vert = smoothstep(0.0, 0.18, h01) * pow(1.0 - h01, 1.3);"
	assert_eq(shader_nan_risks(old_beam).size(), 1, "ancien box_beam refusé")
	assert_eq(shader_nan_risks("float v = pow(max(1.0 - h01, 0.0), 1.3); // pow(1.0 - h01, 1.3)").size(), 0, "box_beam corrigé (commentaire ignoré)")
	# Ancien relief de la boîte mystère : normalize() d'un calcul de dérivées.
	var old_bump := "vec3 dp1 = dFdx(pos);\n\treturn normalize(abs(det) * n - grad * k);"
	assert_eq(shader_nan_risks(old_bump).size(), 1, "ancien relief de la boîte refusé")
	assert_eq(shader_nan_risks("vec3 dp1 = dFdx(pos);\n\tvec3 a = abs(normalize(onorm));").size(), 0, "normalize() d'un nom simple accepté")
	assert_eq(shader_nan_risks("vec3 a = normalize(x * 2.0 - y);").size(), 0, "sans dérivées : normalize() libre")


## Risques de NaN d'un code de shader (vide : aucun). Commentaires « // »
## ignorés (ils peuvent citer pow()).
static func shader_nan_risks(src: String) -> PackedStringArray:
	var lines := PackedStringArray()
	for line in src.split("\n"):
		var c := line.find("//")
		lines.append(line if c < 0 else line.substr(0, c))
	var code := "\n".join(lines)
	var out := PackedStringArray()
	for a in _calls(code, "pow"):
		if a.size() != 2 or not pow_base_safe(a[0]):
			out.append("pow() de base non bornée : pow(%s, ...)" % (a[0] if a.size() > 0 else ""))
	if code.contains("dFdx") or code.contains("dFdy") or code.contains("fwidth"):
		var simple := RegEx.create_from_string("^[A-Za-z_][A-Za-z0-9_.]*$")
		for a in _calls(code, "normalize"):
			if a.size() != 1 or simple.search(a[0]) == null:
				out.append("normalize() d'un calcul dans un shader à dérivées (vecteur nul possible) : normalize(%s)" % ", ".join(a))
	return out


## Base de pow() sûre : littéral positif, ou expression ENTIÈREMENT enveloppée
## par abs(x), max(x, 0…) / max(0…, x) ou clamp(x, 0…, …) (la parenthèse
## fermante de l'enveloppe termine la base).
static func pow_base_safe(base: String) -> bool:
	base = base.strip_edges()
	if base.is_valid_float():
		return not base.begins_with("-")
	for f in ["abs", "max", "clamp"]:
		if not base.begins_with(f + "(") or _close_paren(base, f.length()) != base.length() - 1:
			continue
		var args := _split_args(base.substr(f.length() + 1, base.length() - f.length() - 2))
		match f:
			"abs":
				return args.size() == 1
			"max":
				return args.size() == 2 and (_nonneg_literal(args[0]) or _nonneg_literal(args[1]))
			"clamp":
				return args.size() == 3 and _nonneg_literal(args[1])
	return false


static func _nonneg_literal(s: String) -> bool:
	s = s.strip_edges()
	return s.is_valid_float() and not s.begins_with("-")


## Arguments de chaque appel `fn(…)` de `code` (pas d'un nom qui finit par fn).
static func _calls(code: String, fn: String) -> Array[PackedStringArray]:
	var out: Array[PackedStringArray] = []
	var at := code.find(fn + "(")
	while at >= 0:
		var prev := code.substr(at - 1, 1) if at > 0 else ""
		var ident := prev != "" and (prev == "_" or prev.is_valid_identifier() or prev.is_valid_int())
		var open := at + fn.length()
		var close := _close_paren(code, open)
		if not ident:
			if close < 0:
				out.append(PackedStringArray([code.substr(open + 1)]))
			else:
				out.append(_split_args(code.substr(open + 1, close - open - 1)))
		at = code.find(fn + "(", open + 1)
	return out


## Indice de la parenthèse fermante qui correspond à celle en `open` (-1 : aucune).
static func _close_paren(s: String, open: int) -> int:
	var depth := 0
	for i in range(open, s.length()):
		var ch := s[i]
		if ch == "(":
			depth += 1
		elif ch == ")":
			depth -= 1
			if depth == 0:
				return i
	return -1


## Découpe des arguments de premier niveau (virgules hors parenthèses).
static func _split_args(s: String) -> PackedStringArray:
	var out := PackedStringArray()
	var depth := 0
	var start := 0
	for i in s.length():
		var ch := s[i]
		if ch == "(":
			depth += 1
		elif ch == ")":
			depth -= 1
		elif ch == "," and depth == 0:
			out.append(s.substr(start, i - start).strip_edges())
			start = i + 1
	out.append(s.substr(start).strip_edges())
	return out


## Scripts qui contiennent du code de shader (Shader.code en chaîne).
func _gd_with_shaders(dir: String, out: Array[String]) -> void:
	for d in DirAccess.get_directories_at(dir):
		_gd_with_shaders(dir.path_join(d), out)
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			var path := dir.path_join(f)
			if FileAccess.get_file_as_string(path).contains("shader_type "):
				out.append(path)
