extends TestCase
## Lecture sûre des réglages (SafeConfig) : fichier absent, trop gros ou
## illisible, texte .cfg mal formé, et lecture typée d'entiers (bornes, type
## inattendu, NaN / infini).

## Fichier temporaire hors des données du joueur (jamais user://).
const TMP := "res://tests/_out/safe_config_unittest.cfg"


func after_each() -> void:
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(TMP)


func _write(text: String) -> void:
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func test_load_file_failures() -> void:
	assert_eq(SafeConfig.load_file("res://tests/_out/absent_safe_config_unittest.cfg"), null, "fichier absent")
	_write("[a]\nb=1\n" + " ".repeat(SafeConfig.MAX_BYTES))
	assert_eq(SafeConfig.load_file(TMP), null, "fichier de plus de 1 Mo refusé")
	# (Fichier mal formé : refusé aussi, mais Godot écrit « ERROR: », compté
	# comme un échec par tools/check.sh ; non testé ici.)
	_write("[a]\nb=3\n")
	var cfg := SafeConfig.load_file(TMP)
	assert_true(cfg != null and cfg.get_value("a", "b") == 3, "fichier correct lu")


func test_parse_text_failures() -> void:
	# (Texte mal formé : refusé aussi, mais Godot affiche alors une erreur de
	# lecture « ERROR: » que tools/check.sh compte comme un échec ; non testé ici.)
	assert_eq(SafeConfig.parse_text("[a]\nb=Object(Node)\n", "test"), null, "constructeur interdit")
	assert_true(SafeConfig.parse_text("", "test") != null, "texte vide = réglages vides")


func test_get_int_bounds_and_types() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("s", "i", 50)
	cfg.set_value("s", "f", 7.9)
	cfg.set_value("s", "big", 1e30)
	cfg.set_value("s", "nan", NAN)
	cfg.set_value("s", "inf", INF)
	cfg.set_value("s", "txt", "12")
	cfg.set_value("s", "arr", [1])
	cfg.set_value("s", "b", true)
	assert_eq(SafeConfig.get_int(cfg, "s", "i", 3, 0, 10), 10, "entier borné en haut")
	assert_eq(SafeConfig.get_int(cfg, "s", "i", 3, 60, 90), 60, "entier borné en bas")
	assert_eq(SafeConfig.get_int(cfg, "s", "f", 3), 7, "flottant tronqué")
	assert_eq(SafeConfig.get_int(cfg, "s", "f", 3, 0, 5), 5, "flottant borné")
	cfg.set_value("s", "large", 1e6)
	assert_eq(SafeConfig.get_int(cfg, "s", "large", 3, 0, 100), 100, "grand flottant borné")
	# Flottant au-delà de l'entier 64 bits : borné avant la conversion.
	assert_eq(SafeConfig.get_int(cfg, "s", "big", 3, 0, 100), 100, "flottant 1e30 : borne haute (pas de débordement)")
	assert_eq(SafeConfig.get_int(cfg, "s", "nan", 3), 3, "NaN -> défaut")
	assert_eq(SafeConfig.get_int(cfg, "s", "inf", 3), 3, "infini -> défaut")
	assert_eq(SafeConfig.get_int(cfg, "s", "txt", 3), 3, "texte -> défaut")
	assert_eq(SafeConfig.get_int(cfg, "s", "arr", 3), 3, "tableau -> défaut")
	assert_eq(SafeConfig.get_int(cfg, "s", "b", 3), 3, "booléen -> défaut")
	assert_eq(SafeConfig.get_int(cfg, "s", "absent", 4), 4, "clé absente -> défaut")


func test_typed_reads_from_parsed_text() -> void:
	var cfg := SafeConfig.parse_text("[s]\ni=\"9\"\ns=42\nb=1\n", "test")
	assert_true(cfg != null, "texte lu")
	assert_eq(SafeConfig.get_int(cfg, "s", "i", 1), 1, "entier écrit en texte refusé")
	assert_eq(SafeConfig.get_string(cfg, "s", "s", "d"), "d", "nombre au lieu d'un texte")
	assert_eq(SafeConfig.get_bool(cfg, "s", "b", false), false, "1 au lieu d'un booléen")
