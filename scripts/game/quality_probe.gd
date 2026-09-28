class_name QualityProbe
extends Node
## Préréglage graphique automatique au premier lancement (Settings.quality).
##
## Deux indices, combinés par choose() :
##  1. la carte graphique (RenderingServer.get_video_adapter_name / _type) :
##     une table de modèles connus donne un indice de puissance relatif à la
##     GTX 1050 (= 1.0, cible du projet) ; puces intégrées et rendu logiciel
##     -> LOW d'office ;
##  2. un mini-banc d'essai de quelques secondes dans le menu principal : temps
##     GPU moyen du viewport (préréglage MEDIUM imposé pendant la mesure),
##     ramené à 1080p et comparé à la référence mesurée sur la GTX 1070 de
##     développement (REF_MENU_MS) -> indice de puissance mesuré.
## L'indice mesuré l'emporte (pilotes, portables bridés) ; l'indice du modèle
## ne sert que si la mesure est impossible. Seuils : voir choose() et
## docs/ARCHITECTURE.md (« Préréglage automatique »). Le joueur peut toujours
## changer dans OPTIONS > VIDÉO ; la détection ne se refait jamais ensuite
## (clé video/quality_auto de user://settings.cfg).

## Indice de puissance de la GTX 1070 de développement (GTX 1050 = 1).
const DEV_SCORE := 3.5
## Temps GPU du menu principal (MEDIUM) sur la GTX 1070, ramené à 1080p par
## le nombre de pixels : 1,3-1,45 ms mesurés dans la fenêtre 1280x720 du
## premier lancement (x 2,25), 2,6-2,9 ms en 1920x1080. Le coût n'est pas tout
## à fait proportionnel aux pixels : une petite fenêtre sous-estime un peu
## l'indice (choix prudent).
const REF_MENU_MS := 2.9
## Indice minimal pour MEDIUM (60 fps en 1080p en partie) et pour HIGH.
const MEDIUM_MIN := 0.9
const HIGH_MIN := 2.6
## Mesure : attente de stabilisation puis durée d'échantillonnage (s).
const SETTLE_SEC := 2.0
const SAMPLE_SEC := 3.0

## [motif (minuscules), indice] : premier motif trouvé dans le nom de la
## carte. Ordre : du plus précis au plus général.
const ADAPTERS := [
	# NVIDIA
	["rtx 40", 9.0], ["rtx 30", 7.0], ["rtx 20", 5.0], ["rtx a2000", 4.4],
	["gtx 1660", 2.3], ["gtx 1650 super", 1.9], ["gtx 1650", 1.4],
	["gtx 1080", 4.5], ["gtx 1070", 3.5], ["gtx 1060", 2.2],
	["gtx 1050 ti", 1.25], ["gtx 1050", 1.0], ["gt 1030", 0.45],
	["gtx 980", 2.4], ["gtx 970", 2.0], ["gtx 960", 1.1], ["gtx 950", 0.9],
	["gtx 750", 0.6], ["geforce mx", 0.5],
	# AMD (Polaris « rx 5x0 » avant les RDNA « rx 5xxx »)
	["rx 590 ", 2.3], ["rx 580 ", 2.1], ["rx 570 ", 1.8], ["rx 480 ", 2.0], ["rx 470 ", 1.7],
	["rx 560 ", 1.1], ["rx 550 ", 0.7], ["vega 64", 3.3], ["vega 56", 3.0],
	["rx 7", 7.0], ["rx 6", 5.0], ["rx 5", 3.5],
	# Intel dédiées
	["arc a7", 4.0], ["arc a5", 2.8], ["arc a3", 1.3],
]
## Puces intégrées ou rendu logiciel : LOW sans discussion.
const WEAK := ["llvmpipe", "swiftshader", "software", "basic render", "microsoft basic",
	"intel(r) hd", "intel(r) uhd", "intel hd", "intel uhd", "iris", "radeon(tm) graphics",
	"radeon graphics", "vega 3", "vega 6", "vega 8", "vega 10", "vega 11"]

signal done(quality: int, info: String)


## Indice de puissance d'après le nom de la carte (-1 : inconnu, 0 : faible).
static func adapter_score(adapter: String, integrated := false) -> float:
	var n := adapter.to_lower() + " "  # motifs terminés par une espace : « rx 570 » != « rx 5700 »
	for w in WEAK:
		if n.contains(w):
			return 0.0
	for row in ADAPTERS:
		if n.contains(row[0]):
			return float(row[1])
	return 0.0 if integrated else -1.0


## Indice de puissance mesuré : temps GPU du menu (ms) pour `pixels` pixels.
static func bench_score(gpu_ms: float, pixels: float) -> float:
	if gpu_ms <= 0.0 or pixels <= 0.0:
		return -1.0
	var ms_1080p := gpu_ms * (1920.0 * 1080.0) / pixels
	return DEV_SCORE * REF_MENU_MS / ms_1080p


## Préréglage pour un indice de puissance (-1 : inconnu -> MEDIUM).
static func quality_for(score: float) -> int:
	if score < 0.0:
		return Settings.Quality.MEDIUM
	if score >= HIGH_MIN:
		return Settings.Quality.HIGH
	if score >= MEDIUM_MIN:
		return Settings.Quality.MEDIUM
	return Settings.Quality.LOW


## Choix final : la mesure si elle existe, sinon le modèle ; une puce
## intégrée ou logicielle reste en LOW quoi qu'il arrive.
static func choose(adapter_s: float, bench_s: float) -> int:
	if adapter_s == 0.0:
		return Settings.Quality.LOW
	return quality_for(bench_s if bench_s >= 0.0 else adapter_s)


## Détection complète : modèle, puis mesure dans le menu ; émet `done`
## (Settings applique et enregistre le résultat).
func run() -> void:
	var adapter := RenderingServer.get_video_adapter_name()
	var integrated := RenderingServer.get_video_adapter_type() in [RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU, RenderingDevice.DEVICE_TYPE_CPU]
	var a_s := adapter_score(adapter, integrated)
	var b_s := -1.0
	var ms := -1.0
	if DisplayServer.get_name() != "headless" and a_s != 0.0:
		ms = await measure_gpu_ms()
		b_s = bench_score(ms, _pixels())
	var q := choose(a_s, b_s)
	var info := "carte « %s » (indice %.2f), menu %.2f ms GPU (indice %.2f) -> %s" % [
		adapter, a_s, ms, b_s, RenderQuality.preset(q).name]
	print("[Qualité auto] " + info)
	done.emit(q, info)


## Pixels de la fenêtre (la référence est prise en 1920x1080, même échelle
## 3D du menu).
func _pixels() -> float:
	var s := Vector2(get_window().size)
	return maxf(s.x * s.y, 1.0)


## Temps GPU moyen (ms) du viewport principal dans le menu, préréglage
## MEDIUM imposé ; -1 si le menu n'est pas affiché ou s'il est quitté pendant
## la mesure (le joueur lance déjà une partie : on garde l'indice du modèle).
func measure_gpu_ms(settle := SETTLE_SEC, dur := SAMPLE_SEC) -> float:
	var t_wait := 0.0
	while not _in_menu():
		await get_tree().process_frame
		t_wait += get_process_delta_time()
		if t_wait > 20.0:
			return -1.0
	var scene := get_tree().current_scene
	if Settings.quality != Settings.Quality.MEDIUM:
		Settings.quality = Settings.Quality.MEDIUM
		Settings.changed.emit()
	var rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	await get_tree().create_timer(settle, true, false, true).timeout
	var acc := 0.0
	var n := 0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < dur * 1000.0:
		await get_tree().process_frame
		if get_tree().current_scene != scene:
			return -1.0
		var g := RenderingServer.viewport_get_measured_render_time_gpu(rid)
		if g > 0.0:
			acc += g
			n += 1
	return acc / n if n > 0 else -1.0


func _in_menu() -> bool:
	var s := get_tree().current_scene
	return s != null and s.name == "MainMenu"
