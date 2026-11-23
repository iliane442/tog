# Multijoueur — guide de test avec des amis

Le jeu a un serveur persistant : comptes, persos sauvegardés côté
serveur, joueurs visibles sur la map, chat global, rencontres partagées
et invitations de combat entre joueurs de la même map.

## Lancer le serveur

```bash
cd tog
godot --headless --path . scenes/serveur_monde.tscn
```

Depuis le jeu, le menu d'accueil propose aussi un bouton **Lancer le serveur**
qui démarre ce même serveur en tâche de fond. Le bouton détecte un serveur
déjà lancé (par le terminal, par exemple) et affiche « Serveur en ligne ».

Le serveur écoute sur le port **7777** (64 joueurs max). Autre port :

```bash
godot --headless --path . scenes/serveur_monde.tscn -- 8000
```

Les données du serveur vivent dans `mmo.db` (comptes `mmo_comptes`,
persos `mmo_persos`, coffres du monde partagés `mmo_coffres`).
Pour repartir de zéro : supprime ce fichier.

## Se connecter

Depuis le menu principal, ouvre **Multijoueur** pour te connecter ou créer un compte.

- **Créer un compte** demande un pseudo et un mot de passe de quatre
  caractères minimum. Une fois connecté, crée le personnage de ton compte.
- **Se connecter** reprend le personnage sauvegardé sur le serveur. Un compte
  sans personnage ouvre l’écran de création. La partie en ligne utilise la
  sauvegarde du serveur, actualisée à chaque changement important et toutes les
  30 secondes.

**Jouer en solo** ou **Reprendre en solo** ouvre la partie locale et utilise
`perso.cfg`. Le bouton **Accueil** du menu en jeu permet de changer de mode.

L'adresse du serveur se note `ip:port` (ex. `127.0.0.1:7777`), le
dernier pseudo/adresse utilisés sont retenus.

Sur la carte, appuie sur **T** pour écrire dans le chat global. Entrée
envoie le message et Échap ferme la saisie. Le nom du personnage est
affiché sur la carte, dans le chat, dans les groupes et dans les duels.

**Rencontres partagées** : quand quelqu'un vainc une rencontre (un
groupe d'ennemis étiqueté), elle disparaît pour tous les joueurs de
la même map jusqu'à ce que le serveur la fasse réapparaître (5
minutes). Un joueur qui arrive sur une map reçoit son état courant.

**Ressources partagées** : les coffres posés sur les maps appartiennent
au monde partagé — le serveur fait autorité :

- un coffre ouvert par un joueur l'est pour tous (même sprite ouvert,
  même butin : le tirage a lieu sur le serveur, une seule fois) ;
- un objet pris (ou un coffre vidé) disparaît de la fenêtre de loot
  des autres joueurs de la map ; le serveur arbitre les prises
  simultanées — l'inventaire n'est crédité qu'à sa confirmation ;
- un joueur qui arrive sur une map reçoit l'état courant de ses
  coffres ;
- en ligne, `coffres.cfg` (sauvegarde locale) n'est ni lu ni écrit :
  il ne sert qu'en solo. Les coffres-objets ouverts depuis
  l'inventaire restent personnels.

**Cartes au trésor personnelles** : une carte utilisée plante une
croix qui n'appartient qu'à son chasseur — les autres joueurs ne la
voient pas et ne peuvent pas en fouiller le trésor. En ligne, les
croix non fouillées suivent la sauvegarde serveur du perso (elles
retrouvent leur propriétaire à chaque connexion) ; en solo, elles
vivent dans `cartes_tresor.cfg`.

## Chat

Le chat est une **fenêtre dédiée** (style menu : titre, historique
complet, ligne de saisie) :

- **T ou Entrée** ouvre la fenêtre, la saisie prend le clavier
  directement ; **Échap** ou le bouton « Fermer » la referme.
- **Entrée** envoie le message saisi. Le chat n'apparaît qu'en ligne
  (connecté à un serveur).
- Les annonces du serveur (arrivées, départs, duels, groupes) et les
  messages des joueurs arrivent dans l'historique ; les commandes de
  chat commencent par `/` (`/joueurs`, `/groupe`, `/defier`).

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
  pseudo, leur vrai sprite et leurs pv) sur des cases autour de toi ;
  tous les joueurs d'un même combat contre un camp partagent le même
  plan d'arène : leurs déplacements sont rejoués sur les mêmes cases
  et ton miroir rejoint leur vraie position dès qu'ils bougent ;
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

Écris **`/defier Nom du personnage`** dans le chat pour lancer un défi à un
joueur en ligne. Il reçoit un popup « X te défie en duel ! » avec
Accepter / Refuser. S'il accepte, le duel démarre des deux côtés :

- Chacun combat dans sa propre arène, contre un **miroir** de
  l'autre : ses déplacements, sorts et dégâts sont rejoués en direct
  par le réseau. Les grilles des deux côtés sont identiques (même
  plan d'arène), les positions restent approximatives mais les
  portées et lignes de vue se calculent toujours localement.
- Le miroir de l'adversaire porte son **vrai visuel** (race/sexe,
  même planche de sprites que sur la map) : le serveur l'envoie au
  lancement du duel et le profil réseau le confirme ensuite.
- Les valeurs font foi : les dégâts, soins et états sont **résolus
  chez le lanceur** puis envoyés tels quels — pas de second jet de
  dés chez la victime. Les pv restent détenus par leur propriétaire,
  qui annonce sa défaite lui-même.
- Celui qui a défié joue en premier (sans jet d'initiative), puis les
  tours alternent (fin de tour, sorts, déplacement : tout le moteur
  habituel). Le nom du joueur dont c'est le tour s'affiche à l'écran :
  « À toi de jouer ! », « Au tour de Pseudo… », « Les ennemis jouent… »
- Le perdant tombe à zéro pv et le serveur annonce la victoire à
  l'autre (« X est à terre — tu remportes le duel ! »). Se
  déconnecter en plein duel équivaut à fuir : l'adversaire gagne.
- Le vainqueur ne remporte pas de récompense pour l'instant (ni
  Berry ni XP).

Un joueur en duel porte le badge « (en combat) » et ne peut pas
recevoir d'invitation de combat de groupe tant que le duel dure —
et réciproquement.

## Groupes de joueurs

Pour jouer à plusieurs quand ton équipage n'est pas connecté : les
groupes sont des associations **à la volée**, sans rapport avec les
équipages. Ils vivent le temps de la session du serveur (pas de
persistance).

- **Inviter** avec `/groupe Nom du personnage` dans le chat. La cible reçoit un
  popup « Rejoindre / Refuser ». Seul le chef du groupe peut inviter
  (le fondateur est chef tant qu'il ne part pas), jusqu'à **5
  joueurs** par groupe. Un joueur n'appartient qu'à un seul groupe.
- **Lister** : `/groupe` renvoie les membres (le chef est marqué).
- **Partir** : `/groupe quitter`. Si le chef part, le premier membre
  restant prend la tête ; le dernier parti dissout le groupe. Une
  déconnexion vaut départ.
- **Repérage** : le panneau au-dessus du chat liste tes compagnons
  (chef en doré), et leurs noms apparaissent en **vert** sur la
  map. Les annonces du groupe passent dans le chat.
- **Rejoindre un combat en cours** : un compagnon en combat affiche un
  bouton **« Rejoindre »** dans le panneau du groupe (même si tu n'as
  pas vu la popup d'invitation au départ du combat). Le serveur
  vérifie que tu es libre, sur la même map, et que son combat est une
  rencontre rejoignable — sinon un message du Serveur t'explique quoi
  faire. Le statut « en combat » de chacun se met à jour en direct.

Si deux personnages portent le même nom, `/joueurs` affiche leur référence
de session. Tu peux alors utiliser `/groupe #identifiant` ou `/defier #identifiant`.

## Équipages en ligne

En ligne, les équipages (guildes) sont **serveur-autoritaires** : le
serveur écrit dans sa propre base `mmo_equipages.db` (le fichier solo
`equipages.db` n'est jamais touché par le serveur, ni lu par un client
connecté).

- **Chaque action passe par le serveur** : fonder, dissoudre, quitter,
  recruter, virer, nommer/destituer un vice-capitaine, description,
  caisse, alliances. Le client envoie une demande (`demander_equipage`),
  le serveur valide, écrit, puis renvoie à chaque membre en ligne un
  instantané complet de son état (équipage, membres, journal, autres
  équipages, flotte).
- **Recrutement** : « Ajouter un membre » envoie une **invitation** —
  la cible reçoit un popup « Rejoindre / Refuser », le capitaine
  apprend sa réponse dans l'onglet Équipage. On ne peut recruter
  qu'un compte en ligne qui n'est engagé dans aucun équipage.
- **Caisse** : les Berry online vivent dans le perso serveur. Déposer
  ou retirer ajuste la bourse via le serveur, qui renvoie le solde à
  jour au client (et l'onglet affiche chaque confirmation ou refus,
  même asynchrone).
- **Alliances / flottes** : conclure ou rompre une alliance
  rafraîchit l'état de tous les équipages de la(s) flotte(s) touchée(s).
- **Solo inchangé** : hors ligne, le jeu local `equipages.db` reste la
  référence et le recrutement reste immédiat (pas d'invitation).

## Hôtel des ventes (HDV) partagé

En ligne, les **mises en vente des joueurs** vivent sur le serveur
(table `mmo_hdventes`) : tout le monde les voit et peut les acheter.
Les offres des vendeurs PNJ restent locales à chaque joueur.

- **Mettre en vente** (onglet HDV du menu, panneau de droite) : les
  objets quittent ton inventaire immédiatement, l'offre part au
  serveur et apparaît sous « Mises en vente des joueurs » chez tous
  les joueurs connectés.
- **Acheter** (panneau de gauche, sous les offres PNJ) : le serveur
  vérifie ta bourse (Berry du perso serveur), te livre les objets,
  débite ton solde et **crédite le vendeur — même s'il est hors
  ligne** (sa bourse sera à jour à sa prochaine connexion). Une
  commission HDV de 2 % est retenue. Impossible d'acheter sa propre
  mise en vente ; l'offre disparaît avant tout mouvement, personne ne
  peut l'acheter deux fois.
- **Retirer** : le serveur vérifie que la mise est bien la tienne et
  te rend les objets par livraison réseau ; l'offre disparaît pour
  tout le monde.
- **Acheteurs simulés** : ils fonctionnent hors ligne, comme avant ;
  en ligne, seuls de vrais joueurs achètent (pas de simulation).
- Les confirmations et refus du serveur s'affichent dans l'onglet HDV.

## Échanges d'objets entre joueurs

Écris **`/echanger Nom du personnage`** dans le chat : la cible reçoit
un popup « X te propose un échange ! » (Accepter / Refuser). Si elle
accepte, une **fenêtre d'échange** s'ouvre des deux côtés :

- **Mon offre** à gauche : piocher des objets de ton inventaire
  (quantité bornée par ce que tu possèdes) et des Berry ; chaque
  ajout/retrait/retrait de Berry est envoyé en direct au partenaire.
- **Offre reçue** à droite : ce que le partenaire propose apparaît en
  direct, avec son état (« compose son offre... » / « est prêt ! »).
- **Confirmation croisée** : « Confirmer l'échange » envoie ton accord
  pour l'offre en cours. Dès que l'un des deux **change son offre**,
  les deux confirmations retombent — il faut reconfirmer. L'échange ne
  s'exécute que si les deux ont confirmé la même version des offres.
- À l'exécution : les objets et Berry offerts quittent ton inventaire,
  ceux du partenaire y entrent (sauvegarde serveur immédiate du Berry).
- **Annuler** / refuser / déconnecter : rien
  ne s'échange, le partenaire en est informé dans le chat.
- Un joueur ne peut participer qu'à un échange à la fois ; les
  exemplaires de noms se ciblent via `#identifiant` (cf. `/joueurs`).

Hors ligne, la commande n'a pas d'effet (elle passe par le serveur).

## Indicateurs sociaux

- **Arrivées et départs** : le chat annonce « X a embarqué ! » quand un
  joueur se connecte et « X a débarqué. » quand il part.
- **Commande `/joueurs`** : écris `/joueurs` dans le chat pour recevoir
  la liste des joueurs en ligne (réponse visible par toi seul).
- **Joueurs en combat** : l'avatar de map d'un joueur engagé dans un
  combat disparaît de la carte le temps de son combat (il vit dans les
  arènes, où les invitations ne le sollicitent pas) et réapparaît à la
  fin, à sa vraie position.

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
- Sauvegarde serveur : le perso part au serveur immédiatement à chaque
  changement important (création, sorts, équipement, XP...) puis
  toutes les 30 secondes ; `perso.cfg` n'est plus touché en ligne.
- **Position mémorisée** : la position d'exploration (jamais pendant
  un combat) est mémorisée toutes les 10 s — en ligne, elle suit la
  sauvegarde du perso sur le serveur (connexion depuis une autre
  machine comprise) ; en solo, elle suit le fichier local de la
  machine. Le joueur reprend sa place à l'ouverture du jeu ou à la
  reconnexion ; les traversées de zones vers un marqueur d'arrivée
  restent prioritaires.
