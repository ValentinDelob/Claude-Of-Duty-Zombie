extends TestCase
## Format 17 (docs/LEVELS_PLAN.md § 7) : l'export en jeu (MapLayoutExport, par
## le chemin de l'aperçu 3D : MapPreviewWorld.compute) des cartes d'avant,
## CONVERTIES au chargement (EditorMap.migrate_levels), est celui que donnait
## le code du format 16 (références tests/fixtures/levels/*_layout_f16.json,
## enregistrées avant la refonte). Les seules différences admises sont
## listées dans TOLERATED, avec leur raison.

const DIR := "res://tests/fixtures/levels/"
const EPS := 0.0011

const EVAC := "format 18 : porte d'évacuation ajoutée aux fixtures (obligatoire)"
## Ses cases ne sont plus du sol : le regard de départ (vers le milieu du sol
## de la zone de départ) bouge d'un centième de radian.
const EVAC_YAW := "format 18 : cases de la porte d'évacuation retirées du sol de la zone de départ"
const STATION := "format 19 : station de construction ajoutée aux fixtures (obligatoire)"
## Différences admises : carte -> {chemin (préfixe) : raison}.
const TOLERATED := {
	"draft_arena": {"/markers/evac": EVAC, "/markers/player_yaw": EVAC_YAW, "/markers/station": STATION},
	"smallest": {"/markers/evac": EVAC, "/markers/player_yaw": EVAC_YAW, "/markers/station": STATION},
	"smallest_door": {"/markers/evac": EVAC, "/markers/player_yaw": EVAC_YAW, "/markers/station": STATION},
	"smallest_double_door": {"/markers/evac": EVAC, "/markers/player_yaw": EVAC_YAW, "/markers/station": STATION},
}
## Format 18 : erreur « aucune porte d'évacuation » propre aux nouvelles
## règles, absente des références f16 (non comptée) ; format 19 : de même,
## « aucune station de construction ».
const EVAC_ERROR := "porte d'évacuation"
const STATION_ERROR := "station de construction"


## Carte d'avant (format 16) de la référence `name`.
static func legacy_map(name: String) -> EditorMap:
	if name == "draft_arena":
		return EditorMap.load_dir("res://tests/fixtures/maps/legacy_draft_arena/")
	if name.begins_with("smallest"):
		return EditorMap.load_dir("res://tests/fixtures/maps/%s/" % name)
	var texts: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + "%s_map_f16.json" % name))
	return EditorMap.from_texts(texts if texts is Dictionary else {})


static func names() -> Array:
	var out := []
	for f in DirAccess.get_files_at(DIR):
		if f.ends_with("_layout_f16.json"):
			out.append(f.trim_suffix("_layout_f16.json"))
	out.sort()
	return out


## Différences entre deux valeurs JSON (nombres à EPS près) : [chemin...].
static func diff(a: Variant, b: Variant, path := "", out: Array = []) -> Array:
	if out.size() > 40:
		return out
	if (a is float or a is int) and (b is float or b is int):
		if absf(float(a) - float(b)) > EPS:
			out.append("%s : %s -> %s" % [path, str(a), str(b)])
		return out
	if a is Dictionary and b is Dictionary:
		for k in a:
			if not b.has(k):
				out.append("%s/%s : retiré" % [path, k])
			else:
				diff(a[k], b[k], "%s/%s" % [path, k], out)
		for k in b:
			if not a.has(k):
				out.append("%s/%s : ajouté" % [path, k])
		return out
	if a is Array and b is Array:
		if a.size() != b.size():
			out.append("%s : %d -> %d éléments" % [path, a.size(), b.size()])
			return out
		for i in a.size():
			diff(a[i], b[i], "%s[%d]" % [path, i], out)
		return out
	if typeof(a) != typeof(b) or a != b:
		out.append("%s : %s -> %s" % [path, str(a).left(60), str(b).left(60)])
	return out


func test_references_present() -> void:
	assert_true(names().size() >= 16, "références enregistrées (%d)" % names().size())


## Régénération des références après un changement VOULU de l'export
## (format 20 : architecture sur la grille des cubes de 5 cm,
## docs/VOXEL_ARCHITECTURE_PLAN.md § 2.5), par le lanceur de tests :
##   REGEN_LEVEL_REFS=1 godot --headless --path . res://tests/test_runner.tscn -- --files=test_levels_reference.gd
## Chaque référence est réécrite (même nombre d'erreurs du validateur, gardé ;
## différences avec l'ancienne imprimées), puis DRAFT ARENA est réenregistrée
## au format courant (assets/maps/draft_arena/). Un nombre d'erreurs qui
## change ou une valeur d'architecture hors de la grille fait échouer.
static func regenerate() -> int:
	var bad := 0
	for name in names():
		var path := DIR + "%s_layout_f16.json" % name
		var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		var doc := legacy_map(name)
		var raw: Dictionary = MapPreviewWorld.compute(doc).data
		var now: Dictionary = JSON.parse_string(JSON.stringify(raw))
		var d := diff(old.layout, now, "", [])
		var v := MapRaster.build(doc).v
		v.analyze()
		var errs := v.errors().filter(func(m): return not String(m.fr).contains(EVAC_ERROR) and not String(m.fr).contains(STATION_ERROR))
		var off := MapLayoutExport.off_grid(now)
		print("[refs] %s : %d différence(s), %d erreur(s) (référence %d), %d valeur(s) hors grille" % [name, d.size(), errs.size(), int(old.errors), off.size()])
		for line in d.slice(0, 40):
			print("         ", line)
		if errs.size() != int(old.errors) or not off.is_empty():
			bad += 1
			print("[refs] ATTENTION %s : erreurs %d (référence %d), hors grille %s" % [name, errs.size(), int(old.errors), ", ".join(off.slice(0, 5))])
		var fa := FileAccess.open(path, FileAccess.WRITE)
		# Écrite comme les références d'origine : la description telle que
		# calculée (entiers gardés), JSON trié, indentée d'une espace ; « map »
		# et « messages » (validateur du code du format 16, pour information)
		# gardés tels quels.
		var out := old.duplicate()
		out["layout"] = raw
		out["errors"] = int(old.errors)
		fa.store_string(JSON.stringify(out, " ", true))
		fa.close()
	var src := String(EditorMap.EXAMPLES.draft_arena)
	var draft := EditorMap.load_dir(src)
	print("[refs] DRAFT ARENA : format %d -> %d, %d valeur(s) arrondie(s)" % [draft.format_read, EditorMap.FORMAT, draft.cube_changes])
	if draft.save_dir(ProjectSettings.globalize_path(src)) != OK:
		bad += 1
	return bad


func test_export_identical_after_migration() -> void:
	if OS.get_environment("REGEN_LEVEL_REFS") == "1":
		assert_eq(regenerate(), 0, "références régénérées sans problème")
	for name in names():
		var ref: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + "%s_layout_f16.json" % name))
		var doc := legacy_map(name)
		assert_true(doc.load_errors.is_empty(), "%s : lue sans erreur %s" % [name, doc.load_errors])
		assert_false(doc.carte.has("etages"), "%s : convertie au format 17" % name)
		var now: Variant = JSON.parse_string(JSON.stringify(MapPreviewWorld.compute(doc).data))
		var d := diff(ref.layout, now)
		var tol: Dictionary = TOLERATED.get(name, {})
		var left := d.filter(func(line: String) -> bool:
			for pre in tol:
				if line.begins_with(String(pre)):
					return false
			return true)
		assert_true(left.is_empty(), "%s : export différent de la référence f16 :\n  %s" % [name, "\n  ".join(left.slice(0, 15))])
		# Messages du validateur : autant d'erreurs qu'avant.
		var v := MapRaster.build(doc).v
		v.analyze()
		var errs := v.errors().filter(func(m): return not String(m.fr).contains(EVAC_ERROR) and not String(m.fr).contains(STATION_ERROR))
		assert_eq(errs.size(), int(ref.errors), "%s : nombre d'erreurs du validateur (%s)" % [name, "\n".join(errs.map(func(m): return String(m.fr)))])


## Format 20 : TOUTES les valeurs d'architecture de chaque référence (et de
## l'export actuel) sont des multiples de 5 cm (MapLayoutExport.off_grid).
func test_references_on_cube_grid() -> void:
	for name in names():
		var ref: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + "%s_layout_f16.json" % name))
		var off := MapLayoutExport.off_grid(ref.layout)
		assert_true(off.is_empty(), "%s : référence hors de la grille des cubes : %s" % [name, ", ".join(off.slice(0, 8))])
	# Le contrôle attrape bien une valeur hors grille.
	assert_false(MapLayoutExport.off_grid({"rooms": [{"outline": [[0, 0], [1.02, 0], [1, 1]], "floor": 0, "ceiling": 3.19}]}).is_empty())
	assert_true(MapLayoutExport.off_grid({"blocks": [{"box": [0, 0, 0, 0.005, 1, 1], "decor": true}]}).is_empty(), "décor : ses propres règles")


## Le filet attrape bien une différence (sinon il ne prouverait rien).
func test_diff_detects_a_change() -> void:
	var name := "stairs_heights"
	var ref: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + "%s_layout_f16.json" % name))
	var doc := legacy_map(name)
	assert_near(EditorMap.room_ceiling(doc.find("p0")), 3.7, 0.001, "pièce entièrement couverte : plafond porté au dessous de la dalle (4 - 0,3)")
	assert_near(EditorMap.room_ceiling(doc.find("p3")), 3.2, 0.001, "plafond de l'étage 3 (3 m) porté à la dalle du dessus (15,5 - 0,3 - 12)")
	doc.find("p4")["plafond"] = 4.0
	var now: Variant = JSON.parse_string(JSON.stringify(MapPreviewWorld.compute(doc).data))
	assert_false(diff(ref.layout, now).is_empty(), "plafond changé : l'export diffère")
