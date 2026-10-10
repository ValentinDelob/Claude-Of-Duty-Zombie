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
]

## Lot 2 : mobilier et stockage.
const TODO_LOT2 := []

## Lot 3 : décors des effets et luminaires.
const TODO_LOT3 := []

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
	# Lot 1 (gravats et ruines : anciens rubble_heap_a/b/c, debris_scatter, debris_planks, debris_beam, chandelier_fallen).
	"prefab:gravats": {"fp": [6, 6], "h": 1.5, "bloque": "solide", "collision": [{"center": [0.0, 0.1373, 0.0], "size": [2.4, 0.2747, 2.4], "yaw": 0.0, "barrier": false}, {"center": [0.0, 0.3071, 0.0], "size": [1.4, 0.6141, 1.4], "yaw": 0.0, "barrier": false}]},
	"prefab:gros_gravats": {"fp": [10, 8], "h": 2.3, "bloque": "solide", "collision": [{"center": [0.0, 0.3023, 0.0], "size": [4.2, 0.6045, 3.0], "yaw": 0.0, "barrier": false}, {"center": [0.0, 0.5575, -0.05], "size": [2.6, 1.115, 2.1], "yaw": 0.0, "barrier": false}, {"center": [-0.2, 0.7623, -0.15], "size": [1.4, 1.5245, 1.3], "yaw": 0.0, "barrier": false}]},
	"prefab:eboulis": {"fp": [12, 6], "h": 2.9, "bloque": "solide", "collision": [{"center": [0.0, 0.3463, 0.0], "size": [5.2, 0.6926, 2.2], "yaw": 0.0, "barrier": false}, {"center": [-1.0, 0.7647, -0.05], "size": [1.8, 1.5293, 1.5], "yaw": 0.0, "barrier": false}, {"center": [1.3, 0.6011, 0.15], "size": [1.4, 1.2022, 1.1], "yaw": 0.0, "barrier": false}, {"center": [-1.0, 1.1701, -0.05], "size": [0.8, 2.3401, 0.9], "yaw": 0.0, "barrier": false}]},
	"prefab:debris_epars": {"fp": [6, 6], "h": 0.25, "bloque": "non"},
	"prefab:planches": {"fp": [4, 3], "h": 0.4, "bloque": "non", "collision": [{"center": [0.0, 0.15, 0.0], "size": [1.9, 0.3, 1.4], "yaw": 0.0, "barrier": true}]},
	"prefab:poutre": {"fp": [14, 4], "h": 1.8, "bloque": "solide", "collision": [{"center": [-2.257, 0.45, 0.0], "size": [1.9596, 0.9, 0.44], "yaw": 0.0, "barrier": false}, {"center": [-0.2974, 0.85, 0.0], "size": [1.9596, 0.9, 0.44], "yaw": 0.0, "barrier": false}, {"center": [1.6622, 1.25, 0.0], "size": [1.9596, 0.9, 0.44], "yaw": 0.0, "barrier": false}, {"center": [2.292, 0.55, 0.0], "size": [1.4, 1.1, 1.2], "yaw": 0.0, "barrier": false}]},
	"prefab:lustre_tombe": {"fp": [7, 6], "h": 1.5, "bloque": "barriere", "collision": [{"center": [0.0, 0.5, 0.0], "size": [3.2, 1.0, 2.6], "yaw": 0.0, "barrier": true}]},
	# Lot 2 : mobilier et stockage.
	"prefab:tonneaux": {"fp": [4, 4], "h": 1.8, "bloque": "barriere", "collision": [
		{"center": [-0.3661, 0.88, -0.4949], "size": [1.26, 1.76, 0.7], "yaw": 0.0, "barrier": true},
		{"center": [0.1839, 0.45, 0.1201], "size": [1.64, 0.9, 1.41], "yaw": 0.0, "barrier": true}]},
	"prefab:table_renversee": {"fp": [4, 2], "h": 0.9, "bloque": "solide", "surface": "wood",
		"boxes": [{"center": [0, 0.42, 0.25], "size": [1.6, 0.85, 0.12]}, {"center": [0, 0.3, -0.1], "size": [1.5, 0.6, 0.6]}]},
	"prefab:chaise_renversee": {"fp": [2, 1], "h": 0.5, "bloque": "barriere", "surface": "wood",
		"boxes": [{"center": [0, 0.22, 0], "size": [0.9, 0.45, 0.45]}]},
	"prefab:chaise": {"fp": [1, 1], "h": 0.9, "bloque": "barriere", "surface": "wood",
		"boxes": [{"center": [0, 0.43, 0], "size": [0.44, 0.87, 0.45]}]},
	"prefab:bureau": {"fp": [3, 2], "h": 0.8, "bloque": "solide", "support": 0.78, "collision": [
		{"center": [0.0, 0.39, 0.0], "size": [1.4, 0.78, 0.7], "yaw": 0.0, "barrier": false}]},
	"prefab:etagere": {"fp": [3, 1], "h": 1.8, "bloque": "solide", "collision": [
		{"center": [0.0, 0.9, 0.0], "size": [1.2, 1.8, 0.4], "yaw": 0.0, "barrier": false}]},
	"prefab:fauteuils": {"fp": [5, 2], "h": 1.1, "bloque": "barriere", "surface": "fabric",
		"copies": [[-0.84, 0, 0], [-0.28, 0, 0], [0.28, 0, 0], [0.84, 0, 0]],
		"boxes": [{"center": [0, 0.5, 0], "size": [2.24, 1.0, 0.6]}]},
	"prefab:fauteuil_casse": {"fp": [2, 3], "h": 0.7, "bloque": "barriere", "surface": "fabric",
		"boxes": [{"center": [0, 0.32, 0], "size": [0.7, 0.63, 1.2]}]},
	"prefab:pupitre": {"fp": [2, 2], "h": 1.2, "bloque": "solide", "collision": [
		{"center": [0.0, 0.6, 0.0], "size": [0.68, 1.2, 0.6], "yaw": 0.0, "barrier": false}]},
	"prefab:projecteur_film": {"fp": [2, 3], "h": 1.9, "bloque": "solide", "collision": [
		{"center": [0.0, 0.5, 0.0], "size": [0.9, 1.0, 0.9], "yaw": 0.0, "barrier": false},
		{"center": [0.0, 1.45, 0.0], "size": [0.6, 0.9, 1.4], "yaw": 0.0, "barrier": false}]},
	"prefab:chariot": {"fp": [3, 2], "h": 1.0, "bloque": "solide", "surface": "metal", "support": 0.85,
		"boxes": [{"center": [0, 0.5, 0], "size": [1.3, 1.0, 0.75]}]},
	"prefab:epave_voiture": {"fp": [9, 4], "h": 1.5, "bloque": "solide", "surface": "metal",
		"boxes": [{"center": [0, 0.5, 0], "size": [4.3, 1.0, 1.8]}, {"center": [-0.2, 1.2, 0], "size": [2.2, 0.6, 1.6]}]},
	# Lot 3 : décors des effets et luminaires (luminaires : montage, hauteur et réglages de la lumière).
	"prefab:buches": {"fp": [1, 1], "h": 0.15, "bloque": "non", "surface": "wood"},
	"prefab:planches_brulees": {"fp": [5, 2], "h": 0.1, "bloque": "non", "surface": "wood"},
	"prefab:electrodes": {"fp": [3, 1], "h": 1.1, "bloque": "barriere", "surface": "metal",
		"boxes": [{"center": [-0.62, 0.55, 0], "size": [0.2, 1.1, 0.2]}, {"center": [0.62, 0.55, 0], "size": [0.2, 1.1, 0.2]}]},
	"prefab:bobine_tesla": {"fp": [1, 1], "h": 1.55, "bloque": "solide", "surface": "metal",
		"boxes": [{"center": [0, 0.78, 0], "size": [0.4, 1.55, 0.4]}]},
	"prefab:flaque_eau": {"fp": [3, 3], "h": 0.01, "bloque": "non", "surface": "tiles"},
	"prefab:petite_flaque": {"fp": [2, 2], "h": 0.01, "bloque": "non", "surface": "tiles"},
	"prefab:torche_murale": {"fp": [1, 1], "h": 0.5, "bloque": "non", "mount": "mur", "y": 1.8, "surface": "wood"},
	"prefab:tuyau_vapeur": {"fp": [1, 1], "h": 0.2, "bloque": "non", "mount": "mur", "y": 1.2, "surface": "metal"},
	"prefab:boitier_electrique": {"fp": [1, 1], "h": 0.45, "bloque": "non", "mount": "mur", "y": 1.6, "surface": "metal"},
	"prefab:tuyau_fuite": {"fp": [2, 1], "h": 0.2, "bloque": "non", "mount": "mur", "y": 2.0, "surface": "metal"},
	"prefab:cable_suspendu": {"fp": [1, 1], "h": 0.65, "bloque": "non", "mount": "plafond", "surface": "metal"},
	"luminaire:ampoule": {"fp": [1, 1], "mount": "plafond", "drop": 0.75, "couleur": "#ffd9a0", "intensite": 1.6, "portee": 8.0, "courant": true, "vacille": false},
	"luminaire:suspension": {"fp": [1, 1], "mount": "plafond", "drop": 0.7, "couleur": "#ffc88a", "intensite": 2.2, "portee": 10.0, "courant": true, "vacille": false},
	"luminaire:neon": {"fp": [3, 1], "mount": "plafond", "drop": 0.15, "couleur": "#dcebff", "intensite": 2.0, "portee": 10.0, "courant": true, "vacille": false},
	"luminaire:lustre": {"fp": [3, 3], "mount": "plafond", "drop": 1.1, "couleur": "#ffd6a0", "intensite": 2.8, "portee": 12.0, "courant": true, "vacille": false},
	"luminaire:applique": {"fp": [1, 1], "mount": "mur", "y": 2.0, "couleur": "#ffc080", "intensite": 1.4, "portee": 7.0, "courant": true, "vacille": false},
	"luminaire:lampe_bureau": {"fp": [1, 1], "mount": "sol", "y": 0.45, "couleur": "#ffe0b0", "intensite": 0.9, "portee": 5.0, "courant": true, "vacille": false,
		"bloque": "non"},
	"luminaire:projecteur": {"fp": [2, 2], "mount": "sol", "y": 1.7, "couleur": "#fff4e0", "intensite": 3.0, "portee": 14.0, "courant": true, "vacille": false,
		"bloque": "barriere", "boxes": [{"center": [0, 0.85, 0], "size": [0.7, 1.7, 0.7]}]},
	"luminaire:bougies": {"fp": [1, 1], "mount": "sol", "y": 0.25, "couleur": "#ff9a40", "intensite": 0.7, "portee": 4.5, "courant": false, "vacille": true,
		"bloque": "non"},
	"luminaire:feu": {"fp": [2, 2], "mount": "sol", "y": 1.15, "couleur": "#ff7a2a", "intensite": 2.4, "portee": 9.0, "courant": false, "vacille": true,
		"bloque": "solide", "boxes": [{"center": [0, 0.45, 0], "size": [0.62, 0.9, 0.62]}]},
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
		if f.has("h"):
			assert_near(float(d.h), float(f.h), 0.0001, "%s : hauteur inchangée" % k)
		assert_eq(d.get("bloque"), f.get("bloque"), "%s : blocage inchangé" % k)
		# Pose murale, descente sous le plafond et réglages d'un luminaire.
		for key in ["y", "drop", "couleur", "intensite", "portee", "courant", "vacille"]:
			assert_eq(d.get(key), f.get(key), "%s : « %s » inchangé" % [k, key])
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
