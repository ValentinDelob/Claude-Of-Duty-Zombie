# Éditeur de cartes : barrière invisible en polygone, chevauchements du décor
# Map editor: polygon invisible barrier, overlapping props

<!-- À fusionner dans changelogs/next/next.json (items {fr, en}) : ce fichier
     .md n'est pas lu par tools/changelog_merge.gd. -->

- FR : La barrière invisible se trace maintenant en polygone, clic après clic (double-clic, clic sur le premier point ou Entrée pour fermer) : un L, une croix ou le contour d'un meuble tourné en une seule barrière.
  EN: The invisible barrier is now drawn as a polygon, one click per corner (double-click, click the first point or Enter to close): an L, a cross or the outline of a turned piece of furniture in a single barrier.
- FR : Elle se pose n'importe où : à cheval sur un mur, dehors ou par-dessus un objet. Ses sommets se déplacent avec les poignées ; elle se déplace, tourne et s'annule comme le reste.
  EN: It goes anywhere: across a wall, outside or over an object. Drag the handles to move its corners; it moves, rotates and undoes like everything else.
- FR : Hauteur réglable au dixième de mètre, ou « Jusqu'au plafond » (case cochée par défaut). En jeu, elle arrête joueurs et zombies avec sa forme exacte ; les balles passent toujours.
  EN: Height can be set to the tenth of a metre, or "Up to the ceiling" (ticked by default). In game it stops players and zombies with its exact shape; bullets still go through.
- FR : Nouveau réglage de la carte « Autoriser les chevauchements décor / obstacles » : caisses, barils, décor, luminaires et piliers peuvent se recouvrir. Les portes, fenêtres, atouts, armes, boîte, départs et escaliers ne se chevauchent jamais.
  EN: New map setting "Allow decor / obstacle overlaps": crates, barrels, props, light fixtures and pillars may overlap. Doors, windows, perks, weapons, box, starts and stairs never overlap.
- FR : Les cartes déjà faites s'ouvrent sans rien changer : leurs barrières rectangulaires deviennent des polygones de 4 sommets, à la même place.
  EN: Existing maps open unchanged: their rectangular barriers become 4-corner polygons in the same place.
