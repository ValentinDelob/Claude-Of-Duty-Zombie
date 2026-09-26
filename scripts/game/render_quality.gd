class_name RenderQuality
extends Node
## Préréglages de qualité graphique (Settings.quality : LOW / MEDIUM / HIGH).
##
## SEUL endroit qui décide de ce que coûte chaque préréglage. Créé avec
## l'environnement de la carte (WorldLook.setup_environment), il s'applique
## au chargement de la partie puis à chaque Settings.changed (écran OPTIONS).
##
## Ce qu'il règle :
##   - lampes de la carte (groupe LAMP_GROUP) : proportion à ombres portées,
##     distances de fondu de la lumière et de l'ombre ;
##   - ombres positionnelles : taille de l'atlas, filtre (PCF) ;
##   - environnement : glow (et sa qualité), SSAO, brume volumétrique ;
##   - post-traitement FilmPost (groupe GROUP) : variante lisant l'écran
##     (aberration chromatique) ou variante LOW multiplicative ;
##   - viewport : résolution 3D (scaling_3d_scale), MSAA ;
##   - décalques (groupe DECAL_GROUP) : distance de fondu ;
##   - particules : densité (ParticlePool.density) ;
##   - zombies à ombre portée (ZombieShadows : les plus proches seulement) ;
##   - tout nœud du groupe GROUP reçoit apply_quality(preset) (ex. Fx).
##
## Les valeurs sont mesurées avec tools/perf.sh et le scénario perf_costs
## (coût de chaque poste en A/B, voir docs/ARCHITECTURE.md,
## section « Rendu et performances »). Forcer un préréglage en test :
##   godot --path . -- --autotest=map_tour --quality=low

const GROUP := "render_quality"
const LAMP_GROUP := "map_lamps"
const DECAL_GROUP := "quality_decals"

## Index = Settings.Quality (LOW, MEDIUM, HIGH).
const PRESETS := [
	# LOW — GTX 1050 garanti : aucune ombre de lampe, pas de glow, 3D à 85 %.
	{
		"name": "low",
		"lamp_shadows": 0,          # lampes à ombre, sur 3
		"shadow_atlas": 1024,
		"shadow_filter": RenderingServer.SHADOW_QUALITY_HARD,
		"light_fade_begin": 20.0,
		"light_fade_length": 5.0,
		"shadow_fade": 12.0,
		"glow": false,
		"glow_bicubic": false,
		"ssao": false,
		"scale_3d": 0.85,
		"msaa": Viewport.MSAA_DISABLED,
		"decal_fade": 14.0,
		"decals": 0.5,              # part des décalques d'impact / de sang
		"particles": 0.5,           # densité des gerbes de particules
		"volumetric_fog": false,    # brume volumétrique (halos des lampes)
		"fog_volume": [64, 48],     # résolution de la brume (xy, profondeur)
		"post_screen": false,       # post-traitement lisant l'écran (aberration)
		"aberration": 0.0,
		"zombie_shadows": 0,        # zombies à ombre portée (les plus proches)
		"zombie_shadow_dist": 0.0,  # ... à moins de cette distance (m)
	},
	# MEDIUM (défaut) — le rendu de référence.
	{
		"name": "medium",
		"lamp_shadows": 1,
		"shadow_atlas": 4096,
		# Filtre dur (PCF matériel 2x2) : -0,3 à -0,4 ms GPU (GTX 1070, 1080p)
		# pour une différence invisible (lampes ponctuelles, light_size = 0).
		"shadow_filter": RenderingServer.SHADOW_QUALITY_HARD,
		"light_fade_begin": 28.0,
		"light_fade_length": 6.0,
		"shadow_fade": 16.0,
		"glow": true,
		"glow_bicubic": false,
		"ssao": false,
		"scale_3d": 1.0,
		"msaa": Viewport.MSAA_DISABLED,
		"decal_fade": 24.0,
		"decals": 1.0,
		"particles": 1.0,
		"volumetric_fog": true,
		# 48x48x32 : -0,2 ms GPU, halos identiques à l'œil (brume fine filtrée).
		"fog_volume": [48, 32],
		"post_screen": true,
		"aberration": 0.003,
		"zombie_shadows": 6,
		"zombie_shadow_dist": 12.0,
	},
	# HIGH — ombres sur 2 lampes sur 3, filtrées et visibles plus loin,
	# SSAO léger, glow à suréchantillonnage bicubique, MSAA 2x.
	{
		"name": "high",
		"lamp_shadows": 2,
		"shadow_atlas": 4096,
		"shadow_filter": RenderingServer.SHADOW_QUALITY_SOFT_LOW,  # SOFT_MEDIUM : +0,5 à 1 ms pour rien de visible
		"light_fade_begin": 34.0,
		"light_fade_length": 6.0,
		"shadow_fade": 22.0,
		"glow": true,
		"glow_bicubic": true,
		"ssao": true,
		"scale_3d": 1.0,
		"msaa": Viewport.MSAA_2X,
		"decal_fade": 32.0,
		"decals": 1.0,
		"particles": 1.0,
		"volumetric_fog": true,
		"fog_volume": [64, 48],  # 96x96x64 : +0,7 ms, même rendu
		"post_screen": true,
		"aberration": 0.0035,
		"zombie_shadows": 12,
		"zombie_shadow_dist": 20.0,
	},
]

var environment: Environment
var _applied := -1


static func preset(quality: int) -> Dictionary:
	return PRESETS[clampi(quality, 0, PRESETS.size() - 1)]


## Préréglage demandé par les options (pour les nœuds créés en cours de partie).
static func current() -> Dictionary:
	return preset(Settings.quality)


## Nom de qualité (« low », « medium », « high ») -> index, -1 si inconnu.
static func parse(quality_name: String) -> int:
	for i in PRESETS.size():
		if PRESETS[i].name == quality_name.to_lower():
			return i
	return -1


## La lampe n° `index` projette-t-elle une ombre avec ce préréglage ?
static func lamp_has_shadow(index: int, q: Dictionary) -> bool:
	return index % 3 < int(q.lamp_shadows)


func _ready() -> void:
	Settings.changed.connect(_on_settings_changed)
	apply()


## Settings.changed est émis pour toute option (volume, FOV...) : on ne
## réapplique que si la qualité a changé (réallouer l'atlas d'ombres ou les
## tampons MSAA coûte une image).
func _on_settings_changed() -> void:
	if Settings.quality != _applied:
		apply()


func apply() -> void:
	_applied = Settings.quality
	var q := preset(_applied)
	_apply_environment(q)
	_apply_viewport(q)
	for l in get_tree().get_nodes_in_group(LAMP_GROUP):
		apply_lamp(l as OmniLight3D, q)
	for d in get_tree().get_nodes_in_group(DECAL_GROUP):
		apply_decal(d as Decal, q)
	ParticlePool.density = q.particles
	get_tree().call_group(GROUP, "apply_quality", q)
	print("[RenderQuality] préréglage « %s » appliqué" % q.name)


func _apply_environment(q: Dictionary) -> void:
	RenderingServer.environment_glow_set_use_bicubic_upscale(q.glow_bicubic)
	if environment == null:
		return
	environment.glow_enabled = q.glow
	environment.ssao_enabled = q.ssao
	# Brume volumétrique : halos et faisceaux des lampes (réglages de la
	# brume elle-même dans WorldLook.setup_environment).
	environment.volumetric_fog_enabled = q.volumetric_fog
	if q.volumetric_fog:
		RenderingServer.environment_set_volumetric_fog_volume_size(q.fog_volume[0], q.fog_volume[1])
		RenderingServer.environment_set_volumetric_fog_filter_active(true)
	if q.ssao:
		# SSAO discret : assombrit les coins et le pied des caisses, sans halo.
		environment.ssao_radius = 0.8
		environment.ssao_intensity = 1.2
		environment.ssao_power = 1.4
		environment.ssao_detail = 0.3
		RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_LOW, true, 0.5, 2, 20.0, 40.0)


func _apply_viewport(q: Dictionary) -> void:
	var vp := get_viewport()
	vp.positional_shadow_atlas_size = q.shadow_atlas
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = q.scale_3d
	vp.msaa_3d = q.msaa
	RenderingServer.positional_soft_shadow_filter_set_quality(q.shadow_filter)


static func apply_lamp(l: OmniLight3D, q: Dictionary) -> void:
	l.shadow_enabled = lamp_has_shadow(int(l.get_meta("lamp_index", 0)), q)
	l.distance_fade_enabled = true
	l.distance_fade_begin = q.light_fade_begin
	l.distance_fade_length = q.light_fade_length
	l.distance_fade_shadow = q.shadow_fade


static func apply_decal(d: Decal, q: Dictionary) -> void:
	d.distance_fade_enabled = true
	d.distance_fade_begin = q.decal_fade
	d.distance_fade_length = 4.0
