class_name HubFitButton
extends HubButton
## Bouton du hub qui se plie à la largeur que lui donne son conteneur : sa
## largeur minimale ne dépend pas de son texte, le texte rétrécit (jusqu'à
## 9 px) pour tenir. Pour les boutons côte à côte des cartes de contrat
## (« IL MANQUE 3 COLLIERS » + ABANDONNER dans 280 px ; à 130 % rien ne doit
## sortir de l'écran). Même dessin que HubButton.

## Taille de texte la plus petite (à l'échelle).
const MIN_FONT := 9


static func make_fit(t: String, cb: Callable, k := NORMAL, h := "") -> HubFitButton:
	var b := HubFitButton.new()
	b.label = t
	b.kind = k
	b.hint = h
	b.pressed.connect(func():
		Audio.play_ui(MenuStyle.SND_SELECT, MenuStyle.VOL_SELECT)
		cb.call())
	return b


func _resize() -> void:
	var h := HubStyle.px(height if height > 0 else (46 if big else 34))
	custom_minimum_size = Vector2(HubStyle.px(min_width), h)
	queue_redraw()


func _fsize() -> int:
	var s := HubStyle.fs(font_size if font_size > 0 else (20 if big else 15))
	if size.x <= 0.0:
		return s
	var room := size.x - HubStyle.px(10) * 2.0
	while s > MIN_FONT and HubStyle.text_width(label, HubStyle.font("impact", HubStyle.em(0.05, s)), s) > room:
		s -= 1
	return s


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
