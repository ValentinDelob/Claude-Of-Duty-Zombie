class_name MapTransfer
extends RefCounted
## Réception d'une carte perso par morceaux (client), sans réseau : MapShare
## lui passe ce qui arrive. Strict : les morceaux arrivent dans l'ordre
## (canal fiable et ordonné), chacun a exactement la taille annoncée (le
## dernier : le reste), jamais en double, jamais au-delà de la taille totale.
## À la fin : taille totale, nombre de morceaux et SHA-256 vérifiés
## (CustomMapGuard.check_package fait ensuite le contrôle de légitimité).
## Chaque erreur est un code de CustomMapGuard.REASONS.

var sha := ""
var size := 0
var chunk := 0
var count := 0
## Morceaux reçus (le suivant attendu est `received`).
var received := 0
var buf := PackedByteArray()
## Premier code d'erreur ("" : aucune) ; la réception s'arrête là.
var error := ""


## Commence la réception annoncée par `offer` (CustomMapGuard.check_offer).
func begin(offer: Dictionary) -> String:
	error = CustomMapGuard.check_offer(offer)
	if error != "":
		return error
	sha = offer["sha"]
	size = offer["size"]
	chunk = offer["chunk"]
	count = offer["chunks"]
	received = 0
	buf = PackedByteArray()
	return ""


## Taille attendue du morceau `index`.
func expected_size(index: int) -> int:
	return mini(chunk, size - index * chunk)


## Ajoute le morceau `index`. "" si accepté, sinon le code d'erreur.
func add(index: int, data: PackedByteArray) -> String:
	if error != "":
		return error
	if index < 0 or index >= count:
		error = "desordre"
	elif index < received:
		error = "double"
	elif index > received:
		error = "desordre"
	elif data.size() > chunk or buf.size() + data.size() > size:
		error = "trop_gros"
	elif data.size() != expected_size(index):
		error = "morceau"
	if error != "":
		return error
	buf.append_array(data)
	received += 1
	return ""


func complete() -> bool:
	return error == "" and received == count


func progress() -> int:
	return 0 if count <= 0 else int(100.0 * received / count)


## Fin de la réception : {ok, code, bytes}. Vérifie morceaux, taille, empreinte.
func finish() -> Dictionary:
	if error != "":
		return {"ok": false, "code": error}
	if received != count:
		return {"ok": false, "code": "manquant"}
	if buf.size() != size:
		return {"ok": false, "code": "taille"}
	if CustomMapGuard.sha256_hex(buf) != sha:
		return {"ok": false, "code": "hash"}
	return {"ok": true, "code": "", "bytes": buf}
