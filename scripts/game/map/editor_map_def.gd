class_name EditorMapDef
extends MapDef
## Carte faite dans l'ÉDITEUR DE CARTES (docs/MAP_AUTHORING.md) : dossier de
## cinq JSON (EditorMap). Au chargement, la carte est convertie en grille
## (MapRaster), validée (MapValidator) puis décrite en maillage
## (MapLayoutExport) ; le jeu construit sa géométrie lui-même
## (MeshMapGeometry) : aucune étape Blender, jouable aussitôt, même dans le .exe.
##
## Deux sortes : les cartes livrées (assets/maps/<id>/, ex. DRAFT ARENA :
## script de carte `extends EditorMapDef` + `_init_editor`) et les cartes du
## joueur (user://maps/<id>/, identifiant « perso:<id> », bouton Tester).
## En multijoueur, la carte perso de l'hôte est envoyée aux invités (MapShare)
## et tout le monde la joue depuis son cache : « partage:<sha256> ».

const CUSTOM_PREFIX := "perso:"
const SHARED_PREFIX := "partage:"

var dir := ""
var editor_map: EditorMap
## Résultat de la validation (messages, zones...).
var validator: MapValidator
## Description en maillage (vide si la carte est refusée).
var layout_data: Dictionary = {}


func _init_editor(map_dir: String, map_id := "") -> void:
	dir = map_dir
	_setup(EditorMap.load_dir(map_dir), map_id)


static func from_map(m: EditorMap, map_id := "") -> EditorMapDef:
	var d := EditorMapDef.new()
	d._setup(m, map_id)
	return d


## Carte du joueur « perso:<id> » (null si le dossier n'existe pas, ou si la
## carte ne passe pas le contrôle de légitimité : CustomMapGuard).
static func custom(map_id: String) -> EditorMapDef:
	var folder := map_id.trim_prefix(CUSTOM_PREFIX)
	var path := EditorMap.map_dir(folder)
	if folder.contains("/") or folder.contains("\\") or folder.contains("..") or not EditorMap.is_map_dir(path):
		return null
	var r := CustomMapGuard.load_local(path, false)
	if not r.ok:
		push_warning("[EditorMapDef] carte perso « %s » refusée : %s" % [folder, CustomMapGuard.reasons_text(r.reasons).replace("\n", " ; ")])
		return null
	var d := EditorMapDef.new()
	d.dir = path
	d._setup(r.map, CUSTOM_PREFIX + folder)
	return d


## Carte perso reçue d'un hôte « partage:<sha256> » (cache
## user://maps_cache/<sha256>/, empreinte et légitimité revérifiées ; null sinon).
static func shared(map_id: String) -> EditorMapDef:
	var sha := map_id.trim_prefix(SHARED_PREFIX)
	var r := CustomMapGuard.load_cached(sha)
	if not r.ok:
		push_warning("[EditorMapDef] carte partagée %s refusée : %s" % [sha.substr(0, 12), CustomMapGuard.reasons_text(r.reasons).replace("\n", " ; ")])
		return null
	var d := EditorMapDef.new()
	d.dir = CustomMapGuard.cache_dir(sha)
	d._setup(r.map, map_id)
	return d


func _setup(m: EditorMap, map_id: String) -> void:
	editor_map = m
	id = map_id if map_id != "" else m.id()
	display_name = m.display_name()
	var desc: Dictionary = m.carte.get("description", {})
	description = Lang.t(String(desc.get("fr", "")), String(desc.get("en", desc.get("fr", ""))))
	validator = MapRaster.build(m).v
	validator.analyze()
	if not validator.ok():
		return
	layout_data = MapLayoutExport.build(validator)
	var md: Dictionary = layout_data.map_def
	music = String(md.get("music", music))
	zone_names = md.get("zone_names", {})
	doors = md.get("doors", {})
	open_links = md.get("open_links", {})
	box_start = int(md.get("box_start", 0))
	# Format 17 : ciel de la carte (pièces sans plafond), WorldLook.apply_sky.
	if md.get("sky") is Dictionary:
		look["sky"] = md.sky
	# Format 18 : schéma des vagues spéciales et de boss (absent : défaut).
	waves = WaveRules.parse(md.get("waves"))
	# Poste central posé : téléporteur à relier avant chaque voyage (Kino).
	if bool(md.get("teleporter_link", false)):
		teleporter_link = true
		teleporter_cost = 0
		teleporter_charge = 1.8
		teleporter_stay = 30.0
		teleporter_link_cooldown = 90.0


## La carte a passé la validation (jouable) ?
func is_valid() -> bool:
	return not layout_data.is_empty()


func create_layout() -> MapLayout:
	return MeshMapLayout.new(self, layout_data)
