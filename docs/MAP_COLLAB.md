# Éditeur de cartes collaboratif — spécification (v1)

But : plusieurs personnes éditent la MÊME carte en même temps (multijoueur),
et Claude (via un serveur MCP) peut lire la carte et y créer / modifier des
éléments. Tout le monde voit les changements en direct, chacun peut annuler
ce qu'il a fait (et ce que « son » Claude a fait), et retoucher à la main ce
que les autres ont créé.

## 1. Architecture

```
 Éditeur A (HÔTE, autorité)  <── TCP 7790 (LAN/Internet) ──>  Éditeur B (invité)
   │  écoute 127.0.0.1:7791                                     │ écoute 127.0.0.1:7791 (ou suivant libre)
   │                                                            │
 pont MCP (tools/mcp/map_editor_mcp.py) <── stdio ──> Claude Code
```

- **Hôte** : l'éditeur qui a ouvert la carte et choisi Collaboration > Héberger.
  Il détient le document de référence, fixe l'ordre des changements, enregistre
  le fichier. Une carte éditée seul = un hôte sans invité : même code.
- **Invité** : Collaboration > Rejoindre (adresse, port, code de session, pseudo).
  Reçoit la carte complète, puis le flux des changements.
- **Agent (Claude)** : se connecte TOUJOURS à l'éditeur local (127.0.0.1, port
  agent), jamais directement à l'hôte distant. L'éditeur local relaie ses
  changements comme ceux d'un auteur « Claude » rattaché à lui (« parrain »).
  Option Collaboration > « Autoriser Claude (MCP) », activée par défaut sur
  127.0.0.1 uniquement (jamais d'écoute agent sur une autre interface).

Fichiers Godot (nouveaux, pour ne pas entrer en conflit avec un travail en
cours dans `editor_map.gd`) :
- `scripts/editor/collab/map_ops.gd` (`class_name MapOps`) : diff entre deux
  instantanés, application d'opérations, inversion, validation. Logique pure.
- `scripts/editor/collab/map_history.gd` (`class_name MapHistory`) : historique
  à base de diffs, par auteur.
- `scripts/editor/collab/map_collab.gd` (`class_name MapCollab`, Node) : session
  (hôte/invité), transport TCP, poignée de main, présence. Indépendant de
  l'interface : fonctionne sur un `EditorMap` + signaux, testable sans fenêtre
  (deux MapCollab dans le même processus).
- `scripts/editor/collab/map_agent_link.gd` (`class_name MapAgentLink`, Node) :
  écoute agent locale, commandes requête/réponse (§ 5).
- `scripts/editor/collab/collab_panel.gd` : interface (menu, participants…).

## 2. Modèle de données et opérations

Le document = `EditorMap.snapshot()` :
`{carte: {}, pieces: [], ouvertures: [], objets: [], zones: [], depart: ""}`.
Les éléments de `pieces`, `ouvertures`, `objets`, `zones` ont un `id` unique
(texte). L'ordre des listes est conservé (un élément nouveau est ajouté en fin).

Opérations (dictionnaires JSON) :

| op | champs | effet |
|---|---|---|
| `put` | `coll`, `el` (avec `id`) | insère (en fin) ou remplace l'élément de même id |
| `del` | `coll`, `id` | retire l'élément (absent : sans effet) |
| `carte` | `carte` | remplace le dictionnaire `carte` (étages, noms…) |
| `depart` | `id` | zone de départ |
| `add` | `coll`, `el` (sans id ou id provisoire `"$1"`, `"$2"`…) | **agent seulement** : l'éditeur attribue un vrai id (`doc.new_id` avec le même préfixe que `MapEditor.add_object`) ; un `"$n"` cité ailleurs dans le même lot (ex. `zone` d'une pièce) est remplacé par l'id attribué. Converti en `put` avant diffusion. |

`coll` ∈ {`pieces`, `ouvertures`, `objets`, `zones`}.

- `MapOps.diff(avant, après) -> Array` : ops minimales (put des éléments
  nouveaux ou changés, del des disparus, carte/depart si changés).
- `MapOps.apply(doc_snapshot_ou_EditorMap, ops)`.
- `MapOps.validate(ops) -> String` ("" si valide) : coll connue, `el` est un
  dictionnaire avec `id` texte non vide ≤ 64 caractères, profondeur ≤ 8,
  nombres finis, taille JSON totale d'un message ≤ 2 Mo, ≤ 5000 ops par lot.
  Aucun objet Godot décodé (JSON uniquement).

## 3. Changements, ordre, convergence

Un **changement** = `{cid, author, label, ops}` :
- `cid` : identifiant unique choisi par l'émetteur (`"<peer>-<compteur>"`).
- `author` : id de participant (hôte = 1 ; agent = `"<parrain>:claude"`).
- `label` : texte court affiché (« Pièce posée », « Claude : couloir A→B »).

Hook dans l'éditeur : `push_undo()` mémorise l'instantané « avant » ;
`changed()` calcule `MapOps.diff(avant, maintenant)`, l'inscrit dans
l'historique local et l'envoie à la session. (Les glissements continus
n'envoient rien avant le relâchement, voir présence § 6 pour l'aperçu.)

Ordre : l'hôte applique les changements dans leur ordre d'arrivée, leur donne
un numéro `seq` croissant et les rediffuse à TOUS (émetteur compris).
Invité : applique ses changements tout de suite (optimiste) et les garde en
attente ; à chaque changement reçu d'un autre, il retire ses changements en
attente (inverse), applique le reçu, puis réapplique ses changements en
attente ; à l'écho de son propre `cid`, il le retire de l'attente. Résultat :
même ordre que l'hôte, donc mêmes cartes partout (dernier écrit gagne par
élément).
Contrôle : toutes les 5 s l'hôte envoie `{t:"sum", seq, hash}` (hash du JSON
canonique de la carte) ; un invité sans attente et de même seq qui diffère
demande `{t:"resync"}` et reçoit la carte entière.

## 4. Annuler / rétablir (par auteur)

`MapHistory` remplace la pile de copies complètes de `MapEditor` (même
comportement en solo, tests existants à garder verts).
- Entrée = `{cid, author, label, ops, inverse, time}` ; `inverse` = ops qui
  remettent l'état « avant » des seuls éléments touchés.
- Ctrl+Z d'une personne annule SA dernière entrée encore active OU celle de
  son Claude (la plus récente des deux) ; Ctrl+Y rétablit. L'annulation est
  un nouveau changement normal (diffusé), libellé « Annuler : <label> ».
- Conflit : si un élément a été modifié par quelqu'un d'autre depuis, cet
  élément n'est pas touché ; message « N élément(s) modifié(s) entre-temps
  par X : non annulé(s) ».
- Panneau Historique : liste des entrées (auteur coloré, libellé, heure),
  bouton « Annuler cette action » sur les miennes et celles de mon Claude.

## 5. Protocole

Transport : TCP, une ligne JSON UTF-8 par message (`\n`), messages ≤ 2 Mo
(au-delà : déconnexion). Champ `t` = type.

### 5.1 Entre éditeurs (port 7790 par défaut)

Invité → hôte :
- `{t:"hello", proto:1, name, code, app_version}` (code de session : 6
  caractères affichés chez l'hôte ; refus après 5 essais faux par IP).
- `{t:"change", cid, label, ops, author?}` (`author` seulement pour son agent :
  `"<moi>:claude"`).
- `{t:"presence", cursor:[x,y], floor, selection, tool, live?}`.
- `{t:"resync"}`, `{t:"ping"}`.

Hôte → invité :
- `{t:"welcome", you, peers:[{id,name,color,kind}], map, seq, history}` ou
  `{t:"reject", reason_fr, reason_en}`.
- `{t:"change", seq, cid, author, label, ops}`.
- `{t:"presence", peer, ...}`, `{t:"peers", peers}`, `{t:"sum", seq, hash}`,
  `{t:"map", map, seq}` (resync), `{t:"saved", by, time}`, `{t:"bye", reason_fr, reason_en}`.

Limites : 8 participants humains, ≤ 30 changements/s et ≤ 20 présences/s par
pair (au-delà ignorés), délai de poignée de main 5 s.

### 5.2 Agent ↔ éditeur local (127.0.0.1, port 7791 ; si pris : 7792…7799)

Le port réel et un jeton aléatoire sont écrits dans
`user://editor_collab/agent.json` = `{port, token, pid, map_id}`
(`%APPDATA%\Godot\app_userdata\Call of Claude Zombie\editor_collab\agent.json`).
Le fichier est supprimé à la fermeture de l'éditeur.

Requête : `{id, cmd, args}` ; réponse : `{id, ok:true, result}` ou
`{id, ok:false, error}`. Première requête obligatoire :
`{id, cmd:"hello", args:{token, client:"claude-mcp"}}`.
L'éditeur peut aussi pousser `{event:"change"|"selection"|"peers", ...}`.

| cmd | args | result |
|---|---|---|
| `hello` | `token` | `{map_id, map_name, role:"host"/"guest"/"solo", peers, editor_version}` |
| `status` | — | idem + `floor`, `selection`, `dirty` |
| `get_map` | — | snapshot complet |
| `get_selection` | — | `{ids, elements, floor, cursor}` (curseur souris en mètres) |
| `apply` | `label`, `ops`, `animate` (défaut true) | `{cid, ids:{"$1":"p7",...}, invalid:{id:raison}}` |
| `undo` | — | annule le dernier changement de Claude encore actif |
| `validate` | — | rapport `MapValidator` (texte + liste des problèmes) |
| `screenshot` | `floor?`, `ids?` (cadrer sur ces éléments) | `{png_base64, width, height, bounds:[x0,y0,x1,y1]}` |
| `highlight` | `ids`, `message` | montre ces éléments à l'utilisateur (contour pulsé + bulle) |
| `catalog` | — | types admis (`MapCatalog`), prefabs, luminaires, armes, atouts |

## 6. Ce que voient les utilisateurs

- Barre du haut : bouton « Collaboration » (Héberger…, Rejoindre…, Quitter la
  session, Autoriser Claude (MCP) ✓, Historique) et pastilles colorées des
  participants (Claude compris, avec une icône distincte).
- Curseurs des autres sur le plan (couleur + pseudo), leur sélection en
  contour de leur couleur, leur étage indiqué ; aperçu en direct d'un objet
  qu'ils glissent (`presence.live`, 10/s).
- Changement reçu : les éléments touchés clignotent brièvement dans la couleur
  de l'auteur ; ligne d'état « Bob : Pièce posée ».
- Lot de Claude (`animate`) : éléments apparaissent un par un (≤ 1,5 s au
  total), contour pulsé violet, bulle « Claude : couloir A→B » ; UNE entrée
  d'historique, donc un seul Ctrl+Z.
- Tout texte en français ET en anglais (`Lang.t(fr, en)`).

## 7. Enregistrement

Seul l'hôte enregistre le dossier de la carte (Ctrl+S) ; il prévient les
invités (`saved`). Un invité a « Enregistrer une copie… ». Sauvegarde
automatique : hôte seulement, comme aujourd'hui.

## 8. Sécurité

- Écoute agent : 127.0.0.1 seulement + jeton. Écoute invités : seulement
  quand l'hôte l'a demandé, code de session obligatoire.
- Tout message est validé (§ 2) ; un message invalide = déconnexion du pair.
- Jamais d'objet Godot décodé, jamais de chemin de fichier venu du réseau.

## 9. Précisions de l'implémentation (v1)

Ce qui suit complète les sections précédentes sans en changer les noms
(commandes, champs, ports, `agent.json`). Code : `scripts/editor/collab/`.
Tests : `tests/test_map_ops.gd`, `test_map_history.gd`, `test_map_collab.gd`,
`test_map_agent_link.gd`.

### Identifiants de participants

Toujours du **texte** : hôte `"1"`, invités `"2"`, `"3"`… (dans l'ordre
d'arrivée), agent `"<parrain>:claude"` (`"1:claude"`, `"2:claude"`). `you`,
`author`, `peer`, `peers[].id` et `skipped_by` suivent ce format. Un éditeur
seul est l'id `"1"` (rôle `solo`) ; s'il héberge, ses entrées d'historique
restent les siennes.

### Opérations (§ 2)

- `put` accepte un champ facultatif `at` (entier ≥ 0) : indice où insérer
  l'élément s'il est absent (ignoré s'il existe : remplacé sur place).
  `MapOps.diff` le met sur les éléments nouveaux et `MapOps.inverse` sur les
  éléments supprimés, pour qu'une suppression annulée retrouve sa place (et
  que les cartes restent identiques élément par élément, ordre compris).
  L'agent peut l'omettre (ajout en fin).
- `add` sans `id` : l'id attribué est rendu sous la clé `"#<indice de l'op>"`
  dans `ids` (avec `id` provisoire : sous `"$n"`).
- `add` remplit aussi, comme `MapEditor.add_object` : pièce sans `nom` →
  « Pièce N » ; pièce sans zone existante → zone créée (même nom, devient la
  zone de départ s'il n'y en a pas) ; porte / débris sans `prix` → 750, 1000
  puis 1250 ; fenêtre sans `largeur` ; une seule boîte `depart`. `etage`
  absent → 0.
- Contrôle du contenu (en plus de `validate`) : chaque élément `put` passe
  les règles des cartes reçues (`CustomMapGuard` : types, clés, valeurs,
  étages existants, identifiants `[A-Za-z0-9_-]` de 32 caractères au plus) et
  les tailles maximales des listes (256 pièces, 512 ouvertures, 2048 objets,
  64 zones). Un élément refusé n'est pas appliqué (agent : listé dans
  `invalid` ; invité : retiré du lot et signalé dans le journal, sans
  déconnexion).
- Empreinte (`sum.hash`) : SHA-256 du JSON canonique (clés triées, nombres
  entiers sans décimale, précision complète). Tous les messages sont écrits
  en précision complète (`JSON.stringify(..., full_precision = true)`).

### Changements et annulations (§ 3, § 4)

- `change` peut porter `undo: <cid>` ou `redo: <cid>` (cid de l'entrée
  annulée ou rétablie). Pour un invité, l'hôte **recalcule** les opérations
  avec son historique (les `ops` envoyées ne servent que d'aperçu optimiste)
  et refuse silencieusement (ops vides) l'annulation d'une entrée qui n'est
  pas à l'expéditeur ou à son Claude. La diffusion ajoute `skipped` (nombre
  d'éléments laissés pour conflit) et `skipped_by` (auteurs).
- Un invité qui appuie sur Ctrl+Z pendant qu'un de ses changements attend
  l'écho : l'annulation part juste après l'écho.
- Au-delà de 30 changements/s (rafale de 60), l'hôte ignore le changement et
  renvoie la carte entière à l'invité (`map`) au plus une fois par seconde ;
  au-delà de 20 présences/s, la présence est ignorée.
- `welcome.history` = `{entries: [{cid, author, label, time, active}], touch,
  authors}` : les 100 dernières entrées pour l'affichage et l'état des
  éléments (dernier changement de chaque élément) ; un invité n'annule que
  ses propres entrées, faites après son arrivée.
- `map` peut porter `reset: true` (l'hôte a ouvert une autre carte :
  historique vidé). Un invité qui ouvre une autre carte quitte la session.
- `presence` peut porter `agent: true/false` (invité → hôte) : un Claude est
  rattaché à cet invité (pastille `"<id>:claude"` dans `peers`).
- Libellés (`label`) : texte court dans la langue de l'émetteur (120
  caractères au plus).

### Agent (§ 5.2)

- `agent.json` : en autotest, dans `tests/_out/editor_collab_<scénario>/` ;
  les tests unitaires utilisent `MapAgentLink.dir_override`. Supprimé à
  l'arrêt seulement s'il porte encore le `pid` et le `port` de cet éditeur
  (un deuxième éditeur ouvert l'a remplacé : le dernier ouvert gagne).
- L'écoute ne démarre jamais en mode `--headless` ni en autotest ; 4 clients
  au plus ; un client sans `hello` valide en 5 s est coupé ; un mauvais
  jeton ou une autre commande avant `hello` = réponse d'erreur puis coupure.
- `error` : texte dans la langue du jeu.
- `hello` rend aussi `you` (`"<moi>:claude"`) ; `status` rend aussi `seq` et
  `can_undo`.
- `apply` : `{cid, ids, invalid}` ; `cid` vide si aucun élément n'a été
  admis. `invalid` liste les éléments refusés (non appliqués) ET ceux posés
  mais mal placés (règles de pose de l'éditeur, dessinés en rouge).
- `undo` : `{cid, undone, label, skipped, conflict}` (ou `{queued: true}`
  chez un invité en attente d'écho).
- `validate` : `{ok, errors, warnings, text, problems: [{level, text, floor,
  points: [[x, y]…]}]}` (points en mètres, 12 au plus par problème).
- `screenshot` : plan dessiné hors écran (1280 × 960, règles en mètres
  comprises dans `bounds`) ; rend aussi `floor` ; erreur en mode sans
  affichage.
- `highlight` : `{shown}` ; version simple (élément cadré, message dans la
  barre d'état). Le rendu riche se branche sur les signaux
  `MapAgentLink.highlight_requested(ids, message)` et
  `animate_requested(ids, label)` (après un `apply` avec `animate`).
- Événements poussés : `{event: "change", cid, author, label, seq, ids}`,
  `{event: "selection", ids}`, `{event: "peers", peers}`.

### Éditeur

- `push_undo()` / `push_undo_snapshot()` mémorisent la carte d'avant (la plus
  ancienne si plusieurs) ; `changed()` calcule le diff et l'envoie à la
  session (`MapCollab.submit_local`) seulement s'il n'est pas vide.
- Un changement reçu pendant un glissement est aussi appliqué à la copie du
  glissement (`MapCanvas.drag.snap`), pour ne pas l'effacer au relâchement.
- Invité : Fichier > « Enregistrer une copie… » (nouveau dossier dans les
  cartes du joueur) ; pas de sauvegarde automatique ; TESTER refusé (copie,
  puis quitter la session). Hôte : TESTER change de scène et ferme la
  session (les invités repassent seuls avec la carte).
