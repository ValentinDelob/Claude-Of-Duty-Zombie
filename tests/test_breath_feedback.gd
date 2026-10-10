extends TestCase
## Essoufflement audible (BreathFeedback) : rythme et volume selon l'énergie,
## halètement à l'épuisement, retour progressif au calme, priorité à la
## respiration de santé basse, niveaux plafonnés à ceux de hud.gd.

const B := BreathFeedback
const DT := 1.0 / 60.0


## Faux objet énergie (contrat de PlayerEnergy : value, max_value, exhausted, ratio()).
class FakeEnergy extends RefCounted:
	var value := 100.0
	var max_value := 100.0
	var exhausted := false

	func ratio() -> float:
		return clampf(value / max_value, 0.0, 1.0)


func test_silent_above_threshold() -> void:
	assert_eq(B.breath_interval(1.0, false), INF, "énergie pleine : rien")
	assert_eq(B.breath_interval(0.5, false), INF, "50 % : rien")
	assert_eq(B.breath_interval(B.THRESHOLD, false), INF, "au seuil : rien")
	assert_eq(B.breath_volume(0.4, false), -INF)
	assert_true(B.breath_interval(0.3, false) < INF, "sous 35 % : audible")


func test_faster_and_louder_as_energy_drops() -> void:
	var prev_i := INF
	var prev_v := -INF
	for r in [0.3, 0.2, 0.1, 0.0]:
		var i := B.breath_interval(r, false)
		var v := B.breath_volume(r, false)
		assert_true(i < prev_i, "%.1f : souffles plus rapprochés (%.2f s)" % [r, i])
		assert_true(v > prev_v, "%.1f : souffles plus forts (%.1f dB)" % [r, v])
		prev_i = i
		prev_v = v
	assert_near(B.breath_interval(0.0, false), B.INTERVAL_LOW, 0.001)


func test_exhausted_pants_hardest() -> void:
	# Épuisé, même avec de l'énergie qui remonte (fin à 50 %) : halètement.
	for r in [0.0, 0.3, 0.49]:
		assert_near(B.breath_interval(r, true), B.INTERVAL_EXHAUSTED, 0.001, "épuisé à %.2f" % r)
		assert_near(B.breath_volume(r, true), B.VOLUME_MAX, 0.001)
	assert_true(B.breath_interval(0.0, true) < B.breath_interval(0.0, false), "plus rapide que l'énergie basse")
	assert_true(B.breath_volume(0.0, true) > B.breath_volume(0.0, false), "plus fort que l'énergie basse")


func test_levels_stay_within_hud_breath() -> void:
	# Jamais plus fort que la respiration de santé basse de hud.gd (-8 dB).
	assert_true(B.VOLUME_MAX <= -8.0)
	for k in [0.0, 0.25, 0.5, 0.75, 1.0, 1.5]:
		assert_true(B.volume_for(k) <= B.VOLUME_MAX + 0.001, "volume %.2f" % k)
		var p := B.pitch_for(k)
		assert_true(p >= B.PITCH_CALM - 0.001 and p <= B.PITCH_MAX + 0.001, "hauteur %.2f" % k)
		assert_true(B.interval_for(k) >= B.INTERVAL_EXHAUSTED - 0.001, "intervalle %.2f" % k)


func test_smoothing_rises_fast_falls_slow() -> void:
	var k := 0.0
	for i in 30:
		k = B.smooth_intensity(k, 1.0, DT)
	assert_near(k, 1.0, 0.001, "0,5 s pour monter au halètement")
	k = B.smooth_intensity(k, 0.0, 1.0)
	assert_near(k, 1.0 - B.FALL_RATE, 0.001, "redescend lentement")
	assert_eq(B.smooth_intensity(0.3, 0.3, 1.0), 0.3, "stable sur la cible")


func test_health_breath_condition() -> void:
	assert_false(B.health_breath_active(100, 100, true), "santé pleine")
	assert_false(B.health_breath_active(60, 100, true), "40 % perdus")
	assert_true(B.health_breath_active(50, 100, true), "50 % perdus : hud.gd respire")
	assert_false(B.health_breath_active(10, 100, false), "à terre : plus de respiration de hud.gd")


## Test « actor » : le nœud seul, avancé à la main.
func _run(b: BreathFeedback, seconds: float) -> void:
	for i in int(seconds / DT):
		b._process(DT)


func test_actor_rhythm_and_recovery() -> void:
	var e := FakeEnergy.new()
	var b := BreathFeedback.new()
	host.add_child(b)
	b.set_process(false)  # avancé à la main
	b.setup(e)
	_run(b, 3.0)
	assert_eq(b.breaths, 0, "énergie pleine : silence")

	e.value = 20.0
	_run(b, 6.0)
	var low := b.breaths
	assert_true(low >= 2 and low <= 6, "énergie basse : quelques souffles (%d)" % low)

	e.value = 0.0
	e.exhausted = true
	b.breaths = 0
	_run(b, 6.0)
	assert_true(b.breaths > low, "épuisé : halètement plus rapide (%d > %d)" % [b.breaths, low])
	assert_near(b.intensity, 1.0, 0.001)

	# Fin de l'épuisement à 50 % : retour progressif au calme.
	e.value = 50.0
	e.exhausted = false
	b.breaths = 0
	_run(b, 1.0)
	assert_true(b.breaths >= 1, "toujours essoufflé juste après")
	assert_true(b.intensity > 0.5, "le calme revient progressivement (%.2f)" % b.intensity)
	_run(b, 6.0)
	assert_true(b.intensity < B.SILENT, "calme retrouvé")
	b.breaths = 0
	_run(b, 3.0)
	assert_eq(b.breaths, 0, "plus aucun souffle")
	b.queue_free()


func test_actor_suppressed_by_low_health() -> void:
	var e := FakeEnergy.new()
	e.value = 0.0
	e.exhausted = true
	var b := BreathFeedback.new()
	host.add_child(b)
	b.set_process(false)
	b.setup(e)
	b.suppressed = true
	_run(b, 4.0)
	assert_eq(b.breaths, 0, "santé basse prioritaire : aucun souffle d'énergie")
	assert_near(b.intensity, 1.0, 0.001, "l'essoufflement suit quand même l'énergie")
	b.suppressed = false
	_run(b, 2.0)
	assert_true(b.breaths >= 2, "reprend dès que la santé remonte (%d)" % b.breaths)
	b.queue_free()


func test_no_energy_object_is_harmless() -> void:
	var b := BreathFeedback.new()
	host.add_child(b)
	b.set_process(false)
	_run(b, 1.0)
	assert_eq(b.breaths, 0)
	b.queue_free()
