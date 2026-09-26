extends TestCase
## Préréglage automatique du premier lancement (QualityProbe) et ombres des
## zombies limitées par préréglage.


func test_adapter_scores() -> void:
	assert_eq(QualityProbe.adapter_score("NVIDIA GeForce GTX 1050"), 1.0)
	assert_eq(QualityProbe.adapter_score("NVIDIA GeForce GTX 1050 Ti"), 1.25, "Ti avant le modèle de base")
	assert_eq(QualityProbe.adapter_score("NVIDIA GeForce GTX 1070"), QualityProbe.DEV_SCORE)
	assert_eq(QualityProbe.adapter_score("NVIDIA GeForce GTX 1650 SUPER"), 1.9)
	assert_eq(QualityProbe.adapter_score("Radeon RX 580 Series"), 2.1, "Polaris avant RDNA")
	assert_eq(QualityProbe.adapter_score("AMD Radeon RX 5700 XT"), 3.5)
	assert_eq(QualityProbe.adapter_score("Intel(R) UHD Graphics 630"), 0.0, "puce intégrée")
	assert_eq(QualityProbe.adapter_score("AMD Radeon(TM) Graphics"), 0.0, "APU")
	assert_eq(QualityProbe.adapter_score("llvmpipe (LLVM 15.0.7, 256 bits)"), 0.0, "rendu logiciel")
	assert_eq(QualityProbe.adapter_score("Carte inconnue 9000"), -1.0)
	assert_eq(QualityProbe.adapter_score("Carte inconnue 9000", true), 0.0, "inconnue mais intégrée")


func test_quality_thresholds() -> void:
	assert_eq(QualityProbe.quality_for(-1.0), Settings.Quality.MEDIUM, "inconnu : MEDIUM")
	assert_eq(QualityProbe.quality_for(0.5), Settings.Quality.LOW)
	assert_eq(QualityProbe.quality_for(1.0), Settings.Quality.MEDIUM, "GTX 1050 : MEDIUM")
	assert_eq(QualityProbe.quality_for(QualityProbe.DEV_SCORE), Settings.Quality.HIGH, "GTX 1070 : HIGH")


func test_bench_score_is_resolution_independent() -> void:
	var full := QualityProbe.bench_score(QualityProbe.REF_MENU_MS, 1920.0 * 1080.0)
	assert_near(full, QualityProbe.DEV_SCORE, 0.001, "référence = GTX 1070")
	# Même carte, fenêtre 1280x720 : 2,25x moins de pixels, même indice.
	assert_near(QualityProbe.bench_score(QualityProbe.REF_MENU_MS / 2.25, 1280.0 * 720.0), full, 0.001)
	# Carte 3,5x plus lente : indice 1 (GTX 1050).
	assert_near(QualityProbe.bench_score(QualityProbe.REF_MENU_MS * 3.5, 1920.0 * 1080.0), 1.0, 0.001)
	assert_eq(QualityProbe.bench_score(-1.0, 100.0), -1.0, "mesure impossible")


func test_choose_prefers_bench_but_keeps_integrated_low() -> void:
	assert_eq(QualityProbe.choose(QualityProbe.DEV_SCORE, 0.6), Settings.Quality.LOW, "la mesure l'emporte")
	assert_eq(QualityProbe.choose(1.0, -1.0), Settings.Quality.MEDIUM, "sans mesure : le modèle")
	assert_eq(QualityProbe.choose(-1.0, -1.0), Settings.Quality.MEDIUM, "rien : MEDIUM")
	assert_eq(QualityProbe.choose(0.0, 5.0), Settings.Quality.LOW, "intégrée : LOW")


func test_zombie_shadow_budget_per_preset() -> void:
	var counts := []
	for q in RenderQuality.PRESETS:
		counts.append(int(q.zombie_shadows))
	assert_eq(counts[0], 0, "LOW : aucune ombre de zombie")
	assert_true(counts[0] <= counts[1] and counts[1] <= counts[2], "ordonné par coût")
	assert_true(counts[1] >= 4, "MEDIUM : les zombies proches gardent leur ombre")
