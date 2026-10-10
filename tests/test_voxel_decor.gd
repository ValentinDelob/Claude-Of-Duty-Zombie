extends TestCase
## Décors CUBIQUES de l'éditeur de cartes (docs/VOXEL_DECOR_PLAN.md,
## GAME_CONCEPT.md § 4.19) : chaque modèle de décor ou de luminaire cité par
## le catalogue (MapCatalog.PREFABS, LIGHTS) passe VoxelCheck (mode statique,
## cubes de 5 cm), sauf les entrées encore « à faire » (TODO_*, listes
## explicites que les lots de conversion vident) ; une entrée convertie garde
## son emprise, sa hauteur, son blocage, son support et ses collisions
## (FROZEN : valeurs d'avant la conversion) ; le jeu construit ces modèles
## avec le matériau « voxel » (faces émissives d'alpha 0).

# ------------------------------------------------------------------ à faire
# Une ligne par entrée PAS ENCORE cubique, rangée par lot (un lot ne touche
# que son bloc). « prefab:<id> » : MapCatalog.PREFABS ; « luminaire:<id> » :
# MapCatalog.LIGHTS ; « objet:<type> » : objets de carte construits par leur
# script (signalés seulement : chaque lot ajoute son propre contrôle).

## Lot 1 : gravats et ruines.
const TODO_LOT1 := [
	"prefab:gravats", "prefab:gros_gravats", "prefab:eboulis", "prefab:debris_epars",
	"prefab:planches", "prefab:poutre", "prefab:lustre_tombe",
]

## Lot 2 : mobilier et stockage.
const TODO_LOT2 := [
	"prefab:tonneaux", "prefab:table_renversee", "prefab:chaise_renversee", "prefab:chaise",
	"prefab:bureau", "prefab:etagere", "prefab:fauteuils", "prefab:fauteuil_casse",
	"prefab:pupitre", "prefab:projecteur_film", "prefab:chariot", "prefab:epave_voiture",
]

## Lot 3 : décors des effets et luminaires.
const TODO_LOT3 := [
	"prefab:buches", "prefab:planches_brulees", "prefab:electrodes", "prefab:bobine_tesla",
	"prefab:flaque_eau", "prefab:petite_flaque", "prefab:torche_murale", "prefab:tuyau_vapeur",
	"prefab:boitier_electrique", "prefab:tuyau_fuite", "prefab:cable_suspendu",
	"luminaire:ampoule", "luminaire:suspension", "luminaire:neon", "luminaire:lustre",
	"luminaire:applique", "luminaire:lampe_bureau", "luminaire:projecteur", "luminaire:bougies",
	"luminaire:feu",
]

## Lot 4 : objets de carte (portes, barricades, machines...).
const TODO_LOT4 := [
	"objet:porte", "objet:debris", "objet:porte_courant", "objet:fenetre", "objet:boite",
	"objet:courant", "objet:teleporteur", "objet:arrivee", "objet:poste_central", "objet:piege",
	"objet:levier", "objet:evacuation", "objet:caisse", "objet:baril",
]

# ------------------------------------------------------------------ figé
## Entrées converties : valeurs d'AVANT la conversion (catalogue et
## <modèle>.collision.json). Chaque lot ajoute ses entrées ici.
const FROZEN := {
	# Pilote.
	"prefab:caisses": {"fp": [5, 4], "h": 1.5, "bloque": "solide", "collision": [
		{"center": [-0.6085, 0.4, -0.4616], "size": [1.2, 0.8, 0.8], "yaw": 0.0, "barrier": false},
		{"center": [0.7415, 0.45, -0.4616], "size": [1.0, 0.9, 0.9], "yaw": 0.0698, "barrier": false},
		{"center": [0.5415, 0.35, 0.4884], "size": [1.1, 0.7, 0.7], "yaw": -0.1396, "barrier": false},
		{"center": [-0.7585, 0.3, 0.5384], "size": [0.9, 0.6, 0.6], "yaw": 0.2618, "barrier": false},
		{"center": [-0.5585, 1.15, -0.4616], "size": [0.9, 0.7, 0.7], "yaw": 0.1745, "barrier": false}]},
	"prefab:sacs_sable": {"fp": [4, 2], "h": 0.9, "bloque": "solide", "surface": "fabric", "support": 0.9,
		"boxes": [{"center": [0, 0.45, 0], "size": [2.0, 0.9, 0.8]}]},
	"prefab:foyer_pierres": {"fp": [3, 3], "h": 0.3, "bloque": "barriere", "surface": "stone",
		"boxes": [{"center": [0, 0.5, 0], "size": [1.3, 1.0, 1.3]}]},
}

const PROPS_DIR := "res://assets/models/props/"


static func todo() -> Array:
	return TODO_LOT1 + TODO_LOT2 + TODO_LOT3 + TODO_LOT4


## Entrées du catalogue qui ont une apparence 3D : {clé: définition}.
static func catalog_entries() -> Dictionary:
	var out := {}
	for pid in MapCatalog.PREFABS:
		out["prefab:" + pid] = MapCatalog.PREFABS[pid]
	for lid in MapCatalog.LIGHTS:
		out["luminaire:" + lid] = MapCatalog.LIGHTS[lid]
	return out


static func is_voxel(d: Dictionary) -> bool:
	return String(d.get("model", "")).begins_with(MeshMapBuilder.VOXEL_DIR)


func test_every_catalog_model_is_cubic_or_listed_as_todo() -> void:
	var entries := catalog_entries()
	var todo_list := todo()
	var seen := {}
	for k in todo_list:
		assert_false(seen.has(k), "%s listé deux fois" % k)
		seen[k] = true
		if String(k).begins_with("objet:"):
			continue
		assert_true(entries.has(k), "%s (à faire) existe au catalogue" % k)
	var done := 0
	for k in entries:
		var d: Dictionary = entries[k]
		if not is_voxel(d):
			assert_true(seen.has(k), "%s : ni cubique (« model »: \"voxel/<id>\") ni listé à faire (TODO_*)" % k)
			continue
		assert_false(seen.has(k), "%s est converti : le retirer de TODO_*" % k)
		assert_false(d.has("scale") or d.has("remap"), "%s : ni « scale » ni « remap » (modèle à sa taille, couleurs de face)" % k)
		var path := PROPS_DIR + String(d.model) + ".glb"
		var ps := load(path) as PackedScene
		assert_true(ps != null, "%s : modèle %s chargé" % [k, path])
		if ps == null:
			continue
		var scene := ps.instantiate()
		var rep := VoxelCheck.check_scene(scene, false)
		assert_true(bool(rep.ok), "%s : cubique (5 cm) — %s" % [k, rep.get("fr", "")])
		assert_near(float(rep.cube), VoxelCheck.CUBE, 0.0001, "%s : grille du décor" % k)
		# Convention des nœuds : « voxel__<id>__<type> » (matériau du jeu « voxel »).
		for mi in scene.find_children("*", "MeshInstance3D", true, false):
			assert_true(String(mi.name).begins_with(MeshMapBuilder.VOXEL_MAT + "__"), "%s : nœud %s nommé voxel__..." % [k, mi.name])
		# Aucune collision dans le modèle (CollisionBox du catalogue ou .collision.json).
		assert_eq(scene.find_children("*", "CollisionObject3D", true, false).size(), 0, "%s : aucune collision dans le .glb" % k)
		scene.free()
		done += 1
	var left := todo_list.filter(func(k): return not String(k).begins_with("objet:"))
	print("[voxel_decor] décors cubiques : %d ; à faire : %d au catalogue, %d objets de carte" % [done, left.size(), todo_list.size() - left.size()])
	for k in todo_list:
		print("[voxel_decor]   à faire : " + String(k))


func test_converted_entries_keep_footprint_and_collisions() -> void:
	var entries := catalog_entries()
	for k in FROZEN:
		var f: Dictionary = FROZEN[k]
		assert_true(entries.has(k), "%s au catalogue" % k)
		if not entries.has(k):
			continue
		var d: Dictionary = entries[k]
		assert_true(is_voxel(d), "%s : modèle cubique" % k)
		assert_eq(d.fp, f.fp, "%s : emprise inchangée" % k)
		assert_near(float(d.h), float(f.h), 0.0001, "%s : hauteur inchangée" % k)
		assert_eq(String(d.bloque), String(f.bloque), "%s : blocage inchangé" % k)
		assert_eq(d.get("support"), f.get("support"), "%s : support inchangé" % k)
		assert_eq(d.get("surface"), f.get("surface"), "%s : matière d'impact inchangée" % k)
		assert_eq(d.get("mount"), f.get("mount"), "%s : montage inchangé" % k)
		assert_eq(d.get("boxes"), f.get("boxes"), "%s : pavés de collision du catalogue inchangés" % k)
		if f.has("collision"):
			var path := PROPS_DIR + String(d.model) + ".collision.json"
			var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			assert_true(j is Dictionary, "%s : %s lisible" % [k, path])
			if j is Dictionary:
				assert_eq(JSON.stringify(j.boxes), JSON.stringify(f.collision), "%s : collisions du modèle inchangées" % k)
				# Mêmes pavés vus par les prefabs groupes (MapPrefabLib.catalog_boxes).
				var cb := MapPrefabLib.catalog_boxes(k.trim_prefix("prefab:"))
				assert_eq(cb.size(), (f.collision as Array).size(), "%s : pavés des prefabs groupes" % k)


func test_game_builds_voxel_props_with_the_voxel_material() -> void:
	var layout := {"props": [
		{"id": "c", "model": "voxel/caisses", "p": [0.0, 0.0, 0.0], "yaw": 0.0},
		{"id": "f", "model": "voxel/foyer_pierres", "nocollide": true, "p": [3.0, 0.0, 0.0], "yaw": PI / 2}]}
	var world := Node3D.new()
	host.add_child(world)
	var mb := MeshMapBuilder.new(layout, "")
	mb._make_root(world, "Props")
	mb._build_props()
	var meshes := world.find_children("voxel__*", "MeshInstance3D", true, false)
	assert_eq(meshes.size(), 2, "deux décors cubiques construits")
	for mi in meshes:
		var mat := (mi as MeshInstance3D).material_override
		assert_true(mat is ShaderMaterial and (mat as ShaderMaterial).shader.resource_path.ends_with("voxel_prop.gdshader"),
			"%s : matériau voxel" % mi.name)
	# Caisses : collisions de voxel/caisses.collision.json (CollisionBox) ; foyer : aucune (« nocollide »).
	assert_eq(world.find_children("*", "CollisionBox", true, false).size(), 5, "5 pavés des caisses")
	# Braises du foyer : faces émissives (alpha 0 dans les couleurs de face).
	var foyer: MeshInstance3D = meshes.filter(func(m): return String(m.name).contains("foyer"))[0]
	var glow := 0
	for s in foyer.mesh.get_surface_count():
		for c in foyer.mesh.surface_get_arrays(s)[Mesh.ARRAY_COLOR]:
			if c.a < 0.5:
				glow += 1
	assert_true(glow > 0, "braises émissives (%d sommets d'alpha 0)" % glow)
	# Nom de modèle : seul le dossier « voxel/ » est admis.
	assert_true(MeshMapBuilder.model_name_ok("voxel/caisses"), "voxel/<id> admis")
	assert_false(MeshMapBuilder.model_name_ok("voxel/../x"), "chemin refusé")
	assert_false(MeshMapBuilder.model_name_ok("autre/x"), "autre dossier refusé")
	world.queue_free()
	await wait_frames(1)
