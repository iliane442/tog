extends Node
# Reseau : socle multijoueur persistant du jeu (phase 1 du MMO).
#
# Le même script tourne côté serveur (scène serveur_monde.tscn) et côté
# client : les deux process partagent l'autoload, donc les @rpc se
# répondent naturellement. Le serveur fait autorité : il porte les
# comptes (mmo_comptes), les persos en ligne (mmo_persos), relaie les
# positions à ~10 Hz et diffuse le chat.
#
# Phase 1 : chaque joueur vit ses combats en local ; les autres
# joueurs sont des avatars visibles sur la map et on discute avec
# eux. La synchronisation des combats viendra en phase 3.

const PORT_DEFAUT := 7777
const JOUEURS_MAX := 64
const VISUEL_DEFAUT := "humain_pirate"
const THEME := preload("res://themes/theme_pirate.tres")
const GROUPE_UI := preload("res://scripts/ui/groupe_ui.gd")
const SCRIPT_AVATAR := preload("res://scripts/serveur/joueur_distant.gd")
const SCRIPT_ADVERSAIRE_PVP := preload("res://scripts/combat/adversaire_pvp.gd")
const CHEMIN_PREF := "user://serveur.cfg"
const CHEMIN_ACCUEIL := "res://scenes/accueil.tscn"
const DELAI_CONNEXION := 9.0
# les données MMO vivent dans leur propre base : la base du jeu
# (glo.db) est recopiée à chaque lancement depuis l'éditeur et
# écraserait les comptes du serveur
const CHEMIN_DB_MMO := "user://mmo.db"
const FREQUENCE_POSITION := 0.1
const INTERVALLE_SAUVEGARDE := 30.0
# mémorisation de la position d'exploration (jamais la position
# d'arène) : le joueur reprend sa place au prochain lancement
const INTERVALLE_MEMOIRE_POSITION := 10.0
# dernière position d'exploration connue : {scene, x, y} — servie à
# l'ouverture des maps (solo : fichier de préférences, en ligne :
# sauvegarde du perso sur le serveur)
var position_memorisee: Dictionary = {}
var _temps_memoire_position := 0.0
# une rencontre vaincue reste masquée pour tous les joueurs de la map
# pendant cette fenêtre (en secondes), puis le serveur la fait
# reparaître partout : une minute, comme les camps en solo
const RESPAWN_RENCONTRES_S := 60.0
const ITERATIONS_HASH := 24000
# lettres/decorations autorisées dans les pseudos
const CARACTERES_PSEUDO := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_ éèêëàâäîïôöùûüçÉÈÊËÀÂÄÎÏÔÖÙÛÜÇ"

signal authentification_resultat(ok: bool, message: String)
signal chat_recu(nom: String, texte: String)

# mode réseau courant
enum Mode { HORS_LIGNE, CLIENT, SERVEUR }

var mode: int = Mode.HORS_LIGNE
var pseudo := ""

# --- client : envois périodiques ---
var _derniere_position_envoyee := Vector2(INF, INF)
var _temps_position := 0.0
var _temps_sauvegarde := 0.0
var _bourse_equipage_en_attente := false

# --- client : authentification ---
var adresse_preferee := "127.0.0.1:%d" % PORT_DEFAUT
var pseudo_prefere := ""
var message_accueil := ""
var _adresse_auth := ""
var _pseudo_auth := ""
var _mot_de_passe_auth := ""
var _action_en_attente := ""
var _attente_auth := 0.0
var _tentatives_auth := 0

# --- client : chat ---
var _chat: CanvasLayer
# fenêtre de chat complète (menu) : titre, historique, saisie
var _fenetre_chat: PanelContainer
var _chat_log: RichTextLabel
var _chat_saisie: LineEdit
var _chat_ouvert := false

# --- client : monde partagé ---
var _scene_locale := ""
var etat_rencontres_recu: Array = []

# --- client : combats miroir (phase 3) ---
# étiquette du groupe que JE combats ("" si aucun combat en cours)
var combat_groupe_local := ""
# invitation en attente : [chef, groupe]
var invitation_en_attente: Array = []
# pair qui a lancé le combat proposé par l'invitation (0 : inconnu) ;
# l'acceptation se valide par lui : le serveur refuse si son combat a
# démarré entre-temps
var invitation_chef_id := 0
# notre groupe de joueurs (distinct des équipages) :
# [{peer: int, pseudo: String, chef: bool}, ...]
var groupe_local: Array = []
var _groupe_ui: GROUPE_UI

# --- client : avatars des autres joueurs ---
var _avatars := {}
var _annonces_en_attente: Array = []   # joueurs connus avant que la scene locale existe

# --- serveur : sessions et relais ---
var _db_mmo: SQLite
var _sessions := {}          # peer_id -> {pseudo, scene, ...}
# rencontres vaincues, temporaires : scene -> {cle: ticks d'expiration}
var _rencontres_vaincues := {}
var _temps_nettoyage_rencontres := 0.0
# combats en cours agrégés par le serveur :
# scene -> {groupe: peer_id du combatteur}
var _combats_actifs := {}           # peer_id -> {pseudo, position, annonce}
var _positions_a_relais := {}  # peer_id -> Vector2
# membres d'un combat de groupe en cours : "scene|groupe" -> {peer_id: true}
var _membres_groupe := {}
# combats de groupe démarrés (placement validé) : "scene|groupe|partie" ->
# true — interdits aux retardataires tant qu'un membre les combat
var _combats_lances := {}
# membres qui ont validé leur placement, par combat de groupe : "clé" ->
# {peer_id: true} ; quand tous les membres du combat y figurent, le
# serveur annonce le feu vert : les tours commencent, chacun à son tour
var _prets_combat := {}
var _temps_relais := 0.0
var _limiteurs := {}          # peer_id -> {position: ms, chat: ms}
# duels en cours : peer_id -> peer_id de l'adversaire
var _duels := {}
# invitations de duel en attente : peer_cible -> peer_demandeur
var _invites_duel := {}
# échanges d'objets en cours : peer -> peer partenaire
var _echanges := {}
# dernier état d'échange connu d'un pair : {pret: bool, offre: JSON}
var _etats_echange := {}
# invitations d'échange en attente : peer_cible -> peer_demandeur
var _invites_echange := {}
# groupes de joueurs (rien à voir avec les équipages : un groupe se
# forme à la volée pour jouer ensemble quand son équipage n'est pas
# connecté) : peer du chef -> {peer_id: true} — le chef est membre
var _groupes := {}
# invitations de groupe en attente : peer_cible -> peer_demandeur
var _invites_groupe := {}
# invitations de recrutement d'équipage en attente : peer_cible ->
# {demandeur: pseudo du capitaine, cible: pseudo invité}
var _invites_equipage := {}
# taille maximale d'un groupe de joueurs
const GROUPE_TAILLE_MAX := 5

func _ready() -> void:
	# Le réseau continue de tourner pendant les dialogues et la création.
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.connected_to_server.connect(_on_connecte_au_serveur)
	multiplayer.connection_failed.connect(_on_echec_connexion)
	multiplayer.server_disconnected.connect(_on_serveur_perdu)
	# la croix de la fenêtre éteint aussi le serveur dédié amorcé par
	# ce jeu (get_tree().quit() passe par NOTIFICATION_PREDELETE, la
	# croix n'y mène pas toujours : le signal la prend en charge)
	get_tree().root.close_requested.connect(_couper_serveur_local)
	charger_preferences()
	_construire_chat()
	_chat.hide()

func _process(delta: float) -> void:
	if mode == Mode.CLIENT and pseudo != "":
		_client_annoncer_scene()
		_client_envoyer_position(delta)
		_client_sauvegarde_periodique(delta)
		_client_appliquer_annonces_attente()
		_memoriser_position_periodique(delta)
	elif mode == Mode.CLIENT and _action_en_attente != "":
		_client_piloter_auth(delta)
	elif mode == Mode.SERVEUR:
		_serveur_diffuser_positions(delta)
		_serveur_purger_rencontres(delta)
	else:
		# solo : la position suit le fichier de préférences de la machine
		_memoriser_position_periodique(delta)

# ============================================================
#  SERVEUR
# ============================================================

# pid du serveur dédié amorcé depuis ce jeu (0 : aucun) : il ne lui
# survit pas — fermer le jeu éteint aussi le serveur
var pid_serveur_local := 0

# tue le serveur dédié démarré par ce client (bouton « Serveur » de
# l'accueil) ; sans ce nettoyage il restait en tâche de fond après la
# fermeture du jeu
func _couper_serveur_local() -> void:
	if pid_serveur_local <= 0:
		return
	OS.kill(pid_serveur_local)
	pid_serveur_local = 0

func _notification(quoi: int) -> void:
	# destruction de l'autoload (get_tree().quit(), fermeture finale) :
	# le serveur s'éteint avec le jeu — la croix de la fenêtre se
	# prend en compte par le signal close_requested branché dans _ready
	if quoi == NOTIFICATION_PREDELETE:
		_couper_serveur_local()

# démarre le serveur (appelé par la scène serveur_monde.tscn)
func demarrer_serveur(port := PORT_DEFAUT) -> bool:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(port, JOUEURS_MAX) != OK:
		push_error("Impossible d'ouvrir le port %d." % port)
		return false
	multiplayer.multiplayer_peer = peer
	mode = Mode.SERVEUR
	multiplayer.peer_connected.connect(_sur_client_connecte)
	multiplayer.peer_disconnected.connect(_on_peer_deconnecte)
	_ouvrir_base_mmo()
	# les équipages en ligne vivent dans une base serveur dédiée pour
	# ne jamais mélanger avec le fichier du jeu solo de la machine
	Equipages.basculer_serveur(CHEMIN_DB_MMO)
	creer_tables_mmo()
	_migrer_equipages_noms_personnage()
	print("Serveur en écoute sur le port %d (%d joueurs max)." % [port, JOUEURS_MAX])
	return true

# ouvre la base MMO dédiée (le serveur seul y écrit)
func _ouvrir_base_mmo() -> void:
	if _db_mmo != null:
		return
	_db_mmo = SQLite.new()
	_db_mmo.path = CHEMIN_DB_MMO
	_db_mmo.open_db()

# exécute une requête SQL sur la base MMO (INSERT/UPDATE/CREATE...)
func _sql(requete: String) -> bool:
	if _db_mmo == null:
		return false
	return _db_mmo.query(requete)

# lit des lignes dans la base MMO
func _lire(requete: String) -> Array:
	if _db_mmo == null:
		return []
	_db_mmo.query(requete)
	return _db_mmo.query_result

# tables MMO, créées à la volée (idempotent, partagées avec glo.db)
func creer_tables_mmo() -> void:
	_sql(
		"CREATE TABLE IF NOT EXISTS mmo_comptes ("
		+ "id INTEGER PRIMARY KEY AUTOINCREMENT,"
		+ "pseudo TEXT UNIQUE NOT NULL,"
		+ "sel TEXT NOT NULL,"
		+ "hash TEXT NOT NULL,"
		+ "iterations INTEGER NOT NULL,"
		+ "cree_le TEXT DEFAULT (datetime('now')));")
	_sql(
		"CREATE TABLE IF NOT EXISTS mmo_persos ("
		+ "compte_id INTEGER PRIMARY KEY,"
		+ "donnees TEXT NOT NULL,"
		+ "maj_le TEXT DEFAULT (datetime('now')));")
	# coffres du monde partagés : une clé par scène et coffre ; une ligne
	# existe dès que le coffre a été ouvert une fois, contenu = restant
	_sql(
		"CREATE TABLE IF NOT EXISTS mmo_coffres ("
		+ "cle TEXT PRIMARY KEY,"
		+ "contenu TEXT NOT NULL DEFAULT '[]');")
	# HDV partagé : mises en vente des joueurs, visibles et achetables
	# par tout le monde (vendeur = pseudo du compte)
	_sql(
		"CREATE TABLE IF NOT EXISTS mmo_hdventes ("
		+ "id INTEGER PRIMARY KEY AUTOINCREMENT,"
		+ "vendeur TEXT NOT NULL,"
		+ "item_id TEXT NOT NULL,"
		+ "quantite INTEGER NOT NULL DEFAULT 1,"
		+ "prix_unite INTEGER NOT NULL DEFAULT 1,"
		+ "cree_le TEXT DEFAULT (datetime('now')));")

func _hacher_mdp(mdp: String, sel: String) -> String:
	# itérations de SHA-256 salé : petit mais dissuasif pour un jeu
	var empreinte := (sel + mdp).sha256_buffer()
	for i in range(ITERATIONS_HASH - 1):
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		ctx.update(empreinte)
		empreinte = ctx.finish()
	return empreinte.hex_encode()

func _creer_sel() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var sel := ""
	for i in range(16):
		sel += "%02x" % rng.randi_range(0, 255)
	return sel

func _echapper_texte(texte: String) -> String:
	return texte.replace("'", "''")

func _compte(nom_pseudo: String) -> Dictionary:
	var lignes := _lire(
		"SELECT id, sel, hash, iterations FROM mmo_comptes WHERE pseudo = '%s';" % _echapper_texte(nom_pseudo))
	if lignes.is_empty():
		return {}
	return {
		"id": int(lignes[0]["id"]),
		"sel": str(lignes[0]["sel"]),
		"hash": str(lignes[0]["hash"]),
		"iterations": int(lignes[0]["iterations"]),
	}

func _perso_du_serveur(compte_id: int) -> String:
	var lignes := _lire("SELECT donnees FROM mmo_persos WHERE compte_id = %d;" % compte_id)
	if lignes.is_empty() or lignes[0]["donnees"] == null:
		return ""
	return str(lignes[0]["donnees"])

func _ecrire_perso_serveur(compte_id: int, donnees_json: String) -> bool:
	var existant := not _lire(
		"SELECT compte_id FROM mmo_persos WHERE compte_id = %d;" % compte_id).is_empty()
	if existant:
		return _sql("UPDATE mmo_persos SET donnees = '%s', maj_le = datetime('now') WHERE compte_id = %d;" % [
			_echapper_texte(donnees_json), compte_id])
	return _sql("INSERT INTO mmo_persos (compte_id, donnees) VALUES (%d, '%s');" % [
		compte_id, _echapper_texte(donnees_json)])

func _nom_personnage(donnees: Dictionary) -> String:
	var valeur: Variant = donnees.get("nom")
	var nom: String = valeur.strip_edges() if valeur is String else ""
	return nom if not nom.is_empty() else "Héros"

func _visuel_personnage(donnees: Dictionary) -> String:
	return Personnage.prefixe_visuel(
		str(donnees.get("race", "1")), str(donnees.get("sexe", "M")),
		str(donnees.get(Personnage.CHAMP_APPARENCE, "")))

func _ouvrir_session(peer_id: int, nom_pseudo: String, perso_json := "") -> void:
	var donnees: Variant = JSON.parse_string(perso_json) if not perso_json.is_empty() else null
	var amenagement: Dictionary = donnees.get("amenagement_navire", {}) if donnees is Dictionary else {}
	_sessions[peer_id] = {
		"pseudo": nom_pseudo,
		"nom_personnage": _nom_personnage(donnees) if donnees is Dictionary else "",
		"modele_bateau": Personnage.NAVIRES.personnel(str(amenagement.get("modele", ""))),
		"finition_pont": Personnage.FINITIONS_PONT.normaliser(str(amenagement.get("finition_pont", ""))),
		"position": Vector2(INF, INF),
		"annonce": false,
		"embarque": false,
		# étiquette du camp combattu (vide hors combat étiqueté) : c'est
		# elle qu'un compagnon de groupe rejoint à la demande
		"combat_groupe": "",
		"scene": "",
		"visuel": _visuel_personnage(donnees) if donnees is Dictionary else VISUEL_DEFAUT,
	}
	_limiteurs[peer_id] = {"position": 0, "chat": 0}
	print("Connexion : %s (id %d, %d joueur(s) en ligne)" % [nom_pseudo, peer_id, _sessions.size()])

# le nouveau est annoncé aux autres quand on connaît enfin sa
# position (premier paquet), pas dès le login (sinon avatar en 0,0)
func _annoncer_si_premiere_position(peer_id: int, position: Vector2) -> void:
	var session: Dictionary = _sessions[peer_id]
	if bool(session["annonce"]):
		return
	session["annonce"] = true
	session["position"] = position
	if not bool(session["embarque"]):
		session["embarque"] = true
		for autre in _sessions:
			if int(autre) != peer_id and bool(_sessions[autre]["embarque"]):
				rpc_id(int(autre), "recoit_message_chat", "Serveur", "%s a embarqué !" % session["nom_personnage"])
	_annoncer_avatar(peer_id, session)

func _annoncer_avatar(peer_id: int, session: Dictionary) -> void:
	var position: Vector2 = session["position"]
	for autre in _pairs_sur_scene(str(session["scene"])):
		if int(autre) == peer_id:
			continue
		rpc_id(int(autre), "joueur_rejoint", peer_id, str(session["nom_personnage"]),
			float(position.x), float(position.y), bool(session.get("en_combat", false)),
			str(session.get("visuel", VISUEL_DEFAUT)))

# limiteur par paire : true si le paquet arrive trop tôt
func _trop_tot(peer_id: int, cle: String, intervalle_ms: int) -> bool:
	var maintenant := Time.get_ticks_msec()
	var limiteur: Dictionary = _limiteurs[peer_id]
	if maintenant - int(limiteur[cle]) < intervalle_ms:
		return true
	limiteur[cle] = maintenant
	return false

# un pair vient de se brancher : rien avant authentification
func _sur_client_connecte(_peer_id: int) -> void:
	pass

func _pair_authentifie() -> Dictionary:
	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id == 0 or not _sessions.has(peer_id):
		return {}
	return {"peer_id": peer_id, "pseudo": _sessions[peer_id]["pseudo"]}

func _serveur_diffuser_positions(delta: float) -> void:
	_temps_relais += delta
	if _temps_relais < FREQUENCE_POSITION:
		return
	_temps_relais = 0.0
	if _positions_a_relais.is_empty():
		return
	var par_scene := {}
	for peer_id in _positions_a_relais:
		var position: Vector2 = _positions_a_relais[peer_id]
		var nom_scene: String = _sessions[peer_id]["scene"]
		var paquet: Array = par_scene.get_or_add(nom_scene, [])
		paquet.append({"id": peer_id, "x": position.x, "y": position.y})
	_positions_a_relais.clear()
	for nom_scene in par_scene:
		for autre in _pairs_sur_scene(nom_scene):
			rpc_id(int(autre), "maj_positions", par_scene[nom_scene])

# RPC serveur : inscription (crée le compte et connecte)
@rpc("any_peer", "call_remote", "reliable")
func demande_inscription(nom_pseudo: String, mdp: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	nom_pseudo = nom_pseudo.strip_edges()
	var validation := _valider_identifiants(nom_pseudo, mdp)
	if validation != "":
		rpc_id(peer_id, "reponse_authentification", false, validation, "")
		return
	if not _compte(nom_pseudo).is_empty():
		rpc_id(peer_id, "reponse_authentification", false, "Ce pseudo est déjà pris.", "")
		return
	var sel := _creer_sel()
	_sql("INSERT INTO mmo_comptes (pseudo, sel, hash, iterations) VALUES ('%s', '%s', '%s', %d);" % [
		_echapper_texte(nom_pseudo), sel, _hacher_mdp(mdp, sel), ITERATIONS_HASH])
	print("Nouveau compte : %s" % nom_pseudo)
	_ouvrir_session(peer_id, nom_pseudo)
	# nouveau compte : aucun perso n'existe encore, le client doit en
	# créer un avant de jouer (le perso local n'est jamais importé)
	rpc_id(peer_id, "reponse_authentification", true, "Compte créé. Crée ton personnage.", "")
	rpc_id(peer_id, "maj_equipage", _snapshot_equipage(str(_sessions[peer_id].get("nom_personnage", ""))))
	rpc_id(peer_id, "maj_hdventes", _snapshot_hdventes())

# RPC serveur : connexion à un compte existant
@rpc("any_peer", "call_remote", "reliable")
func demande_connexion(nom_pseudo: String, mdp: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var compte := _compte(nom_pseudo.strip_edges())
	if compte.is_empty() or _hacher_mdp(mdp, str(compte["sel"])) != str(compte["hash"]):
		rpc_id(peer_id, "reponse_authentification", false, "Pseudo ou mot de passe incorrect.", "")
		return
	var pseudo_final := nom_pseudo.strip_edges()
	var perso_json := _perso_du_serveur(int(compte["id"]))
	_ouvrir_session(peer_id, pseudo_final, perso_json)
	rpc_id(peer_id, "reponse_authentification", true, "Connexion réussie.", perso_json)
	rpc_id(peer_id, "maj_equipage", _snapshot_equipage(str(_sessions[peer_id].get("nom_personnage", ""))))
	rpc_id(peer_id, "maj_hdventes", _snapshot_hdventes())

# Les avatars existent uniquement dans la scène où leurs joueurs se trouvent.
func _annoncer_presents_sur_scene(peer_id: int, nom_scene: String) -> void:
	for autre in _pairs_sur_scene(nom_scene):
		if int(autre) == peer_id or not bool(_sessions[autre]["annonce"]):
			continue
		rpc_id(peer_id, "joueur_rejoint", int(autre), str(_sessions[autre]["nom_personnage"]),
			float(_sessions[autre]["position"].x), float(_sessions[autre]["position"].y),
			bool(_sessions[autre].get("en_combat", false)),
			str(_sessions[autre].get("visuel", VISUEL_DEFAUT)))

func _valider_identifiants(nom_pseudo: String, mdp: String) -> String:
	if nom_pseudo.length() < 3 or nom_pseudo.length() > 16:
		return "Pseudo : 3 à 16 caractères."
	if mdp.length() < 4:
		return "Mot de passe : 4 caractères minimum."
	for caractere in nom_pseudo:
		if not CARACTERES_PSEUDO.contains(caractere):
			return "Pseudo : lettres, chiffres, - _ et espaces seulement."
	return ""

# RPC serveur : sauvegarde périodique du perso d'un joueur
@rpc("any_peer", "call_remote", "reliable")
func envoie_sauvegarde_perso(donnees_json: String) -> void:
	if not multiplayer.is_server():
		return
	var session := _pair_authentifie()
	var donnees: Variant = JSON.parse_string(donnees_json)
	if session.is_empty() or not donnees is Dictionary:
		return
	var compte := _compte(str(session["pseudo"]))
	if compte.is_empty():
		return
	var peer_id := int(session["peer_id"])
	var partie: Dictionary = _sessions[peer_id]
	var nom := _nom_personnage(donnees)
	# unicité des noms : un changement de nom (la création comprise)
	# vers un nom déjà porté par un autre compte est refusé —
	# l'écran de création vérifie en amont, ceci attrape les
	# créations simultanées de deux comptes
	if str(partie["nom_personnage"]) != nom and not _nom_perso_libre(nom, int(compte["id"]), peer_id):
		rpc_id(peer_id, "recoit_message_chat", "Serveur",
			"Le nom de personnage « %s » est déjà pris — recrée ton perso avec un autre nom." % nom)
		return
	var amenagement: Dictionary = donnees.get("amenagement_navire", {})
	amenagement["modele"] = partie["modele_bateau"]
	amenagement["finition_pont"] = partie["finition_pont"]
	donnees["amenagement_navire"] = amenagement
	if not _ecrire_perso_serveur(int(compte["id"]), JSON.stringify(donnees)):
		return
	var visuel := _visuel_personnage(donnees)
	var nom_modifie: bool = partie["nom_personnage"] != nom
	var visuel_modifie: bool = partie["visuel"] != visuel
	partie["nom_personnage"] = nom
	partie["visuel"] = visuel
	if (nom_modifie or visuel_modifie) and bool(partie["annonce"]):
		_annoncer_avatar(peer_id, partie)
	if nom_modifie:
		var groupe := _trouver_groupe(peer_id)
		if not groupe.is_empty():
			_annoncer_groupe(int(groupe["id"]))

# RPC serveur : l'écran de création demande si un nom est libre
@rpc("any_peer", "call_remote", "reliable")
func verifie_nom_perso(nom: String) -> void:
	if not multiplayer.is_server():
		return
	var session := _pair_authentifie()
	if session.is_empty():
		return
	var nom_nettoye := nom.strip_edges().substr(0, 64)
	var compte := _compte(str(session["pseudo"]))
	var compte_id := int(compte["id"]) if not compte.is_empty() else -1
	rpc_id(int(session["peer_id"]), "reponse_nom_perso",
		_nom_perso_libre(nom_nettoye, compte_id, int(session["peer_id"])), nom_nettoye)

# un nom de personnage est libre s'il n'est porté ni par un perso
# sauvegardé d'un autre compte, ni par un personnage en ligne d'un
# autre joueur (comparaison insensible à la casse) ; le compte et le
# pair demandeurs ne comptent pas (recréer à l'identique est permis)
func _nom_perso_libre(nom: String, compte_exclu: int, peer_exclu: int) -> bool:
	var nom_bas := nom.strip_edges().to_lower()
	if nom_bas.is_empty():
		return false
	for ligne in _lire("SELECT compte_id, donnees FROM mmo_persos;"):
		if int(ligne["compte_id"]) == compte_exclu:
			continue
		var stocke: Variant = JSON.parse_string(str(ligne["donnees"]))
		if stocke is Dictionary and str(stocke.get("nom", "")).strip_edges().to_lower() == nom_bas:
			return false
	var pseudo_demandeur := str(_sessions[peer_exclu]["pseudo"])
	for pair in _sessions:
		if int(pair) == peer_exclu:
			continue
		var autre: Dictionary = _sessions[pair]
		if str(autre["pseudo"]) == pseudo_demandeur:
			continue
		if str(autre["nom_personnage"]).strip_edges().to_lower() == nom_bas:
			return false
	return true

# RPC serveur : position d'un joueur
@rpc("any_peer", "call_remote", "unreliable")
func envoie_position(x: float, y: float, nom_scene: String = "") -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not _sessions.has(peer_id):
		return
	var session: Dictionary = _sessions[peer_id]
	if session["scene"] == "" or (nom_scene != "" and session["scene"] != nom_scene):
		return
	if _trop_tot(peer_id, "position", 30):
		return
	var position := Vector2(x, y)
	if not position.is_finite():
		return
	_annoncer_si_premiere_position(peer_id, position)
	session["position"] = position
	_positions_a_relais[peer_id] = position

# sessions presentes sur une map donnee
func _pairs_sur_scene(nom_scene: String) -> Array:
	var pairs: Array = []
	for peer_id in _sessions:
		if str(_sessions[peer_id]["scene"]) == nom_scene:
			pairs.append(int(peer_id))
	return pairs

# les rencontres vaincues en cours sur une map (non expirees)
func _cles_vaincues(nom_scene: String) -> Array:
	var cles: Array = []
	var vaincues: Dictionary = _rencontres_vaincues.get(nom_scene, {})
	for cle in vaincues:
		cles.append(str(cle))
	return cles

# RPC serveur : le client annonce la map sur laquelle il joue
@rpc("any_peer", "call_remote", "reliable")
func envoie_scene(nom_scene: String, x: float = INF, y: float = INF, carte := "") -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not _sessions.has(peer_id):
		return
	nom_scene = nom_scene.strip_edges().substr(0, 64)
	if carte.length() > 48 or (carte != "" and not carte.is_valid_identifier()):
		return
	var fichier := "res://scenes/%s.tscn" % carte if not carte.is_empty() else ""
	nom_scene = Navires.scene_serveur(peer_id, nom_scene, fichier)
	var session: Dictionary = _sessions[peer_id]
	var ancienne_scene: String = session["scene"]
	if nom_scene == "" or nom_scene == ancienne_scene or str(session["nom_personnage"]).is_empty():
		return
	for autre in _pairs_sur_scene(ancienne_scene):
		if int(autre) != peer_id:
			rpc_id(int(autre), "joueur_quitte", peer_id)
	_positions_a_relais.erase(peer_id)
	session["scene"] = nom_scene
	session["annonce"] = false
	print("%s joue sur : %s" % [str(session["nom_personnage"]), nom_scene])
	var position := Vector2(x, y)
	if position.is_finite():
		_annoncer_si_premiere_position(peer_id, position)
	_annoncer_presents_sur_scene(peer_id, nom_scene)
	# l'etat du monde de cette map part au nouvel arrivant
	rpc_id(peer_id, "etat_rencontres", _cles_vaincues(nom_scene), nom_scene)
	# ressources partagées de cette map : les coffres du monde (les
	# croix au trésor sont personnelles, elles suivent chaque perso)
	rpc_id(peer_id, "etat_coffres", _json_coffres_scene(nom_scene))
	Navires.changement_scene(peer_id, fichier)

# RPC serveur : le client annonce l'apparence de son perso (préfixe de
# planche de sprites, ex. humain_pirate, mink_pirate)
@rpc("any_peer", "call_remote", "reliable")
func annonce_visuel(prefixe: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not _sessions.has(peer_id):
		return
	var visuel := str(prefixe).strip_edges()
	if visuel != "":
		_sessions[peer_id]["visuel"] = visuel

# RPC serveur : un joueur a vaincu une rencontre de sa map
@rpc("any_peer", "call_remote", "reliable")
func envoie_rencontre_vaincue(cle: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not _sessions.has(peer_id):
		return
	var nom_scene := str(_sessions[peer_id]["scene"])
	if nom_scene == "":
		return
	cle = cle.strip_edges().substr(0, 128)
	var vaincues: Dictionary = _rencontres_vaincues.get(nom_scene, {})
	vaincues[cle] = Time.get_ticks_msec() + int(RESPAWN_RENCONTRES_S * 1000.0)
	_rencontres_vaincues[nom_scene] = vaincues
	# masquee pour tous les joueurs de la meme map (l'echo vers le
	# tueur est sans effet : son ennemi est deja libere localement)
	for autre in _pairs_sur_scene(nom_scene):
		rpc_id(int(autre), "rencontre_vaincue", cle)

# purge periodique : une rencontre vaincue depuis trop longtemps
# reapparait pour les joueurs presents sur la map
func _serveur_purger_rencontres(delta: float) -> void:
	_temps_nettoyage_rencontres += delta
	if _temps_nettoyage_rencontres < 5.0:
		return
	_temps_nettoyage_rencontres = 0.0
	var maintenant := Time.get_ticks_msec()
	for nom_scene in _rencontres_vaincues.keys():
		var vaincues: Dictionary = _rencontres_vaincues[nom_scene]
		for cle in vaincues.keys():
			if int(vaincues[cle]) > maintenant:
				continue
			vaincues.erase(cle)
			for autre in _pairs_sur_scene(str(nom_scene)):
				rpc_id(int(autre), "rencontre_revient", str(cle))
		if vaincues.is_empty():
			_rencontres_vaincues.erase(str(nom_scene))

# ============================================================
#  COFFRES DU MONDE PARTAGÉS (le serveur fait foi)
# ============================================================

# clé d'un coffre du monde dans la base : scène + identifiant du coffre
func _cle_coffre(nom_scene: String, coffre_id: String) -> String:
	return "%s|%s" % [nom_scene, coffre_id]

# contenu restant d'un coffre du monde (null si jamais ouvert)
func _contenu_coffre_monde(cle: String) -> Variant:
	var lignes := _lire("SELECT contenu FROM mmo_coffres WHERE cle = '%s';" % _echapper_texte(cle))
	if lignes.is_empty():
		return null
	return JSON.parse_string(str(lignes[0]["contenu"]))

# RPC serveur : un joueur ouvre (ou rouvre) un coffre du monde ; le
# tirage du butin n'a lieu qu'ici — le même contenu fait foi pour tous
@rpc("any_peer", "call_remote", "reliable")
func envoie_ouvrir_coffre(coffre_id: String, rarete: int) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not _sessions.has(peer_id):
		return
	var nom_scene := str(_sessions[peer_id]["scene"])
	if nom_scene == "":
		return
	coffre_id = coffre_id.strip_edges().substr(0, 160)
	if coffre_id == "" or not coffre_id.begins_with("coffre_"):
		return
	var cle := _cle_coffre(nom_scene, coffre_id)
	var contenu: Variant = _contenu_coffre_monde(cle)
	if contenu == null or not contenu is Array:
		# première ouverture : tirage serveur, une seule fois
		contenu = Coffres.tirage_de_coffre(clampi(int(rarete), 1, 4))
		_sql("INSERT OR REPLACE INTO mmo_coffres (cle, contenu) VALUES ('%s', '%s');" % [
			_echapper_texte(cle), _echapper_texte(JSON.stringify(contenu))])
	var contenu_json := JSON.stringify(contenu)
	for autre in _pairs_sur_scene(nom_scene):
		rpc_id(int(autre), "coffre_etat", coffre_id, contenu_json)

# RPC serveur : un joueur veut prendre l'objet n° index d'un coffre ;
# le serveur arbitre — si l'objet y est encore, la prise est confirmée à
# son demandeuse, l'état restant part à toute la map
@rpc("any_peer", "call_remote", "reliable")
func envoie_prendre_objet_coffre(coffre_id: String, index: int) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not _sessions.has(peer_id):
		return
	var nom_scene := str(_sessions[peer_id]["scene"])
	if nom_scene == "":
		return
	var cle := _cle_coffre(nom_scene, coffre_id)
	var contenu: Variant = _contenu_coffre_monde(cle)
	if contenu == null or not contenu is Array:
		return
	if index < 0 or index >= (contenu as Array).size():
		return
	var prise: Variant = contenu[index]
	(contenu as Array).remove_at(index)
	_sql("UPDATE mmo_coffres SET contenu = '%s' WHERE cle = '%s';" % [
		_echapper_texte(JSON.stringify(contenu)), _echapper_texte(cle)])
	rpc_id(peer_id, "coffre_prise", JSON.stringify(prise))
	var contenu_json := JSON.stringify(contenu)
	for autre in _pairs_sur_scene(nom_scene):
		rpc_id(int(autre), "coffre_etat", coffre_id, contenu_json)

# RPC serveur : un joueur vide un coffre du monde entier
@rpc("any_peer", "call_remote", "reliable")
func envoie_vider_coffre(coffre_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not _sessions.has(peer_id):
		return
	var nom_scene := str(_sessions[peer_id]["scene"])
	if nom_scene == "":
		return
	var cle := _cle_coffre(nom_scene, coffre_id)
	var contenu: Variant = _contenu_coffre_monde(cle)
	if contenu == null or not contenu is Array:
		return
	_sql("UPDATE mmo_coffres SET contenu = '[]' WHERE cle = '%s';" % _echapper_texte(cle))
	rpc_id(peer_id, "coffre_prise", JSON.stringify(contenu))
	for autre in _pairs_sur_scene(nom_scene):
		rpc_id(int(autre), "coffre_etat", coffre_id, "[]")

# état des coffres du monde d'une scène (nouvel arrivant sur la map) :
# {coffre_id: contenu restant, ...} en JSON
func _json_coffres_scene(nom_scene: String) -> String:
	var prefixe := nom_scene + "|"
	var lignes := _lire("SELECT cle, contenu FROM mmo_coffres WHERE cle LIKE '%s%%';" % _echapper_texte(prefixe))
	var etat := {}
	for ligne in lignes:
		var cle := str(ligne["cle"])
		etat[cle.substr(prefixe.length())] = JSON.parse_string(str(ligne["contenu"]))
	return JSON.stringify(etat)

# RPC serveur : un joueur engage un groupe étiqueté
@rpc("any_peer", "call_remote", "reliable")
func envoie_debut_combat(groupe: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not _sessions.has(peer_id):
		return
	var session: Dictionary = _sessions[peer_id]
	var nom_scene := str(session["scene"])
	groupe = groupe.strip_edges().substr(0, 64)
	if nom_scene == "" or groupe == "":
		return
	# un combat démarré (placement validé) ne se rejoint plus : le
	# retardataire repart explorer, son instance ne participera pas
	if _combats_lances.has(_cle_combat_groupe(peer_id, nom_scene, groupe)):
		rpc_id(peer_id, "recoit_message_chat", "Serveur",
			"Ce combat est déjà lancé : impossible de le rejoindre.")
		rpc_id(peer_id, "combat_refuse")
		return
	session["en_combat"] = true
	session["combat_groupe"] = groupe
	var combats_scene: Dictionary = _combats_actifs.get(nom_scene, {})
	combats_scene[groupe] = peer_id
	_combats_actifs[nom_scene] = combats_scene
	print("Combat : %s engage [%s] sur %s" % [session["nom_personnage"], groupe, nom_scene])
	# combat de groupe : le premier est l'hôte, les suivants rejoignent —
	# la clé inclut le groupe de joueurs : seuls les membres d'un même
	# groupe partagent un combat, les autres joueurs (même camp, même
	# map) restent sur leur propre instance
	var cle := _cle_combat_groupe(peer_id, nom_scene, groupe)
	var membres: Dictionary = _membres_groupe.get(cle, {})
	var nouveau := not membres.has(peer_id)
	membres[peer_id] = true
	_membres_groupe[cle] = membres
	if nouveau:
		# le nouveau arrivant reçoit les combattants déjà en place
		var presents: Array = []
		for autre in membres:
			if int(autre) == peer_id or not _sessions.has(autre):
				continue
			presents.append({
				"peer": int(autre), "pseudo": str(_sessions[autre]["nom_personnage"]),
				"visuel": str(_sessions[int(autre)].get("visuel", VISUEL_DEFAUT)),
			})
		rpc_id(peer_id, "membres_groupe", presents)
	for autre in _pairs_sur_scene(nom_scene):
		if int(autre) != peer_id:
			rpc_id(int(autre), "etre_en_combat", peer_id, true)
	# invitation pour les membres du groupe présents sur la map et pas
	# déjà en combat : un combat ne se rejoint qu'entre membres d'un
	# même groupe de joueurs (le bouton « Rejoindre » du panneau GROUPE
	# permet aussi de les rejoindre en cours de combat)
	var groupe_pair := _trouver_groupe(peer_id)
	if not groupe_pair.is_empty():
		for membre in groupe_pair["membres"]:
			var autre := int(membre)
			if autre == peer_id or not _sessions.has(autre):
				continue
			if str(_sessions[autre]["scene"]) != nom_scene:
				continue
			if bool(_sessions[autre].get("en_combat", false)):
				continue
			rpc_id(autre, "invitation_combat", str(session["nom_personnage"]), groupe, peer_id)
	# le panneau du groupe suit le statut en combat de chacun
	_annoncer_groupes_du_pair(peer_id)

# RPC serveur : le combat de groupe du pair démarre réellement (fin du
# placement) — le serveur ne laisse plus personne le rejoindre, et
# quand TOUS les membres ont validé leur place, il lève la barrière :
# l'arbitre construit l'ordre des tours et chacun joue à son tour
@rpc("any_peer", "call_remote", "reliable")
func envoie_combat_lance() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not _sessions.has(peer_id):
		return
	var session: Dictionary = _sessions[peer_id]
	var groupe := str(session.get("combat_groupe", ""))
	if groupe == "":
		return
	var cle := _cle_combat_groupe(peer_id, str(session["scene"]), groupe)
	_combats_lances[cle] = true
	var prets: Dictionary = _prets_combat.get(cle, {})
	prets[peer_id] = true
	_prets_combat[cle] = prets
	var membres: Dictionary = _membres_groupe.get(cle, {})
	var tous := true
	for membre in membres:
		if not prets.has(int(membre)):
			tous = false
			break
	if not tous:
		return
	_prets_combat.erase(cle)
	for membre in membres:
		rpc_id(int(membre), "combat_groupe_pret")

# clé d'un combat de groupe : même scène, même camp étiqueté, même
# groupe de joueurs (sans groupe : identifiant du pair — combat isolé)
func _cle_combat_groupe(peer_id: int, nom_scene: String, groupe: String) -> String:
	var groupe_pair := _trouver_groupe(peer_id)
	var id_partie := str(peer_id)
	if not groupe_pair.is_empty():
		id_partie = str(int(groupe_pair["id"]))
	return "%s|%s|%s" % [nom_scene, groupe, id_partie]

# RPC serveur : le combat du joueur est terminé
@rpc("any_peer", "call_remote", "reliable")
func envoie_fin_combat(groupe: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not _sessions.has(peer_id):
		return
	var session: Dictionary = _sessions[peer_id]
	session["en_combat"] = false
	session["combat_groupe"] = ""
	var nom_scene := str(session["scene"])
	groupe = groupe.strip_edges().substr(0, 64)
	# il quitte son combat de groupe : les autres perdent son miroir
	for cle in _membres_groupe.keys():
		var membres: Dictionary = _membres_groupe[cle]
		if not membres.has(peer_id):
			continue
		membres.erase(peer_id)
		for autre in membres:
			rpc_id(int(autre), "sortie_combat_groupe", peer_id)
		if membres.is_empty():
			_membres_groupe.erase(cle)
			# le combat est vide : il se rejoindra de nouveau s'il
			# repart un jour
			_combats_lances.erase(cle)
			_prets_combat.erase(cle)
	for autre in _pairs_sur_scene(nom_scene):
		if int(autre) != peer_id:
			rpc_id(int(autre), "etre_en_combat", peer_id, false)
	# le panneau du groupe suit le statut en combat de chacun
	_annoncer_groupes_du_pair(peer_id)
	var combats_scene: Dictionary = _combats_actifs.get(nom_scene, {})
	if not combats_scene.has(groupe):
		return
	# un autre joueur a-t-il repris ce combat ?
	if int(combats_scene[groupe]) != peer_id:
		return
	combats_scene.erase(groupe)
	if combats_scene.is_empty():
		_combats_actifs.erase(nom_scene)
	for autre in _pairs_sur_scene(nom_scene):
		rpc_id(int(autre), "fin_combat_distante", str(session["nom_personnage"]), groupe)

# nettoyage : un joueur parti ne garde pas la main sur un combat
func _liberer_combats(peer_id: int) -> void:
	if not _sessions.has(peer_id):
		return
	var nom_scene := str(_sessions[peer_id]["scene"])
	var combats_scene: Dictionary = _combats_actifs.get(nom_scene, {})
	for groupe in combats_scene.keys():
		if int(combats_scene[groupe]) == peer_id:
			combats_scene.erase(groupe)
	if combats_scene.is_empty():
		_combats_actifs.erase(nom_scene)

# ============================================================
#  DUELS ENTRE JOUEURS
# ============================================================

# Recherche par identifiant de compte pour les équipages persistants.
func _peer_du_pseudo(pseudo_cherche: String) -> int:
	var cherche := pseudo_cherche.to_lower()
	for peer_id in _sessions:
		if str(_sessions[peer_id]["pseudo"]).to_lower() == cherche:
			return int(peer_id)
	return 0

# pair en ligne portant ce nom de personnage (les équipages identifient
# leurs membres par personnage, pas par compte)
func _peer_du_nom_personnage(nom: String) -> int:
	var cherche := nom.strip_edges().to_lower()
	for peer_id in _sessions:
		if str(_sessions[peer_id].get("nom_personnage", "")).strip_edges().to_lower() == cherche:
			return int(peer_id)
	return 0

# Les commandes de jeu ciblent le nom public ou la référence indiquée par /joueurs.
func _chercher_cible(demandeur: int, cible: String) -> int:
	var identifiant := cible.trim_prefix("#")
	var cible_par_id := cible.begins_with("#") and identifiant.is_valid_int()
	var nom_cherche := cible.to_lower()
	var resultat := 0
	for peer_id in _sessions:
		var session: Dictionary = _sessions[peer_id]
		if not bool(session["embarque"]):
			continue
		var correspond := (
			int(peer_id) == identifiant.to_int() if cible_par_id
			else str(session["nom_personnage"]).to_lower() == nom_cherche
		)
		if not correspond:
			continue
		if resultat != 0:
			rpc_id(demandeur, "recoit_message_chat", "Serveur",
				"Plusieurs personnages portent ce nom. Utilise /joueurs pour trouver leur référence #.")
			return 0
		resultat = int(peer_id)
	if resultat == 0:
		rpc_id(demandeur, "recoit_message_chat", "Serveur",
			"Aucun personnage en ligne ne correspond à %s." % cible)
	return resultat

# le badge « en combat » d'un pair est propagé aux joueurs de sa map
func _annoncer_etat_combat(peer_id: int, actif: bool) -> void:
	if not _sessions.has(peer_id):
		return
	var nom_scene := str(_sessions[peer_id]["scene"])
	for autre in _pairs_sur_scene(nom_scene):
		if int(autre) != peer_id and _pair_connecte(int(autre)):
			rpc_id(int(autre), "etre_en_combat", peer_id, actif)

# le duel entre les deux pairs est clos, badges retirés
func _fin_duel(peer_id: int) -> void:
	var adversaire := int(_duels.get(peer_id, 0))
	for pair in [peer_id, adversaire]:
		if _sessions.has(pair):
			_sessions[pair]["en_combat"] = false
			_annoncer_etat_combat(pair, false)
		_duels.erase(pair)
		_invites_duel.erase(pair)

# RPC serveur : réponse à une invitation de duel
@rpc("any_peer", "call_remote", "reliable")
func reponse_duel(accepte: bool) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not _invites_duel.has(peer_id):
		return
	var demandeur := int(_invites_duel[peer_id])
	_invites_duel.erase(peer_id)
	if not _sessions.has(demandeur) or not _sessions.has(peer_id):
		return
	if _sessions[demandeur]["scene"] != _sessions[peer_id]["scene"]:
		rpc_id(demandeur, "recoit_message_chat", "Serveur", "Ce joueur a changé de zone.")
		return
	var pseudo_demandeur := str(_sessions[demandeur]["nom_personnage"])
	var pseudo_cible := str(_sessions[peer_id]["nom_personnage"])
	if not accepte:
		rpc_id(demandeur, "recoit_message_chat", "Serveur", "%s refuse le duel." % pseudo_cible)
		return
	if _duels.has(demandeur) or _duels.has(peer_id):
		return
	_duels[demandeur] = peer_id
	_duels[peer_id] = demandeur
	_sessions[demandeur]["en_combat"] = true
	_sessions[peer_id]["en_combat"] = true
	_annoncer_etat_combat(demandeur, true)
	_annoncer_etat_combat(peer_id, true)
	print("Duel : %s contre %s" % [pseudo_demandeur, pseudo_cible])
	# le visuel (race/sexe) de l'adversaire part avec : le miroir de
	# duel porte les vrais sprites du joueur distant, pas l'humain de base
	var visuel_demandeur := str(_sessions[demandeur].get("visuel", VISUEL_DEFAUT))
	var visuel_cible := str(_sessions[peer_id].get("visuel", VISUEL_DEFAUT))
	# celui qui a défié ouvre le bal
	rpc_id(demandeur, "debut_duel", pseudo_cible, peer_id, true, visuel_cible)
	rpc_id(peer_id, "debut_duel", pseudo_demandeur, demandeur, false, visuel_demandeur)

# RPC serveur : action de duel à relayer à l'adversaire
@rpc("any_peer", "call_remote", "reliable")
func envoie_action_duel(json: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not _duels.has(peer_id):
		return
	rpc_id(int(_duels[peer_id]), "action_duel", json)

# RPC serveur : action d'un membre d'un combat de groupe, relayée à tous
# les autres membres de son combat (scene|groupe)
@rpc("any_peer", "call_remote", "reliable")
func envoie_action_groupe(json: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	for cle in _membres_groupe:
		var membres: Dictionary = _membres_groupe[cle]
		if not membres.has(peer_id):
			continue
		for autre in membres:
			if int(autre) != peer_id:
				rpc_id(int(autre), "action_groupe", peer_id, str(_sessions[peer_id]["nom_personnage"]), json)
		return

# RPC serveur : le client déclare forfait (ses pv sont tombés à zéro)
@rpc("any_peer", "call_remote", "reliable")
func envoie_defaite_duel() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not _duels.has(peer_id):
		return
	var adversaire := int(_duels[peer_id])
	var nom_defait := str(_sessions[peer_id]["nom_personnage"])
	_fin_duel(peer_id)
	rpc_id(adversaire, "victoire_duel", nom_defait, false)

# RPC serveur : le client fuit le duel, son adversaire l'emporte
@rpc("any_peer", "call_remote", "reliable")
func envoie_fuite_duel() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not _duels.has(peer_id):
		return
	var adversaire := int(_duels[peer_id])
	var nom_fuyard := str(_sessions[peer_id]["nom_personnage"])
	_fin_duel(peer_id)
	rpc_id(adversaire, "victoire_duel", nom_fuyard, true)

# ============================================================
#  ÉCHANGES D'OBJETS ENTRE JOUEURS
# ============================================================

# un joueur propose un échange à un pair en ligne
func _proposer_echange(demandeur: int, cible: int) -> void:
	var nom_cible: String = _sessions[cible]["nom_personnage"]
	var nom_demandeur: String = _sessions[demandeur]["nom_personnage"]
	if cible == demandeur:
		rpc_id(demandeur, "recoit_message_chat", "Serveur", "Échanger avec soi-même, vraiment ?")
		return
	if _echanges.has(demandeur) or _echanges.has(cible):
		rpc_id(demandeur, "recoit_message_chat", "Serveur", "Un des deux joueurs est déjà en échange.")
		return
	if _invites_echange.has(cible):
		rpc_id(demandeur, "recoit_message_chat", "Serveur", "%s a déjà une proposition en attente." % nom_cible)
		return
	_invites_echange[cible] = demandeur
	rpc_id(demandeur, "recoit_message_chat", "Serveur", "Tu proposes un échange à %s..." % nom_cible)
	rpc_id(cible, "invite_echange", nom_demandeur)

# RPC serveur : réponse à une proposition d'échange
@rpc("any_peer", "call_remote", "reliable")
func reponse_echange(accepte: bool) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var demandeur := int(_invites_echange.get(peer_id, 0))
	_invites_echange.erase(peer_id)
	if demandeur == 0 or not _sessions.has(peer_id) or not _sessions.has(demandeur):
		return
	var nom_cible: String = _sessions[peer_id]["nom_personnage"]
	if not accepte:
		rpc_id(demandeur, "recoit_message_chat", "Serveur", "%s refuse l'échange." % nom_cible)
		return
	if _echanges.has(demandeur) or _echanges.has(peer_id):
		rpc_id(demandeur, "recoit_message_chat", "Serveur", "Un des deux joueurs est déjà en échange.")
		return
	_echanges[demandeur] = peer_id
	_echanges[peer_id] = demandeur
	_etats_echange[demandeur] = {"pret": false, "offre": "{}"}
	_etats_echange[peer_id] = {"pret": false, "offre": "{}"}
	var nom_demandeur: String = _sessions[demandeur]["nom_personnage"]
	print("Échange : %s avec %s" % [nom_demandeur, nom_cible])
	rpc_id(demandeur, "debut_echange", nom_cible)
	rpc_id(peer_id, "debut_echange", nom_demandeur)

# RPC serveur : offre d'un joueur (objets + Berry) et son état "prêt" ;
# toute nouvelle offre déverrouille les deux côtés — l'échange ne
# s'exécute que si les deux ont confirmé la même version des offres
@rpc("any_peer", "call_remote", "reliable")
func envoie_offre_echange(offre_json: String, pret: bool) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not _echanges.has(peer_id) or not _etats_echange.has(peer_id):
		return
	var partenaire := int(_echanges[peer_id])
	if not _sessions.has(partenaire) or not _etats_echange.has(partenaire):
		return
	var etat: Dictionary = _etats_echange[peer_id]
	var changement := str(etat.get("offre", "")) != offre_json
	etat["offre"] = offre_json
	if changement:
		etat["pret"] = false
		_etats_echange[partenaire]["pret"] = false
	else:
		etat["pret"] = bool(pret)
	rpc_id(partenaire, "offre_echange", offre_json, bool(etat["pret"]))
	var etat_partenaire: Dictionary = _etats_echange[partenaire]
	if bool(etat["pret"]) and bool(etat_partenaire["pret"]):
		_executer_echange_binaire(peer_id, partenaire)

# les deux côtés ont confirmé : chacun reçoit l'offre définitive de
# l'autre et l'applique dans sa propre sauvegarde
func _executer_echange_binaire(pair_a: int, pair_b: int) -> void:
	var offre_a := str(_etats_echange[pair_a]["offre"])
	var offre_b := str(_etats_echange[pair_b]["offre"])
	_cloturer_echange(pair_a, pair_b)
	rpc_id(pair_a, "executer_echange", offre_b)
	rpc_id(pair_b, "executer_echange", offre_a)

# oublie l'échange entre deux pairs (sans leur envoyer de message)
func _cloturer_echange(pair_a: int, pair_b: int) -> void:
	_echanges.erase(pair_a)
	_echanges.erase(pair_b)
	_etats_echange.erase(pair_a)
	_etats_echange.erase(pair_b)

# RPC serveur : un joueur abandonne l'échange en cours
@rpc("any_peer", "call_remote", "reliable")
func annuler_echange() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not _echanges.has(peer_id):
		return
	var partenaire := int(_echanges[peer_id])
	_cloturer_echange(peer_id, partenaire)
	if _pair_connecte(partenaire):
		rpc_id(partenaire, "fin_echange", "Échange annulé.")

# ============================================================
#  HDV PARTAGÉ (mises en vente des joueurs)
# ============================================================

# instantané de toutes les mises en vente actives
func _snapshot_hdventes() -> String:
	var entrees: Array = []
	for ligne in _lire(
			"SELECT id, vendeur, item_id, quantite, prix_unite"
			+ " FROM mmo_hdventes ORDER BY id DESC;"):
		entrees.append({
			"id": int(ligne["id"]),
			"vendeur": str(ligne["vendeur"]),
			"item": str(ligne["item_id"]),
			"quantite": int(ligne["quantite"]),
			"prix_unite": int(ligne["prix_unite"]),
		})
	return JSON.stringify(entrees)

# pousse l'état du HDV à tous les joueurs connectés
func _diffuser_hdventes() -> void:
	var snapshot := _snapshot_hdventes()
	for autre in _sessions:
		rpc_id(int(autre), "maj_hdventes", snapshot)

# RPC serveur : vendre / retirer / acheter une mise en vente
@rpc("any_peer", "call_remote", "reliable")
func demande_hdvente(action: String, offre_id: int, item: String, quantite: int, prix: int) -> void:
	if not multiplayer.is_server():
		return
	var session := _pair_authentifie()
	if session.is_empty():
		return
	var peer_id := int(session["peer_id"])
	var pseudo_pair := str(session["pseudo"])
	match action:
		"vendre":
			quantite = clampi(quantite, 1, 999)
			prix = maxi(prix, 1)
			item = str(item).strip_edges().substr(0, 40)
			if item == "":
				return
			_sql("INSERT INTO mmo_hdventes (vendeur, item_id, quantite, prix_unite)"
				+ " VALUES ('%s', '%s', %d, %d);" % [
				_echapper_texte(pseudo_pair), _echapper_texte(item), quantite, prix])
			rpc_id(peer_id, "message_hdvente", "Objet en vente : visible par tous les joueurs du serveur.")
			_diffuser_hdventes()
		"retirer":
			var lignes := _lire(
				"SELECT vendeur, item_id, quantite FROM mmo_hdventes WHERE id = %d;" % offre_id)
			if lignes.is_empty():
				return
			if str(lignes[0]["vendeur"]) != pseudo_pair:
				rpc_id(peer_id, "message_hdvente", "Cette mise en vente n'est pas la tienne.")
				return
			_sql("DELETE FROM mmo_hdventes WHERE id = %d;" % offre_id)
			rpc_id(peer_id, "livraison_hdvente", JSON.stringify({
				"item": str(lignes[0]["item_id"]),
				"quantite": int(lignes[0]["quantite"])}))
			_diffuser_hdventes()
		"acheter":
			_acheter_mise_hdvente(peer_id, pseudo_pair, offre_id)

# achat d'une mise en vente : le serveur débite l'acheteur, crédite le
# vendeur (connecté ou non), livre les objets et rafraîchit tout le monde
func _acheter_mise_hdvente(peer_id: int, pseudo_acheteur: String, offre_id: int) -> void:
	var lignes := _lire(
		"SELECT vendeur, item_id, quantite, prix_unite FROM mmo_hdventes WHERE id = %d;" % offre_id)
	if lignes.is_empty():
		rpc_id(peer_id, "message_hdvente", "Cette offre a déjà disparu.")
		return
	var vendeur := str(lignes[0]["vendeur"])
	if vendeur == pseudo_acheteur:
		rpc_id(peer_id, "message_hdvente", "On n'achète pas sa propre mise en vente.")
		return
	var total := int(lignes[0]["prix_unite"]) * int(lignes[0]["quantite"])
	var compte_acheteur := _compte(pseudo_acheteur)
	var perso_acheteur := _perso_json_serveur(compte_acheteur)
	if perso_acheteur.is_empty():
		rpc_id(peer_id, "message_hdvente", "Personnage introuvable")
		return
	if int(perso_acheteur.get("berry", 0)) < total:
		rpc_id(peer_id, "message_hdvente", "Pas assez de Berry (%d requis)." % total)
		return
	# l'offre disparaît avant tout mouvement : personne ne peut la
	# prendre deux fois
	_sql("DELETE FROM mmo_hdventes WHERE id = %d;" % offre_id)
	perso_acheteur["berry"] = int(perso_acheteur.get("berry", 0)) - total
	_ecrire_perso_serveur(int(compte_acheteur["id"]), JSON.stringify(perso_acheteur))
	rpc_id(peer_id, "maj_perso_berry", int(perso_acheteur["berry"]))
	rpc_id(peer_id, "livraison_hdvente", JSON.stringify({
		"item": str(lignes[0]["item_id"]),
		"quantite": int(lignes[0]["quantite"])}))
	rpc_id(peer_id, "message_hdvente", "Achat effectué : %d Berry dépensés." % total)
	# le vendeur encaisse (commission HDV de 2 %) — sa bourse est
	# créditée même s'il est hors ligne
	var gains := int(floor(total * (1.0 - 0.02)))
	var compte_vendeur := _compte(vendeur)
	var perso_vendeur := _perso_json_serveur(compte_vendeur)
	if not perso_vendeur.is_empty():
		perso_vendeur["berry"] = int(perso_vendeur.get("berry", 0)) + gains
		_ecrire_perso_serveur(int(compte_vendeur["id"]), JSON.stringify(perso_vendeur))
		var peer_vendeur := _peer_du_pseudo(vendeur)
		if peer_vendeur != 0:
			rpc_id(peer_vendeur, "maj_perso_berry", int(perso_vendeur["berry"]))
			rpc_id(peer_vendeur, "message_hdvente", "Ta mise en vente s'est vendue : +%d Berry." % gains)
	_diffuser_hdventes()

# RPC serveur : message de chat global
@rpc("any_peer", "call_remote", "reliable")
func envoie_message_chat(texte: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not _sessions.has(peer_id) or not bool(_sessions[peer_id]["embarque"]) or _trop_tot(peer_id, "chat", 300):
		return
	texte = texte.strip_edges().substr(0, 200)
	if texte == "":
		return
	var nom_envoyeur: String = _sessions[peer_id]["nom_personnage"]
	# commande /defier : lancer un défi à un autre joueur
	if texte == "/defier" or texte.begins_with("/defier "):
		var cible := texte.substr(7).strip_edges()
		if cible == "":
			rpc_id(peer_id, "recoit_message_chat", "Serveur", "Utilisation : /defier Nom du personnage")
			return
		var peer_cible := _chercher_cible(peer_id, cible)
		if peer_cible == 0:
			return
		var nom_cible: String = _sessions[peer_cible]["nom_personnage"]
		if peer_cible == peer_id:
			rpc_id(peer_id, "recoit_message_chat", "Serveur", "Se défier soi-même, vraiment ?")
			return
		if _sessions[peer_cible]["scene"] != _sessions[peer_id]["scene"]:
			rpc_id(peer_id, "recoit_message_chat", "Serveur", "Rejoins ce joueur dans sa zone pour le défier.")
			return
		if _duels.has(peer_id) or _duels.has(peer_cible):
			rpc_id(peer_id, "recoit_message_chat", "Serveur", "Un des deux joueurs est déjà en duel.")
			return
		if bool(_sessions[peer_cible].get("en_combat", false)) or bool(_sessions[peer_id].get("en_combat", false)):
			rpc_id(peer_id, "recoit_message_chat", "Serveur", "Un des deux joueurs est en plein combat.")
			return
		if _invites_duel.has(peer_cible):
			rpc_id(peer_id, "recoit_message_chat", "Serveur", "%s a déjà une invitation en attente." % nom_cible)
			return
		_invites_duel[peer_cible] = peer_id
		rpc_id(peer_id, "recoit_message_chat", "Serveur", "Tu défies %s en duel..." % nom_cible)
		rpc_id(peer_cible, "invite_duel", nom_envoyeur)
		return
	# commande /echanger : proposer un échange d'objets et de Berry
	if texte == "/echanger" or texte.begins_with("/echanger "):
		var cible_echange := texte.substr(9).strip_edges()
		if cible_echange == "":
			rpc_id(peer_id, "recoit_message_chat", "Serveur", "Utilisation : /echanger Nom du personnage")
			return
		var peer_cible_echange := _chercher_cible(peer_id, cible_echange)
		if peer_cible_echange == 0:
			return
		_proposer_echange(peer_id, peer_cible_echange)
		return
	# commande /joueurs : la liste revient en privé
	if texte == "/joueurs":
		var joueurs: PackedStringArray = []
		for autre in _sessions:
			if bool(_sessions[autre]["embarque"]):
				joueurs.append("%s (#%d)" % [_sessions[autre]["nom_personnage"], autre])
		rpc_id(peer_id, "recoit_message_chat", "Serveur",
			"En ligne (%d) : %s" % [joueurs.size(), ", ".join(joueurs)])
		return
	# commande /groupe : groupes de joueurs (sans rapport avec les
	# équipages — rejoindre ses amis quand l'équipage n'est pas co)
	# /groupe Nom du personnage -> inviter, /groupe -> liste, /groupe quitter
	if texte == "/groupe" or texte.begins_with("/groupe "):
		var argument := texte.substr(7).strip_edges()
		if argument == "":
			_repondre_liste_groupe(peer_id)
		elif argument.to_lower() == "quitter":
			_sortir_du_groupe(peer_id, true)
		else:
			_inviter_au_groupe(peer_id, argument)
		return
	# messagerie privée : /msg (alias /mp et /w) Nom message ; /r
	# répond au dernier correspondant ; /aide liste les commandes
	var commande_mp := ""
	if texte.begins_with("/msg "):
		commande_mp = texte.substr(5)
	elif texte.begins_with("/mp "):
		commande_mp = texte.substr(4)
	elif texte.begins_with("/w "):
		commande_mp = texte.substr(3)
	if commande_mp != "":
		var espace_mp := commande_mp.find(" ")
		if espace_mp <= 0:
			rpc_id(peer_id, "recoit_message_chat", "Serveur",
				"Utilisation : /msg Nom du personnage ton message")
			return
		var cible_mp := _chercher_cible(peer_id, commande_mp.substr(0, espace_mp).strip_edges())
		if cible_mp == 0:
			return
		var message_mp := commande_mp.substr(espace_mp + 1).strip_edges()
		if message_mp == "":
			rpc_id(peer_id, "recoit_message_chat", "Serveur",
				"Utilisation : /msg Nom du personnage ton message")
			return
		_envoyer_mp(peer_id, cible_mp, message_mp)
		return
	if texte == "/r" or texte.begins_with("/r "):
		var reponse_r := texte.substr(2).strip_edges()
		var dernier_pair := int(_sessions[peer_id].get("mp_de", 0))
		if dernier_pair == 0 or not _sessions.has(dernier_pair):
			rpc_id(peer_id, "recoit_message_chat", "Serveur",
				"Personne ne t'a écrit en MP pour l'instant.")
			return
		if reponse_r == "":
			rpc_id(peer_id, "recoit_message_chat", "Serveur", "Utilisation : /r ton message")
			return
		_envoyer_mp(peer_id, dernier_pair, reponse_r)
		return
	if texte == "/aide" or texte == "/help":
		rpc_id(peer_id, "recoit_message_chat", "Serveur",
			"Commandes : /msg Nom message (MP, alias /mp /w), /r message (répondre),"
			+ " /joueurs, /groupe, /defier, /echanger. Le chat sans commande est public.")
		return
	print("Chat <%s> %s" % [nom_envoyeur, texte])
	for autre in _sessions:
		rpc_id(int(autre), "recoit_message_chat", nom_envoyeur, texte)

# message privé d'un pair à l'autre : les deux voient l'échange, et /r
# sait à qui répondre (le dernier correspondant de chaque côté)
func _envoyer_mp(peer_de: int, peer_vers: int, message: String) -> void:
	if peer_de == peer_vers or not _sessions.has(peer_de) or not _sessions.has(peer_vers):
		rpc_id(peer_de, "recoit_message_chat", "Serveur", "Destinataire introuvable.")
		return
	var nom_de := str(_sessions[peer_de]["nom_personnage"])
	var nom_vers := str(_sessions[peer_vers]["nom_personnage"])
	_sessions[peer_de]["mp_vers"] = peer_vers
	_sessions[peer_vers]["mp_de"] = peer_de
	rpc_id(peer_vers, "recoit_message_chat", "[MP] %s" % nom_de, message)
	rpc_id(peer_de, "recoit_message_chat", "MP vers %s" % nom_vers, message)

# ============================================================
#  GROUPES DE JOUEURS (distinct des équipages)
# ============================================================

# le groupe du joueur : {id: peer du chef, membres: {peer: true}},
# {} s'il n'est dans aucun groupe
func _trouver_groupe(peer_id: int) -> Dictionary:
	for id_chef in _groupes:
		if (_groupes[id_chef] as Dictionary).has(peer_id):
			return {"id": int(id_chef), "membres": _groupes[id_chef]}
	return {}

# invite à rejoindre le groupe du demandeur (il en devient le chef
# s'il n'en a pas)
func _inviter_au_groupe(demandeur: int, cible: String) -> void:
	var peer_cible := _chercher_cible(demandeur, cible)
	if peer_cible == 0:
		return
	var nom_cible: String = _sessions[peer_cible]["nom_personnage"]
	if peer_cible == demandeur:
		rpc_id(demandeur, "recoit_message_chat", "Serveur",
			"Un groupe, c'est à plusieurs — invite quelqu'un d'autre.")
		return
	if not _trouver_groupe(peer_cible).is_empty():
		rpc_id(demandeur, "recoit_message_chat", "Serveur",
			"%s est déjà dans un groupe." % nom_cible)
		return
	if _invites_groupe.has(peer_cible):
		rpc_id(demandeur, "recoit_message_chat", "Serveur",
			"%s a déjà une invitation en attente." % nom_cible)
		return
	var groupe_demandeur := _trouver_groupe(demandeur)
	if not groupe_demandeur.is_empty() and groupe_demandeur["id"] != demandeur:
		rpc_id(demandeur, "recoit_message_chat", "Serveur",
			"Seul le chef du groupe peut inviter.")
		return
	if not groupe_demandeur.is_empty() and (groupe_demandeur["membres"] as Dictionary).size() >= GROUPE_TAILLE_MAX:
		rpc_id(demandeur, "recoit_message_chat", "Serveur",
			"Le groupe est plein (%d joueurs max)." % GROUPE_TAILLE_MAX)
		return
	_invites_groupe[peer_cible] = demandeur
	rpc_id(demandeur, "recoit_message_chat", "Serveur",
		"Tu invites %s dans ton groupe..." % nom_cible)
	rpc_id(peer_cible, "invite_groupe", str(_sessions[demandeur]["nom_personnage"]))

# RPC serveur : réponse à une invitation de groupe
@rpc("any_peer", "call_remote", "reliable")
func reponse_groupe(accepte: bool) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var demandeur := int(_invites_groupe.get(peer_id, 0))
	_invites_groupe.erase(peer_id)
	if demandeur == 0 or not _sessions.has(peer_id) or not _sessions.has(demandeur):
		return
	var pseudo_cible := str(_sessions[peer_id]["nom_personnage"])
	var pseudo_demandeur := str(_sessions[demandeur]["nom_personnage"])
	if not accepte:
		rpc_id(demandeur, "recoit_message_chat", "Serveur",
			"%s refuse de rejoindre le groupe." % pseudo_cible)
		return
	if not _trouver_groupe(peer_id).is_empty():
		rpc_id(demandeur, "recoit_message_chat", "Serveur",
			"%s vient de rejoindre un autre groupe." % pseudo_cible)
		return
	# le demandeur fonde son groupe s'il n'en a pas (il en est le chef)
	if not _groupes.has(demandeur):
		_groupes[demandeur] = {demandeur: true}
	var membres: Dictionary = _groupes[demandeur]
	if membres.size() >= GROUPE_TAILLE_MAX:
		rpc_id(peer_id, "recoit_message_chat", "Serveur", "Le groupe est plein.")
		return
	membres[peer_id] = true
	for membre in membres:
		rpc_id(int(membre), "recoit_message_chat", "Serveur",
			"%s a rejoint le groupe." % pseudo_cible)
	_annoncer_groupe(demandeur)
	print("Groupe de %s : %d membre(s)" % [pseudo_demandeur, membres.size()])

# le groupe de ce joueur, en texte, revient en privé
func _repondre_liste_groupe(peer_id: int) -> void:
	var groupe := _trouver_groupe(peer_id)
	if groupe.is_empty():
		rpc_id(peer_id, "recoit_message_chat", "Serveur",
			"Tu n'es dans aucun groupe. Utilise /groupe Nom du personnage pour inviter un joueur.")
		return
	var membres: Dictionary = groupe["membres"]
	var noms: Array[String] = []
	for membre in membres:
		var nom_membre := str(_sessions[membre]["nom_personnage"])
		if int(membre) == groupe["id"]:
			nom_membre += " (chef)"
		noms.append(nom_membre)
	rpc_id(peer_id, "recoit_message_chat", "Serveur",
		"Groupe (%d/%d) : %s" % [noms.size(), GROUPE_TAILLE_MAX, ", ".join(PackedStringArray(noms))])

# retire un joueur de son groupe (volontairement ou à sa déconnexion) ;
# le chef partant laisse la tête au premier membre restant, un groupe
# vide se dissout
func _sortir_du_groupe(peer_id: int, volontaire: bool) -> void:
	var groupe := _trouver_groupe(peer_id)
	if groupe.is_empty():
		if volontaire and _sessions.has(peer_id):
			rpc_id(peer_id, "recoit_message_chat", "Serveur", "Tu n'es dans aucun groupe.")
		return
	var id_chef: int = groupe["id"]
	var membres: Dictionary = _groupes[id_chef]
	var nom_partant := str(_sessions[peer_id]["nom_personnage"])
	membres.erase(peer_id)
	if volontaire:
		rpc_id(peer_id, "maj_groupe", [])
	if membres.is_empty():
		_groupes.erase(id_chef)
		if _sessions.has(peer_id) and volontaire:
			rpc_id(peer_id, "recoit_message_chat", "Serveur", "Le groupe est dissous.")
		return
	# le chef part : le premier membre restant prend la tête
	var nouveau_chef := int(membres.keys()[0])
	if id_chef == peer_id:
		_groupes.erase(id_chef)
		_groupes[nouveau_chef] = membres
		for membre in membres:
			if not _pair_connecte(int(membre)):
				continue
			rpc_id(int(membre), "recoit_message_chat", "Serveur",
				"%s mène désormais le groupe." % str(_sessions[nouveau_chef]["nom_personnage"]))
	for membre in membres:
		if not _pair_connecte(int(membre)):
			continue
		rpc_id(int(membre), "recoit_message_chat", "Serveur",
			"%s %s le groupe." % [nom_partant, "a quitté" if volontaire else "a quitté (déconnexion)"])
	_annoncer_groupe(nouveau_chef)
	# le chef parti volontairement apprend la passation
	if _sessions.has(peer_id) and volontaire and id_chef == peer_id:
		rpc_id(peer_id, "recoit_message_chat", "Serveur",
			"%s prend la tête du groupe." % str(_sessions[nouveau_chef]["nom_personnage"]))

# diffuse la composition du groupe à ses membres (interface + couleur)
func _annoncer_groupe(id_chef: int) -> void:
	var membres: Dictionary = _groupes.get(id_chef, {})
	var liste: Array = []
	for membre in membres:
		liste.append({"peer": int(membre), "pseudo": str(_sessions[membre]["nom_personnage"]),
			"chef": int(membre) == id_chef,
			"combat": bool(_sessions[int(membre)].get("en_combat", false))})
	for membre in membres:
		if _pair_connecte(int(membre)):
			rpc_id(int(membre), "maj_groupe", liste)

# ============================================================
#  ÉQUIPAGES EN LIGNE (serveur-autoritaires)
# ============================================================

# instantané complet de l'état équipage d'un joueur : son équipage,
# les membres, le journal, les autres équipages (avec effectifs) et
# sa flotte — tout l'onglet Équipage du client en découle ; le
# paramètre est le nom du personnage du joueur (l'identité des
# équipages, pas le pseudo du compte)
func _snapshot_equipage(nom_personnage: String) -> String:
	if nom_personnage.is_empty():
		return "{}"
	var joueur_avant := Equipages.joueur_courant
	var equipage_avant := Equipages.mon_equipage
	Equipages.joueur_courant = nom_personnage
	Equipages._recharger_mon_equipage()
	if not Equipages.mon_equipage.is_empty():
		Equipages.mon_equipage["flotte_navires"] = Equipages.liste_galions()
		var galion := Equipages.galion_du_joueur(nom_personnage)
		Equipages.mon_equipage["modules_galion"] = Equipages.donnees_galion(galion).get("equipement", {})
	var instantané := {
		"equipage": Equipages.mon_equipage,
		"membres": Equipages.liste_membres(),
		"journal": Equipages.liste_journal(),
		"autres": Equipages.autres_equipages(),
		"flotte": Equipages.ma_flotte(),
		"membres_flotte": Equipages.membres_de_ma_flotte(),
	}
	Equipages.joueur_courant = joueur_avant
	Equipages.mon_equipage = equipage_avant
	return JSON.stringify(instantané)

# pousse son instantané à chaque membre en ligne d'un équipage
# (les membres sont identifiés par leur nom de personnage)
func _diffuser_equipage(id_equipage: int) -> void:
	for nom_membre in Equipages.noms_de_l_equipage(id_equipage):
		var peer_membre := _peer_du_nom_personnage(str(nom_membre))
		if peer_membre != 0:
			rpc_id(peer_membre, "maj_equipage", _snapshot_equipage(str(nom_membre)))

func _diffuser_annuaire_equipages() -> void:
	for peer_id: int in _sessions:
		var nom_personnage := str(_sessions[peer_id].get("nom_personnage", ""))
		if not nom_personnage.is_empty():
			rpc_id(peer_id, "maj_equipage", _snapshot_equipage(nom_personnage))

# les équipages créés avant l'identification par personnage référençaient
# le pseudo du compte : une réécriture unique les passe aux noms de
# personnages (chaque compte qui possède un perso fournit la
# correspondance pseudo -> nom) ; le marqueur posé en fin évite tout
# second passage même après redémarrage
func _migrer_equipages_noms_personnage() -> void:
	Equipages._ecrire("CREATE TABLE IF NOT EXISTS _meta_equipages (cle TEXT PRIMARY KEY, valeur TEXT);")
	for ligne in Equipages._lire("SELECT valeur FROM _meta_equipages WHERE cle = 'identite_membres';"):
		if str(ligne.get("valeur", "")) == "nom_personnage":
			return
	var noms: Dictionary = {}
	for ligne in _lire(
			"SELECT c.pseudo AS pseudo, p.donnees AS donnees"
			+ " FROM mmo_comptes c JOIN mmo_persos p ON p.compte_id = c.id;"):
		var donnees: Variant = JSON.parse_string(str(ligne["donnees"]))
		if donnees is Dictionary and str(donnees.get("nom", "")) != "":
			noms[str(ligne["pseudo"])] = str(donnees.get("nom"))
	if not noms.is_empty():
		print("Équipages : réécriture vers les noms de personnages (%d comptes migrés)." % noms.size())
	for pseudo_compte in noms:
		var nom_perso := str(noms[pseudo_compte])
		Equipages._ecrire("UPDATE equipages SET capitaine = '%s' WHERE capitaine = '%s';" % [
			Equipages._echapper(nom_perso), Equipages._echapper(str(pseudo_compte))])
		Equipages._ecrire("UPDATE equipages_membres SET nom_joueur = '%s' WHERE nom_joueur = '%s';" % [
			Equipages._echapper(nom_perso), Equipages._echapper(str(pseudo_compte))])
	Equipages._ecrire("INSERT OR REPLACE INTO _meta_equipages (cle, valeur) VALUES ('identite_membres', 'nom_personnage');")

# JSON du perso serveur d'un compte (dictionnaire vide si absent ou
# illisible : le joueur n'a pas encore créé son personnage)
func _perso_json_serveur(compte: Dictionary) -> Dictionary:
	var perso: Dictionary = {}
	if compte.is_empty():
		return perso
	var analyse: Variant = JSON.parse_string(_perso_du_serveur(int(compte["id"])))
	if analyse is Dictionary:
		perso = analyse
	return perso

# RPC serveur : action d'équipage demandée par un client (le serveur
# tranche seul : jamais d'écriture directe côté client en ligne)
@rpc("any_peer", "call_remote", "reliable")
func demande_equipage(action: String, argument: String, montant: int) -> void:
	if not multiplayer.is_server():
		return
	var session := _pair_authentifie()
	if session.is_empty():
		return
	var peer_id := int(session["peer_id"])
	var pseudo_pair := str(session["pseudo"])
	# l'identité des équipages est le nom du personnage : un compte
	# sans perso ne peut pas encore agir sur un équipage
	var nom_joueur := str(_sessions[peer_id].get("nom_personnage", ""))
	if nom_joueur.is_empty():
		if action == "deposer" or action == "retirer":
			rpc_id(peer_id, "resultat_bourse_equipage", 0, "Crée d’abord ton personnage.")
		else:
			rpc_id(peer_id, "message_equipage", "Crée d’abord ton personnage.")
		return
	Equipages.joueur_courant = nom_joueur
	Equipages._recharger_mon_equipage()
	match action:
		"creer":
			var erreur_creer := Equipages.creer(argument)
			if erreur_creer != "":
				rpc_id(peer_id, "message_equipage", erreur_creer)
			else:
				_diffuser_annuaire_equipages()
		"dissoudre":
			if not Equipages.suis_capitaine():
				rpc_id(peer_id, "message_equipage", "Vous n'êtes capitaine d'aucun équipage")
			else:
				Equipages.dissoudre()
				if Equipages.mon_equipage.is_empty():
					_diffuser_annuaire_equipages()
				else:
					rpc_id(peer_id, "message_equipage", "Impossible de dissoudre l’équipage.")
		"quitter":
			if Equipages.mon_equipage.is_empty():
				rpc_id(peer_id, "message_equipage", "Vous n'êtes dans aucun équipage")
			else:
				var membres_quittes := Equipages.noms_de_l_equipage(int(Equipages.mon_equipage["id"]))
				Equipages.quitter()
				for nom_membre in membres_quittes:
					var peer_membre := _peer_du_nom_personnage(str(nom_membre))
					if peer_membre != 0:
						rpc_id(peer_membre, "maj_equipage", _snapshot_equipage(str(nom_membre)))
		"ajouter":
			_inviter_dans_equipage(peer_id, nom_joueur, argument)
		"virer":
			if Equipages.mon_equipage.is_empty():
				rpc_id(peer_id, "message_equipage", "Vous n'êtes dans aucun équipage")
			else:
				var erreur_virer := Equipages.virer(argument)
				if erreur_virer != "":
					rpc_id(peer_id, "message_equipage", erreur_virer)
				else:
					var membres_vires := Equipages.noms_de_l_equipage(int(Equipages.mon_equipage["id"]))
					membres_vires.append(argument.strip_edges())
					for nom_membre in membres_vires:
						var peer_membre := _peer_du_nom_personnage(str(nom_membre))
						if peer_membre != 0:
							rpc_id(peer_membre, "maj_equipage", _snapshot_equipage(str(nom_membre)))
		"nommer_vice":
			var erreur_vice := Equipages.nommer_vice(argument)
			if erreur_vice != "":
				rpc_id(peer_id, "message_equipage", erreur_vice)
			elif not Equipages.mon_equipage.is_empty():
				_diffuser_equipage(int(Equipages.mon_equipage["id"]))
		"destituer_vice":
			var erreur_destituer := Equipages.destituer_vice()
			if erreur_destituer != "":
				rpc_id(peer_id, "message_equipage", erreur_destituer)
			elif not Equipages.mon_equipage.is_empty():
				_diffuser_equipage(int(Equipages.mon_equipage["id"]))
		"description":
			var erreur_description := Equipages.changer_description(argument)
			if erreur_description != "":
				rpc_id(peer_id, "message_equipage", erreur_description)
			elif not Equipages.mon_equipage.is_empty():
				_diffuser_equipage(int(Equipages.mon_equipage["id"]))
		"deposer", "retirer":
			_equipage_bourse(peer_id, pseudo_pair, montant, action == "deposer")
		"acheter_galions":
			var modele := argument if not argument.is_empty() else "ateliers"
			var erreur := Equipages.acheter_galions(montant, modele)
			if erreur.is_empty():
				_diffuser_equipage(int(Equipages.mon_equipage["id"]))
				rpc_id(peer_id, "message_equipage", "Flotte mise à jour.")
			else:
				rpc_id(peer_id, "message_equipage", erreur)
		"assigner_galion", "choisir_galion":
			var erreur := Equipages.assigner_galion(montant, argument) if action == "assigner_galion" \
				else Equipages.choisir_galion(montant, argument)
			if erreur.is_empty():
				_diffuser_equipage(int(Equipages.mon_equipage["id"]))
			else:
				rpc_id(peer_id, "message_equipage", erreur)
		"virement", "alliance", "accepter_alliance", "refuser_alliance", "guerre", "lever_guerre":
			_action_equipage_cible(peer_id, action, argument, montant)
		"rompre":
			_rompre_alliance_equipage(peer_id)
	Equipages.joueur_courant = ""
	if action in ["assigner_galion", "dissoudre", "quitter", "virer"]:
		Navires.equipage_modifie()

# le recrutement devient une invitation : la cible reçoit une popup
# (l'émetteur et la cible sont identifiés par leur nom de personnage)
func _inviter_dans_equipage(peer_id: int, nom_demandeur: String, cible_nom: String) -> void:
	var cible := cible_nom.strip_edges()
	if cible.to_lower() == nom_demandeur.to_lower():
		rpc_id(peer_id, "message_equipage", "On ne se recrute pas soi-même !")
		return
	var erreur := Equipages._valider_recrutement(cible)
	if erreur != "":
		rpc_id(peer_id, "message_equipage", erreur)
		return
	if Equipages._deja_engage(cible):
		rpc_id(peer_id, "message_equipage", "%s fait déjà partie d'un équipage." % cible)
		return
	var peer_cible := _peer_du_nom_personnage(cible)
	if peer_cible == 0:
		rpc_id(peer_id, "message_equipage", "%s n'est pas en ligne." % cible)
		return
	if _invites_equipage.has(peer_cible):
		rpc_id(peer_id, "message_equipage", "%s a déjà une invitation en attente." % cible)
		return
	_invites_equipage[peer_cible] = {"demandeur": nom_demandeur, "cible": cible}
	rpc_id(peer_id, "message_equipage", "Invitation envoyée à %s..." % cible)
	rpc_id(peer_cible, "invite_equipage", str(Equipages.mon_equipage.get("nom", "?")), nom_demandeur)

# RPC serveur : réponse à une invitation de recrutement
@rpc("any_peer", "call_remote", "reliable")
func reponse_equipage_recruit(accepte: bool) -> void:
	if not multiplayer.is_server():
		return
	var session := _pair_authentifie()
	if session.is_empty():
		return
	var peer_id := int(session["peer_id"])
	var nom_pair := str(_sessions[peer_id].get("nom_personnage", ""))
	var invitation_lue: Variant = _invites_equipage.get(peer_id, {})
	_invites_equipage.erase(peer_id)
	if not invitation_lue is Dictionary:
		return
	var invitation: Dictionary = invitation_lue
	var demandeur := str(invitation["demandeur"])
	var cible := str(invitation["cible"])
	var peer_demandeur := _peer_du_nom_personnage(demandeur)
	if peer_demandeur == 0:
		return  # le capitaine s'est déconnecté, l'invitation tombe
	if not accepte:
		rpc_id(peer_demandeur, "message_equipage", "%s refuse de rejoindre l'équipage." % nom_pair)
		return
	# re-validation côté demandeur puis ajout effectif
	Equipages.joueur_courant = demandeur
	Equipages._recharger_mon_equipage()
	var erreur := Equipages._valider_recrutement(cible)
	if erreur != "":
		rpc_id(peer_demandeur, "message_equipage", erreur)
	else:
		var erreur_ajout := Equipages.ajouter_membre(cible)
		if erreur_ajout != "":
			rpc_id(peer_demandeur, "message_equipage", erreur_ajout)
		else:
			_diffuser_equipage(int(Equipages.mon_equipage["id"]))
			# la cible vient d'entrer dans l'équipage : son état change aussi
			rpc_id(peer_id, "maj_equipage", _snapshot_equipage(cible))
			rpc_id(peer_demandeur, "message_equipage", "%s rejoint l'équipage !" % cible)
	Equipages.joueur_courant = ""

# Une transaction SQLite couvre la bourse serveur, la caisse et le journal.
func _equipage_bourse(peer_id: int, pseudo_pair: String, montant: int, depot: bool) -> void:
	if not Equipages.montant_valide(montant):
		rpc_id(peer_id, "resultat_bourse_equipage", 0, "Montant invalide.")
		return
	var compte := _compte(pseudo_pair)
	var perso := _perso_json_serveur(compte)
	if perso.is_empty():
		rpc_id(peer_id, "resultat_bourse_equipage", 0, "Personnage introuvable.")
		return
	var delta := -montant if depot else montant
	var solde := int(perso.get("berry", 0)) + delta
	if solde < 0:
		rpc_id(peer_id, "resultat_bourse_equipage", 0, "Pas assez de Berry dans votre bourse.")
		return
	perso["berry"] = solde
	var erreur := Equipages.echanger_bourse(-delta, int(compte["id"]), JSON.stringify(perso))
	if not erreur.is_empty():
		rpc_id(peer_id, "resultat_bourse_equipage", 0, erreur)
		return
	var message := "%d Berry déposés." if depot else "%d Berry retirés."
	_diffuser_equipage(int(Equipages.mon_equipage["id"]))
	rpc_id(peer_id, "resultat_bourse_equipage", delta, message % montant)

func _action_equipage_cible(peer_id: int, action: String, argument: String, montant: int) -> void:
	var id_equipage := int(Equipages.mon_equipage.get("id", 0))
	if id_equipage == 0 or not argument.is_valid_int():
		rpc_id(peer_id, "message_equipage", "Équipage introuvable.")
		return
	var id_cible := int(argument)
	var erreur := ""
	var succes := ""
	match action:
		"virement":
			erreur = Equipages.virer_berry(id_cible, montant)
			succes = "Virement envoyé."
		"alliance":
			erreur = Equipages.proposer_alliance(id_cible)
			succes = "Demande d’alliance envoyée."
		"accepter_alliance":
			erreur = Equipages.repondre_alliance(id_cible, true)
			succes = "Alliance conclue."
		"refuser_alliance":
			erreur = Equipages.repondre_alliance(id_cible, false)
			succes = "Proposition d’alliance close."
		"guerre":
			erreur = Equipages.declarer_guerre(id_cible)
			succes = "Guerre déclarée."
		"lever_guerre":
			erreur = Equipages.lever_guerre(id_cible)
			succes = "Déclaration de guerre levée."
	if not erreur.is_empty():
		rpc_id(peer_id, "message_equipage", erreur)
		return
	var touches := {id_equipage: true, id_cible: true}
	if action == "accepter_alliance":
		for id: int in Equipages.equipages_de_la_flotte_de(id_equipage):
			touches[id] = true
	for id: int in touches:
		_diffuser_equipage(id)
	rpc_id(peer_id, "message_equipage", succes)

# rupture d'alliance : les équipages concernés se rafraîchissent
func _rompre_alliance_equipage(peer_id: int) -> void:
	if Equipages.mon_equipage.is_empty():
		rpc_id(peer_id, "message_equipage", "Vous n'êtes pas engagé dans un équipage")
		return
	var equipages_touches := Equipages.equipages_de_la_flotte_de(int(Equipages.mon_equipage["id"]))
	var erreur := Equipages.rompre_alliance()
	if erreur != "":
		rpc_id(peer_id, "message_equipage", erreur)
		return
	for id_equipage in equipages_touches:
		_diffuser_equipage(int(id_equipage))
	rpc_id(peer_id, "message_equipage", "Alliance quittée.")

# le statut en combat d'un membre apparaît dans le panneau du groupe :
# on rediffuse la composition après chaque changement
func _annoncer_groupes_du_pair(peer_id: int) -> void:
	var groupe := _trouver_groupe(peer_id)
	if not groupe.is_empty():
		_annoncer_groupe(int(groupe["id"]))

# RPC serveur : un joueur veut rejoindre le combat en cours d'un membre
# de son groupe (bouton « Rejoindre » du panneau GROUPE)
@rpc("any_peer", "call_remote", "reliable")
func demande_rejoindre_combat(peer_cible: int) -> void:
	if not multiplayer.is_server():
		return
	var session := _pair_authentifie()
	if session.is_empty():
		return
	var peer_id := int(session["peer_id"])
	if peer_id == peer_cible or not _sessions.has(peer_cible):
		return
	var cible: Dictionary = _sessions[peer_cible]
	var nom_cible := str(cible["nom_personnage"])
	if bool(_sessions[peer_id].get("en_combat", false)):
		return  # déjà occupé : le bouton disparaîtra au prochain tour d'annonce
	if not bool(cible.get("en_combat", false)):
		rpc_id(peer_id, "recoit_message_chat", "Serveur",
			"%s n'est plus en combat." % nom_cible)
		return
	var combat_cible := str(cible.get("combat_groupe", ""))
	if combat_cible == "":
		rpc_id(peer_id, "recoit_message_chat", "Serveur",
			"%s est dans un combat qui ne se rejoint pas." % nom_cible)
		return
	# un combat démarré (placement validé) ne se rejoint plus
	if _combats_lances.has(_cle_combat_groupe(peer_cible, str(cible["scene"]), combat_cible)):
		rpc_id(peer_id, "recoit_message_chat", "Serveur",
			"Le combat de %s est déjà lancé : impossible de le rejoindre." % nom_cible)
		return
	if str(cible["scene"]) != str(_sessions[peer_id]["scene"]):
		rpc_id(peer_id, "recoit_message_chat", "Serveur",
			"Rejoins la même map que %s pour combattre à ses côtés." % nom_cible)
		return
	# on ne rejoint le combat d'un joueur que si on est dans son groupe
	# de joueurs (mention « Rejoindre » du panneau GROUPE)
	var groupe_demandeur := _trouver_groupe(peer_id)
	var groupe_cible := _trouver_groupe(peer_cible)
	if groupe_demandeur.is_empty() or groupe_cible.is_empty() \
			or int(groupe_demandeur["id"]) != int(groupe_cible["id"]):
		rpc_id(peer_id, "recoit_message_chat", "Serveur",
			"Seuls les membres du groupe de %s rejoignent son combat." % nom_cible)
		return
	# validé : le client engage ce camp dans sa propre instance
	rpc_id(peer_id, "rejoindre_combat_permis", combat_cible)

# NETTOYAGE : un pair se déconnecte
func _pair_connecte(peer_id: int) -> bool:
	var serveur := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if serveur == null or peer_id not in multiplayer.get_peers():
		return false
	var pair := serveur.get_peer(peer_id)
	return pair != null and pair.get_state() == ENetPacketPeer.STATE_CONNECTED

func _nettoyer_session(peer_id: int) -> void:
	if not _sessions.has(peer_id):
		return
	# un duel en cours se solde par forfait du fuyard
	if _duels.has(peer_id):
		var adversaire := int(_duels[peer_id])
		var nom_fuyard := str(_sessions[peer_id]["nom_personnage"])
		_fin_duel(peer_id)
		if _pair_connecte(adversaire):
			rpc_id(adversaire, "victoire_duel", nom_fuyard, true)
	# un échange en cours tombe, son partenaire est prévenu
	if _echanges.has(peer_id):
		var partenaire_echange := int(_echanges[peer_id])
		var nom_parti_echange := str(_sessions[peer_id]["nom_personnage"])
		_cloturer_echange(peer_id, partenaire_echange)
		if _pair_connecte(partenaire_echange):
			rpc_id(partenaire_echange, "fin_echange", "Échange interrompu : %s a déconnecté." % nom_parti_echange)
	_invites_echange.erase(peer_id)
	for cible_invite_echange in _invites_echange.keys():
		if int(_invites_echange[cible_invite_echange]) == peer_id:
			_invites_echange.erase(cible_invite_echange)
	# son groupe de joueurs l'oublie (partance de tête si nécessaire)
	# son combat de groupe l'oublie : les autres perdent son miroir ;
	# vide, il redevient rejoignable
	for cle in _membres_groupe.keys():
		var membres_combat: Dictionary = _membres_groupe[cle]
		if not membres_combat.has(peer_id):
			continue
		membres_combat.erase(peer_id)
		for autre in membres_combat:
			if _pair_connecte(int(autre)):
				rpc_id(int(autre), "sortie_combat_groupe", peer_id)
		if membres_combat.is_empty():
			_membres_groupe.erase(cle)
			_combats_lances.erase(cle)
			_prets_combat.erase(cle)
	_sortir_du_groupe(peer_id, false)
	_liberer_combats(peer_id)
	_invites_groupe.erase(peer_id)
	_invites_equipage.erase(peer_id)
	var session: Dictionary = _sessions[peer_id]
	var nom_quittant: String = session["nom_personnage"]
	_sessions.erase(peer_id)
	Navires.deconnexion_serveur(peer_id, str(session.get("port_navire", "")))
	_limiteurs.erase(peer_id)
	_positions_a_relais.erase(peer_id)
	print("Déconnexion : %s (%d joueur(s) en ligne)" % [session["pseudo"], _sessions.size()])
	for autre in _sessions:
		if not _pair_connecte(int(autre)):
			continue
		rpc_id(int(autre), "joueur_quitte", peer_id)
		if bool(session["embarque"]) and bool(_sessions[autre]["embarque"]):
			rpc_id(int(autre), "recoit_message_chat", "Serveur", "%s a débarqué." % nom_quittant)

# ============================================================
#  CLIENT
# ============================================================

# se connecte à un serveur "ip:port" (port optionnel, 7777 par défaut)
func demarrer_client(adresse_recue: String) -> bool:
	var adresse := adresse_recue.strip_edges()
	var port := PORT_DEFAUT
	if adresse.contains(":"):
		var morceaux := adresse.split(":")
		if morceaux.size() != 2 or not morceaux[1].is_valid_int():
			return false
		adresse = morceaux[0].strip_edges()
		port = int(morceaux[1])
	if adresse.is_empty() or port <= 0 or port > 65535:
		return false
	var hote := IP.resolve_hostname(adresse, IP.TYPE_IPV4)
	if hote == "":
		hote = IP.resolve_hostname(adresse, IP.TYPE_IPV6)
	if hote == "":
		return false
	# toujours repartir d'un pair neuf et vider les caches du
	# SceneMultiplayer : réutiliser un pair refermé désynchronise les
	# caches de nœuds et le serveur jette ensuite tous nos RPC
	var pair := multiplayer.multiplayer_peer
	if pair != null:
		pair.close()
	multiplayer.multiplayer_peer = null
	multiplayer.clear()
	var peer := ENetMultiplayerPeer.new()
	# le pair doit d'abord établir la connexion avant d'être confié
	# au SceneTree (sinon il est rejeté)
	if peer.create_client(hote, port) != OK:
		return false
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	return true

func _on_connecte_au_serveur() -> void:
	# la première requête part avec un léger délai : le serveur doit
	# d'abord mettre notre nœud en cache, sinon le RPC part dans le
	# vide (course au handshake ENet) ; _process renverra au besoin
	_attente_auth = 0.0
	_tentatives_auth = 0

# Envoie la requête après la connexion ENet et la renvoie si nécessaire.
func _envoyer_requete_auth() -> void:
	var requete := "demande_inscription" if _action_en_attente == "inscription" else "demande_connexion"
	rpc_id(1, requete, _pseudo_auth, _mot_de_passe_auth)
	_attente_auth = 0.0
	_tentatives_auth += 1

func _client_piloter_auth(delta: float) -> void:
	_attente_auth += delta
	var pair := multiplayer.multiplayer_peer
	if pair == null or pair.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		if _attente_auth >= DELAI_CONNEXION:
			_echouer_authentification("Le serveur est injoignable. Vérifie son adresse.")
		return
	if _tentatives_auth == 0:
		if _attente_auth >= 0.25:
			_envoyer_requete_auth()
	elif _attente_auth >= 2.0:
		if _tentatives_auth >= 4:
			_echouer_authentification("Le serveur ne répond pas.")
		else:
			_envoyer_requete_auth()

func _effacer_tentative_auth() -> void:
	_action_en_attente = ""
	_adresse_auth = ""
	_pseudo_auth = ""
	_mot_de_passe_auth = ""
	_attente_auth = 0.0
	_tentatives_auth = 0

# Déconnecte le compte et restaure le personnage solo s’il était chargé.
func fermer_connexion() -> void:
	_effacer_tentative_auth()
	var peer := multiplayer.multiplayer_peer
	if peer != null:
		peer.close()
	multiplayer.multiplayer_peer = null
	multiplayer.clear()
	pseudo = ""
	mode = Mode.HORS_LIGNE
	_bourse_equipage_en_attente = false
	_scene_locale = ""
	Navires.reinitialiser()
	_annonces_en_attente.clear()
	etat_rencontres_recu.clear()
	combat_groupe_local = ""
	invitation_en_attente.clear()
	# le groupe de joueurs ne survit pas à la déconnexion
	groupe_local = []
	_maj_panneau_groupe()
	_groupe_ui.cacher_invite_groupe()
	_cacher_invite_equipage()
	_cacher_invite_echange()
	_fermer_fenetre_echange()
	_retirer_tous_avatars()
	_cacher_invitation()
	_cacher_invite_duel()
	_fermer_chat(false)
	_chat.hide()
	_chat_log.clear()
	if Personnage.en_ligne:
		_retablir_perso_local()
	if Coffres.en_ligne or CartesTresor.en_ligne or Equipages.en_ligne or HotelVentes.en_ligne:
		_retablir_ressources_partagees()
	get_tree().paused = false

func _on_echec_connexion() -> void:
	if not _action_en_attente.is_empty():
		_echouer_authentification("Impossible de joindre le serveur.")

func _on_serveur_perdu() -> void:
	if not _action_en_attente.is_empty():
		_echouer_authentification("Connexion au serveur perdue.")
	elif mode == Mode.CLIENT:
		revenir_accueil("Connexion au serveur perdue.")

func _echouer_authentification(message: String) -> void:
	fermer_connexion()
	authentification_resultat.emit(false, message)

# Le personnage solo reprend sa place en mémoire au départ du compte.
func _retablir_perso_local() -> void:
	Personnage.en_ligne = false
	Inventaire.recharger_etat_local()
	Personnage.reinitialiser()
	Personnage.charger_perso()

# Les coffres du monde et les croix en ligne quittent la mémoire : la
# sauvegarde locale redevient la référence, comme hors ligne.
func _retablir_ressources_partagees() -> void:
	Coffres.recharger_etat_local()
	CartesTresor.recharger_etat_local()
	Equipages.recharger_etat_local()
	HotelVentes.recharger_etat_local()

# RPC client : réponse d'inscription/connexion (le perso suit si connu)
@rpc("any_peer", "call_remote", "reliable")
func reponse_authentification(ok: bool, message: String, perso_json: String) -> void:
	if multiplayer.is_server() or _action_en_attente.is_empty():
		return
	if not ok:
		_echouer_authentification(message)
		return
	pseudo = _pseudo_auth
	pseudo_prefere = pseudo
	adresse_preferee = _adresse_auth
	_effacer_tentative_auth()
	sauvegarder_preferences()
	Personnage.en_ligne = true
	# ressources partagées : coffres du monde et croix au trésor
	# vivent sur le serveur pendant la session
	Coffres.basculer_en_ligne()
	CartesTresor.basculer_en_ligne()
	Equipages.basculer_en_ligne()
	HotelVentes.basculer_en_ligne()
	if perso_json != "":
		_appliquer_perso(perso_json)
	else:
		Personnage.reinitialiser()
		Inventaire.basculer_en_ligne(null, null)
	authentification_resultat.emit(true, message)
	print("Connecté en tant que %s." % pseudo)

# RPC client : un joueur arrive (avatar visible)
@rpc("any_peer", "call_remote", "reliable")
func joueur_rejoint(peer_id: int, nom_recu: String, x: float, y: float, en_combat: bool, visuel := VISUEL_DEFAUT) -> void:
	if multiplayer.is_server():
		return
	if get_tree().current_scene == null:
		_annonces_en_attente.append(
			{"id": peer_id, "nom": nom_recu, "x": x, "y": y, "combat": en_combat, "visuel": str(visuel)})
		return
	if _scene_locale != str(get_tree().current_scene.name) and not (
			get_tree().current_scene.scene_file_path == Personnage.SCENE_NAVIRE and _scene_locale.begins_with("Lanterne:")):
		return
	_maj_avatar(peer_id, nom_recu, Vector2(x, y), str(visuel))
	if is_instance_valid(_avatars.get(peer_id)):
		(_avatars[peer_id] as Node2D).maj_combat(en_combat)

# des joueurs ont ete annonces pendant que la scene locale etait
# indisponible (login, chargement) : les afficher desormais
func _client_appliquer_annonces_attente() -> void:
	if _annonces_en_attente.is_empty() or get_tree().current_scene == null:
		return
	var attente := _annonces_en_attente
	_annonces_en_attente = []
	for entree in attente:
		_maj_avatar(int(entree["id"]), str(entree["nom"]),
			Vector2(float(entree["x"]), float(entree["y"])),
			str(entree.get("visuel", VISUEL_DEFAUT)))
		if is_instance_valid(_avatars.get(int(entree["id"]))):
			(_avatars[int(entree["id"])] as Node2D).maj_combat(bool(entree["combat"]))

# RPC client : l'etat de combat d'un joueur change
@rpc("any_peer", "call_remote", "reliable")
func etre_en_combat(peer_id: int, actif: bool) -> void:
	if multiplayer.is_server():
		return
	if is_instance_valid(_avatars.get(peer_id)):
		(_avatars[peer_id] as Node2D).maj_combat(actif)

# RPC client : un joueur part
@rpc("any_peer", "call_remote", "reliable")
func joueur_quitte(peer_id: int) -> void:
	if multiplayer.is_server():
		return
	_retirer_avatar(peer_id)

# RPC client : paquet de positions ~10 Hz
@rpc("any_peer", "call_remote", "unreliable")
func maj_positions(paquet: Array) -> void:
	if multiplayer.is_server():
		return
	var identifiant := multiplayer.get_unique_id()
	for entree in paquet:
		var id_distant := int(entree["id"])
		if id_distant == identifiant or not is_instance_valid(_avatars.get(id_distant)):
			continue
		(_avatars[id_distant] as Node2D).viser(Vector2(float(entree["x"]), float(entree["y"])))

# RPC client : message de chat
@rpc("any_peer", "call_remote", "reliable")
func recoit_message_chat(nom_recu: String, texte: String) -> void:
	if multiplayer.is_server():
		return
	chat_recu.emit(nom_recu, texte)
	_chat_log.push_color(Color("#ffd166"))
	_chat_log.push_bold()
	_chat_log.add_text(nom_recu)
	_chat_log.pop()
	_chat_log.pop()
	_chat_log.add_text(" : %s\n" % texte)

# --- envois périodiques du client ---

func _joueur_local() -> Node2D:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.find_child("player", true, false) as Node2D

func _client_envoyer_position(delta: float) -> void:
	_temps_position += delta
	if _temps_position < FREQUENCE_POSITION:
		return
	_temps_position = 0.0
	var joueur := _joueur_local()
	if joueur == null or not is_instance_valid(joueur):
		return
	# en combat, le joueur vit dans l'arène : ses coordonnées ne sont
	# plus celles de la map — les envoyer téléporterait son avatar chez
	# les autres au milieu de leur arène (le même joueur y apparaissait
	# deux fois : son avatar de map et son miroir de combat)
	var scene := get_tree().current_scene
	if scene != null:
		var combat: Node = scene.get_node_or_null("CombatManager")
		if combat != null and bool(combat.get("en_combat")):
			return
	if joueur.global_position.distance_to(_derniere_position_envoyee) < 4.0:
		return
	_derniere_position_envoyee = joueur.global_position
	rpc_id(1, "envoie_position", float(joueur.global_position.x), float(joueur.global_position.y), _scene_locale)

# le joueur change de map : la nouvelle scene part au serveur, qui
# renvoie l'etat des rencontres vaincues a cet endroit
func _client_annoncer_scene() -> void:
	var scene := get_tree().current_scene
	var joueur := _joueur_local()
	if scene == null or joueur == null or not Personnage.perso_cree:
		return
	var nom := str(scene.name)
	if scene.scene_file_path == Personnage.SCENE_NAVIRE:
		nom = "Lanterne:%d" % (Navires.hote if Navires.hote != 0 else multiplayer.get_unique_id())
	if nom == _scene_locale:
		return
	_retirer_tous_avatars()
	_annonces_en_attente.clear()
	etat_rencontres_recu.clear()
	invitation_en_attente.clear()
	_cacher_invitation()
	_scene_locale = nom
	_chat.show()
	var combat := scene.get_node_or_null("CombatManager")
	if combat != null and not combat.placement_commence.is_connected(_sur_placement_groupe):
		combat.placement_commence.connect(_sur_placement_groupe)
		combat.combat_termine.connect(_sur_fin_combat_groupe)
	_groupe_ui.actualiser_actions_combat(_combat_joinable())
	_derniere_position_envoyee = joueur.global_position
	if joueur.has_method("_prefixe_visuel_race"):
		rpc_id(1, "annonce_visuel", str(joueur.call("_prefixe_visuel_race")))
	rpc_id(1, "envoie_scene", nom, joueur.global_position.x, joueur.global_position.y, scene.scene_file_path.get_file().get_basename())
	Navires.entree_locale(scene.scene_file_path)

# RPC client : etat du monde recu (rencontres deja vaincues sur la map)
@rpc("any_peer", "call_remote", "reliable")
func etat_rencontres(cles: Array, nom_scene: String = "") -> void:
	if multiplayer.is_server() or (nom_scene != "" and nom_scene != _scene_locale):
		return
	etat_rencontres_recu = []
	for cle in cles:
		etat_rencontres_recu.append(str(cle))
		cacher_rencontre(str(cle))

# RPC client : une rencontre vient d'etre vaincue par un joueur de la
# meme map
@rpc("any_peer", "call_remote", "reliable")
func rencontre_vaincue(cle: String) -> void:
	if multiplayer.is_server():
		return
	cacher_rencontre(cle)

# RPC client : une rencontre vaincue reapparait
@rpc("any_peer", "call_remote", "reliable")
func rencontre_revient(cle: String) -> void:
	if multiplayer.is_server():
		return
	reviver_rencontre(cle)

# --- coffres du monde partagés (côté client) ---

# RPC client : le serveur fait foi sur ce coffre — réponse à notre
# ouverture ou évolution diffusée à toute la map (prise par autrui)
@rpc("any_peer", "call_remote", "reliable")
func coffre_etat(coffre_id: String, contenu_json: String) -> void:
	if multiplayer.is_server():
		return
	Coffres.maj_etat_distant(coffre_id, contenu_json)

# RPC client : prise confirmée par le serveur (objet ou vidage que nous
# avons demandés) — créditée à l'inventaire par l'autoload Coffres
@rpc("any_peer", "call_remote", "reliable")
func coffre_prise(prises_json: String) -> void:
	if multiplayer.is_server():
		return
	Coffres.recevoir_prise_distante(prises_json)

# RPC client : état des coffres du monde à l'arrivée sur une map
@rpc("any_peer", "call_remote", "reliable")
func etat_coffres(etat_json: String) -> void:
	if multiplayer.is_server():
		return
	Coffres.appliquer_etat_scene(etat_json)

# API appelée par Coffres : demande d'ouverture au serveur
func demander_ouverture_coffre(coffre_id: String, rarete: int) -> void:
	if mode != Mode.CLIENT or pseudo == "":
		return
	rpc_id(1, "envoie_ouvrir_coffre", coffre_id, clampi(rarete, 1, 4))

# API appelée par Coffres : demande de prise d'un objet
func demander_prise_coffre(coffre_id: String, index: int) -> void:
	if mode != Mode.CLIENT or pseudo == "":
		return
	rpc_id(1, "envoie_prendre_objet_coffre", coffre_id, index)

# API appelée par Coffres : demande de vidage complet
func demander_vidage_coffre(coffre_id: String) -> void:
	if mode != Mode.CLIENT or pseudo == "":
		return
	rpc_id(1, "envoie_vider_coffre", coffre_id)

# l'identifiant reseau d'une rencontre : "Parent/Noeud" (stable entre
# les clients : les scenes sont identiques)
func cle_rencontre(ennemi: Node) -> String:
	var parent := ennemi.get_parent()
	if parent == null:
		return str(ennemi.name)
	return "%s/%s" % [str(parent.name), str(ennemi.name)]

# appele par ennemy.gd quand le vainqueur LOCAL veut partager sa victoire
func signaler_rencontre_vaincue(ennemi: Node) -> void:
	if mode != Mode.CLIENT or pseudo == "":
		return
	rpc_id(1, "envoie_rencontre_vaincue", cle_rencontre(ennemi))

# masque l'ennemi correspondant a la cle : vaincu pour tout le monde
# sur cette map, jusqu'a ce que le serveur le fasse reapparaitre
# API appelée par combat_manager quand le joueur engage un groupe
func debut_combat_local(groupe: String) -> void:
	if mode != Mode.CLIENT or pseudo == "" or groupe == "":
		return
	combat_groupe_local = groupe
	rpc_id(1, "envoie_debut_combat", groupe)

# API appelée par combat_manager à la fin du combat
func fin_combat_local(groupe: String) -> void:
	if mode != Mode.CLIENT or pseudo == "" or groupe == "":
		return
	combat_groupe_local = ""
	rpc_id(1, "envoie_fin_combat", groupe)

# API appelée par combat_manager quand le combat de groupe démarre
# réellement (placement validé) : le serveur refuse les retardataires
func combat_local_lance() -> void:
	if mode != Mode.CLIENT or pseudo == "" or combat_groupe_local == "":
		return
	rpc_id(1, "envoie_combat_lance")

# RPC client : le serveur refuse notre engagement (combat déjà lancé)
# — la partie locale se referme, on n'y a jamais participé
@rpc("any_peer", "call_remote", "reliable")
func combat_refuse() -> void:
	if multiplayer.is_server():
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var cm := scene.get_node_or_null("CombatManager")
	if cm != null and bool(cm.get("en_combat")):
		cm.call("terminer_combat", false)
	combat_groupe_local = ""

# RPC client : un joueur de la map engage un groupe étiqueté
@rpc("any_peer", "call_remote", "reliable")
func invitation_combat(chef: String, groupe: String, chef_id := 0) -> void:
	if multiplayer.is_server():
		return
	if combat_groupe_local != "" or not _combat_joinable():
		return
	invitation_en_attente = [chef, groupe]
	invitation_chef_id = int(chef_id)
	_groupe_ui.montrer_invite_combat(chef)

# RPC client : le combat du chef est terminé, l'invitation tombe
@rpc("any_peer", "call_remote", "reliable")
func fin_combat_distante(chef: String, groupe: String) -> void:
	if multiplayer.is_server():
		return
	if invitation_en_attente == [chef, groupe]:
		invitation_en_attente = []
		_cacher_invitation()

# un CombatManager opérationnel et hors combat est nécessaire pour
# rejoindre un combat
func _combat_joinable() -> bool:
	var scene := get_tree().current_scene
	if scene == null:
		return false
	var cm := scene.get_node_or_null("CombatManager")
	return cm != null and not bool(cm.get("en_combat"))

# rejoins le combat du groupe étiqueté : engage notre instance locale
# de la même rencontre (combat miroir : chacun sa grille, son tour,
# contre le même camp)
func rejoindre_combat(groupe: String) -> void:
	invitation_en_attente = []
	_cacher_invitation()
	var scene := get_tree().current_scene
	var cm: Node = null
	if scene != null:
		cm = scene.get_node_or_null("CombatManager")
	if cm == null or bool(cm.get("en_combat")):
		return
	var rencontres := scene.get_node_or_null("Rencontres")
	if rencontres == null:
		return
	var meme_groupe: Array = []
	for ennemi in rencontres.get_children():
		if int(ennemi.get("pv")) <= 0 or str(ennemi.get("groupe")) != groupe:
			continue
		meme_groupe.append(ennemi)
	if meme_groupe.is_empty():
		return
	cm.call("lancer_combat", meme_groupe)

# --- duels entre joueurs (côté client) ---

# RPC client : un joueur nous défie en duel
@rpc("any_peer", "call_remote", "reliable")
func invite_duel(pseudo_defiant: String) -> void:
	if multiplayer.is_server():
		return
	_montrer_invite_duel(pseudo_defiant)

# RPC client : le duel démarre, notre miroir de l'adversaire apparaît
@rpc("any_peer", "call_remote", "reliable")
func debut_duel(pseudo_adv: String, adversaire_id: int, premier: bool, visuel := VISUEL_DEFAUT) -> void:
	if multiplayer.is_server():
		return
	_demarrer_duel_local(pseudo_adv, adversaire_id, premier, visuel)

# RPC client : une action de l'adversaire, rejouée sur notre grille
@rpc("any_peer", "call_remote", "reliable")
func action_duel(json: String) -> void:
	if multiplayer.is_server():
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var cm := scene.get_node_or_null("CombatManager")
	if cm == null or not bool(cm.get("pvp_actif")):
		return
	cm.call("pvp_action_recue", JSON.parse_string(json))

# RPC client : l'adversaire est à terre (ou a fui) : victoire
@rpc("any_peer", "call_remote", "reliable")
func victoire_duel(pseudo_adv: String, par_fuite: bool) -> void:
	if multiplayer.is_server():
		return
	var texte := ""
	var scene := get_tree().current_scene
	if scene != null:
		var cm := scene.get_node_or_null("CombatManager")
		if cm != null and bool(cm.get("pvp_actif")):
			cm.call("terminer_combat", true)
	if par_fuite:
		texte = "%s a fui le duel — victoire !" % pseudo_adv
	else:
		texte = "%s est à terre — tu remportes le duel !" % pseudo_adv
	call("recoit_message_chat", "Serveur", texte)

# API appelée par player.gd : envoie une action résolue à l'adversaire
func emettre_action_duel(evenement: Dictionary) -> void:
	if pseudo == "":
		return
	rpc_id(1, "envoie_action_duel", JSON.stringify(evenement))

# API appelée par player.gd : envoie une action résolue aux coéquipiers
# de notre combat de groupe
func emettre_action_groupe(evenement: Dictionary) -> void:
	if mode != Mode.CLIENT or pseudo == "" or combat_groupe_local == "":
		return
	rpc_id(1, "envoie_action_groupe", JSON.stringify(evenement))

# RPC client : les combattants déjà en place sur ce combat de groupe
@rpc("any_peer", "call_remote", "reliable")
func membres_groupe(presents: Array) -> void:
	if multiplayer.is_server():
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var cm := scene.get_node_or_null("CombatManager")
	if cm != null:
		cm.call("groupe_membres_recus", presents)

# RPC client : le serveur a vu tous les membres du combat valider leur
# placement — la barrière tombe, les tours synchronisés commencent
@rpc("any_peer", "call_remote", "reliable")
func combat_groupe_pret() -> void:
	if multiplayer.is_server():
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var cm := scene.get_node_or_null("CombatManager")
	if cm != null:
		cm.call("groupe_pret")

# RPC client : une action d'un coéquipier, rejouée dans notre arène
@rpc("any_peer", "call_remote", "reliable")
func action_groupe(peer_exp: int, pseudo_exp: String, json: String) -> void:
	if multiplayer.is_server():
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var cm := scene.get_node_or_null("CombatManager")
	if cm != null:
		cm.call("groupe_action_recue", peer_exp, pseudo_exp, JSON.parse_string(json))

# RPC client : un coéquipier quitte le combat de groupe (fin ou défaite)
@rpc("any_peer", "call_remote", "reliable")
func sortie_combat_groupe(peer_qui_part: int) -> void:
	if multiplayer.is_server():
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var cm := scene.get_node_or_null("CombatManager")
	if cm != null:
		cm.call("groupe_membre_parti", peer_qui_part)

# API appelée par combat_manager : nos pv sont tombés à zéro
func declarer_defaite_duel() -> void:
	if pseudo == "":
		return
	rpc_id(1, "envoie_defaite_duel")

# API appelée par combat_manager : on fuit le duel, l'adversaire
# l'emporte par forfait
func declarer_fuite_duel() -> void:
	if pseudo == "":
		return
	rpc_id(1, "envoie_fuite_duel")

func _demarrer_duel_local(pseudo_adv: String, _adversaire_id: int, premier: bool, visuel := VISUEL_DEFAUT) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var cm := scene.get_node_or_null("CombatManager")
	if cm == null or bool(cm.get("en_combat")):
		return
	var adversaire := SCRIPT_ADVERSAIRE_PVP.new()
	adversaire.nom = pseudo_adv
	adversaire.visuel = str(visuel)
	scene.add_child(adversaire)
	cm.call("lancer_duel", adversaire, premier)
	# le profil part juste après : le miroir distant existe déjà, la
	# grille identique est prête à recevoir nos stats réelles
	var joueur := scene.find_child("player", true, false)
	var pa_max_joueur := 6
	var pm_max_joueur := 3
	if joueur != null:
		pa_max_joueur = int(joueur.get("pa_max"))
		pm_max_joueur = int(joueur.get("pm_max"))
	var noms_sorts: Array = []
	for id_sort in Personnage.sorts:
		noms_sorts.append(str(Personnage.sorts[id_sort].get("nom", id_sort)))
	var visuel_joueur := ""
	if joueur != null and joueur.has_method("_prefixe_visuel_race"):
		visuel_joueur = str(joueur.call("_prefixe_visuel_race"))
	emettre_action_duel({
		"t": "profil", "profil": {
			"pseudo": Personnage.nom,
			"visuel": visuel_joueur,
			"pv": int(Personnage.vie),
			"pv_max": int(Personnage.vie_max),
			"attaque": int(Personnage.attaque),
			"defense": int(Personnage.defense),
			"pa_max": pa_max_joueur,
			"pm_max": pm_max_joueur,
			"sorts": noms_sorts,
		},
	})

# popup d'invitation au duel (Accepter / Refuser)
var _panneau_duel: PanelContainer

func _montrer_invite_duel(pseudo_defiant: String) -> void:
	if _panneau_duel == null:
		_construire_invite_duel()
	var etiquette: Label = _panneau_duel.get_meta("etiquette")
	etiquette.text = "%s te défie en duel !" % pseudo_defiant
	_panneau_duel.show()

func _cacher_invite_duel() -> void:
	if _panneau_duel != null:
		_panneau_duel.hide()

func _construire_invite_duel() -> void:
	_panneau_duel = PanelContainer.new()
	_panneau_duel.theme = THEME
	_panneau_duel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_panneau_duel.offset_top = 150.0
	_chat.add_child(_panneau_duel)
	var marges := MarginContainer.new()
	for marge in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		marges.add_theme_constant_override(marge, 16)
	_panneau_duel.add_child(marges)
	var colonne := VBoxContainer.new()
	colonne.add_theme_constant_override("separation", 10)
	marges.add_child(colonne)
	var etiquette := Label.new()
	etiquette.add_theme_font_size_override("font_size", 17)
	colonne.add_child(etiquette)
	_panneau_duel.set_meta("etiquette", etiquette)
	var boutons := HBoxContainer.new()
	boutons.alignment = BoxContainer.ALIGNMENT_CENTER
	boutons.add_theme_constant_override("separation", 14)
	colonne.add_child(boutons)
	var accepter := Button.new()
	accepter.text = "Accepter le duel"
	accepter.custom_minimum_size = Vector2(0, 42)
	accepter.pressed.connect(_on_duel_accepte)
	boutons.add_child(accepter)
	var refuser := Button.new()
	refuser.text = "Refuser"
	refuser.custom_minimum_size = Vector2(0, 42)
	refuser.pressed.connect(_on_duel_refuse)
	boutons.add_child(refuser)
	_panneau_duel.hide()

func _on_duel_accepte() -> void:
	_cacher_invite_duel()
	rpc_id(1, "reponse_duel", true)

func _on_duel_refuse() -> void:
	_cacher_invite_duel()
	rpc_id(1, "reponse_duel", false)

# ============================================================
#  ÉCHANGES D'OBJETS (côté client)
# ============================================================

# état local de l'échange en cours
var _echange_actif := false
var _echange_partenaire := ""
var _offre_echange_locale: Dictionary = {}    # id d'objet -> quantité
var _offre_echange_distante: Dictionary = {}
var _offre_echange_distante_json := "{}"
var _berry_echange_local := 0
var _berry_echange_distant := 0
var _echange_pret_local := false
var _echange_pret_distant := false

# interface
var _panneau_invite_echange: PanelContainer
var _fenetre_echange: PanelContainer
var _etiquette_partenaire_echange: Label
var _etat_partenaire_echange: Label
var _liste_offre_locale: VBoxContainer
var _liste_offre_distante: VBoxContainer
var _choix_objet_echange: OptionButton
var _qte_objet_echange: SpinBox
var _berry_echange_spin: SpinBox
var _ids_objets_echange: Array = []

# RPC client : un joueur nous propose un échange
@rpc("any_peer", "call_remote", "reliable")
func invite_echange(nom: String) -> void:
	if multiplayer.is_server():
		return
	_montrer_invite_echange(nom)

# RPC client : l'échange démarre, la fenêtre s'ouvre des deux côtés
@rpc("any_peer", "call_remote", "reliable")
func debut_echange(nom_partenaire: String) -> void:
	if multiplayer.is_server():
		return
	_ouvrir_fenetre_echange(nom_partenaire)

# RPC client : offre du partenaire et son état "prêt"
@rpc("any_peer", "call_remote", "reliable")
func offre_echange(offre_json: String, pret_distant: bool) -> void:
	if multiplayer.is_server() or not _echange_actif:
		return
	var changement := offre_json != _offre_echange_distante_json
	_offre_echange_distante_json = offre_json
	_offre_echange_distante = {}
	_berry_echange_distant = 0
	var analyse: Variant = JSON.parse_string(offre_json)
	if analyse is Dictionary:
		var offre: Dictionary = analyse
		var objets_offerts: Variant = offre.get("objets", {})
		if objets_offerts is Dictionary:
			_offre_echange_distante = (objets_offerts as Dictionary).duplicate()
		_berry_echange_distant = int(offre.get("berry", 0))
	_echange_pret_distant = bool(pret_distant)
	# le partenaire vient de changer son offre : notre confirmation
	# éventuelle ne vaut plus, il faudra reconfirmer
	if changement:
		_echange_pret_local = false
	_rafraichir_echange()

# RPC client : les deux côtés ont confirmé — l'échange s'applique ici :
# les objets et Berry offerts quittent notre inventaire, ceux du
# partenaire y entrent
@rpc("any_peer", "call_remote", "reliable")
func executer_echange(offre_json: String) -> void:
	if multiplayer.is_server():
		return
	for id_offre in _offre_echange_locale:
		var qte_possedee := int(Inventaire.objets.get(str(id_offre), 0))
		var qte_offerte := mini(int(_offre_echange_locale[id_offre]), qte_possedee)
		if qte_offerte > 0:
			Inventaire.retirer_objet(str(id_offre), qte_offerte)
	var analyse_finale: Variant = JSON.parse_string(offre_json)
	if analyse_finale is Dictionary:
		var offre_finale: Dictionary = analyse_finale
		var objets_recus: Variant = offre_finale.get("objets", {})
		if objets_recus is Dictionary:
			for id_recu in (objets_recus as Dictionary):
				Inventaire.ajouter_objet(str(id_recu), int((objets_recus as Dictionary)[id_recu]))
		_berry_echange_local = mini(_berry_echange_local, Personnage.berry)
		_berry_echange_distant = int(offre_finale.get("berry", _berry_echange_distant))
	Personnage.berry = maxi(Personnage.berry - _berry_echange_local + _berry_echange_distant, 0)
	Personnage.caracteristiques_modifiees.emit()
	sauvegarder_perso_immediat()
	var nom_partenaire_echange := _echange_partenaire
	_fermer_fenetre_echange()
	recoit_message_chat("Serveur", "Échange effectué avec %s !" % nom_partenaire_echange)

# RPC client : l'échange s'arrête sans rien échanger
@rpc("any_peer", "call_remote", "reliable")
func fin_echange(raison: String) -> void:
	if multiplayer.is_server():
		return
	if _echange_actif:
		_fermer_fenetre_echange()
		recoit_message_chat("Serveur", raison)

# popup de proposition d'échange
func _montrer_invite_echange(nom_proposant: String) -> void:
	if _panneau_invite_echange == null:
		_construire_invite_echange()
	var etiquette: Label = _panneau_invite_echange.get_meta("etiquette")
	etiquette.text = "%s te propose un échange !" % nom_proposant
	_panneau_invite_echange.show()

func _cacher_invite_echange() -> void:
	if _panneau_invite_echange != null:
		_panneau_invite_echange.hide()

func _construire_invite_echange() -> void:
	_panneau_invite_echange = PanelContainer.new()
	_panneau_invite_echange.theme = THEME
	_panneau_invite_echange.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_panneau_invite_echange.offset_top = 430.0
	_chat.add_child(_panneau_invite_echange)
	var marges := MarginContainer.new()
	for marge in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		marges.add_theme_constant_override(marge, 16)
	_panneau_invite_echange.add_child(marges)
	var colonne := VBoxContainer.new()
	colonne.add_theme_constant_override("separation", 10)
	marges.add_child(colonne)
	var etiquette := Label.new()
	etiquette.add_theme_font_size_override("font_size", 17)
	colonne.add_child(etiquette)
	_panneau_invite_echange.set_meta("etiquette", etiquette)
	var boutons := HBoxContainer.new()
	boutons.alignment = BoxContainer.ALIGNMENT_CENTER
	boutons.add_theme_constant_override("separation", 14)
	colonne.add_child(boutons)
	var accepter := Button.new()
	accepter.text = "Accepter"
	accepter.custom_minimum_size = Vector2(0, 42)
	accepter.pressed.connect(func() -> void:
		_cacher_invite_echange()
		rpc_id(1, "reponse_echange", true))
	boutons.add_child(accepter)
	var refuser := Button.new()
	refuser.text = "Refuser"
	refuser.custom_minimum_size = Vector2(0, 42)
	refuser.pressed.connect(func() -> void:
		_cacher_invite_echange()
		rpc_id(1, "reponse_echange", false))
	boutons.add_child(refuser)
	_panneau_invite_echange.hide()

# ouvre la fenêtre d'échange, offre remise à zéro
func _ouvrir_fenetre_echange(partenaire: String) -> void:
	if _fenetre_echange == null:
		_construire_fenetre_echange()
	_echange_actif = true
	_echange_partenaire = partenaire
	_offre_echange_locale = {}
	_offre_echange_distante = {}
	_offre_echange_distante_json = "{}"
	_berry_echange_local = 0
	_berry_echange_distant = 0
	_echange_pret_local = false
	_echange_pret_distant = false
	_berry_echange_spin.max_value = maxi(Personnage.berry, 0)
	_berry_echange_spin.set_value_no_signal(0.0)
	_fermer_chat(false)
	_rafraichir_choix_objets_echange()
	_rafraichir_echange()
	_fenetre_echange.show()

# referme la fenêtre et oublie l'échange en cours
func _fermer_fenetre_echange() -> void:
	_echange_actif = false
	_echange_partenaire = ""
	_offre_echange_locale = {}
	_offre_echange_distante = {}
	_offre_echange_distante_json = "{}"
	_berry_echange_local = 0
	_berry_echange_distant = 0
	_echange_pret_local = false
	_echange_pret_distant = false
	if _fenetre_echange != null:
		_fenetre_echange.hide()

# notre offre part au partenaire dès qu'elle change (et déverrouille
# les confirmations des deux côtés, via le serveur)
func _envoyer_offre_echange() -> void:
	if mode != Mode.CLIENT or pseudo == "" or not _echange_actif:
		return
	var charge := JSON.stringify({
		"objets": _offre_echange_locale,
		"berry": int(_berry_echange_local),
	})
	rpc_id(1, "envoie_offre_echange", charge, bool(_echange_pret_local))

# bouton "Confirmer l'échange" : notre accord part avec notre offre
func _on_confirmer_echange() -> void:
	if not _echange_actif:
		return
	_echange_pret_local = true
	_rafraichir_echange()
	_envoyer_offre_echange()

# bouton "Annuler" : prévient le serveur et referme
func _on_annuler_echange() -> void:
	var etait_actif := _echange_actif
	_fermer_fenetre_echange()
	if etait_actif and mode == Mode.CLIENT and pseudo != "":
		rpc_id(1, "annuler_echange")

# ajoute l'objet sélectionné à notre offre (borné par l'inventaire)
func _on_ajouter_objet_echange() -> void:
	if not _echange_actif or _ids_objets_echange.is_empty() or int(_choix_objet_echange.selected) < 0:
		return
	var id_choisi := str(_ids_objets_echange[int(_choix_objet_echange.selected)])
	var dispo := int(Inventaire.objets.get(id_choisi, 0)) - int(_offre_echange_locale.get(id_choisi, 0))
	if dispo <= 0:
		return
	var qte := clampi(int(_qte_objet_echange.value), 1, dispo)
	_offre_echange_locale[id_choisi] = int(_offre_echange_locale.get(id_choisi, 0)) + qte
	_echange_pret_local = false
	_rafraichir_echange()
	_envoyer_offre_echange()

# retire un objet de notre offre
func _retirer_objet_echange(id: String) -> void:
	_offre_echange_locale.erase(id)
	_echange_pret_local = false
	_rafraichir_echange()
	_envoyer_offre_echange()

# Berry offerts ajustés dans la fenêtre
func _on_berry_echange_change(valeur: float) -> void:
	if not _echange_actif or int(valeur) == _berry_echange_local:
		return
	_berry_echange_local = clampi(int(valeur), 0, maxi(Personnage.berry, 0))
	_echange_pret_local = false
	_rafraichir_echange()
	_envoyer_offre_echange()

# borne la quantité à ce qu'on possède encore hors offre en cours
func _on_objet_echange_choisi(_index: int) -> void:
	if _ids_objets_echange.is_empty() or int(_choix_objet_echange.selected) < 0:
		return
	var id_choisi := str(_ids_objets_echange[int(_choix_objet_echange.selected)])
	var dispo := maxi(int(Inventaire.objets.get(id_choisi, 0)) - int(_offre_echange_locale.get(id_choisi, 0)), 1)
	_qte_objet_echange.max_value = dispo
	_qte_objet_echange.value = 1.0

# remplissage du sélecteur avec notre inventaire
func _rafraichir_choix_objets_echange() -> void:
	_choix_objet_echange.clear()
	_ids_objets_echange = []
	for id_possede in Inventaire.objets:
		_ids_objets_echange.append(str(id_possede))
		_choix_objet_echange.add_item("%s (x%d)" % [
			Inventaire.nom_objet(str(id_possede)), int(Inventaire.objets[id_possede])])
	if _ids_objets_echange.is_empty():
		_choix_objet_echange.add_item("Inventaire vide")
		_choix_objet_echange.selected = 0
	else:
		_choix_objet_echange.selected = 0
		_on_objet_echange_choisi(0)

# reconstruit les deux colonnes d'offres et les états
func _rafraichir_echange() -> void:
	if _fenetre_echange == null:
		return
	for enfant in _liste_offre_locale.get_children():
		enfant.queue_free()
	for enfant in _liste_offre_distante.get_children():
		enfant.queue_free()
	_etiquette_partenaire_echange.text = "avec %s" % _echange_partenaire
	# mon offre
	if _offre_echange_locale.is_empty() and _berry_echange_local == 0:
		var vide_mien := Label.new()
		vide_mien.text = "(rien)"
		vide_mien.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		_liste_offre_locale.add_child(vide_mien)
	for id_offre in _offre_echange_locale:
		var rangee := HBoxContainer.new()
		rangee.add_theme_constant_override("separation", 6)
		_liste_offre_locale.add_child(rangee)
		var ligne_offre := Label.new()
		ligne_offre.text = "%dx %s" % [
			int(_offre_echange_locale[id_offre]), Inventaire.nom_objet(str(id_offre))]
		ligne_offre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rangee.add_child(ligne_offre)
		var retirer_offre := Button.new()
		retirer_offre.text = "Retirer"
		retirer_offre.pressed.connect(_retirer_objet_echange.bind(str(id_offre)))
		rangee.add_child(retirer_offre)
	if _berry_echange_local > 0:
		var ligne_berry_mien := Label.new()
		ligne_berry_mien.text = "%d Berry" % _berry_echange_local
		ligne_berry_mien.add_theme_color_override("font_color", Color("#ffd166"))
		_liste_offre_locale.add_child(ligne_berry_mien)
	# son offre
	if _offre_echange_distante.is_empty() and _berry_echange_distant == 0:
		var vide_sien := Label.new()
		vide_sien.text = "(rien pour l'instant)"
		vide_sien.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		_liste_offre_distante.add_child(vide_sien)
	for id_distante in _offre_echange_distante:
		var ligne_distante := Label.new()
		ligne_distante.text = "%dx %s" % [
			int(_offre_echange_distante[id_distante]), Inventaire.nom_objet(str(id_distante))]
		_liste_offre_distante.add_child(ligne_distante)
	if _berry_echange_distant > 0:
		var ligne_berry_sien := Label.new()
		ligne_berry_sien.text = "%d Berry" % _berry_echange_distant
		ligne_berry_sien.add_theme_color_override("font_color", Color("#ffd166"))
		_liste_offre_distante.add_child(ligne_berry_sien)
	# états de confirmation
	_etat_partenaire_echange.text = "%s est prêt !" % _echange_partenaire if _echange_pret_distant else "%s compose son offre..." % _echange_partenaire
	var etat_local := Label.new()
	etat_local.text = "Tu es prêt !" if _echange_pret_local else "Sélectionne tes objets, puis confirme."
	etat_local.add_theme_font_size_override("font_size", 14)
	etat_local.add_theme_color_override("font_color", Color("#7bd88f") if _echange_pret_local else Color(0.6, 0.6, 0.6))
	_liste_offre_locale.add_child(etat_local)
	var etat_distant := Label.new()
	etat_distant.text = "%s est prêt !" % _echange_partenaire if _echange_pret_distant else "%s compose son offre..." % _echange_partenaire
	etat_distant.add_theme_font_size_override("font_size", 14)
	etat_distant.add_theme_color_override("font_color", Color("#7bd88f") if _echange_pret_distant else Color(0.6, 0.6, 0.6))
	_liste_offre_distante.add_child(etat_distant)

# la fenêtre d'échange complète
func _construire_fenetre_echange() -> void:
	_fenetre_echange = PanelContainer.new()
	_fenetre_echange.theme = THEME
	_fenetre_echange.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_fenetre_echange.offset_left = -320.0
	_fenetre_echange.offset_top = -220.0
	_fenetre_echange.offset_right = 320.0
	_fenetre_echange.offset_bottom = 220.0
	_chat.add_child(_fenetre_echange)
	var marges := MarginContainer.new()
	for marge in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		marges.add_theme_constant_override(marge, 14)
	_fenetre_echange.add_child(marges)
	var colonne := VBoxContainer.new()
	colonne.add_theme_constant_override("separation", 10)
	marges.add_child(colonne)
	var entete := HBoxContainer.new()
	entete.add_theme_constant_override("separation", 10)
	colonne.add_child(entete)
	var titre_echange := Label.new()
	titre_echange.text = "ÉCHANGE"
	titre_echange.add_theme_font_size_override("font_size", 18)
	titre_echange.add_theme_color_override("font_color", Color("#ffd166"))
	entete.add_child(titre_echange)
	_etiquette_partenaire_echange = Label.new()
	_etiquette_partenaire_echange.add_theme_font_size_override("font_size", 16)
	_etiquette_partenaire_echange.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entete.add_child(_etiquette_partenaire_echange)
	var annuler := Button.new()
	annuler.text = "Annuler"
	annuler.pressed.connect(_on_annuler_echange)
	entete.add_child(annuler)
	var corps := HBoxContainer.new()
	corps.add_theme_constant_override("separation", 20)
	corps.size_flags_vertical = Control.SIZE_EXPAND_FILL
	colonne.add_child(corps)
	# à gauche : mon offre
	var gauche := VBoxContainer.new()
	gauche.add_theme_constant_override("separation", 6)
	gauche.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	corps.add_child(gauche)
	var titre_mienne := Label.new()
	titre_mienne.text = "Mon offre"
	titre_mienne.add_theme_color_override("font_color", Color("#ffd166"))
	gauche.add_child(titre_mienne)
	_liste_offre_locale = VBoxContainer.new()
	_liste_offre_locale.add_theme_constant_override("separation", 2)
	_liste_offre_locale.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gauche.add_child(_liste_offre_locale)
	var choix := HBoxContainer.new()
	choix.add_theme_constant_override("separation", 6)
	gauche.add_child(choix)
	_choix_objet_echange = OptionButton.new()
	_choix_objet_echange.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_choix_objet_echange.item_selected.connect(_on_objet_echange_choisi)
	choix.add_child(_choix_objet_echange)
	_qte_objet_echange = SpinBox.new()
	_qte_objet_echange.min_value = 1
	_qte_objet_echange.max_value = 1
	choix.add_child(_qte_objet_echange)
	var ajouter := Button.new()
	ajouter.text = "Ajouter"
	ajouter.pressed.connect(_on_ajouter_objet_echange)
	choix.add_child(ajouter)
	var ligne_berry := HBoxContainer.new()
	ligne_berry.add_theme_constant_override("separation", 8)
	gauche.add_child(ligne_berry)
	var etiquette_berry := Label.new()
	etiquette_berry.text = "Berry offerts :"
	ligne_berry.add_child(etiquette_berry)
	_berry_echange_spin = SpinBox.new()
	_berry_echange_spin.min_value = 0
	_berry_echange_spin.max_value = 0
	_berry_echange_spin.value_changed.connect(_on_berry_echange_change)
	ligne_berry.add_child(_berry_echange_spin)
	var confirmer := Button.new()
	confirmer.text = "Confirmer l'échange"
	confirmer.pressed.connect(_on_confirmer_echange)
	gauche.add_child(confirmer)
	# à droite : l'offre du partenaire
	var droite := VBoxContainer.new()
	droite.add_theme_constant_override("separation", 6)
	droite.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	corps.add_child(droite)
	var titre_sienne := Label.new()
	titre_sienne.text = "Offre reçue"
	titre_sienne.add_theme_color_override("font_color", Color("#7bd88f"))
	droite.add_child(titre_sienne)
	_liste_offre_distante = VBoxContainer.new()
	_liste_offre_distante.add_theme_constant_override("separation", 2)
	_liste_offre_distante.size_flags_vertical = Control.SIZE_EXPAND_FILL
	droite.add_child(_liste_offre_distante)
	_etat_partenaire_echange = Label.new()
	_etat_partenaire_echange.add_theme_font_size_override("font_size", 14)
	droite.add_child(_etat_partenaire_echange)
	_fenetre_echange.hide()

func cacher_rencontre(cle: String) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var ennemi := scene.get_node_or_null(cle)
	if ennemi == null or not is_instance_valid(ennemi):
		return
	# l'ennemi est engage dans NOTRE combat : on le retire proprement
	# (les recompenses restent au joueur qui l'a vaincu)
	var cm := scene.get_node_or_null("CombatManager")
	if cm != null:
		var engages = cm.get("_ennemis")
		if engages is Array and (engages as Array).has(ennemi):
			cm.call("ennemi_vaincu", ennemi)
			ennemi.queue_free()
			return
	ennemi.set("pv", 0)
	ennemi.hide()
	var zone := ennemi.get_node_or_null("ZoneDetection")
	if zone != null:
		zone.set_deferred("monitoring", false)

# une rencontre reapparait : l'ennemi redevient actif
func reviver_rencontre(cle: String) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var ennemi := scene.get_node_or_null(cle)
	if ennemi == null or not is_instance_valid(ennemi):
		return
	ennemi.show()
	ennemi.set("pv", int(ennemi.get("pv_max")))
	var zone := ennemi.get_node_or_null("ZoneDetection")
	if zone != null:
		zone.set_deferred("monitoring", true)

func _client_sauvegarde_periodique(delta: float) -> void:
	_temps_sauvegarde += delta
	if _temps_sauvegarde >= INTERVALLE_SAUVEGARDE:
		_temps_sauvegarde = 0.0
		sauvegarder_perso_immediat()

# La réponse de la caisse doit arriver avant de renvoyer la bourse locale.
func sauvegarder_perso_immediat() -> void:
	if mode != Mode.CLIENT or not multiplayer.has_multiplayer_peer():
		return
	if not Personnage.perso_cree or _bourse_equipage_en_attente or Navires.sauvegarde_suspendue():
		return
	_temps_sauvegarde = 0.0
	rpc_id(1, "envoie_sauvegarde_perso", JSON.stringify(serialiser_perso()))

# --- unicité du nom de personnage (création en ligne) ---

# réponse attendue de verifie_nom_perso : { "nom", "ok" } (une seule
# vérification à la fois : l'écran de création n'en fait qu'une)
var _attente_nom: Dictionary = {}

# API de l'écran de création : ce nom de personnage est-il libre ?
# Hors ligne, aucun contrôle (un perso local ne se gêne pas) ; en
# ligne, réponse du serveur ; sans réponse en 4 s, on laisse passer —
# la sauvegarde serveur refuse de toute façon un nom déjà pris
func nom_perso_disponible(nom: String) -> bool:
	if mode != Mode.CLIENT or pseudo == "":
		return true
	var nom_nettoye := nom.strip_edges().substr(0, 64)
	_attente_nom = {"nom": nom_nettoye, "ok": null}
	rpc_id(1, "verifie_nom_perso", nom_nettoye)
	var depart := Time.get_ticks_msec()
	# ignore_time_pause : l'écran de création met l'arbre en pause,
	# la vérification doit suivre quand même
	while _attente_nom.get("nom", "") == nom_nettoye and _attente_nom.get("ok") == null \
			and Time.get_ticks_msec() - depart < 4000:
		await get_tree().create_timer(0.05, true).timeout
	if _attente_nom.get("nom", "") == nom_nettoye and _attente_nom.get("ok") != null:
		return bool(_attente_nom["ok"])
	return true

# RPC client : le serveur a répondu, la vérification en attente suit
@rpc("any_peer", "call_remote", "reliable")
func reponse_nom_perso(disponible: bool, nom: String) -> void:
	if multiplayer.is_server():
		return
	if str(_attente_nom.get("nom", "")) == nom:
		_attente_nom["ok"] = disponible

# --- avatars ---

func _conteneur_avatars() -> Node2D:
	var scene := get_tree().current_scene as Node2D
	if scene == null:
		return null
	var conteneur := scene.get_node_or_null("JoueursDistants") as Node2D
	if conteneur == null:
		conteneur = Node2D.new()
		conteneur.name = "JoueursDistants"
		scene.add_child(conteneur)
	return conteneur

func _maj_avatar(peer_id: int, nom_recu: String, position: Vector2, visuel := VISUEL_DEFAUT, creer_si_absent := true) -> void:
	if peer_id == multiplayer.get_unique_id():
		return
	var avatar_existant = _avatars.get(peer_id)
	if is_instance_valid(avatar_existant):
		avatar_existant.pseudo = nom_recu
		avatar_existant.definir_visuel(visuel)
		avatar_existant.viser(position)
		return
	if not creer_si_absent:
		return
	var conteneur := _conteneur_avatars()
	if conteneur == null:
		return
	var avatar := SCRIPT_AVATAR.new()
	avatar.pseudo = nom_recu
	avatar.definir_visuel(visuel)
	avatar.position = conteneur.to_local(position)
	conteneur.add_child(avatar)
	# les compagnons de groupe ont un repère distinct sur la carte
	avatar.marquer_groupe(est_dans_groupe(peer_id))
	_avatars[peer_id] = avatar

func _retirer_avatar(peer_id: int) -> void:
	var avatar = _avatars.get(peer_id)
	_avatars.erase(peer_id)
	if is_instance_valid(avatar):
		avatar.queue_free()

func _retirer_tous_avatars() -> void:
	for peer_id in _avatars.keys():
		_retirer_avatar(int(peer_id))

# --- sérialisation du perso (mêmes champs que perso.cfg) ---

func serialiser_perso() -> Dictionary:
	var donnees := {
		"nom": Personnage.nom, "race": Personnage.race_id, "classe": Personnage.classe_id,
		"sexe": Personnage.sexe, "niveau": Personnage.niveau, "xp": Personnage.xp,
		Personnage.CHAMP_APPARENCE: Personnage.apparence,
		"vie": Personnage.vie, "berry": Personnage.berry,
		"points_statistique": Personnage.points_statistique,
		"points_depenses": Personnage.points_depenses, "equipement": Personnage.equipement,
		"bateau": Personnage.bateau,
		"amenagement_navire": Personnage.amenagement_navire(),
		"sac": Inventaire.objets,
		"cale_navire": Inventaire.objets_en_cale(),
		"ameliorations": Personnage.ameliorations,
		"metiers": Personnage.metiers, "barre_sorts": Personnage.barre_sorts,
		"barre_objets": Personnage.barre_objets,
		"fruit": Personnage.fruit_id, "fruit_xp": Personnage.fruit_xp, "buffs": Personnage.buffs,
		# croix au trésor non fouillées : elles sont personnelles, elles
		# suivent la sauvegarde du perso sur le serveur
		"croix": CartesTresor.croix_serialisables(),
	}
	# position d'exploration : pas pendant un combat (le corps vit
	# alors dans l'arène, pas sur la map)
	var position := _position_exploration()
	var scene_fichier := _nom_fichier_scene()
	if position.is_finite() and scene_fichier != "":
		donnees["position"] = {"scene": scene_fichier, "x": position.x, "y": position.y}
	if scene_fichier == "lanterne" and not Navires.est_pilote() and not Navires.escale.is_empty():
		donnees["position"] = {"scene": str(Navires.escale["scene"]).get_file().get_basename(),
			"x": Navires.escale["x"], "y": Navires.escale["y"]}
	return donnees

# remplace le perso en mémoire par la version sauvegardée sur le serveur
func _appliquer_perso(perso_json: String) -> void:
	var analyse: Variant = JSON.parse_string(perso_json)
	if analyse == null or not analyse is Dictionary:
		return
	var d: Dictionary = analyse
	Inventaire.basculer_en_ligne(d.get("sac"), d.get("cale_navire"))
	Personnage.nom = _nom_personnage(d)
	Personnage.race_id = str(d.get("race", Personnage.race_id))
	Personnage.classe_id = str(d.get("classe", Personnage.classe_id))
	Personnage.sexe = str(d.get("sexe", Personnage.sexe))
	Personnage.apparence = Personnage.normaliser_apparence(
		Personnage.race_id, str(d.get(Personnage.CHAMP_APPARENCE, "")))
	Personnage.niveau = int(d.get("niveau", Personnage.niveau))
	Personnage.xp = int(d.get("xp", Personnage.xp))
	Personnage.vie = int(d.get("vie", Personnage.vie))
	Personnage.berry = int(d.get("berry", Personnage.berry))
	Personnage.points_statistique = int(d.get("points_statistique", Personnage.points_statistique))
	var depenses = d.get("points_depenses", {})
	if depenses is Dictionary:
		Personnage.points_depenses = depenses
	var equipement = d.get("equipement", {})
	if equipement is Dictionary:
		Personnage.equipement = equipement
	# pièces installées sur le navire
	var navire = d.get("bateau", {})
	if navire is Dictionary:
		for emplacement in Personnage.bateau:
			Personnage.bateau[emplacement] = str(navire.get(emplacement, ""))
	Personnage.appliquer_amenagement_navire(d.get("amenagement_navire", {}))
	var ameliorations: Variant = d.get("ameliorations", {})
	Personnage.ameliorations = ameliorations if ameliorations is Dictionary else {}
	var metiers = d.get("metiers", {})
	if metiers is Dictionary:
		Personnage.metiers = metiers
	var barre = d.get("barre_sorts", [])
	if barre is Array:
		var nouvelle_barre: Array[String] = []
		for id_sort in barre:
			nouvelle_barre.append(str(id_sort))
		Personnage.barre_sorts = nouvelle_barre
	var barre_objets = d.get("barre_objets", [])
	if barre_objets is Array:
		var nouvelle_barre_objets: Array[String] = []
		for id_objet in barre_objets:
			nouvelle_barre_objets.append(str(id_objet))
		Personnage.barre_objets = nouvelle_barre_objets
	Personnage.fruit_id = str(d.get("fruit", ""))
	Personnage.fruit_xp = int(d.get("fruit_xp", 0))
	var buffs_lus = d.get("buffs", [])
	if buffs_lus is Array:
		Personnage.buffs = []
		for buff in buffs_lus:
			if buff is Dictionary:
				Personnage.buffs.append(buff)
	# croix au trésor personnelles non fouillées : elles suivent le perso
	CartesTresor.appliquer_croix_serveur(d.get("croix", []))
	# dernière position d'exploration : la map y replacera le joueur
	var position_lue = d.get("position", {})
	if position_lue is Dictionary and str((position_lue as Dictionary).get("scene", "")) != "":
		position_memorisee = (position_lue as Dictionary).duplicate()
	Personnage.perso_cree = true
	Personnage.recalculer_stats()
	Personnage.caracteristiques_modifiees.emit()
	# la barre de sorts peut différer de la version locale : le HUD suit
	Personnage.barre_sorts_modifiee.emit()
	Personnage.barre_objets_modifiee.emit()

# ============================================================
#  ACCUEIL ET PRÉFÉRENCES DU CLIENT
# ============================================================

func authentifier(adresse: String, nom_pseudo: String, mot_de_passe: String, inscription: bool) -> String:
	if mode != Mode.HORS_LIGNE:
		return "Une connexion est déjà en cours."
	nom_pseudo = nom_pseudo.strip_edges()
	adresse = adresse.strip_edges()
	if inscription:
		var erreur := _valider_identifiants(nom_pseudo, mot_de_passe)
		if erreur != "":
			return erreur
	elif nom_pseudo.is_empty() or mot_de_passe.is_empty():
		return "Indique ton pseudo et ton mot de passe."
	if adresse.is_empty():
		return "Indique l’adresse du serveur."
	if not demarrer_client(adresse):
		return "Adresse du serveur invalide ou introuvable."
	_action_en_attente = "inscription" if inscription else "connexion"
	_adresse_auth = adresse
	_pseudo_auth = nom_pseudo
	_mot_de_passe_auth = mot_de_passe
	return ""

func annuler_authentification() -> void:
	if not _action_en_attente.is_empty():
		fermer_connexion()

func jouer_hors_ligne() -> void:
	if mode == Mode.CLIENT:
		fermer_connexion()
	# solo : la dernière position locale fait foi (elle écrase toute
	# position ramenée du serveur par une session en ligne)
	_charger_position_locale()

func revenir_accueil(message: String = "") -> void:
	jouer_hors_ligne()
	message_accueil = message
	get_tree().change_scene_to_file.call_deferred(CHEMIN_ACCUEIL)

# --- mémorisation de la position du joueur ---

# position d'exploration du joueur (rien s'il est en combat : son
# corps vit dans l'arène, pas sur la map)
func _position_exploration() -> Vector2:
	var scene := get_tree().current_scene
	if scene == null:
		return Vector2(INF, INF)
	var cm := scene.get_node_or_null("CombatManager")
	if cm != null and bool(cm.get("en_combat")):
		return Vector2(INF, INF)
	var joueur := _joueur_local()
	if joueur == null or not is_instance_valid(joueur):
		return Vector2(INF, INF)
	if scene.scene_file_path == Personnage.SCENE_NAVIRE:
		return scene.position_sur_plan(joueur.global_position)
	return joueur.global_position

# nom du fichier de la scène courante ("fushia", "drum"…) : c'est lui
# qui identifie une map dans la sauvegarde, pas le nom du nœud racine
func _nom_fichier_scene() -> String:
	var scene := get_tree().current_scene
	if scene == null or scene.scene_file_path == "":
		return ""
	return scene.scene_file_path.get_file().get_basename()

# mémorise la position d'exploration toutes les 10 s : en mémoire
# (part au perso serveur à chaque sauvegarde) et, hors ligne, dans le
# fichier de préférences
func _memoriser_position_periodique(delta: float) -> void:
	_temps_memoire_position += delta
	if _temps_memoire_position < INTERVALLE_MEMOIRE_POSITION:
		return
	_temps_memoire_position = 0.0
	var position := _position_exploration()
	var scene_fichier := _nom_fichier_scene()
	if not position.is_finite() or scene_fichier == "":
		return
	position_memorisee = {"scene": scene_fichier, "x": position.x, "y": position.y}
	if mode != Mode.HORS_LIGNE:
		return
	var cfg := ConfigFile.new()
	if cfg.load(CHEMIN_PREF) != OK:
		return
	cfg.set_value("position", "scene", scene_fichier)
	cfg.set_value("position", "x", position.x)
	cfg.set_value("position", "y", position.y)
	cfg.save(CHEMIN_PREF)

# charge la position mémorisée localement (solo) : les préférences de
# la machine font foi, elles écrasent toute position en ligne
func _charger_position_locale() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CHEMIN_PREF) != OK:
		return
	var scene := str(cfg.get_value("position", "scene", ""))
	if scene == "":
		return
	position_memorisee = {
		"scene": scene,
		"x": float(cfg.get_value("position", "x", 0.0)),
		"y": float(cfg.get_value("position", "y", 0.0)),
	}

# replace le joueur à sa dernière position mémorisée sur cette map
# (appelé à l'ouverture de chaque map) ; renvoie true si appliqué
func appliquer_position_memorisee(chemin_scene: String, joueur: Node2D) -> bool:
	if position_memorisee.is_empty() or joueur == null or not is_instance_valid(joueur):
		return false
	var scene_attendue := str(position_memorisee.get("scene", ""))
	# comparaison insensible à la casse : les vieilles sauvegardes
	# retenaient le nom du nœud racine ("Fushia"), pas le fichier
	if scene_attendue == "" or scene_attendue.to_lower() != chemin_scene.get_file().get_basename().to_lower():
		return false
	var position := Vector2(
		float(position_memorisee.get("x", 0.0)), float(position_memorisee.get("y", 0.0)))
	if not position.is_finite() or position == Vector2.ZERO:
		return false
	joueur.global_position = position
	position_memorisee = {}
	return true

# un nouveau perso ne reprend pas l'exploration de l'ancien : la
# position mémorisée disparaît de la mémoire et des préférences
func oublier_position_memorisee() -> void:
	position_memorisee = {}
	var cfg := ConfigFile.new()
	if cfg.load(CHEMIN_PREF) != OK:
		return
	if cfg.has_section("position"):
		cfg.erase_section("position")
		cfg.save(CHEMIN_PREF)

# scène où le perso a été laissé : chemin complet si le fichier existe
# ("" pour reprendre au village de départ) ; appelé par l'accueil
# avant de charger la partie
func scene_de_reprise() -> String:
	var nom := str(position_memorisee.get("scene", ""))
	if nom == "":
		return ""
	var chemin := "res://scenes/%s.tscn" % nom
	if not ResourceLoader.exists(chemin):
		chemin = "res://scenes/%s.tscn" % nom.to_lower()
		if not ResourceLoader.exists(chemin):
			return ""
	return chemin

func charger_preferences() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CHEMIN_PREF) != OK:
		return
	adresse_preferee = str(cfg.get_value("serveur", "adresse", adresse_preferee))
	pseudo_prefere = str(cfg.get_value("serveur", "pseudo", ""))

func sauvegarder_preferences() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("serveur", "adresse", adresse_preferee)
	cfg.set_value("serveur", "pseudo", pseudo_prefere)
	cfg.save(CHEMIN_PREF)

# le pair distant se déconnecte (reçu par les deux côtés)
func _on_peer_deconnecte(peer_id: int) -> void:
	if mode == Mode.SERVEUR:
		_nettoyer_session(peer_id)

# ============================================================
#  CHAT GLOBAL
# ============================================================

func _construire_chat() -> void:
	_chat = CanvasLayer.new()
	_chat.layer = 35
	add_child(_chat)
	# le chat est une fenêtre à part entière, style menu : titre, bouton
	# de fermeture, historique complet et ligne de saisie (ouverte par T
	# ou Entrée, refermée par Échap)
	_fenetre_chat = PanelContainer.new()
	_fenetre_chat.theme = THEME
	_fenetre_chat.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_fenetre_chat.offset_left = -300.0
	_fenetre_chat.offset_top = -240.0
	_fenetre_chat.offset_right = 300.0
	_fenetre_chat.offset_bottom = 240.0
	_chat.add_child(_fenetre_chat)
	var marges := MarginContainer.new()
	for marge in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		marges.add_theme_constant_override(marge, 14)
	_fenetre_chat.add_child(marges)
	var colonne := VBoxContainer.new()
	colonne.add_theme_constant_override("separation", 10)
	marges.add_child(colonne)
	var entete := HBoxContainer.new()
	entete.add_theme_constant_override("separation", 10)
	colonne.add_child(entete)
	var titre_chat := Label.new()
	titre_chat.text = "CHAT"
	titre_chat.add_theme_font_size_override("font_size", 18)
	titre_chat.add_theme_color_override("font_color", Color("#ffd166"))
	titre_chat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entete.add_child(titre_chat)
	var fermer_chat := Button.new()
	fermer_chat.text = "Fermer"
	fermer_chat.pressed.connect(_fermer_chat.bind(false))
	entete.add_child(fermer_chat)
	_chat_log = RichTextLabel.new()
	_chat_log.scroll_following = true
	_chat_log.bbcode_enabled = true
	_chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	colonne.add_child(_chat_log)
	_chat_saisie = LineEdit.new()
	_chat_saisie.placeholder_text = "Écris ton message puis Entrée ; Échap referme le chat ; /aide liste les commandes"
	_chat_saisie.text_submitted.connect(_on_chat_envoye)
	colonne.add_child(_chat_saisie)
	_fenetre_chat.hide()
	_groupe_ui = GROUPE_UI.new()
	_groupe_ui.name = "GroupeUI"
	_groupe_ui.theme = THEME
	_groupe_ui.combat_demande.connect(demander_rejoindre_combat)
	_groupe_ui.groupe_quitte.connect(_quitter_groupe_depuis_panneau)
	_groupe_ui.invitation_repondue.connect(_repondre_invite_groupe)
	_groupe_ui.combat_accepte.connect(_on_invitation_rejoint)
	_groupe_ui.combat_ignore.connect(_cacher_invitation)
	_chat.add_child(_groupe_ui)

# --- groupes de joueurs (côté client) : distincts des équipages ---

# RPC client : un joueur nous invite dans son groupe
@rpc("any_peer", "call_remote", "reliable")
func invite_groupe(pseudo_inviteur: String) -> void:
	if multiplayer.is_server():
		return
	_groupe_ui.montrer_invite_groupe(pseudo_inviteur)

# RPC client : composition du groupe et repérage des compagnons sur la carte
@rpc("any_peer", "call_remote", "reliable")
func maj_groupe(membres: Array) -> void:
	if multiplayer.is_server():
		return
	groupe_local = []
	for membre in membres:
		if membre is Dictionary:
			groupe_local.append(membre)
	_maj_panneau_groupe()
	for pair in _avatars.keys():
		var avatar = _avatars[pair]
		if is_instance_valid(avatar):
			avatar.marquer_groupe(est_dans_groupe(int(pair)))

# demande au serveur l'autorisation de rejoindre le combat en cours
# d'un compagnon (bouton « Rejoindre » du panneau GROUPE)
func demander_rejoindre_combat(peer_cible: int) -> void:
	if mode != Mode.CLIENT or pseudo == "" or not _combat_joinable():
		return
	rpc_id(1, "demande_rejoindre_combat", peer_cible)

# RPC client : le serveur a validé — on engage ce camp dans notre
# propre instance (même chemin que l'invitation de map)
@rpc("any_peer", "call_remote", "reliable")
func rejoindre_combat_permis(groupe: String) -> void:
	if multiplayer.is_server():
		return
	invitation_en_attente = []
	_cacher_invitation()
	rejoindre_combat(groupe)

# true si ce pair fait partie de notre groupe
func est_dans_groupe(peer_id: int) -> bool:
	for membre in groupe_local:
		if int(membre.get("peer", 0)) == peer_id:
			return true
	return false

func _maj_panneau_groupe() -> void:
	var id_local := multiplayer.get_unique_id() if not groupe_local.is_empty() else 0
	_groupe_ui.afficher_membres(groupe_local, id_local, GROUPE_TAILLE_MAX, _combat_joinable())

func _quitter_groupe_depuis_panneau() -> void:
	if mode == Mode.CLIENT and pseudo != "" and not groupe_local.is_empty():
		rpc_id(1, "envoie_message_chat", "/groupe quitter")

func _repondre_invite_groupe(acceptee: bool) -> void:
	_groupe_ui.cacher_invite_groupe()
	rpc_id(1, "reponse_groupe", acceptee)

# --- équipages en ligne (côté client) : le serveur est seul maître ---

# toute action d'équipage en ligne passe par le serveur : il valide,
# écrit dans sa base et renouvelle les instantanés des membres
func demander_equipage(action: String, argument := "", montant := 0) -> void:
	if mode != Mode.CLIENT or pseudo == "":
		return
	var touche_bourse := action == "deposer" or action == "retirer"
	if touche_bourse:
		if _bourse_equipage_en_attente:
			Equipages.message_serveur("Une opération de caisse est déjà en cours.")
			return
		sauvegarder_perso_immediat()
		_bourse_equipage_en_attente = true
	if rpc_id(1, "demande_equipage", action, argument, montant) != OK:
		if touche_bourse:
			_bourse_equipage_en_attente = false
		Equipages.message_serveur("Impossible d’envoyer la demande au serveur.")

# RPC client : instantané complet de mon état d'équipage
@rpc("any_peer", "call_remote", "reliable")
func maj_equipage(snapshot_json: String) -> void:
	if multiplayer.is_server():
		return
	Equipages.appliquer_snapshot(snapshot_json)

# --- Greffe de Vie : soin du bistouri hors combat, entre compagnons ---

# le chirurgien opère un compagnon de groupe/équipage : le serveur
# vérifie qu'ils sont bien ensemble, puis coud la cible elle-même
func envoie_soin_groupe(nom_cible: String, fraction: float) -> void:
	if mode != Mode.CLIENT or pseudo == "":
		return
	rpc_id(1, "demande_soin_groupe", nom_cible, fraction)

# compagnons de groupe ou d'équipage visibles à portée d'un point :
# les cibles possibles de la Greffe de Vie hors combat
func compagnons_proches(reference: Vector2, rayon: float) -> Array:
	var proches: Array = []
	if multiplayer.is_server():
		return proches
	for peer_id in _avatars.keys():
		var avatar = _avatars[peer_id]
		if avatar == null or not is_instance_valid(avatar):
			continue
		if not est_dans_groupe(int(peer_id)) and not _est_de_mon_equipage(str(avatar.pseudo)):
			continue
		var position_avatar: Vector2 = avatar.global_position
		if position_avatar.distance_to(reference) > rayon:
			continue
		proches.append({"nom": str(avatar.pseudo), "position": position_avatar})
	return proches

func _est_de_mon_equipage(nom: String) -> bool:
	for membre in Equipages.liste_membres():
		if str(membre.get("nom_joueur", "")).to_lower() == nom.to_lower():
			return true
	return false

# RPC serveur : le chirurgien demande la greffe pour un compagnon
@rpc("any_peer", "call_remote", "reliable")
func demande_soin_groupe(nom_cible: String, fraction: float) -> void:
	if not multiplayer.is_server():
		return
	var session := _pair_authentifie()
	if session.is_empty():
		return
	var demandeur := int(session["peer_id"])
	var cible := str(nom_cible).strip_edges()
	var pair_cible := _peer_du_nom_personnage(cible)
	if pair_cible == 0:
		rpc_id(demandeur, "message_soin", "%s n'est pas en ligne." % cible)
		return
	if not _compagnon_du_pair(demandeur, pair_cible):
		rpc_id(demandeur, "message_soin", "La Greffe de Vie ne recoud que ton groupe ou ton équipage.")
		return
	rpc_id(pair_cible, "soin_groupe_recu", clampf(fraction, 0.0, 1.0),
		str(_sessions[demandeur].get("nom_personnage", "")))
	rpc_id(demandeur, "message_soin", "Tu opères %s : la Greffe de Vie lui rend la moitié de ses PV." % cible)

# vrais compagnons du demandeur : même groupe de chasse ou même équipage
func _compagnon_du_pair(demandeur: int, cible: int) -> bool:
	var groupe := _trouver_groupe(demandeur)
	if not groupe.is_empty() and (groupe["membres"] as Dictionary).has(cible):
		return true
	Equipages.joueur_courant = str(_sessions[demandeur].get("nom_personnage", ""))
	Equipages._recharger_mon_equipage()
	var id_equipage := int(Equipages.mon_equipage.get("id", 0)) if not Equipages.mon_equipage.is_empty() else 0
	Equipages.joueur_courant = ""
	if id_equipage == 0:
		return false
	for nom_membre in Equipages.noms_de_l_equipage(id_equipage):
		if _peer_du_nom_personnage(str(nom_membre)) == cible:
			return true
	return false

# RPC client : la Greffe de Vie d'un compagnon te recoud
@rpc("any_peer", "call_remote", "reliable")
func soin_groupe_recu(fraction: float, nom_operateur: String) -> void:
	if multiplayer.is_server():
		return
	var soin := maxi(roundi(float(Personnage.vie_max) * fraction), 1)
	Personnage.soigner(soin)
	var interface_hud := get_tree().current_scene.find_child("HUD", true, false) if get_tree().current_scene != null else null
	if interface_hud != null:
		interface_hud.afficher_message_sort("La Greffe de Vie de %s te rend %d PV." % [nom_operateur, soin])

# RPC client : réponse du serveur à la demande de greffe
@rpc("any_peer", "call_remote", "reliable")
func message_soin(texte: String) -> void:
	if multiplayer.is_server():
		return
	var interface_hud := get_tree().current_scene.find_child("HUD", true, false) if get_tree().current_scene != null else null
	if interface_hud != null:
		interface_hud.afficher_message_sort(texte)

# --- HDV partagé (côté client) ---

# toute action HDV en ligne passe par le serveur (vendre, retirer,
# acheter une mise en vente d'un autre joueur)
func demander_hdvente(action: String, offre_id := 0, item := "", quantite := 0, prix := 0) -> void:
	if mode != Mode.CLIENT or pseudo == "":
		return
	rpc_id(1, "demande_hdvente", action, offre_id, item, quantite, prix)

# RPC client : instantané des mises en vente du serveur
@rpc("any_peer", "call_remote", "reliable")
func maj_hdventes(snapshot_json: String) -> void:
	if multiplayer.is_server():
		return
	HotelVentes.appliquer_hdventes(snapshot_json)

# RPC client : message du serveur (confirmation ou refus d'une action)
@rpc("any_peer", "call_remote", "reliable")
func message_hdvente(texte: String) -> void:
	if multiplayer.is_server():
		return
	HotelVentes.message_serveur(texte)

# RPC client : les objets achetés ou retirés entrent dans l'inventaire
@rpc("any_peer", "call_remote", "reliable")
func livraison_hdvente(livraison_json: String) -> void:
	if multiplayer.is_server():
		return
	var analyse: Variant = JSON.parse_string(livraison_json)
	if not analyse is Dictionary:
		return
	var livraison: Dictionary = analyse
	Inventaire.ajouter_objet(str(livraison.get("item", "")), int(livraison.get("quantite", 0)))

# RPC client : message du serveur (confirmation ou refus d'une action)
@rpc("any_peer", "call_remote", "reliable")
func message_equipage(texte: String) -> void:
	if multiplayer.is_server():
		return
	Equipages.message_serveur(texte)

@rpc("authority", "call_remote", "reliable")
func resultat_bourse_equipage(delta: int, texte: String) -> void:
	if not _bourse_equipage_en_attente:
		return
	_bourse_equipage_en_attente = false
	if delta != 0:
		Personnage.ajouter_berry(delta)
	else:
		sauvegarder_perso_immediat()
	Equipages.message_serveur(texte)

# RPC client : mon solde de Berry vient de changer côté serveur
@rpc("any_peer", "call_remote", "reliable")
func maj_perso_berry(solde: int) -> void:
	if multiplayer.is_server():
		return
	Personnage.berry = int(solde)
	Personnage.caracteristiques_modifiees.emit()

# RPC client : le capitaine d'un équipage me recrute
@rpc("any_peer", "call_remote", "reliable")
func invite_equipage(nom_equipage: String, capitaine_pseudo: String) -> void:
	if multiplayer.is_server():
		return
	_montrer_invite_equipage(nom_equipage, capitaine_pseudo)

# popup d'invitation de recrutement dans un équipage
var _panneau_invite_equipage: PanelContainer

func _montrer_invite_equipage(nom_equipage: String, capitaine_pseudo: String) -> void:
	if _panneau_invite_equipage == null:
		_construire_invite_equipage()
	var etiquette: Label = _panneau_invite_equipage.get_meta("etiquette")
	etiquette.text = "%s t'invite dans son équipage « %s » !" % [capitaine_pseudo, nom_equipage]
	_panneau_invite_equipage.show()

func _cacher_invite_equipage() -> void:
	if _panneau_invite_equipage != null:
		_panneau_invite_equipage.hide()

func _construire_invite_equipage() -> void:
	_panneau_invite_equipage = PanelContainer.new()
	_panneau_invite_equipage.theme = THEME
	_panneau_invite_equipage.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_panneau_invite_equipage.offset_top = 340.0
	_chat.add_child(_panneau_invite_equipage)
	var marges := MarginContainer.new()
	for marge in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		marges.add_theme_constant_override(marge, 16)
	_panneau_invite_equipage.add_child(marges)
	var colonne := VBoxContainer.new()
	colonne.add_theme_constant_override("separation", 10)
	marges.add_child(colonne)
	var etiquette := Label.new()
	etiquette.add_theme_font_size_override("font_size", 17)
	colonne.add_child(etiquette)
	_panneau_invite_equipage.set_meta("etiquette", etiquette)
	var boutons := HBoxContainer.new()
	boutons.alignment = BoxContainer.ALIGNMENT_CENTER
	boutons.add_theme_constant_override("separation", 14)
	colonne.add_child(boutons)
	var accepter := Button.new()
	accepter.text = "Rejoindre"
	accepter.custom_minimum_size = Vector2(0, 42)
	accepter.pressed.connect(func() -> void:
		_cacher_invite_equipage()
		rpc_id(1, "reponse_equipage_recruit", true))
	boutons.add_child(accepter)
	var refuser := Button.new()
	refuser.text = "Refuser"
	refuser.custom_minimum_size = Vector2(0, 42)
	refuser.pressed.connect(func() -> void:
		_cacher_invite_equipage()
		rpc_id(1, "reponse_equipage_recruit", false))
	boutons.add_child(refuser)
	_panneau_invite_equipage.hide()

func _sur_placement_groupe() -> void:
	_groupe_ui.actualiser_actions_combat(false)
	invitation_en_attente.clear()
	_cacher_invitation()

func _sur_fin_combat_groupe(_victoire: bool) -> void:
	_groupe_ui.actualiser_actions_combat(true)

func _cacher_invitation() -> void:
	_groupe_ui.cacher_invite_combat()
	invitation_chef_id = 0

func _on_invitation_rejoint() -> void:
	if invitation_en_attente.is_empty() or not _combat_joinable():
		return
	# l'acceptation se valide par le serveur : il refuse si le combat a
	# démarré entre-temps (le fondateur a validé son placement)
	if invitation_chef_id != 0:
		var chef_combat := invitation_chef_id
		invitation_en_attente = []
		_cacher_invitation()
		demander_rejoindre_combat(chef_combat)
	else:
		rejoindre_combat(str(invitation_en_attente[1]))

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if not _chat.visible:
		return
	# T ou Entrée ouvre la fenêtre de chat ; Échap la referme (le_traiter
	# d'abord : la fenêtre du menu ne doit pas s'ouvrir par-dessus)
	if event.keycode == KEY_ESCAPE and _chat_ouvert:
		_fermer_chat(false)
		get_viewport().set_input_as_handled()
		return
	if (event.keycode == KEY_T or event.keycode == KEY_ENTER \
			or event.keycode == KEY_KP_ENTER) and not _chat_ouvert:
		if mode == Mode.CLIENT and pseudo != "" and not _menu_ouvert():
			ouvrir_chat()
			get_viewport().set_input_as_handled()

# ouvre la fenêtre de chat : la saisie prend le clavier directement
func ouvrir_chat() -> void:
	if _fenetre_chat == null or _chat_ouvert:
		return
	_chat_ouvert = true
	_fenetre_chat.show()
	_chat_saisie.grab_focus()

# une fenêtre de jeu (menu principal) est-elle déjà ouverte ? le chat
# ne doit pas s'ouvrir par-dessus
func _menu_ouvert() -> bool:
	if get_tree().paused:
		return true
	var menu_ui := get_tree().root.find_child("MenuUI", false, false)
	if menu_ui == null:
		return false
	var fenetre_menu: Variant = menu_ui.get("fenetre")
	return fenetre_menu is Control and bool((fenetre_menu as Control).visible)

func _fermer_chat(envoyer: bool) -> void:
	if envoyer and _chat_saisie.text.strip_edges() != "":
		rpc_id(1, "envoie_message_chat", _chat_saisie.text)
	_chat_ouvert = false
	_chat_saisie.text = ""
	_chat_saisie.release_focus()
	if _fenetre_chat != null:
		_fenetre_chat.hide()

func _on_chat_envoye(_texte: String) -> void:
	_fermer_chat(true)
