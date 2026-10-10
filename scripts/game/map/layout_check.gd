class_name LayoutCheck
extends RefCounted
## Contrôle de l'ARCHITECTURE CUBIQUE d'une carte jouable
## (docs/VOXEL_ARCHITECTURE_PLAN.md, GAME_CONCEPT.md § 4.19) : toute
## l'architecture (sols, plafonds, dalles, murs droits, en biais et courbes,
## piliers, cours, escaliers, rampes, garde-corps) n'est faite que de cubes
## sur la grille de 5 cm du monde :
##   - VALEURS : chaque coordonnée d'architecture de la description (contours,
##     altitudes, bouts des murs, escaliers, garde-corps, dalles) est un
##     multiple de 5 cm (MapLayoutExport.off_grid) ;
##   - MAILLAGES : chaque triangle construit a sa normale géométrique sur un
##     axe (la normale d'ÉCLAIRAGE peut pencher : MeshMapGeometry.step_shade)
##     et chaque sommet est sur la grille de 5 cm du monde (x, y et z). Les
##     marches de 10 cm des murs en biais et des escaliers tournés
##     (`step_grain`) sont aussi sur cette grille.
## Les collisions (pavés tournés lisses, rampes des escaliers) ne sont pas
## visibles : elles ne sont pas contrôlées (décision § 2.2 et § 2.3).
## Fonctions pures : la géométrie construite est libérée, rien n'est écrit.
##
## Rapport (Dictionary) : ok, values (valeurs hors grille, textes), faces
## (triangles vérifiés), oblique (faces non axiales), off_grid (sommets hors
## grille), meshes (maillages vérifiés), bad (noms des maillages fautifs, avec
## leurs comptes), fr, en (texte lisible).

## Pas de la grille de l'architecture (m) : un cube.
const GRID := 0.05
## Écart admis d'un sommet à la grille (m) : arrondis des flottants.
const TOL := 0.0005
## |composante dominante| minimale d'une normale de face « axiale ».
const NORMAL_MIN := 0.9999


## Description de carte (`layout`, repère du jeu) : valeurs et architecture
## construite par le jeu (MeshMapGeometry).
static func check(L: Dictionary) -> Dictionary:
	var arch := MeshMapGeometry.build(L)
	var rep := check_nodes(arch)
	arch.free()
	rep["values"] = MapLayoutExport.off_grid(L)
	return _finish(rep)


## Carte de l'éditeur : sa description exportée (comme en jeu).
static func check_map(m: EditorMap) -> Dictionary:
	var data: Dictionary = MapPreviewWorld.compute(m).data
	if data.is_empty():
		return _finish({"values": [], "faces": 0, "oblique": 0, "off_grid": 0, "meshes": 0, "bad": []})
	return check(data)


## Carte du jeu, quelle que soit sa forme : grille (MapBuilder) ou
## description (MeshMapGeometry : test_levels, cartes de l'éditeur).
static func check_def(def: MapDef) -> Dictionary:
	var lay := def.create_layout()
	if lay is MeshMapLayout:
		return check((lay as MeshMapLayout).data)
	return check_grid(def)


## Carte en grille (MapDef à `rows`, BUNKER K-7) : géométrie de MapBuilder.
static func check_grid(def: MapDef) -> Dictionary:
	var holder := Node3D.new()
	var b := MapBuilder.new(MapData.parse(def.rows), def)
	b.build(holder)
	var rep := check_nodes(holder.get_node("Geometry"))
	holder.free()
	rep["values"] = []
	return _finish(rep)


## Tous les maillages sous `root` (transformations comprises, repère de
## `root` = monde) : faces axiales et sommets sur la grille de 5 cm.
static func check_nodes(root: Node) -> Dictionary:
	var rep := {"faces": 0, "oblique": 0, "off_grid": 0, "meshes": 0, "bad": []}
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		# Blocs de décor (« <mat>__<salle>__decor<i> ») : modèles cubiques du
		# décor, avec leurs propres règles (VoxelCheck, docs/VOXEL_DECOR_PLAN.md).
		# Maillages d'ombre seule (pavés lisses des murs en escalier) : jamais vus.
		if mi.mesh == null or String(mi.name).get_slice("__", 2).begins_with("decor") \
				or mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			continue
		var xf := _to_root(mi, root)
		var ob := 0
		var og := 0
		rep.meshes += 1
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var n_tri := (idx.size() if idx.size() > 0 else vs.size()) / 3
			for t in n_tri:
				var a := xf * vs[idx[3 * t] if idx.size() > 0 else 3 * t]
				var b := xf * vs[idx[3 * t + 1] if idx.size() > 0 else 3 * t + 1]
				var c := xf * vs[idx[3 * t + 2] if idx.size() > 0 else 3 * t + 2]
				var cr := (b - a).cross(c - a)
				if cr.length_squared() < 1e-12:
					continue
				rep.faces += 1
				var n := cr.normalized()
				if maxf(absf(n.x), maxf(absf(n.y), absf(n.z))) < NORMAL_MIN:
					ob += 1
			for v in vs:
				var p := xf * v
				if not (on_grid(p.x) and on_grid(p.y) and on_grid(p.z)):
					og += 1
		rep.oblique += ob
		rep.off_grid += og
		if ob > 0 or og > 0:
			rep.bad.append("%s (%d faces non axiales, %d sommets hors grille)" % [mi.name, ob, og])
	return rep


static func on_grid(x: float) -> bool:
	return absf(x - roundf(x / GRID) * GRID) <= TOL


static func _to_root(n: Node3D, root: Node) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p != null and p != root:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


static func _finish(rep: Dictionary) -> Dictionary:
	var values: Array = rep.get("values", [])
	rep["ok"] = values.is_empty() and rep.oblique == 0 and rep.off_grid == 0
	if rep.ok:
		rep["fr"] = "Architecture cubique : %d faces axiales sur la grille de 5 cm (%d maillages)." % [rep.faces, rep.meshes]
		rep["en"] = "Cubic architecture: %d axis-aligned faces on the 5 cm grid (%d meshes)." % [rep.faces, rep.meshes]
		return rep
	var fr := PackedStringArray()
	var en := PackedStringArray()
	if not values.is_empty():
		fr.append("%d valeurs d'architecture hors de la grille de 5 cm (%s)" % [values.size(), ", ".join(values.slice(0, 4))])
		en.append("%d architecture values off the 5 cm grid (%s)" % [values.size(), ", ".join(values.slice(0, 4))])
	if rep.oblique > 0 or rep.off_grid > 0:
		var where := ", ".join(PackedStringArray(rep.bad.slice(0, 4)))
		fr.append("%d faces non axiales, %d sommets hors de la grille de 5 cm : %s" % [rep.oblique, rep.off_grid, where])
		en.append("%d non axis-aligned faces, %d vertices off the 5 cm grid: %s" % [rep.oblique, rep.off_grid, where])
	rep["fr"] = "Architecture non cubique : " + " ; ".join(fr)
	rep["en"] = "Non-cubic architecture: " + "; ".join(en)
	return rep
