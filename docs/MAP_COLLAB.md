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
- `scripts/editor/collab/collab_view.gd` (`class_name CollabView`) : rendu
  sur le plan (curseurs, sélections, aperçus, clignotements, lots et
  highlight de Claude) ; `collab_history.gd` (`CollabHistory`) : onglet
  Historique.

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
- `{t:"hello", proto:2, name, code, app_version}` (code de session : 6
  caractères affichés chez l'hôte ; refus après 5 essais faux par IP ;
  `proto` 2 depuis le TESTER à plusieurs, § 5.3 : un éditeur plus ancien est
  refusé à l'arrivée).
- `{t:"change", cid, label, ops, author?}` (`author` seulement pour son agent :
  `"<moi>:claude"`).
- `{t:"presence", cursor:[x,y], floor, selection, tool, live?, vue?, z?}`
  (`vue` : plan de la vue survolée quand c'est une élévation, `z` : hauteur
  du curseur en m ; docs/EDITOR_VIEWS.md § 6.4 ; ignorées par une version
  plus ancienne).
- `{t:"resync"}`, `{t:"ping"}`.

Hôte → invité :
- `{t:"welcome", you, peers:[{id,name,color,kind}], map, seq, history}` ou
  `{t:"reject", reason_fr, reason_en}`.
- `{t:"change", seq, cid, author, label, ops}`.
- `{t:"presence", peer, ...}`, `{t:"peers", peers}`, `{t:"sum", seq, hash}`,
  `{t:"map", map, seq}` (resync), `{t:"saved", by, time}`, `{t:"bye", reason_fr, reason_en}`.

Limites : 8 participants humains, ≤ 30 changements/s et ≤ 20 présences/s par
pair (au-delà ignorés), délai de poignée de main 5 s.

### 5.3 TESTER à plusieurs (`CollabPlaytest`)

L'hôte de la session appuie sur TESTER : tous les participants jouent la carte
ensemble, puis reviennent dans l'éditeur, **dans la même session** (la
connexion entre éditeurs n'est jamais coupée).

1. Hôte : vérifie la carte et l'écrit dans une copie de travail, sans
   l'enregistrer (comme en solo, `user://maps/_tester/`), ouvre une partie
   réseau du jeu (`Net.host`) sur le **même numéro de port, en UDP** que la
   session (7790 par défaut ; s'il est pris, les 9 suivants), annonce la
   carte (`Net.set_lobby_map` : paquet `MapShare` envoyé et vérifié chez
   chacun, comme une carte perso du salon) puis envoie
   `{t:"playtest", port}` à tous.
2. Invité : rejoint la partie sur l'adresse IP de la connexion à l'hôte et ce
   port (`Net.join`). En cas d'échec (partie injoignable, déjà en partie,
   adresse non IPv4, carte refusée) : `{t:"playtest_status", ok:false,
   reason_fr, reason_en}` à l'hôte, et il reste dans l'éditeur avec le motif.
   Un port hors 1024-65535 est un message invalide (session quittée).
3. Hôte : lance la partie (`Net.start_match`) dès que tous les invités encore
   là l'ont rejointe avec la carte ; après 30 s sans progrès d'un
   téléchargement de la carte (une grosse carte qui arrive encore prolonge
   l'attente, chez l'hôte comme chez les invités : `_download_mark`), les
   retardataires sont coupés de la partie (pas de la session) et la partie
   démarre sans eux ; s'il ne reste personne, il joue seul. Abandon avant le lancement (carte refusée,
   session fermée, éditeur quitté) : `{t:"playtest_cancel"}`.
4. Pendant la partie : au passage en chargement, le nœud `MapCollab` quitte
   la scène de l'éditeur pour le nœud `CollabPlaytest` (sous la racine) avec
   `keep_alive` (pas de `leave()` en sortant de l'arbre) ; la session continue
   de tourner (changements, présences, empreintes).
5. Retour (fin de partie, ou départ d'un joueur : `Router.return_scene`) :
   l'éditeur reprend ce même nœud (`CollabPlaytest.take`) avec la carte,
   l'historique, le dossier, la sélection et la vue d'avant le test. Si l'hôte
   quitte en pleine partie, les invités reviennent aussi dans l'éditeur
   (« Test terminé : l'hôte a quitté la partie »).

Par Internet, l'hôte redirige donc le port de la session en TCP **et** en UDP.
Test : `sh tools/mp_test.sh editorplay` (deux jeux, deux éditeurs, deux tests
de suite) ; `tests/test_map_collab.gd` (messages, `keep_alive`, reprise).

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
| `get_elements` | `ids` | `{elements: {id: {coll, el, z_min, z_max, z_monde, hauteur_pose?, glissement_vertical}}, absents}` (hauteurs en m) |
| `apply` | `label`, `ops`, `animate` (défaut true), `decouper` (défaut false) | `{cid, ids:{"$1":"p7",...}, invalid:{id:raison}, decoupe?}` |
| `undo` | — | annule le dernier changement de Claude encore actif |
| `validate` | — | rapport `MapValidator` (texte + liste des problèmes) |
| `screenshot` | `floor?`, `ids?` (cadrer sur ces éléments), `view?` (`dessus` par défaut, `avant`, `arriere`, `gauche`, `droite`, `dessous`), `coupe?` [p0, p1] | `{png_base64, width, height, bounds:[x0,y0,x1,y1]}` ; élévation : `{…, view, axe_horizontal, bounds_h, bounds_z, coupe?}` |
| `highlight` | `ids`, `message` | montre ces éléments à l'utilisateur (contour pulsé + bulle) |
| `catalog` | — | types admis (`MapCatalog`), prefabs, luminaires, armes, atouts ; `prefabs_carte` : prefabs de la carte ouverte (pid, ref, nom, sorte, emprise, hauteur, bloque, pose) |
| `prefab_list` | — | `{prefabs: [fiche], nombre, modeles, peut_modifier, note}` ; fiche : `pid`, `ref` (« map:<pid> »), `objet` à poser, `nom`, `sorte` (groupe / modele), `emprise_cases`, `emprise_m`, `hauteur`, `bloque`, `collision`, `pose`, `objets_poses` ; groupe : `parties` ; modèle : `echelle`, `taille_modele_m` [x, y, hauteur], `aabb_brute`, `sha256`, `octets`, `triangles`, `sommets`, `maillages`, `materiaux`, `images` |
| `prefab_sources` | — | `{cartes: [{carte, nom, dossier, ouverte, prefabs: [{pid, nom, sorte, emprise_cases, hauteur, octets?}]}], cartes_sans_prefab, dossier_des_cartes}` |
| `prefab_create` | `nom`, `ids` + `remplacer` (défaut true) OU `parties` [{decor, pos [x, y], rot}], `label` | fiche + `contenu`, `exclus` [{sorte, nombre, raison}], `absents`, `parties_reprises`, `remplace`, `objet_pose`, `cid` |
| `prefab_import_model` | `chemin` (fichier local) OU `data_base64` (+ `format` glb / gltf), `nom`, `echelle` (0,01 à 100), `bloque` (solide / barriere / non) | fiche du modèle importé |
| `prefab_import` | `carte` (id d'une carte de l'utilisateur) OU `chemin` (dossier de prefab ou de carte), `pids` | `{importes: [{pid_source, pid, ref, renomme, nom, sorte}], refuses: [{pid, raison}], source}` |
| `prefab_update` | `pid`, `nom`, `echelle`, `bloque` (ces deux : modèle seulement) | fiche + `objets_mal_places` |
| `prefab_delete` | `pid`, `avec_objets` (défaut false), `label` | `{supprime, nom, objets_supprimes, cid}` |

Outils MCP des prefabs : `MapAgentPrefabs.tool_defs()` (`editor_prefab_list`,
`editor_prefab_sources`, `editor_prefab_create`, `editor_prefab_import_model`,
`editor_prefab_import`, `editor_prefab_update`, `editor_prefab_delete` ; format
`{name, description, inputSchema, cmd}`, transmis tels quels). Règles (§ 9,
« Prefabs ») : la bibliothèque ne change qu'en solo ou chez l'hôte (invité :
`error`), elle n'est pas dans l'historique d'annulation (chaque résultat le
rappelle dans `note`) ; le remplacement du décor (`prefab_create` avec
`remplacer`) et la suppression des objets posés (`prefab_delete` avec
`avec_objets`) sont des lots de Claude, annulables par `undo`.

## 6. Ce que voient les utilisateurs

- Barre du haut : bouton « Collaboration » (Héberger…, Rejoindre…, Quitter la
  session, Autoriser Claude (MCP) ✓, Historique) et pastilles colorées des
  participants (Claude compris, avec une icône distincte).
- Curseurs des autres sur le plan (couleur + pseudo), leur sélection en
  contour de leur couleur, leur étage indiqué ; aperçu en direct d'un objet
  qu'ils glissent (`presence.live`, 10/s). Dans les élévations (vues
  multiples) : leurs sélections et aperçus projetés, leur curseur à sa vraie
  hauteur s'ils sont dans une élévation du même plan, sinon un trait
  vertical pointillé dans la colonne de leur position.
- Changement reçu : les éléments touchés clignotent brièvement dans la couleur
  de l'auteur ; ligne d'état « Bob : Pièce posée ».
- Lot de Claude (`animate`) : éléments apparaissent un par un (≤ 1,5 s au
  total), contour pulsé violet, bulle « Claude : couloir A→B » ; UNE entrée
  d'historique, donc un seul Ctrl+Z.
- Tout texte en français ET en anglais (`Lang.t(fr, en)`).

## 7. Enregistrement

Seul l'hôte enregistre le dossier de la carte (Ctrl+S) ; il prévient les
invités (`saved`). Ouvrir ou enregistrer la carte est l'affaire de l'hôte :
chez un invité, Fichier > Nouvelle, Ouvrir, Enregistrer, Enregistrer sous,
Exporter / Importer et Cartes récentes sont grisés (« Réservé à l'hôte de la
session », `MapEditor.update_file_menu`, `refuse_guest`), raccourcis compris.
Côté hôte, un invité n'envoie que des `change` (tout autre message, `map` ou
`saved` compris, le déconnecte) et l'identifiant de la carte (nom de son
dossier) d'un `carte` venu d'un invité reste celui de l'hôte
(`MapCollab.host_only_guard`). Copie de récupération : hôte seulement ; les
changements des invités et de Claude marquent la carte de l'hôte modifiée
(étoile) sans l'enregistrer ; l'hôte confirme avant de la perdre, jamais
l'invité (docs/MAP_AUTHORING.md § 6).

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
  mais mal placés (règles de pose de l'éditeur, dessinés en rouge). Une pièce
  du lot (`put` ou `add`) qui recouvre une pièce du même étage fait refuser
  le lot entier (`error` qui explique), sauf avec `decouper: true` : les
  pièces recouvertes sont découpées dans le MÊME lot (une annulation ;
  `MapCarve.carve_ops`, docs/MAP_AUTHORING.md § 3, « Pièce tracée sur une
  autre ») et `decoupe` détaille chaque découpe (`decoupees` : id, nom,
  `retire_m2`, `supprimee`, `morceaux`, `zone_propre`, `passages` ;
  `ouvertures_deplacees`, `ouvertures_retirees`, `ouvertures_reliees`,
  `zone_depart_deplacee`, `objets_supprimes`,
  `a_revoir`, `texte`).
- `undo` : `{cid, undone, label, skipped, conflict}` (ou `{queued: true}`
  chez un invité en attente d'écho).
- `validate` : `{ok, errors, warnings, text, problems: [{level, text, floor,
  points: [[x, y]…]}]}` (points en mètres, 12 au plus par problème).
- `screenshot` : plan dessiné hors écran (1280 × 960, règles en mètres
  comprises dans `bounds`) ; rend aussi `floor` ; erreur en mode sans
  affichage.
- `highlight` : `{shown}` ; contour pulsé, bulle et cadrage (§ 9 « Rendu »).
  Signaux `MapAgentLink.highlight_requested(ids, message)` et
  `animate_requested(ids, label)` (après un `apply` avec `animate`).
- Événements poussés : `{event: "change", cid, author, label, seq, ids}`,
  `{event: "selection", ids}`, `{event: "peers", peers}`.

### Prefabs (§ 5.2, `scripts/editor/collab/map_agent_prefabs.gd`)

- `MapAgentLink` délègue les commandes `prefab_*` à
  `MapAgentPrefabs.handle(editor, cmd, args)` (sans éditeur : `error`) ;
  `MapAgentPrefabs.tool_defs()` donne les outils MCP.
- Mêmes fonctions que l'interface (`MapPrefabTools.make_group`,
  `import_file` / `import_glb`, `update_prefab`, `delete_prefab` ; refus
  gardé dans `MapPrefabTools.last_error`), sans boîte de dialogue ; mêmes
  contrôles (`MapPrefabLib.read_import` / `import_bytes`, `check_glb`,
  `from_objects`, `from_model`) ; inventaire, rendu et invités mis à jour
  comme à la main (`_library_changed` : `broadcast_map`), carte marquée
  modifiée.
- `prefab_import` : chaque prefab de la source passe
  `MapPrefabLib.check_entries` (comme une carte reçue) ; pid déjà pris →
  `MapPrefabLib.new_pid` (« statue » → « statue_2 »).
- `data_base64` passe par la ligne JSON de la liaison (2 Mo au plus avec le
  transport TCP) : pour un gros modèle, `chemin`.
- Tests : `tests/test_map_agent_prefabs.gd`.

### Éditeur

- `push_undo()` / `push_undo_snapshot()` mémorisent la carte d'avant (la plus
  ancienne si plusieurs) ; `changed()` calcule le diff et l'envoie à la
  session (`MapCollab.submit_local`) seulement s'il n'est pas vide.
- Un changement reçu pendant un glissement est aussi appliqué à la copie du
  glissement (`MapCanvas.drag.snap`), pour ne pas l'effacer au relâchement.
- Invité : ni Ouvrir ni Enregistrer (§ 7, réservés à l'hôte) ; pas de
  copie de récupération ni confirmation de sortie ; TESTER réservé à
  l'hôte (l'invité rejoint sa partie tout seul). Hôte : TESTER lance la
  partie avec tous les participants et garde la session ouverte (§ 5.3).

### Rendu (§ 6)

Code : `CollabView` (dessiné par `MapCanvas._draw_peers`), pastilles dans
`CollabPanel`, onglet `CollabHistory`. Tests : `tests/test_collab_view.gd`.

- Pastilles : une par participant, rangées directement dans la barre du
  haut (elle passe à la ligne entre deux pastilles) : disque de sa couleur
  avec son initiale (Claude : disque violet et étoile à huit branches ; moi :
  anneau clair), pseudo (14 caractères au plus), « Étage N » s'il est sur un
  autre étage que celui affiché ; info-bulle : pseudo, rôle (hôte, invité,
  Claude rattaché à X), étage. Affichées dès qu'il y a deux participants
  (Claude compris).
- Curseurs : flèche de la couleur du pair et étiquette avec son pseudo,
  seulement à l'étage affiché ; glissés vers chaque nouvelle présence
  (lissage exponentiel), placés d'un coup à la première ou après un
  changement d'étage. Claude n'a pas de curseur.
- Sélection des autres : contour de leur couleur (forme exacte, sinon
  rectangle écarté de 5 px).
- `presence.live` = `{coll, el}` : l'élément glissé (déplacé, redimensionné,
  tourné) tel qu'il est. L'émetteur l'envoie au plus toutes les 100 ms
  (`MapEditor.send_live`, en plus de la limite de MapCollab) et le retire au
  relâchement ou à l'abandon. Le récepteur ne le dessine que s'il passe les
  règles des éléments reçus (`MapOps.check_elements`) : silhouette
  semi-transparente de la couleur du pair.
- Changement confirmé d'un autre (ou annulation par mon Claude) : les
  éléments touchés clignotent 0,8 s dans la couleur de l'auteur ; ligne
  d'état « Bob : Pièce posée ».
- Lot de Claude (`animate`) : carte, historique et diffusion ont déjà le lot
  entier ; seul le dessin cache les éléments pas encore apparus (les murs
  générés de leurs pièces sont recouverts par le terrain). Un élément toutes
  les 0,12 s, 1,5 s au plus pour le lot, et au moins un de plus par image
  pour un gros lot ; contour pulsé violet et bulle « Claude : <label> » au
  bord haut du groupe, effacés après 3 s. Tout changement confirmé pendant
  l'apparition la termine (sauf l'écho du lot lui-même chez un invité). Si
  aucun élément n'est visible (autre étage, hors champ), la vue y est amenée
  (jamais pendant un glissement).
- `highlight` : contour pulsé violet et bulle avec le message pendant 4 s ;
  étage et vue amenés sur les éléments s'ils sont hors champ (dézoom si le
  groupe est plus grand que la vue) ; la sélection ne change pas.
- Onglet Historique (aussi Collaboration > Historique) : les 100 dernières
  entrées, la plus récente en haut ; pastille de l'auteur, libellé, auteur et
  heure locale ; entrées annulées grisées (« annulée ») ; « Annuler cette
  action » sur mes entrées et celles de mon Claude encore actives
  (`MapCollab.request_undo_of(cid)`, même règle de conflit que Ctrl+Z, mis
  en attente chez un invité qui attend un écho) ; le message de conflit
  s'affiche sous le titre. Survol d'une ligne : éléments touchés surlignés
  sur le plan. Reconstruit seulement quand l'onglet est affiché.
