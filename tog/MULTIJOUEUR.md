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

## Combats ensemble (phase 4 : combats de groupe)

Quand un joueur engage une rencontre (groupe d'ennemis étiqueté),
les autres joueurs de la même map reçoivent une invitation :
**« Pseudo engage le groupe [camp] — Rejoindre le combat ? »**. En
rejoignant, chacun combat le même camp dans sa propre instance, mais
les combattants sont maintenant reliés par le serveur :

- les **coéquipiers apparaissent dans ton arène** (miroirs avec leur
  pseudo, leur vrai sprite et leurs pv) placés à côté de toi ;
- leurs **dégâts s'appliquent à tes ennemis** : chaque sort lancé est
  relayé et frappe le même ennemi de ton côté (identification par
  index dans le groupe) — le camp tombe d'autant plus vite à plusieurs ;
- leurs soins, états, déplacements et fins de tour sont rejoués chez
  toi en direct (comme en duel : les valeurs sont résolues chez le
  lanceur, pas de second jet de dés) ;
- quand un coéquipier tombe ou termine son combat, son miroir
  disparaît et un message l'annonce ;
- les ennemis restent pilotés par chaque client (ils attaquent le
  joueur local de chaque instance) et le loot/XP reste par instance.

Les tours restent parallèles (pas d'ordre de tour global) : chacun
joue à son rythme contre le même camp. Le monde reste cohérent grâce
aux rencontres partagées (le camp vaincu par l'un disparaît pour les
autres, les ennemis tombés à distance sont retirés proprement des
combats locaux).

L'invitation tombe d'elle-même quand le combat initial se termine.
Un joueur déjà en combat n'est pas sollicité.

## Duels entre joueurs (PvP)

Écris **`/defier Pseudo`** dans le chat (T) pour lancer un défi à un
joueur en ligne. Il reçoit un popup « X te défie en duel ! » avec
Accepter / Refuser. S'il accepte, le duel démarre des deux côtés :

- Chacun combat dans sa propre arène, contre un **miroir** de
  l'autre : ses déplacements, sorts et dégâts sont rejoués en direct
  par le réseau. Les grilles des deux côtés sont identiques (même
  plan d'arène), les positions restent approximatives mais les
  portées et lignes de vue se calculent toujours localement.
- Les valeurs font foi : les dégâts, soins et états sont **résolus
  chez le lanceur** puis envoyés tels quels — pas de second jet de
  dés chez la victime. Les pv restent détenus par leur propriétaire,
  qui annonce sa défaite lui-même.
- Celui qui a défié joue en premier, puis les tours alternent
  (fin de tour, sorts, déplacement : tout le moteur habituel).
- Le perdant tombe à zéro pv et le serveur annonce la victoire à
  l'autre (« X est à terre — tu remportes le duel ! »). Se
  déconnecter en plein duel équivaut à fuir : l'adversaire gagne.
- Le vainqueur ne remporte pas de récompense pour l'instant (ni
  Berry ni XP).

Un joueur en duel porte le badge « (en combat) » et ne peut pas
recevoir d'invitation de combat de groupe tant que le duel dure —
et réciproquement.

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

- Les tours des combats de groupe restent parallèles : pas encore
  d'ordre de tour global ni d'initiative partagée, et chaque client
  pilote les ennemis de son instance (ils n'attaquent que lui).
- Les mots de passe transitent en clair sur le réseau local : attends
  un vrai serveur (VPS + TLS/WSS) avant d'ouvrir le jeu à des
  inconnus.
- Les joueurs ne se voient que s'ils sont sur la même scène du monde.
- Sauvegarde serveur : le perso est renvoyé au serveur toutes les
  30 secondes et à la déconnexion.
