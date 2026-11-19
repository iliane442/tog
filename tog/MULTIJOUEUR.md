# Multijoueur — guide de test avec des amis (phase 1)

Le jeu a désormais un serveur persistant : comptes, persos sauvegardés
côté serveur, joueurs visibles sur la map, chat global. Les combats
restent pour l'instant locaux à chaque joueur (la synchronisation des
combats à plusieurs est la phase 3).

## Lancer le serveur

```bash
cd tog
godot --headless --path . scenes/serveur_monde.tscn
```

Le serveur écoute sur le port **7777** (64 joueurs max). Autre port :

```bash
godot --headless --path . scenes/serveur_monde.tscn -- 8000
```

Les données du serveur vivent dans `mmo.db` (comptes `mmo_comptes`,
persos `mmo_persos`). Pour repartir de zéro : supprime ce fichier.

## Se connecter

Au lancement du jeu, un écran de connexion propose :

- **Créer un compte** : pseudo + mot de passe (4 caractères min.), puis
  connexion immédiate. À la première connexion, ton perso local actuel
  est importé comme perso serveur.
- **Se connecter** : reprend le perso sauvegardé côté serveur (il
  écrase la version locale en mémoire pendant la session).
- **Jouer hors ligne** : le jeu d'avant, sauvegardes locales, sans
  réseau.

L'adresse du serveur se note `ip:port` (ex. `127.0.0.1:7777`), le
dernier pseudo/adresse utilisés sont retenus.

Sur la map : appuie sur **T** pour écrire dans le chat global, Entrée
envoie, Échap annule. Les autres joueurs apparaissent avec leur pseudo.

## Tester en local

1. Lance le serveur (ci-dessus).
2. Lance le jeu normalement (depuis l'éditeur ou un export).
3. Connecte-toi avec `127.0.0.1:7777`.

## Tester avec des amis

Le serveur doit être joignable depuis Internet. Trois options :

- **Tailscale (recommandé, gratuit, sans toucher à la box)** :
  installe Tailscale sur ta machine et celle de chaque ami ; chacun
  récupère une IP Tailscale (100.x.x.x). Tes amis entrent
  `100.x.x.x:7777` dans l'écran de connexion avec TON IP Tailscale.
- **Réseau local (LAN)** : si vos machines sont sur la même box, les
  amis utilisent ton IP locale (`ipconfig getifaddr en0` sur Mac) et
  tu rediriges le port **7777/UDP** vers ta machine dans la box.
- **VPS (dédié)** : loue un petit serveur (2 vCPU / 2 Go suffisent
  largement pour ~50 joueurs), exporte le projet en mode `Linux
  dedicated server`, envoie le dossier avec `mmo.db` initial, et
  fais tourner `./serveur --headless`. C'est l'option cible une fois
  que le jeu se stabilise ; les deux premières suffisent pour jouer
  entre amis dès maintenant.

## Limites connues de la phase 1

- Les combats ne sont pas partagés : chaque joueur combat dans sa
  propre instance, les autres te voient juste te déplacer.
- Les mots de passe transitent en clair sur le réseau local : attends
  un vrai serveur (VPS + TLS/WSS) avant d'ouvrir le jeu à des
  inconnus.
- Une seule map partagée : tous les joueurs doivent être sur la même
  scène du monde.
- Sauvegarde serveur : le perso est renvoyé au serveur toutes les
  30 secondes et à la déconnexion.
