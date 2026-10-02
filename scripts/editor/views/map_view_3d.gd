class_name MapView3D
extends MapView
## Fenêtre de vue en 3D (docs/EDITOR_VIEWS.md, D14) : l'aperçu 3D en direct
## (MapPreviewPanel, même MapPreviewWorld) intégré dans une fenêtre de la
## disposition. Une seule 3D à la fois : tant qu'elle est ici, l'aperçu
## quitte son panneau flottant ; sans fenêtre 3D, le panneau flottant et la
## touche P marchent comme avant. En-tête : mode de caméra, « ⌖ Sélection »,
## « Affichage ▾ » ; ViewCube isométrique (sur l'aperçu).

var preview: MapPreviewPanel


func _ready() -> void:
	plane = "3d"
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## L'aperçu entre dans cette fenêtre.
func attach() -> void:
	if preview != null:
		preview.attach_to(self)


## L'aperçu retourne dans son panneau flottant (caché).
func detach() -> void:
	if preview != null and preview.pane_host == self:
		preview.detach_from_pane()


func zoom_percent() -> int:
	return 100


func header_sub() -> String:
	if preview == null:
		return ""
	match preview.world.rig.mode:
		MapPreviewCamera.Mode.FLY:
			return Lang.t("Vol libre", "Free flight")
		MapPreviewCamera.Mode.WALK:
			return Lang.t("Joueur", "Player")
	return Lang.t("Orbite", "Orbit")


func header_chips() -> Array:
	return [{"id": "cam", "text": Lang.t("Caméra ▾", "Camera ▾")}, {"id": "sel", "text": Lang.t("⌖ Sélection", "⌖ Selection")},
		{"id": "disp", "text": Lang.t("Affichage ▾", "Display ▾")}]


func header_menu(id: String) -> Array:
	if id == "cam" and preview != null:
		var m := int(preview.world.rig.mode)
		return [{"id": MapPreviewCamera.Mode.ORBIT, "text": Lang.t("Orbite", "Orbit"), "radio": m == MapPreviewCamera.Mode.ORBIT},
			{"id": MapPreviewCamera.Mode.FLY, "text": Lang.t("Vol libre", "Free flight"), "radio": m == MapPreviewCamera.Mode.FLY},
			{"id": MapPreviewCamera.Mode.WALK, "text": Lang.t("Joueur", "Player"), "radio": m == MapPreviewCamera.Mode.WALK},
			{"sep": ""}, {"id": 10, "text": Lang.t("Recadrer sur la carte", "Frame the map")}]
	return []


func header_menu_pressed(id: String, i: int) -> void:
	if preview == null:
		return
	match id:
		"cam":
			if i == 10:
				preview.world.frame_map()
			else:
				preview.set_camera_mode(i)
		"sel":
			preview.center_on_selection()
		"disp":
			var pm := preview.display_menu.get_popup()
			pm.reset_size()
			pm.position = Vector2i(get_screen_position() + Vector2(size.x - pm.size.x, 0))
			pm.popup()


func frame_all() -> void:
	if preview != null:
		preview.world.frame_map()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("101113"))
