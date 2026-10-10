extends SceneTree
## Vérification d'un paquet exporté (docs/RELEASE.md § 7) : liste son contenu
## (format PCK de Godot 4, lu directement : Godot n'expose pas cette liste) et
## échoue si un fichier n'est pas d'un type autorisé ou si le paquet dépasse
## la taille maximale. La release s'arrête alors (tools/release.sh).
##   godot --headless -s res://tools/pack_check.gd -- --pck=<fichier> [--max-mb=40] [--list=<sortie.txt>] [--vox]
## --vox : paquet de répliques (seulement des .import et .oggvorbisstr de
## assets/audio/vox/).

## Types autorisés dans un paquet du jeu (extension du chemin dans le paquet).
const ALLOWED := [
	"gdc", "gd", "remap", "import", "uid",                    # scripts et redirections
	"scn", "tscn", "res", "tres",                              # scènes et ressources
	"ctex", "ctexarray", "ctex3d", "image",                    # textures importées
	"oggvorbisstr", "sample", "mp3str", "wav",                 # sons importés
	"mesh", "fontdata", "ttf", "otf",                          # modèles, polices
	"gdshader", "gdshaderinc", "json", "cfg", "bin", "binary", # shaders, données, caches Godot
]
## Fichiers de travail qui ne doivent JAMAIS partir chez les joueurs, quel que
## soit leur chemin (message clair).
const FORBIDDEN := ["blend", "blend1", "py", "md", "zip", "log", "psd", "kra", "xcf", "bat", "sh", "exe", "pck", "tmp"]
## Seuls documents embarqués : ceux que le serveur MCP du jeu livre à l'IA
## (McpDocs, docs/MCP.md ; export_presets.cfg, include_filter).
const EMBEDDED_DOCS := ["res://docs/MAP_DESIGN_RULES.md", "res://docs/MAP_AUTHORING.md", "res://docs/MAP_OBJECTS.md",
	"res://docs/EDITOR_VIEWS.md", "res://docs/EDITOR_SCALE_ROTATE.md"]


func _init() -> void:
	var pck := ""
	var max_mb := 40.0
	var list_out := ""
	var vox := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pck="):
			pck = a.substr(6)
		elif a.begins_with("--max-mb="):
			max_mb = a.substr(9).to_float()
		elif a.begins_with("--list="):
			list_out = a.substr(7)
		elif a == "--vox":
			vox = true
	var files := read_pck(pck)
	if files.is_empty():
		printerr("[pack] paquet illisible ou vide : " + pck)
		quit(1)
		return
	var bad := PackedStringArray()
	var by_ext := {}
	var lines := PackedStringArray()
	for f: Dictionary in files:
		var path: String = f.path
		var ext := path.get_extension().to_lower()
		by_ext[ext] = int(by_ext.get(ext, 0)) + 1
		lines.append("%10d  %s" % [f.size, path])
		if path == "res://icon.svg":
			continue  # icône de la fenêtre (application/config/icon)
		if not vox and path in EMBEDDED_DOCS:
			continue  # documents lus par le serveur MCP du jeu (McpDocs)
		if ext in FORBIDDEN or not ext in ALLOWED:
			bad.append("%s (type .%s non autorisé)" % [path, ext])
		elif vox and not (path.begins_with("res://assets/audio/vox/") and ext == "import" or path.begins_with("res://.godot/imported/") and ext == "oggvorbisstr"):
			bad.append("%s (hors des répliques)" % path)
		elif path.begins_with("res://tests/_out/") or path.begins_with("res://build/") or path.begins_with("res://tools/") \
				or path.begins_with("res://docs/") or path.begins_with("res://launcher/"):
			bad.append("%s (dossier de travail)" % path)
	# Fichiers de données lus par le jeu (contrats, échanges du hub…) : tous
	# dans le paquet du jeu (export_presets.cfg, include_filter
	# « assets/data/* »), sinon le jeu exporté tournerait sans eux.
	if not vox:
		var inside := {}
		for f: Dictionary in files:
			inside[f.path] = true
		for want in data_files("res://assets/data"):
			if not inside.has(want):
				bad.append("%s (donnée du jeu absente du paquet)" % want)
	if list_out != "":
		var fo := FileAccess.open(list_out, FileAccess.WRITE)
		fo.store_string("\n".join(lines) + "\n")
	var size_mb := FileAccess.get_file_as_bytes(pck).size() / 1048576.0 if FileAccess.file_exists(pck) else 0.0
	var summary := PackedStringArray()
	for e in by_ext:
		summary.append("%s:%d" % [e, by_ext[e]])
	print("[pack] %s : %d fichiers, %.1f Mo (%s)" % [pck.get_file(), files.size(), size_mb, " ".join(summary)])
	var ok := true
	if size_mb > max_mb:
		print("[pack] ECHEC : %.1f Mo > %.0f Mo autorisés" % [size_mb, max_mb])
		ok = false
	for b in bad.slice(0, 30):
		print("[pack] ECHEC fichier parasite : " + b)
	if not bad.is_empty():
		print("[pack] ECHEC : %d fichier(s) parasite(s)" % bad.size())
		ok = false
	quit(0 if ok else 1)


## Fichiers de données du projet sous `dir` (récursif, chemins res://).
static func data_files(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".import") and not f.ends_with(".uid"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(data_files(dir.path_join(d)))
	return out


## Liste [{path, size}] d'un PCK Godot 4 (versions de format 2 à 4), [] si
## le fichier n'en est pas un. Répertoire en fin de fichier (format 3+) ou
## juste après l'en-tête (format 2).
static func read_pck(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() < 32:
		return []
	if f.get_32() != 0x43504447:  # « GDPC »
		return []
	var fmt := f.get_32()
	f.get_32()  # version de Godot : majeure
	f.get_32()  # mineure
	f.get_32()  # correctif
	if fmt < 2 or fmt > 4:
		return []
	var flags := f.get_32()
	if flags & 1:  # répertoire chiffré : illisible ici
		return []
	var file_base := f.get_64()
	var dir_at := f.get_position() + 16 * 4
	if fmt >= 3:
		dir_at = f.get_64()
	f.seek(dir_at)
	var count := f.get_32()
	var out := []
	if count > 200000:
		return []
	for i in count:
		var n := f.get_32()
		if n <= 0 or n > 4096:
			return []
		var raw := f.get_buffer(n)
		var p := raw.get_string_from_utf8()
		if not p.begins_with("res://"):
			p = "res://" + p
		var _offset := f.get_64() + file_base
		var size := f.get_64()
		f.get_buffer(16)  # md5
		f.get_32()        # drapeaux du fichier
		out.append({"path": p, "size": size})
	return out
