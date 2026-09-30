extends TestCase
## Manifeste des releases (tools/manifest.gd, utilisé par tools/release.sh et
## tools/promote.sh ; docs/RELEASE.md § 4) : entrée « launcher » adressée par
## son contenu, champs relus par les scripts, promotion en stable (manifestes
## de v0.2.0-snapshot.165 à 167 sans entrée « launcher » compris), et
## manifeste produit accepté par le lanceur (Releases.parse_manifest).
## Sans fichier ni réseau.

const Manifest := preload("res://tools/manifest.gd")
const LauncherReleases := "res://launcher/scripts/releases.gd"

const TAG := "v0.2.0-snapshot.180"
const H_ENG := "1111111111111111111111111111111111111111111111111111111111111111"
const H_CORE := "2222222222222222222222222222222222222222222222222222222222222222"
const H_VOX := "3333333333333333333333333333333333333333333333333333333333333333"
const H_LAU := "4444444444444444444444444444444444444444444444444444444444444444"
const IN_LAU := "5555555555555555555555555555555555555555555555555555555555555555"


## Lignes TSV telles que release.sh les écrit (7 colonnes, la dernière vide
## sauf pour le lanceur).
func _tsv(launcher_line := true) -> String:
	var lines := [
		"engine\tengine-4.7.2.exe\t%s\t109268480\tv0.2.0-snapshot.165\t%s\t" % [H_ENG, H_ENG],
		"core\tcore-22222222.pck\t%s\t15000000\t%s\t\t" % [H_CORE, TAG],
		"vox-fr\tvox-fr-abcdef12.pck\t%s\t26000000\tv0.2.0-snapshot.166\tabcdef12\t" % [H_VOX],
	]
	if launcher_line:
		lines.append("launcher\tClaudeOfDutyZombie-Launcher.exe\t%s\t109300000\tv0.2.0-snapshot.170\t%s\t8" % [H_LAU, IN_LAU])
	return "\r\n".join(lines) + "\r\n"


func _make(tsv: String) -> Dictionary:
	return Manifest.make(tsv, TAG, "snapshot", "0.2.0-snapshot.180", "4.7.2")


func test_make_records_the_launcher_by_content() -> void:
	var d := _make(_tsv())
	assert_false(d.is_empty(), "manifeste construit")
	assert_eq(d.launcher, {"file": "ClaudeOfDutyZombie-Launcher.exe", "sha256": H_LAU, "size": 109300000,
		"release": "v0.2.0-snapshot.170", "inputs": IN_LAU, "version": 8}, "entrée launcher : fichier de la release qui le porte")
	assert_eq(d.engine.godot, "4.7.2")
	assert_eq(d.engine.release, "v0.2.0-snapshot.165", "moteur repris d'une release plus ancienne")
	assert_eq((d.packs as Array).size(), 2)
	assert_true(d.packs[0].main and not d.packs[0].has("inputs"), "core principal, sans empreinte d'entrée")
	assert_eq(d.packs[1].lang, "fr")
	assert_false(d.packs[1].has("version"), "le numéro n'est lu que pour le lanceur")


func test_make_requires_a_valid_launcher() -> void:
	assert_true(_make(_tsv(false)).is_empty(), "sans lanceur : manifeste refusé (le lanceur doit toujours être décrit)")
	for bad in ["", "0", "-1", "huit", "8.5"]:
		var tsv := _tsv().replace("\t%s\t8\r\n" % IN_LAU, "\t%s\t%s\r\n" % [IN_LAU, bad])
		assert_true(_make(tsv).is_empty(), "numéro du lanceur « %s » refusé" % bad)


func test_get_field_for_the_release_scripts() -> void:
	# Relu après JSON (tailles et numéros deviennent des nombres à virgule).
	var d: Dictionary = JSON.parse_string(JSON.stringify(_make(_tsv())))
	assert_eq(Manifest.get_field(d, "launcher", "version"), "8")
	assert_eq(Manifest.get_field(d, "launcher", "size"), "109300000", "entier sans « .0 »")
	assert_eq(Manifest.get_field(d, "launcher", "inputs"), IN_LAU)
	assert_eq(Manifest.get_field(d, "launcher", "release"), "v0.2.0-snapshot.170")
	assert_eq(Manifest.get_field(d, "vox-fr", "inputs"), "abcdef12")
	assert_eq(Manifest.get_field(d, "", "build"), "0.2.0-snapshot.180", "champ du manifeste lui-même")
	assert_eq(Manifest.get_field(d, "", "packs"), "", "liste : pas une valeur")
	assert_eq(Manifest.get_field(d, "core", "inputs"), "", "champ absent")
	var old: Dictionary = d.duplicate(true)
	old.erase("launcher")
	assert_eq(Manifest.get_field(old, "launcher", "version"), "", "manifeste 165 à 167 : pas de lanceur")


func test_promote_keeps_the_snapshot_launcher() -> void:
	var snap: Dictionary = JSON.parse_string(JSON.stringify(_make(_tsv())))
	var d := Manifest.promote(snap, "v0.2.0")
	assert_eq(d.version, "v0.2.0")
	assert_eq(d.channel, "stable")
	assert_eq(d.promoted_from, TAG)
	assert_eq(d.build, "0.2.0-snapshot.180", "même build que la snapshot")
	assert_eq(d.launcher.release, "v0.2.0-snapshot.170", "lanceur de la snapshot gardé tel quel")
	assert_eq(d.launcher.version, 8, "numéros entiers après relecture")
	assert_eq(d.packs[0].size, 15000000)
	assert_eq(snap.channel, "snapshot", "manifeste de la snapshot non modifié")


func test_promote_old_snapshot_adds_the_launcher() -> void:
	var snap: Dictionary = JSON.parse_string(JSON.stringify(_make(_tsv())))
	snap.erase("launcher")
	assert_true(Manifest.promote(snap, "v0.2.0").is_empty(), "sans entrée launcher ni lanceur fourni : refusé")
	var line := "launcher\tClaudeOfDutyZombie-Launcher.exe\t%s\t109300000\tv0.2.0-snapshot.167\t\t7\n" % H_LAU
	var l: Dictionary = Manifest._launcher_line(line)
	assert_eq(l, {"file": "ClaudeOfDutyZombie-Launcher.exe", "sha256": H_LAU, "size": 109300000,
		"release": "v0.2.0-snapshot.167", "version": 7}, "ligne du lanceur joint à la snapshot")
	var d := Manifest.promote(snap, "v0.2.0", l)
	assert_eq(d.launcher.version, 7)
	assert_eq(d.launcher.release, "v0.2.0-snapshot.167")
	assert_true(Manifest._launcher_line("launcher\tx.exe\t%s\t1\tv0.2.0\t\tzéro\n" % H_LAU).is_empty(), "numéro illisible refusé")


func test_launcher_accepts_the_produced_manifests() -> void:
	# Le script du lanceur est lu tel quel (projet séparé, launcher/).
	var releases: GDScript = load(LauncherReleases)
	assert_true(releases != null, "launcher/scripts/releases.gd lisible")
	if releases == null:
		return
	var text := JSON.stringify(_make(_tsv()), "  ")
	var m: Dictionary = releases.parse_manifest(text, TAG)
	assert_false(m.is_empty(), "manifeste de release.sh accepté par le lanceur")
	assert_eq(m.get("launcher", {}).get("url", ""),
		"https://github.com/ValentinDelob/Claude-Of-Duty-Zombie/releases/download/v0.2.0-snapshot.170/ClaudeOfDutyZombie-Launcher.exe")
	var snap: Dictionary = JSON.parse_string(text)
	var stable := JSON.stringify(Manifest.promote(snap, "v0.2.0"))
	var ms: Dictionary = releases.parse_manifest(stable, "v0.2.0")
	assert_eq(ms.get("channel", ""), "stable", "manifeste promu accepté par le lanceur")
	assert_eq(ms.get("launcher", {}).get("version", 0), 8)
