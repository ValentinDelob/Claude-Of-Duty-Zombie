# Pont MCP de l'éditeur de cartes

`map_editor_mcp.py` laisse Claude Code lire et modifier **en direct** la carte
ouverte dans l'éditeur de cartes du jeu : ce que Claude pose apparaît tout de
suite chez vous (et chez les autres participants d'une session collaborative),
et chaque action de Claude s'annule d'un seul Ctrl+Z.

## Installation

Rien à installer : Python 3 (`py`, bibliothèque standard seulement). Le serveur
est déclaré dans `.mcp.json` à la racine du dépôt (nom `map-editor`).

## Activation

1. Ouvrez Claude Code dans le dossier du projet. Au premier lancement, il
   demande d'approuver le serveur MCP `map-editor` du projet : acceptez
   (commande `/mcp` pour voir son état ou le réactiver).
2. Lancez le jeu et ouvrez l'**éditeur de cartes**, avec
   **Collaboration > Autoriser Claude (MCP)** coché (par défaut). L'éditeur
   écrit son port et un jeton dans
   `%APPDATA%\Godot\app_userdata\Call of Claude Zombie\editor_collab\agent.json` ;
   le pont s'y connecte (127.0.0.1 seulement) et se reconnecte tout seul si
   l'éditeur a été fermé puis rouvert.
3. Demandez à Claude ce que vous voulez faire sur la carte.

Variables d'environnement facultatives : `CLAUDE_MAP_EDITOR_AGENT_JSON`
(autre chemin pour `agent.json`), `CLAUDE_MAP_EDITOR_TIMEOUT` (délai de
réponse de l'éditeur, 30 s par défaut).

## Outils

| Outil | Rôle |
|---|---|
| `editor_status` | carte ouverte, rôle (solo / hôte / invité), participants, étage, sélection |
| `editor_get_map` | résumé calculé (pièces, voisines, pièces proches, ouvertures, objets, zones) ou carte complète (`format: "full"`) |
| `editor_get_element` | éléments complets d'après leurs ids |
| `editor_get_selection` | sélection de l'utilisateur et position de la souris (m) |
| `editor_apply` | lot d'opérations (`add`, `put`, `del`, `carte`, `depart`) = une étape d'annulation, avec un libellé |
| `editor_undo_last` | annule la dernière action de Claude |
| `editor_validate` | validateur de l'éditeur (erreurs, avertissements BO1) |
| `editor_screenshot` | image du plan, bornes en mètres |
| `editor_highlight` | montre des éléments à l'utilisateur (contour pulsé + bulle) |
| `editor_catalog` | types d'objets admis, décors, luminaires, armes, atouts |
| `editor_events` | derniers changements faits par les autres |
| `editor_plan_corridor` | **propose** un couloir (droit ou en L) entre deux pièces, sans l'appliquer |

## Exemples de demandes

- « Regarde la carte ouverte et dis-moi ce qui manque pour respecter
  docs/MAP_DESIGN_RULES.md. »
- « Relie la pièce sélectionnée à la cave par un couloir de 2,5 m avec une
  porte à 1000. »
- « Décore l'atelier : établis, caisses, deux suspensions qui vacillent. »
- « Mets trois fenêtres sur le mur nord de l'entrée et vérifie la carte. »
- « Annule ce que tu viens de faire. »

## Tests

```
py -m unittest tools/mcp/test_map_editor_mcp.py
```

Un faux éditeur (serveur TCP en mémoire) joue le protocole ; aucun jeu ni
fenêtre n'est lancé. Le dossier `tools/` n'est pas exporté avec le jeu
(`export_presets.cfg`).
