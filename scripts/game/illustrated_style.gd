class_name IllustratedStyle
extends RefCounted
## Style « ILLUSTRÉ » (prototype, OPTIONS > VIDÉO > STYLE ; Settings.art_style,
## CLASSIQUE par défaut) : rendu façon planche dessinée (docs/art/
## gemini_target.webp, docs/ART_DIRECTION.md « Style illustré ») :
##   - ÉCLAIRAGE EN APLATS : chaque matériau du jeu passe sur une VARIANTE de
##     son shader, générée ici à partir de son code (aucun fichier en double,
##     le shader d'origine n'est pas modifié) : définition de la sorte de
##     surface (CEL_ARCHI, CEL_PROP, CEL_CHAR, CEL_WEAPON) puis, à la fin,
##     la fonction light() de assets/shaders/cel_light.gdshaderinc (diffus en
##     2-3 paliers, ombres teintées bleu-vert, lumière chaude, spéculaire
##     réduit à un reflet net) ;
##   - ENCRAGE : ScreenOutline passe sur assets/shaders/screen_ink.gdshader
##     (trait épais sur les silhouettes, plus fin sur les arêtes intérieures).
##
## Les matériaux partagés du jeu s'inscrivent ici à leur création (bind) ;
## au changement de style (Settings.changed), leur shader est remplacé en
## direct (les paramètres du matériau et d'instance gardent leur nom).

enum Kind { ARCHI, PROP, CHAR, WEAPON }

## Valeur de stencil écrite par les surfaces qui ne sont pas l'architecture
## (personnages, décor cubique, armes) : l'encrage les distingue.
const STENCIL_OBJECT := 2
const CEL_INCLUDE :="res://assets/shaders/cel_light.gdshaderinc"
const KIND_DEFINES := ["CEL_ARCHI", "CEL_PROP", "CEL_CHAR", "CEL_WEAPON"]
## Sorte de surface d'après le shader d'origine (bind sans `kind`).
const KIND_BY_SHADER := {
	"res://assets/shaders/pixel_surface.gdshader": Kind.ARCHI,
	"res://assets/shaders/voxel_prop.gdshader": Kind.PROP,
	"res://assets/shaders/zombie.gdshader": Kind.CHAR,
	"res://assets/shaders/zombie_dissolve.gdshader": Kind.CHAR,
	"res://assets/shaders/zombie_voxel.gdshader": Kind.CHAR,
	"res://assets/shaders/zombie_voxel_dissolve.gdshader": Kind.CHAR,
	"res://assets/shaders/player_voxel.gdshader": Kind.CHAR,
	"res://assets/shaders/weapon.gdshader": Kind.WEAPON,
}

## Variantes générées : « id du shader d'origine|sorte » -> Shader.
static var _variants := {}
## Matériaux inscrits : id -> référence faible (un matériau libéré sort seul).
static var _mats := {}
static var _applied := -1
static var _connected := false
## Forcé par les tests (-1 : suivre Settings.art_style).
static var debug_force := -1


## Le style illustré est-il demandé ?
static func active() -> bool:
	if debug_force >= 0:
		return debug_force == Settings.ArtStyle.ILLUSTRATED
	return Settings.art_style == Settings.ArtStyle.ILLUSTRATED


## Variante illustrée du shader `base` pour la sorte `kind` (mise en cache).
static func variant(base: Shader, kind: int) -> Shader:
	var key := "%d|%d" % [base.get_instance_id(), kind]
	if _variants.has(key):
		return _variants[key]
	var sh := Shader.new()
	sh.code = variant_code(base.code, kind)
	_variants[key] = sh
	return sh


## Code de la variante : sorte de surface définie juste après la ligne
## `shader_type`, éclairage en aplats ajouté à la fin.
static func variant_code(code: String, kind: int) -> String:
	var defs := "\n#define STYLE_CEL\n#define %s\n" % KIND_DEFINES[clampi(kind, 0, KIND_DEFINES.size() - 1)]
	if kind != Kind.ARCHI:
		# Personnages, décor, armes : marqués dans le stencil (encre plus
		# appuyée sur leurs arêtes intérieures, screen_ink.gdshader).
		defs += "stencil_mode write, compare_always, %d;\n" % STENCIL_OBJECT
	var i := code.find("shader_type spatial;")
	if i < 0:
		return code
	i += "shader_type spatial;".length()
	return code.substr(0, i) + defs + code.substr(i) + "\n#include \"%s\"\n" % CEL_INCLUDE


## Shader à utiliser pour le matériau d'origine `base` dans le style courant.
static func shader_for(base: Shader, kind: int) -> Shader:
	return variant(base, kind) if active() else base


## Inscrit un matériau partagé du jeu : son shader suivra le style.
## `kind` : Kind, ou -1 pour la déduire du shader (KIND_BY_SHADER).
static func bind(mat: ShaderMaterial, kind := -1) -> ShaderMaterial:
	if mat == null or mat.shader == null:
		return mat
	if not mat.has_meta("style_base"):
		var base: Shader = mat.shader
		if kind < 0:
			kind = KIND_BY_SHADER.get(base.resource_path, Kind.PROP)
		mat.set_meta("style_base", base)
		mat.set_meta("style_kind", kind)
	if not _mats.has(mat.get_instance_id()):
		_mats[mat.get_instance_id()] = weakref(mat)
	_connect()
	_apply_to(mat, active())
	return mat


## Shader d'origine d'un matériau inscrit (le sien sinon).
static func base_shader(mat: ShaderMaterial) -> Shader:
	return mat.get_meta("style_base", mat.shader)


static func _apply_to(mat: ShaderMaterial, on: bool) -> void:
	var base: Shader = mat.get_meta("style_base", null)
	if base == null:
		return
	var want := variant(base, int(mat.get_meta("style_kind", Kind.PROP))) if on else base
	if mat.shader != want:
		mat.shader = want


## Applique le style courant à tous les matériaux inscrits (appelé à chaque
## Settings.changed ; sans effet si le style n'a pas changé).
static func sync(force := false) -> void:
	var on := active()
	if not force and _applied == int(on):
		return
	_applied = int(on)
	apply_all(on)


## Variantes en aplats (`on`) ou shaders d'origine sur tous les matériaux
## inscrits (mesures A/B de perf_costs ; sinon passer par sync).
static func apply_all(on: bool) -> void:
	for id in _mats.keys():
		var m := (_mats[id] as WeakRef).get_ref() as ShaderMaterial
		if m == null:
			_mats.erase(id)
		else:
			_apply_to(m, on)


## Nombre de matériaux inscrits encore en vie (tests).
static func bound_count() -> int:
	var n := 0
	for w in _mats.values():
		if (w as WeakRef).get_ref() != null:
			n += 1
	return n


static func _connect() -> void:
	if _connected:
		return
	_connected = true
	_applied = int(active())
	Settings.changed.connect(func(): IllustratedStyle.sync())
