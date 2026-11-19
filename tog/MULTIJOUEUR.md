# Multijoueur — guide de test avec des amis

Le jeu a un serveur persistant : comptes, persos sauvegardés côté
serveur, joueurs visibles sur la map, chat global, rencontres partagées
et invitations de combat entre joueurs de la même map.

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

**Rencontres partagées** : quand quelqu'un vainc une rencontre (un
groupe d'ennemis étiqueté), elle disparaît pour tous les joueurs de
la même map jusqu'à ce que le serveur la fasse réapparaître (5
minutes). Un joueur qui arrive sur une map reçoit son état courant.

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

## Combats ensemble (phase 3, première passe)

Quand un joueur engage une rencontre (groupe d'ennemis étiqueté),
les autres joueurs de la même map reçoivent une invitation :
**« Pseudo engage le groupe [camp] — Rejoindre le combat ? »**. En
rejoignant, chacun combat le même camp dans sa propre instance
miroir : même groupe, même map, chacun sa grille, son tour et son
loot. Le monde reste cohérent grâce aux rencontres partagées (le camp
vaincu par l'un disparaît pour les autres, les ennemis tombés à
distance sont retirés proprement des combats locaux).

L'invitation tombe d'elle-même quand le combat initial se termine.
Un joueur déjà en combat n'est pas sollicité.

## Indicateurs sociaux

- **Arrivées et départs** : le chat annonce « X a embarqué ! » quand un
  joueur se connecte et « X a débarqué. » quand il part.
- **Commande `/joueurs`** : écris `/joueurs` dans le chat pour recevoir
  la liste des joueurs en ligne (réponse visible par toi seul).
- **Badge « en combat »** : l'avatar d'un joueur engagé dans un combat
  affiche « (en combat) » à côté de son pseudo, en jaune. Le badge
  disparaît à la fin de son combat (les avatars marqués ne sont pas
  sollicités par les invitations).

## Déployer sur un VPS

Pour héberger le serveur sur une machine allumée 24 h/24 :

1. **Exporter le serveur dédié** : dans Godot, Projet → Exporter,
   ajoute une cible *Linux Server* (ou `godot --headless --export-release
   "Linux Server" serveur.x86_64`), ce qui produit un binaire sans
   interface.
2. **Machine** : un petit VPS suffit (2 vCPU / 2 Go pour une
   cinquantaine de joueurs). Ubuntu LTS, par exemple.
3. **Ouvrir le port** : `7777/UDP` uniquement. UFW :
   `sudo ufw allow 7777/udp`.
4. **Lancer** : `./serveur.x86_64 --headless --path .` dans le dossier
   du projet (avec tous les fichiers du jeu, pas seulement le binaire).
   `mmo.db` est créé automatiquement au premier démarrage ; garde-le
   entre les mises à jour (c'est là que vivent les comptes).
5. **Service persistant** : tmux suffit pour tester (`tmux new -s serveur`,
   lancer, `Ctrl+B D` pour détacher). Pour du long terme, un service
   systemd le relance en cas de crash :
   ```ini
   # /etc/systemd/system/tog-serveur.service
   [Unit]
   Description=Serveur ToG
   After=network.target

   [Service]
   WorkingDirectory=/opt/tog
   ExecStart=/opt/tog/serveur.x86_64 --headless --path .
   Restart=always
   User=tog

   [Install]
   WantedBy=multi-user.target
   ```
   puis `sudo systemctl enable --now tog-serveur`.
6. **Sauvegardes** : copie `mmo.db` régulièrement (c'est l'unique état
   persistant). Les joueurs entrent `ip.du.vps:7777` dans l'écran de
   connexion.

## Limites connues

- Les combats restent des instances miroir : chaque joueur combat le
  même camp dans sa propre grille, il n'y a pas encore de tour partagé
  ni de dégâts croisés.
- Les mots de passe transitent en clair sur le réseau local : attends
  un vrai serveur (VPS + TLS/WSS) avant d'ouvrir le jeu à des
  inconnus.
- Une seule map partagée : tous les joueurs doivent être sur la même
  scène du monde.
- Sauvegarde serveur : le perso est renvoyé au serveur toutes les
  30 secondes et à la déconnexion.
