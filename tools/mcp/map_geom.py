"""Géométrie 2D des cartes de l'éditeur, côté pont MCP (bibliothèque standard).

Reprend les conventions de scripts/editor/map_geom.gd : coordonnées en mètres,
x vers l'est, y vers le sud ; une pièce = un contour (liste de [x, y]) qui est
le trait de ses murs ; deux côtés parallèles à moins de JOIN_TOL (3 cm) l'un
de l'autre forment un bord commun (mur mitoyen).

Sert à résumer une carte (editor_get_map, format « summary ») et à proposer un
couloir entre deux pièces (editor_plan_corridor), sans jamais rien appliquer.
"""

from __future__ import annotations

import math

EPS = 0.001
JOIN_TOL = 0.03
CELL = 0.5
# Tolérance pour dire qu'une ouverture (position) est sur le trait d'une pièce.
OPENING_TOL = 0.05
# Prix des portes de l'éditeur (MapCatalog.DOOR_PRICES).
DOOR_PRICES = [750, 1000, 1250]

Point = tuple[float, float]


# ------------------------------------------------------------------ bases

def pts(contour) -> list[Point]:
    """Contour JSON ([[x, y], ...]) en liste de tuples ; ignore les points illisibles."""
    out: list[Point] = []
    for p in contour or []:
        try:
            out.append((float(p[0]), float(p[1])))
        except (TypeError, ValueError, IndexError):
            continue
    return out


def r2(v: float) -> float:
    """Arrondi au centimètre (affichage), sans « -0.0 »."""
    v = round(float(v), 2)
    return 0.0 if v == 0 else v


def rp(p: Point) -> list[float]:
    return [r2(p[0]), r2(p[1])]


def bbox(poly: list[Point]) -> list[float]:
    """Boîte englobante [x0, y0, x1, y1] (vide : [0, 0, 0, 0])."""
    if not poly:
        return [0.0, 0.0, 0.0, 0.0]
    xs = [p[0] for p in poly]
    ys = [p[1] for p in poly]
    return [min(xs), min(ys), max(xs), max(ys)]


def area(poly: list[Point]) -> float:
    """Surface (m², formule du lacet, toujours positive)."""
    s = 0.0
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        s += x1 * y2 - x2 * y1
    return abs(s) / 2.0


def centroid(poly: list[Point]) -> Point:
    """Centre de gravité du contour (moyenne des sommets si surface nulle)."""
    a = 0.0
    cx = cy = 0.0
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        c = x1 * y2 - x2 * y1
        a += c
        cx += (x1 + x2) * c
        cy += (y1 + y2) * c
    if abs(a) < EPS:
        if not poly:
            return (0.0, 0.0)
        return (sum(p[0] for p in poly) / n, sum(p[1] for p in poly) / n)
    a *= 0.5
    return (cx / (6 * a), cy / (6 * a))


def is_axis_rect(poly: list[Point]) -> bool:
    """Rectangle aligné sur les axes (comme MapGeom.is_axis_rect)."""
    if len(poly) < 4:
        return False
    x0, y0, x1, y1 = bbox(poly)
    for x, y in poly:
        on_x = abs(x - x0) < EPS or abs(x - x1) < EPS
        on_y = abs(y - y0) < EPS or abs(y - y1) < EPS
        if not (on_x and on_y):
            return False
    return abs(area(poly) - (x1 - x0) * (y1 - y0)) < EPS


def edges(poly: list[Point]):
    n = len(poly)
    for i in range(n):
        yield poly[i], poly[(i + 1) % n]


def closest_on_segment(p: Point, a: Point, b: Point) -> Point:
    dx, dy = b[0] - a[0], b[1] - a[1]
    l2 = dx * dx + dy * dy
    if l2 < EPS * EPS:
        return a
    t = max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / l2))
    return (a[0] + t * dx, a[1] + t * dy)


def dist(a: Point, b: Point) -> float:
    return math.hypot(a[0] - b[0], a[1] - b[1])


def dist_to_segment(p: Point, a: Point, b: Point) -> float:
    return dist(p, closest_on_segment(p, a, b))


def dist_to_boundary(poly: list[Point], p: Point) -> float:
    return min((dist_to_segment(p, a, b) for a, b in edges(poly)), default=math.inf)


def on_boundary(poly: list[Point], p: Point, tol: float = OPENING_TOL) -> bool:
    return dist_to_boundary(poly, p) <= tol


def contains(poly: list[Point], p: Point) -> bool:
    """Point dans le polygone (règle pair-impair ; bord : indéterminé)."""
    x, y = p
    inside = False
    n = len(poly)
    j = n - 1
    for i in range(n):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > y) != (yj > y):
            xc = xi + (y - yi) * (xj - xi) / (yj - yi)
            if x < xc:
                inside = not inside
        j = i
    return inside


def strictly_inside(poly: list[Point], p: Point, tol: float = JOIN_TOL) -> bool:
    return contains(poly, p) and dist_to_boundary(poly, p) > tol


# ------------------------------------------------------------------ bords communs, distances

def edge_common(a1: Point, a2: Point, pb: list[Point], tol: float = JOIN_TOL) -> list[list[Point]]:
    """Parties du segment [a1, a2] qui longent le contour pb (MapGeom.edge_common)."""
    out: list[list[Point]] = []
    dx, dy = a2[0] - a1[0], a2[1] - a1[1]
    seg_len = math.hypot(dx, dy)
    if seg_len < EPS:
        return out
    dx /= seg_len
    dy /= seg_len
    nx, ny = -dy, dx
    for b1, b2 in edges(pb):
        if abs((b1[0] - a1[0]) * nx + (b1[1] - a1[1]) * ny) > tol:
            continue
        if abs((b2[0] - a1[0]) * nx + (b2[1] - a1[1]) * ny) > tol:
            continue
        bl = dist(b1, b2)
        if bl > EPS and abs(((b2[0] - b1[0]) * nx + (b2[1] - b1[1]) * ny) / bl) > 0.0175:
            continue
        t1 = (b1[0] - a1[0]) * dx + (b1[1] - a1[1]) * dy
        t2 = (b2[0] - a1[0]) * dx + (b2[1] - a1[1]) * dy
        lo = max(0.0, min(t1, t2))
        hi = min(seg_len, max(t1, t2))
        if hi - lo > EPS:
            out.append([(a1[0] + dx * lo, a1[1] + dy * lo), (a1[0] + dx * hi, a1[1] + dy * hi)])
    return out


def common_segments(pa: list[Point], pb: list[Point], tol: float = JOIN_TOL) -> list[list[Point]]:
    """Segments communs (mur mitoyen) des contours de deux pièces."""
    ba, bb = bbox(pa), bbox(pb)
    g = tol + 0.01
    if ba[2] + g < bb[0] or bb[2] + g < ba[0] or ba[3] + g < bb[1] or bb[3] + g < ba[1]:
        return []
    out: list[list[Point]] = []
    for a1, a2 in edges(pa):
        out.extend(edge_common(a1, a2, pb, tol))
    return out


def closest_points(pa: list[Point], pb: list[Point]) -> tuple[float, Point, Point]:
    """Distance entre les contours de deux pièces et points les plus proches
    (sur le bord de pa, sur le bord de pb). Pour deux segments qui ne se coupent
    pas, le minimum est atteint à un bout de l'un d'eux."""
    best = (math.inf, (0.0, 0.0), (0.0, 0.0))
    if not pa or not pb:
        return best
    for a1, a2 in edges(pa):
        for b1, b2 in edges(pb):
            if segments_cross(a1, a2, b1, b2):
                p = intersection(a1, a2, b1, b2) or a1
                return (0.0, p, p)
            for p, (s1, s2), first in ((a1, (b1, b2), True), (a2, (b1, b2), True),
                                       (b1, (a1, a2), False), (b2, (a1, a2), False)):
                q = closest_on_segment(p, s1, s2)
                d = dist(p, q)
                if d < best[0]:
                    best = (d, p, q) if first else (d, q, p)
    return best


def nearest_edge_point(room: list[Point], other: list[Point]) -> Point:
    """Point du bord de `room` le plus proche de la pièce `other`."""
    return closest_points(room, other)[1]


def _orient(a: Point, b: Point, c: Point) -> float:
    return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])


def segments_cross(a1: Point, a2: Point, b1: Point, b2: Point, tol: float = 1e-9) -> bool:
    """Les deux segments se coupent-ils franchement (pas un simple contact) ?"""
    d1 = _orient(b1, b2, a1)
    d2 = _orient(b1, b2, a2)
    d3 = _orient(a1, a2, b1)
    d4 = _orient(a1, a2, b2)
    return ((d1 > tol and d2 < -tol) or (d1 < -tol and d2 > tol)) and \
        ((d3 > tol and d4 < -tol) or (d3 < -tol and d4 > tol))


def intersection(a1: Point, a2: Point, b1: Point, b2: Point) -> Point | None:
    d = (a2[0] - a1[0]) * (b2[1] - b1[1]) - (a2[1] - a1[1]) * (b2[0] - b1[0])
    if abs(d) < 1e-12:
        return None
    t = ((b1[0] - a1[0]) * (b2[1] - b1[1]) - (b1[1] - a1[1]) * (b2[0] - b1[0])) / d
    return (a1[0] + t * (a2[0] - a1[0]), a1[1] + t * (a2[1] - a1[1]))


def _samples(poly: list[Point]) -> list[Point]:
    """Points témoins de l'intérieur d'un contour : sommets décalés vers
    l'intérieur, milieux des côtés décalés, centre."""
    out: list[Point] = []
    c = centroid(poly)
    if contains(poly, c):
        out.append(c)
    for a, b in edges(poly):
        m = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
        for p in (a, m):
            q = (p[0] + (c[0] - p[0]) * 0.02, p[1] + (c[1] - p[1]) * 0.02)
            if contains(poly, q):
                out.append(q)
        # Point juste à l'intérieur du milieu du côté (normale vers l'intérieur).
        dx, dy = b[0] - a[0], b[1] - a[1]
        ln = math.hypot(dx, dy)
        if ln > EPS:
            for s in (1, -1):
                q = (m[0] - s * dy / ln * 0.1, m[1] + s * dx / ln * 0.1)
                if strictly_inside(poly, q, 0.05):
                    out.append(q)
                    break
    return out


def polys_overlap(pa: list[Point], pb: list[Point]) -> bool:
    """Les intérieurs des deux contours se recouvrent-ils ? (un bord commun ou
    un contact ne compte pas). Approché mais sûr pour des pièces usuelles :
    côtés qui se coupent franchement ou point témoin de l'un dans l'autre."""
    ba, bb = bbox(pa), bbox(pb)
    if ba[2] <= bb[0] + JOIN_TOL or bb[2] <= ba[0] + JOIN_TOL or \
            ba[3] <= bb[1] + JOIN_TOL or bb[3] <= ba[1] + JOIN_TOL:
        return False
    for a1, a2 in edges(pa):
        for b1, b2 in edges(pb):
            if segments_cross(a1, a2, b1, b2):
                return True
    for p in _samples(pa):
        if strictly_inside(pb, p):
            return True
    for p in _samples(pb):
        if strictly_inside(pa, p):
            return True
    return False


def segment_on_boundary(poly: list[Point], a: Point, b: Point, tol: float = JOIN_TOL) -> bool:
    """Le segment [a, b] est-il entièrement porté par le contour (un côté droit) ?"""
    cover = 0.0
    for e1, e2 in edges(poly):
        for s in edge_common(a, b, [e1, e2], tol):
            cover += dist(s[0], s[1])
    # Un polygone à 2 points [e1, e2] donne aussi le côté retour : moitié.
    return cover / 2.0 >= dist(a, b) - 0.01


def snap(v: float, step: float = CELL) -> float:
    return round(v / step) * step


# ------------------------------------------------------------------ résumé de carte

def room_of_opening(rooms: list[dict], pos: Point) -> list[str]:
    """Ids des pièces dont le trait passe par la position d'une ouverture."""
    return [r["id"] for r in rooms if on_boundary(r["_poly"], pos)]


def _num(v):
    if isinstance(v, (bool, int)) or not isinstance(v, float):
        return v
    return r2(v)


def _obj_place(o: dict) -> dict:
    """Emplacement compact d'un objet (position, rect, segment ou arc)."""
    out: dict = {}
    if isinstance(o.get("position"), list):
        out["pos"] = rp(pts([o["position"]])[0]) if pts([o["position"]]) else o["position"]
    if isinstance(o.get("rect"), list) and len(o["rect"]) == 4:
        try:
            out["rect"] = [r2(float(v)) for v in o["rect"]]
        except (TypeError, ValueError):
            out["rect"] = o["rect"]
    if isinstance(o.get("a"), list) and isinstance(o.get("b"), list):
        ab = pts([o["a"], o["b"]])
        if len(ab) == 2:
            out["a"], out["b"] = rp(ab[0]), rp(ab[1])
    if isinstance(o.get("centre"), list):
        c = pts([o["centre"]])
        if c:
            out["centre"] = rp(c[0])
        if "rayon" in o:
            out["rayon"] = _num(o.get("rayon"))
    return out


# Clés qui précisent un objet (ce qu'il est, contre quel mur).
_OBJ_DETAIL_KEYS = ("atout", "arme", "prefab", "luminaire", "variante", "mur", "angle", "rot",
                    "monte", "depart", "epaisseur", "hauteur", "courant")


def _name(v) -> str:
    if isinstance(v, dict):
        return str(v.get("fr", v.get("en", "")))
    return "" if v is None else str(v)


def summarize(doc: dict, floor: int | None = None, near_limit: int = 3, near_max: float = 20.0) -> dict:
    """Résumé compact de la carte pour raisonner : par étage, pièces (zone,
    boîte, surface, voisines par bord commun, pièces proches non collées avec
    les points les plus proches), ouvertures (pièces reliées), objets par type,
    zones, départ."""
    carte = doc.get("carte") or {}
    pieces = [p for p in doc.get("pieces") or [] if isinstance(p, dict)]
    ouvertures = [o for o in doc.get("ouvertures") or [] if isinstance(o, dict)]
    objets = [o for o in doc.get("objets") or [] if isinstance(o, dict)]
    zones = [z for z in doc.get("zones") or [] if isinstance(z, dict)]
    depart = str(doc.get("depart") or "")
    etages = carte.get("etages") or [{"sol": 0, "hauteur": 3.2}]

    rooms = []
    for p in pieces:
        poly = pts(p.get("contour"))
        rooms.append({"id": str(p.get("id", "")), "_poly": poly, "_k": int(p.get("etage", 0) or 0), "_src": p})

    floors_out = []
    n_floors = max([len(etages)] + [r["_k"] + 1 for r in rooms] +
                   [int(o.get("etage", 0) or 0) + 1 for o in ouvertures + objets])
    for k in range(n_floors):
        if floor is not None and k != floor:
            continue
        f = etages[k] if k < len(etages) and isinstance(etages[k], dict) else {}
        on = [r for r in rooms if r["_k"] == k]
        out_rooms = []
        all_pts: list[Point] = []
        for r in on:
            p = r["_src"]
            poly = r["_poly"]
            all_pts.extend(poly)
            e: dict = {"id": r["id"], "nom": _name(p.get("nom")), "zone": str(p.get("zone", "")),
                       "bbox": [r2(v) for v in bbox(poly)], "surface": r2(area(poly))}
            if not is_axis_rect(poly):
                e["contour"] = [rp(q) for q in poly]
            for key in ("plafond", "double_hauteur", "forme"):
                if key in p:
                    e[key] = p[key] if key != "forme" else p[key].get("type") if isinstance(p[key], dict) else p[key]
            voisins = []
            proches = []
            for o in on:
                if o is r:
                    continue
                segs = common_segments(poly, o["_poly"])
                if segs:
                    longueur = sum(dist(s[0], s[1]) for s in segs)
                    longest = max(segs, key=lambda s: dist(s[0], s[1]))
                    voisins.append({"id": o["id"], "bord": [rp(longest[0]), rp(longest[1])], "longueur": r2(longueur)})
                else:
                    d, pa, pb = closest_points(poly, o["_poly"])
                    if d <= near_max:
                        proches.append({"id": o["id"], "distance": r2(d), "point_ici": rp(pa), "point_la_bas": rp(pb)})
            if voisins:
                e["voisins"] = voisins
            if proches:
                proches.sort(key=lambda x: x["distance"])
                e["proches"] = proches[:near_limit]
            out_rooms.append(e)

        out_open = []
        for o in ouvertures:
            if int(o.get("etage", 0) or 0) != k:
                continue
            pp = pts([o.get("position")])
            e = {"id": str(o.get("id", "")), "type": str(o.get("type", ""))}
            if pp:
                e["pos"] = rp(pp[0])
                e["pieces"] = room_of_opening(on, pp[0])
                all_pts.append(pp[0])
            for key in ("largeur", "prix", "variante"):
                if key in o:
                    e[key] = _num(o[key])
            out_open.append(e)

        by_type: dict[str, list] = {}
        for o in objets:
            if int(o.get("etage", 0) or 0) != k:
                continue
            e = {"id": str(o.get("id", ""))}
            e.update(_obj_place(o))
            for key in _OBJ_DETAIL_KEYS:
                if key in o:
                    e[key] = _num(o[key])
            by_type.setdefault(str(o.get("type", "?")), []).append(e)

        fl = {"etage": k, "sol": _num(f.get("sol", k * 3.5)), "hauteur": _num(f.get("hauteur", 3.2)),
              "bornes": [r2(v) for v in bbox(all_pts)], "pieces": out_rooms, "ouvertures": out_open,
              "objets": by_type}
        floors_out.append(fl)

    zones_out = []
    for z in zones:
        zid = str(z.get("id", ""))
        e = {"id": zid, "nom": _name(z.get("nom")), "pieces": [r["id"] for r in rooms if str(r["_src"].get("zone", "")) == zid]}
        if isinstance(z.get("nom"), dict) and z["nom"].get("en"):
            e["nom_en"] = str(z["nom"]["en"])
        if zid == depart:
            e["depart"] = True
        zones_out.append(e)

    paid = [o for o in ouvertures if str(o.get("type", "")) in ("porte", "debris")]
    return {
        "carte": {"id": carte.get("id"), "nom": carte.get("nom"), "format": carte.get("format"),
                  "etages": len(etages), "zone_depart": depart},
        "totaux": {"pieces": len(pieces), "ouvertures": len(ouvertures), "objets": len(objets), "zones": len(zones),
                   "portes_payantes": len(paid), "cout_total_portes": sum(int(o.get("prix", 0) or 0) for o in paid)},
        "etages": floors_out,
        "zones": zones_out,
        "unites": "mètres ; x vers l'est, y vers le sud ; bbox = [x0, y0, x1, y1]",
    }


def find_elements(doc: dict, ids: list[str]) -> dict:
    """{id: {"coll": ..., "el": ...}} ; ids absents : {"absent": [...]}"""
    found: dict = {}
    for coll in ("pieces", "ouvertures", "objets", "zones"):
        for e in doc.get(coll) or []:
            if isinstance(e, dict) and str(e.get("id", "")) in ids:
                found[str(e["id"])] = {"coll": coll, "el": e}
    missing = [i for i in ids if i not in found]
    return {"elements": found, "absents": missing}


# ------------------------------------------------------------------ proposition de couloir

class PlanError(Exception):
    pass


def _next_price(doc: dict) -> int:
    n = sum(1 for o in doc.get("ouvertures") or [] if isinstance(o, dict) and o.get("type") in ("porte", "debris"))
    return DOOR_PRICES[min(n, len(DOOR_PRICES) - 1)]


def _band(lo: float, hi: float, w: float, prefer: float, margin: float) -> tuple[float, float] | None:
    """Bande [a, a + w] calée sur la grille de 0,5 m dans [lo + margin, hi -
    margin], la plus proche possible de `prefer` (centre souhaité)."""
    lo2, hi2 = lo + margin, hi - margin
    if hi2 - lo2 < w - EPS:
        return None
    a = snap(prefer - w / 2)
    a = max(math.ceil((lo2 - EPS) / CELL) * CELL, min(a, math.floor((hi2 - w + EPS) / CELL) * CELL))
    if a < lo2 - EPS or a + w > hi2 + EPS:
        return None
    return (a, a + w)


def _rect_poly(x0, y0, x1, y1) -> list[Point]:
    return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]


def plan_corridor(doc: dict, room_a: str, room_b: str, width: float = 2.5, price: int | None = None) -> dict:
    """Propose (sans rien appliquer) les ops d'un couloir entre deux pièces du
    même étage : couloir droit si leurs côtés se font face, en L sinon ; ou
    simplement une porte si elles ont déjà un mur commun. Le couloir est mis
    dans la zone de room_a (passage libre côté A), porte payante côté B si B
    est d'une autre zone. Lève PlanError si aucun tracé simple n'est sûr."""
    rooms = {str(p.get("id")): p for p in doc.get("pieces") or [] if isinstance(p, dict)}
    if room_a not in rooms or room_b not in rooms:
        raise PlanError("pièce inconnue : %s" % ", ".join(i for i in (room_a, room_b) if i not in rooms))
    if room_a == room_b:
        raise PlanError("room_a et room_b sont la même pièce")
    A, B = rooms[room_a], rooms[room_b]
    k = int(A.get("etage", 0) or 0)
    if int(B.get("etage", 0) or 0) != k:
        raise PlanError("les deux pièces ne sont pas au même étage (relier deux étages : un escalier, pas un couloir)")
    w = snap(float(width))
    if w < 1.0 or w > 6.0:
        raise PlanError("largeur %.2f m hors de 1 à 6 m (couloir : 2 à 3 m, docs/MAP_DESIGN_RULES.md § 3.2)" % width)
    pa, pb = pts(A.get("contour")), pts(B.get("contour"))
    if len(pa) < 3 or len(pb) < 3:
        raise PlanError("contour illisible")
    zone_a, zone_b = str(A.get("zone", "")), str(B.get("zone", ""))
    same_zone = zone_a != "" and zone_a == zone_b
    door_price = int(price) if price is not None else _next_price(doc)
    warnings: list[str] = []
    others = [pts(p.get("contour")) for i, p in rooms.items()
              if i not in (room_a, room_b) and int(p.get("etage", 0) or 0) == k]

    def door_op(pos: Point, max_w: float) -> dict:
        if same_zone:
            return {"op": "add", "coll": "ouvertures",
                    "el": {"type": "passage", "etage": k, "position": rp(pos), "largeur": r2(max_w)}}
        return {"op": "add", "coll": "ouvertures",
                "el": {"type": "porte", "etage": k, "position": rp(pos), "largeur": r2(min(2.0, max_w)), "prix": door_price}}

    items = _wall_items(doc, k)

    # Déjà collées : une porte (ou un passage) sur le plus long mur commun, au
    # plus près du milieu sans toucher une ouverture ou un objet mural.
    segs = common_segments(pa, pb)
    if segs:
        for o in doc.get("ouvertures") or []:
            q = pts([o.get("position")]) if isinstance(o, dict) and int(o.get("etage", 0) or 0) == k else []
            if q and o.get("type") != "fenetre" and on_boundary(pa, q[0]) and on_boundary(pb, q[0]):
                raise PlanError("les pièces sont déjà reliées par %s (%s)" % (o.get("id"), o.get("type")))
        s = max(segs, key=lambda s: dist(s[0], s[1]))
        ln = dist(s[0], s[1])
        if ln < 1.5:
            raise PlanError("mur commun trop court (%.2f m) pour une porte" % ln)
        ow = min(w, snap(ln - 0.5)) if ln - 0.5 >= 1.0 else 1.0
        ow_door = ow if same_zone else min(2.0, ow)
        ux, uy = (s[1][0] - s[0][0]) / ln, (s[1][1] - s[0][1]) / ln
        spot = None
        steps = int(ln / 0.25) + 1
        for i in range(steps):
            off = (i + 1) // 2 * 0.25 * (1 if i % 2 else -1)
            t = ln / 2 + off
            if t < ow_door / 2 + 0.25 - EPS or t > ln - ow_door / 2 - 0.25 + EPS:
                continue
            p = (s[0][0] + ux * t, s[0][1] + uy * t)
            if not _blocked(p, ow_door / 2, items):
                spot = p
                break
        if spot is None:
            raise PlanError("pas de place libre sur le mur commun (ouvertures ou objets muraux déjà là)")
        op = door_op(spot, ow)
        return {"type": "porte_directe", "label": "Claude : porte %s → %s" % (room_a, room_b), "ops": [op],
                "notes": ["Les pièces ont déjà un mur commun : pas de couloir, une ouverture sur le mur commun."],
                "avertissements": warnings}

    ax0, ay0, ax1, ay1 = bbox(pa)
    bx0, by0, bx1, by1 = bbox(pb)
    margin = 0.5
    candidates = []  # (nom, contour, point_porte_A, point_porte_B, longueurs)

    # Couloir droit horizontal (A et B l'un à côté de l'autre, bandes en y communes).
    for left, right, lname in (((ax1, pa), (bx0, pb), "AB"), ((bx1, pb), (ax0, pa), "BA")):
        x_from, x_to = left[0], right[0]
        if x_to - x_from <= EPS:
            continue
        lo, hi = max(ay0, by0), min(ay1, by1)
        band = _band(lo, hi, w, (lo + hi) / 2, margin)
        if band:
            y0, y1 = band
            poly = _rect_poly(x_from, y0, x_to, y1)
            ym = (y0 + y1) / 2
            pA, pB = ((x_from, ym), (x_to, ym)) if lname == "AB" else ((x_to, ym), (x_from, ym))
            candidates.append(("droit", poly, pA, pB, [x_to - x_from]))
    # Couloir droit vertical.
    for top, bottom, lname in (((ay1, pa), (by0, pb), "AB"), ((by1, pb), (ay0, pa), "BA")):
        y_from, y_to = top[0], bottom[0]
        if y_to - y_from <= EPS:
            continue
        lo, hi = max(ax0, bx0), min(ax1, bx1)
        band = _band(lo, hi, w, (lo + hi) / 2, margin)
        if band:
            x0, x1 = band
            poly = _rect_poly(x0, y_from, x1, y_to)
            xm = (x0 + x1) / 2
            pA, pB = ((xm, y_from), (xm, y_to)) if lname == "AB" else ((xm, y_to), (xm, y_from))
            candidates.append(("droit", poly, pA, pB, [y_to - y_from]))

    # Couloir en L : sort d'un côté de A, tourne, entre par un côté de B.
    if not candidates:
        candidates.extend(_l_candidates(pa, pb, w, margin))
        candidates.extend((n, poly, qa, qb, ls) for n, poly, qb, qa, ls in _l_candidates(pb, pa, w, margin))

    refused = []
    for name, poly, pA, pB, lengths in candidates:
        if not segment_on_boundary(pa, *_end_segment(poly, pA)) or not segment_on_boundary(pb, *_end_segment(poly, pB)):
            refused.append("%s : un bout du couloir ne tombe pas sur un mur droit de la pièce" % name)
            continue
        busy = _blocked(pA, w / 2, items) + _blocked(pB, (w if same_zone else min(2.0, w)) / 2, items)
        if busy:
            refused.append("%s : une porte tomberait sur %s" % (name, ", ".join(busy)))
            continue
        hit = [i for i, o in enumerate(others) if polys_overlap(poly, o)]
        if hit or polys_overlap(poly, pa) or polys_overlap(poly, pb):
            refused.append("%s : chevaucherait une autre pièce" % name)
            continue
        ops = [{"op": "add", "coll": "pieces",
                "el": {"nom": "Couloir", "etage": k, "zone": zone_a, "contour": [rp(q) for q in poly]}},
               {"op": "add", "coll": "ouvertures",
                "el": {"type": "passage", "etage": k, "position": rp(pA), "largeur": r2(w)}},
               door_op(pB, w)]
        for ln in lengths:
            if ln > 12.0 + EPS:
                warnings.append("tronçon droit de %.1f m : plus de 12 m (§ 3.2), ajoute un coude, une ouverture latérale ou un élargissement" % ln)
        if w > 3.0:
            warnings.append("plus de 3 m de large : ce n'est plus un couloir mais une salle à encombrer (§ 3.2)")
        if w < 2.0:
            warnings.append("moins de 2 m : seulement pour un trajet secondaire (§ 3.2)")
        notes = ["Couloir dans la zone de %s (%s) : passage libre côté %s." % (room_a, zone_a, room_a),
                 ("Passage libre côté %s (même zone)." % room_b) if same_zone else
                 ("Porte payante (%d) côté %s : changer « prix » selon la courbe d'ouverture (§ 9.2)." % (door_price, room_b)),
                 "Rien n'est appliqué : relire les ops puis les passer à editor_apply (un seul appel = un seul Ctrl+Z).",
                 "Après application : editor_validate, puis décorer le couloir (§ 10.2) et vérifier les fenêtres de la zone."]
        return {"type": name, "label": "Claude : couloir %s → %s" % (room_a, room_b), "ops": ops,
                "contour": [rp(q) for q in poly], "longueurs": [r2(x) for x in lengths],
                "notes": notes, "avertissements": warnings}
    detail = ("; ".join(refused)) if refused else "les pièces ne se font face sur aucun côté droit assez large (%.1f m + marges)" % w
    raise PlanError("aucun couloir simple (droit ou en L) n'est sûr : " + detail +
                    ". Dessine-le à la main avec editor_apply (pièce + ouvertures).")


def _wall_items(doc: dict, k: int) -> list[tuple[str, Point, float]]:
    """Ouvertures et objets muraux de l'étage k : (id, position, demi-largeur)."""
    out = []
    for o in doc.get("ouvertures") or []:
        if not isinstance(o, dict) or int(o.get("etage", 0) or 0) != k:
            continue
        q = pts([o.get("position")])
        if q:
            try:
                half = float(o.get("largeur", 1.0)) / 2
            except (TypeError, ValueError):
                half = 0.5
            out.append((str(o.get("id", "")), q[0], half))
    for o in doc.get("objets") or []:
        if not isinstance(o, dict) or int(o.get("etage", 0) or 0) != k or "mur" not in o:
            continue
        q = pts([o.get("position")])
        if q:
            out.append((str(o.get("id", "")), q[0], 0.75))
    return out


def _blocked(p: Point, half: float, items) -> list[str]:
    """Ids des ouvertures / objets muraux trop près d'une ouverture de
    demi-largeur `half` centrée en p (0,25 m de jeu)."""
    return [i for i, q, h in items if dist(p, q) < half + h + 0.25 - EPS]


def _end_segment(poly: list[Point], p: Point) -> tuple[Point, Point]:
    """Côté du contour du couloir qui contient le point de porte p (son bout)."""
    best = None
    for a, b in edges(poly):
        d = dist_to_segment(p, a, b)
        if best is None or d < best[0]:
            best = (d, a, b)
    return best[1], best[2]


def _l_candidates(pa: list[Point], pb: list[Point], w: float, margin: float) -> list:
    """Couloirs en L partant d'un côté vertical de A (est ou ouest) puis
    entrant par un côté horizontal de B (nord ou sud)."""
    out = []
    ax0, ay0, ax1, ay1 = bbox(pa)
    bx0, by0, bx1, by1 = bbox(pb)
    for east in (True, False):
        # Sortie de A par l'est (B à l'est) ou par l'ouest (B à l'ouest).
        if east and bx0 - ax1 < w - EPS:
            continue
        if not east and ax0 - bx1 < w - EPS:
            continue
        for south in (True, False):
            # Entrée dans B par le nord (B au sud de A) ou par le sud (B au nord).
            if south and not by0 > ay0 + w + margin:
                continue
            if not south and not by1 < ay1 - w - margin:
                continue
            # Bande horizontale (dans le flanc de A), la plus proche de B.
            prefer_y = ay1 if south else ay0
            hb = _band(ay0, ay1, w, prefer_y, margin)
            # Bande verticale (dans le flanc de B), la plus proche de A.
            prefer_x = bx0 if east else bx1
            vb = _band(bx0, bx1, w, prefer_x, margin)
            if not hb or not vb:
                continue
            y0, y1 = hb
            x0, x1 = vb
            if south and not by0 > y1 + EPS:
                continue
            if not south and not by1 < y0 - EPS:
                continue
            if east:
                xa = ax1
                if south:
                    poly = [(xa, y0), (x1, y0), (x1, by0), (x0, by0), (x0, y1), (xa, y1)]
                else:
                    poly = [(xa, y0), (x0, y0), (x0, by1), (x1, by1), (x1, y1), (xa, y1)]
                h_len = x1 - xa
            else:
                xa = ax0
                if south:
                    poly = [(xa, y0), (xa, y1), (x1, y1), (x1, by0), (x0, by0), (x0, y0)]
                else:
                    poly = [(xa, y0), (xa, y1), (x0, y1), (x0, by1), (x1, by1), (x1, y0)]
                h_len = xa - x0
            v_len = (by0 - y0) if south else (y1 - by1)
            pA = (xa, (y0 + y1) / 2)
            pB = ((x0 + x1) / 2, by0 if south else by1)
            out.append(("en_L", poly, pA, pB, [h_len, v_len]))
    return out
