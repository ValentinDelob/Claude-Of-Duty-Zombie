# Éditeur de cartes : prefabs de la carte
# Map editor: map prefabs

<!-- À fusionner dans changelogs/next/next.json (items {fr, en}) : ce fichier
     .md n'est pas lu par tools/changelog_merge.gd. -->

- FR : Nouvelle catégorie de l'inventaire « Prefabs de la carte » : des décors propres à votre carte, rangés dans son dossier et réutilisables autant de fois que vous voulez.
  EN: New inventory category "Map prefabs": props of your own, stored in the map's folder and reusable as many times as you like.
- FR : « Créer… » : glissez un rectangle autour de décors déjà posés pour les grouper en un seul prefab (chaque pièce garde sa place, sa rotation et sa collision) ; le groupe peut remplacer les décors d'origine, Ctrl+Z les ramène.
  EN: "Create…": drag a rectangle around props already placed to group them into a single prefab (each piece keeps its place, rotation and collision); the group can replace the original props, Ctrl+Z brings them back.
- FR : « Importer… » : ajoutez votre propre modèle 3D (.glb ou .gltf). Il est copié dans le dossier de la carte, posé au sol, avec une collision automatique (solide, barrière ou aucune) et une échelle réglable.
  EN: "Import…": add your own 3D model (.glb or .gltf). It is copied into the map's folder, sits on the floor, gets an automatic collision (solid, barrier or none) and an adjustable scale.
- FR : Les prefabs se posent, pivotent et se chevauchent comme le reste du décor, apparaissent dans l'aperçu 3D et en jeu, et voyagent avec la carte : enregistrement, archive .zip et carte partagée en multijoueur.
  EN: Prefabs are placed, rotated and overlapped like any other prop, show in the 3D preview and in game, and travel with the map: saving, .zip archive and maps shared in multiplayer.
- FR : Les modèles reçus d'autres joueurs sont vérifiés avant d'être ouverts (taille, contenu, aucun fichier externe) ; un modèle illisible devient une simple boîte au lieu de bloquer la partie.
  EN: Models received from other players are checked before being opened (size, content, no external files); an unreadable model becomes a plain box instead of breaking the game.
