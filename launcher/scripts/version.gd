extends RefCounted
## Version du lanceur lui-même (entier). À augmenter quand le lanceur change :
## tools/release.sh l'inscrit dans le manifeste (entrée « launcher » ; aussi
## launcher_version.txt quand le lanceur est publié) et les lanceurs plus
## anciens se mettent à jour tout seuls. La release échoue si le lanceur a
## changé sans que ce numéro augmente.

const LAUNCHER_VERSION := 8
