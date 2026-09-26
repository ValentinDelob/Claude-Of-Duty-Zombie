class_name SynthStems
extends RefCounted
## Pistes procédurales (composition originale) mélangées à des enregistrements
## CC0 par tools/audio/sfx_import.gd : couche `{"stem": "<nom>"}` d'une
## recette SfxRecipes. Déterministe (graine fixe par nom).

const MONKEY_BPM := 135.0
const MONKEY_SECONDS := 8.0


static func build(n: String) -> PackedFloat32Array:
	var s := Synth.new(hash(n))
	match n:
		"monkey_tune":
			return monkey_tune(s)
	push_error("[SynthStems] piste inconnue : " + n)
	return PackedFloat32Array()


## Grille de temps nommée (clé `times` d'une couche de recette).
static func grid(n: String) -> PackedFloat32Array:
	match n:
		"monkey_beats":
			return monkey_beats()
	push_error("[SynthStems] grille inconnue : " + n)
	return PackedFloat32Array([0.0])


## Instants (s) des temps de l'air du singe : 135 bpm pendant 8 s, les trois
## derniers temps ralentissent comme un ressort qui se détend. Les cymbales
## (enregistrement CC0) tombent sur ces temps.
static func monkey_beats() -> PackedFloat32Array:
	var beat := 60.0 / MONKEY_BPM
	var n := int(MONKEY_SECONDS / beat)
	var out := PackedFloat32Array()
	var t := 0.0
	for i in n:
		out.append(snappedf(t, 0.001))
		t += beat * (1.0 + maxf(0.0, float(i - (n - 4))) * 0.12)
	return out


## SINGE-TAMBOUR : air de fête foraine (orgue de barbarie désaccordé, basse
## « oum-pa »), sans les cymbales (enregistrées, voir la recette monkey_music).
static func monkey_tune(s: Synth) -> PackedFloat32Array:
	var beat := 60.0 / MONKEY_BPM
	var b := s.buf(MONKEY_SECONDS + 0.6)
	var melody := [7, 9, 11, 12, 11, 9, 7, 4, 5, 7, 9, 7, 5, 4, 2, 0,
		7, 9, 11, 12, 14, 12, 11, 9, 7, 11, 14, 12, 11, 9, 7, 0]
	var n := int(MONKEY_SECONDS / beat)
	var t := 0.0
	for i in n:
		var slow := 1.0 + maxf(0.0, float(i - (n - 4))) * 0.12
		var bass: float = 98.0 if (i / 2) % 2 == 0 else 73.4
		s.mix(b, s.env_exp(s.tone(beat, bass if i % 2 == 0 else bass * 1.5, "tri"), 0.004, 0.12), t, 0.35)
		for h in 2:
			var note: int = melody[(i * 2 + h) % melody.size()]
			var f: float = 523.25 * pow(2.0, note / 12.0) * (1.0 - 0.02 * float(i) / n)
			var v := s.env_exp(s.tone(beat * 0.6, f, "square"), 0.003, 0.09)
			s.mix(v, s.env_exp(s.tone(beat * 0.6, f * 1.006, "saw"), 0.003, 0.07), 0.0, 0.5)
			s.mix(b, s.lowpass(v, 3200.0), t + h * beat * 0.5 * slow, 0.16)
		t += beat * slow
	return s.finish(s.reverb(b, 0.6, 0.22, 0.6), 0.8)
