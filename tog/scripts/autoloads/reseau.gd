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
# délai avant qu'une rencontre vaincue réapparaisse pour tous
const RESPAWN_RENCONTRES_S := 300.0
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
# notre groupe de joueurs (distinct des équipages) :
# [{peer: int, pseudo: String, chef: bool}, ...]
var groupe_local: Array = []
# panneau des membres du groupe (construit avec le chat)
var _panneau_groupe: PanelContainer

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
# membres d'un combat de groupe en cours : "scene|groupe" -> {peer_id: pseudo}
var _membres_groupe := {}
var _temps_relais := 0.0
var _limiteurs := {}          # peer_id -> {position: ms, chat: ms}
# duels en cours : peer_id -> peer_id de l'adversaire
var _duels := {}
# invitations de duel en attente : peer_cible -> peer_demandeur
var _invites_duel := {}
# groupes de joueurs (rien à voir avec les équipages : un groupe se
# forme à la volée pour jouer ensemble quand son équipage n'est pas
# connecté) : peer du chef -> {peer_id: pseudo} — le chef est membre
var _groupes := {}
# invitations de groupe en attente : peer_cible -> peer_demandeur
var _invites_groupe := {}
# taille maximale d'un groupe de joueurs
const GROUPE_TAILLE_MAX := 5

func _ready() -> void:
	# Le réseau continue de tourner pendant les dialogues et la création.
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.connected_to_server.connect(_on_connecte_au_serveur)
	multiplayer.connection_failed.connect(_on_echec_connexion)
	multiplayer.server_disconnected.connect(_on_serveur_perdu)
	charger_preferences()
	_construire_chat()
	_chat.hide()

func _process(delta: float) -> void:
	if mode == Mode.CLIENT and pseudo != "":
		_client_annoncer_scene()
		_client_envoyer_position(delta)
		_client_sauvegarde_periodique(delta)
		_client_appliquer_annonces_attente()
	elif mode == Mode.CLIENT and _action_en_attente != "":
		_client_piloter_auth(delta)
	elif mode == Mode.SERVEUR:
		_serveur_diffuser_positions(delta)
		_serveur_purger_rencontres(delta)

# ============================================================
#  SERVEUR
# ============================================================

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
	creer_tables_mmo()
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

func _ecrire_perso_serveur(compte_id: int, donnees_json: String) -> void:
	var existant := not _lire(
		"SELECT compte_id FROM mmo_persos WHERE compte_id = %d;" % compte_id).is_empty()
	if existant:
		_sql("UPDATE mmo_persos SET donnees = '%s', maj_le = datetime('now') WHERE compte_id = %d;" % [
			_echapper_texte(donnees_json), compte_id])
	else:
		_sql("INSERT INTO mmo_persos (compte_id, donnees) VALUES (%d, '%s');" % [
			compte_id, _echapper_texte(donnees_json)])

func _ouvrir_session(peer_id: int, nom_pseudo: String) -> void:
	_sessions[peer_id] = {
		"pseudo": nom_pseudo,
		"position": Vector2(INF, INF),
		"annonce": false,
		"scene": "",
		"visuel": VISUEL_DEFAUT,
	}
	_limiteurs[peer_id] = {"position": 0, "chat": 0}
	print("Connexion : %s (id %d, %d joueur(s) en ligne)" % [nom_pseudo, peer_id, _sessions.size()])
	# les joueurs déjà annoncés apprennent l'arrivée
	for autre in _sessions:
		if int(autre) == peer_id or not bool(_sessions[int(autre)]["annonce"]):
			continue
		rpc_id(int(autre), "recoit_message_chat", "Serveur", "%s a embarqué !" % nom_pseudo)

# le nouveau est annoncé aux autres quand on connaît enfin sa
# position (premier paquet), pas dès le login (sinon avatar en 0,0)
func _annoncer_si_premiere_position(peer_id: int, position: Vector2) -> void:
	var session: Dictionary = _sessions[peer_id]
	if bool(session["annonce"]):
		return
	session["annonce"] = true
	session["position"] = position
	for autre in _pairs_sur_scene(str(session["scene"])):
		if int(autre) == peer_id:
			continue
		rpc_id(int(autre), "joueur_rejoint", peer_id, str(session["pseudo"]),
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
	rpc_id(peer_id, "reponse_authentification", true, "Bienvenue %s ! Crée ton personnage." % nom_pseudo, "")

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
	_ouvrir_session(peer_id, pseudo_final)
	rpc_id(peer_id, "reponse_authentification", true, "Bienvenue %s !" % pseudo_final,
		_perso_du_serveur(int(compte["id"])))

# Les avatars existent uniquement dans la scène où leurs joueurs se trouvent.
func _annoncer_presents_sur_scene(peer_id: int, nom_scene: String) -> void:
	for autre in _pairs_sur_scene(nom_scene):
		if int(autre) == peer_id or not bool(_sessions[autre]["annonce"]):
			continue
		rpc_id(peer_id, "joueur_rejoint", int(autre), str(_sessions[autre]["pseudo"]),
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
	if session.is_empty() or JSON.parse_string(donnees_json) == null:
		return
	var compte := _compte(str(session["pseudo"]))
	if compte.is_empty():
		return
	_ecrire_perso_serveur(int(compte["id"]), donnees_json)

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
func envoie_scene(nom_scene: String, x: float = INF, y: float = INF) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not _sessions.has(peer_id):
		return
	nom_scene = nom_scene.strip_edges().substr(0, 64)
	var session: Dictionary = _sessions[peer_id]
	var ancienne_scene: String = session["scene"]
	if nom_scene == "" or nom_scene == ancienne_scene:
		return
	for autre in _pairs_sur_scene(ancienne_scene):
		if int(autre) != peer_id:
			rpc_id(int(autre), "joueur_quitte", peer_id)
	_positions_a_relais.erase(peer_id)
	session["scene"] = nom_scene
	session["annonce"] = false
	print("%s joue sur : %s" % [str(session["pseudo"]), nom_scene])
	var position := Vector2(x, y)
	if position.is_finite():
		_annoncer_si_premiere_position(peer_id, position)
	_annoncer_presents_sur_scene(peer_id, nom_scene)
	# l'etat du monde de cette map part au nouvel arrivant
	rpc_id(peer_id, "etat_rencontres", _cles_vaincues(nom_scene), nom_scene)
	# ressources partagées de cette map : les coffres du monde (les
	# croix au trésor sont personnelles, elles suivent chaque perso)
	rpc_id(peer_id, "etat_coffres", _json_coffres_scene(nom_scene))

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
	session["en_combat"] = true
	var combats_scene: Dictionary = _combats_actifs.get(nom_scene, {})
	combats_scene[groupe] = peer_id
	_combats_actifs[nom_scene] = combats_scene
	print("Combat : %s engage [%s] sur %s" % [session["pseudo"], groupe, nom_scene])
	# combat de groupe : le premier est l'hôte, les suivants rejoignent
	var cle := "%s|%s" % [nom_scene, groupe]
	var membres: Dictionary = _membres_groupe.get(cle, {})
	var nouveau := not membres.has(peer_id)
	membres[peer_id] = str(session["pseudo"])
	_membres_groupe[cle] = membres
	if nouveau:
		# le nouveau arrivant reçoit les combattants déjà en place
		var presents: Array = []
		for autre in membres:
			if int(autre) == peer_id:
				continue
			presents.append({
				"peer": int(autre), "pseudo": str(membres[autre]),
				"visuel": str(_sessions[int(autre)].get("visuel", VISUEL_DEFAUT)),
			})
		rpc_id(peer_id, "membres_groupe", presents)
	for autre in _pairs_sur_scene(nom_scene):
		if int(autre) != peer_id:
			rpc_id(int(autre), "etre_en_combat", peer_id, true)
	# invitation pour les autres joueurs de la map pas déjà en combat
	for autre in _pairs_sur_scene(nom_scene):
		if int(autre) == peer_id or bool(_sessions[int(autre)].get("en_combat", false)):
			continue
		rpc_id(int(autre), "invitation_combat", str(session["pseudo"]), groupe)

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
	for autre in _pairs_sur_scene(nom_scene):
		if int(autre) != peer_id:
			rpc_id(int(autre), "etre_en_combat", peer_id, false)
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
		rpc_id(int(autre), "fin_combat_distante", str(session["pseudo"]), groupe)

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

# peer d'un pseudo en ligne (0 si introuvable, insensible à la casse)
func _peer_du_pseudo(pseudo: String) -> int:
	var cherche := pseudo.to_lower()
	for peer_id in _sessions:
		if str(_sessions[peer_id]["pseudo"]).to_lower() == cherche:
			return int(peer_id)
	return 0

# le badge « en combat » d'un pair est propagé aux joueurs de sa map
func _annoncer_etat_combat(peer_id: int, actif: bool) -> void:
	if not _sessions.has(peer_id):
		return
	var nom_scene := str(_sessions[peer_id]["scene"])
	for autre in _pairs_sur_scene(nom_scene):
		if int(autre) != peer_id:
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
	var pseudo_demandeur := str(_sessions[demandeur]["pseudo"])
	var pseudo_cible := str(_sessions[peer_id]["pseudo"])
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
	# celui qui a défié ouvre le bal
	rpc_id(demandeur, "debut_duel", pseudo_cible, peer_id, true)
	rpc_id(peer_id, "debut_duel", pseudo_demandeur, demandeur, false)

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
				rpc_id(int(autre), "action_groupe", peer_id, str(membres[peer_id]), json)
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
	var pseudo := str(_sessions[peer_id]["pseudo"])
	_fin_duel(peer_id)
	rpc_id(adversaire, "victoire_duel", pseudo, false)

# RPC serveur : message de chat global
@rpc("any_peer", "call_remote", "reliable")
func envoie_message_chat(texte: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not _sessions.has(peer_id) or _trop_tot(peer_id, "chat", 300):
		return
	texte = texte.strip_edges().substr(0, 200)
	if texte == "":
		return
	var nom_envoyeur: String = _sessions[peer_id]["pseudo"]
	# commande /defier : lancer un défi à un autre joueur
	if texte.begins_with("/defier"):
		var cible := texte.substr(7).strip_edges()
		if cible == "":
			rpc_id(peer_id, "recoit_message_chat", "Serveur", "Utilisation : /defier Pseudo")
			return
		var peer_cible := _peer_du_pseudo(cible)
		if peer_cible == 0:
			rpc_id(peer_id, "recoit_message_chat", "Serveur", "Aucun joueur en ligne ne s'appelle %s." % cible)
			return
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
			rpc_id(peer_id, "recoit_message_chat", "Serveur", "%s a déjà une invitation en attente." % cible)
			return
		_invites_duel[peer_cible] = peer_id
		rpc_id(peer_id, "recoit_message_chat", "Serveur", "Tu défies %s en duel..." % cible)
		rpc_id(peer_cible, "invite_duel", nom_envoyeur)
		return
	# commande /joueurs : la liste revient en privé
	if texte == "/joueurs":
		var pseudos: Array = []
		for autre in _sessions:
			pseudos.append(str(_sessions[int(autre)]["pseudo"]))
		rpc_id(peer_id, "recoit_message_chat", "Serveur",
			"En ligne (%d) : %s" % [pseudos.size(), ", ".join(pseudos)])
		return
	# commande /groupe : groupes de joueurs (sans rapport avec les
	# équipages — rejoindre ses amis quand l'équipage n'est pas co)
	# /groupe Pseudo -> inviter, /groupe -> liste, /groupe quitter
	if texte.begins_with("/groupe"):
		var argument := texte.substr(7).strip_edges()
		if argument == "":
			_repondre_liste_groupe(peer_id)
		elif argument.to_lower() == "quitter":
			_sortir_du_groupe(peer_id, true)
		else:
			_inviter_au_groupe(peer_id, argument)
		return
	print("Chat <%s> %s" % [nom_envoyeur, texte])
	for autre in _sessions:
		rpc_id(int(autre), "recoit_message_chat", nom_envoyeur, texte)

# ============================================================
#  GROUPES DE JOUEURS (distinct des équipages)
# ============================================================

# le groupe du joueur : {id: peer du chef, membres: {peer: pseudo}},
# {} s'il n'est dans aucun groupe
func _trouver_groupe(peer_id: int) -> Dictionary:
	for id_chef in _groupes:
		if (_groupes[id_chef] as Dictionary).has(peer_id):
			return {"id": int(id_chef), "membres": _groupes[id_chef]}
	return {}

# invite à rejoindre le groupe du demandeur (il en devient le chef
# s'il n'en a pas)
func _inviter_au_groupe(demandeur: int, cible_pseudo: String) -> void:
	var peer_cible := _peer_du_pseudo(cible_pseudo)
	if peer_cible == 0:
		rpc_id(demandeur, "recoit_message_chat", "Serveur",
			"Aucun joueur en ligne ne s'appelle %s." % cible_pseudo)
		return
	if peer_cible == demandeur:
		rpc_id(demandeur, "recoit_message_chat", "Serveur",
			"Un groupe, c'est à plusieurs — invite quelqu'un d'autre.")
		return
	if not _trouver_groupe(peer_cible).is_empty():
		rpc_id(demandeur, "recoit_message_chat", "Serveur",
			"%s est déjà dans un groupe." % cible_pseudo)
		return
	if _invites_groupe.has(peer_cible):
		rpc_id(demandeur, "recoit_message_chat", "Serveur",
			"%s a déjà une invitation en attente." % cible_pseudo)
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
		"Tu invites %s dans ton groupe..." % cible_pseudo)
	rpc_id(peer_cible, "invite_groupe", str(_sessions[demandeur]["pseudo"]))

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
	var pseudo_cible := str(_sessions[peer_id]["pseudo"])
	var pseudo_demandeur := str(_sessions[demandeur]["pseudo"])
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
		_groupes[demandeur] = {demandeur: pseudo_demandeur}
	var membres: Dictionary = _groupes[demandeur]
	if membres.size() >= GROUPE_TAILLE_MAX:
		rpc_id(peer_id, "recoit_message_chat", "Serveur", "Le groupe est plein.")
		return
	membres[peer_id] = pseudo_cible
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
			"Tu n'es dans aucun groupe. Utilise /groupe Pseudo pour inviter un joueur.")
		return
	var membres: Dictionary = groupe["membres"]
	var noms: Array[String] = []
	for membre in membres:
		var nom_membre := str(membres[membre])
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
		if _sessions.has(peer_id):
			rpc_id(peer_id, "recoit_message_chat", "Serveur", "Tu n'es dans aucun groupe.")
		return
	var id_chef: int = groupe["id"]
	var membres: Dictionary = _groupes[id_chef]
	var pseudo_partant := str(membres.get(peer_id, "?"))
	membres.erase(peer_id)
	if _sessions.has(peer_id):
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
			rpc_id(int(membre), "recoit_message_chat", "Serveur",
				"%s mène désormais le groupe." % str(membres[nouveau_chef]))
	for membre in membres:
		rpc_id(int(membre), "recoit_message_chat", "Serveur",
			"%s %s le groupe." % [pseudo_partant, "a quitté" if volontaire else "a quitté (déconnexion)"])
	_annoncer_groupe(nouveau_chef)
	# le chef parti volontairement apprend la passation
	if _sessions.has(peer_id) and volontaire and id_chef == peer_id:
		rpc_id(peer_id, "recoit_message_chat", "Serveur",
			"%s prend la tête du groupe." % str(membres[nouveau_chef]))

# diffuse la composition du groupe à ses membres (interface + couleur)
func _annoncer_groupe(id_chef: int) -> void:
	var membres: Dictionary = _groupes.get(id_chef, {})
	var liste: Array = []
	for membre in membres:
		liste.append({"peer": int(membre), "pseudo": str(membres[membre]),
			"chef": int(membre) == id_chef})
	for membre in membres:
		rpc_id(int(membre), "maj_groupe", liste)

# NETTOYAGE : un pair se déconnecte
func _nettoyer_session(peer_id: int) -> void:
	if not _sessions.has(peer_id):
		return
	# un duel en cours se solde par forfait du fuyard
	if _duels.has(peer_id):
		var adversaire := int(_duels[peer_id])
		var pseudo_fuyard := str(_sessions[peer_id]["pseudo"])
		_fin_duel(peer_id)
		rpc_id(adversaire, "victoire_duel", pseudo_fuyard, true)
	# son groupe de joueurs l'oublie (partance de tête si nécessaire)
	_sortir_du_groupe(peer_id, false)
	_liberer_combats(peer_id)
	_invites_groupe.erase(peer_id)
	var pseudo_quittant: String = _sessions[peer_id]["pseudo"]
	_sessions.erase(peer_id)
	_limiteurs.erase(peer_id)
	_positions_a_relais.erase(peer_id)
	print("Déconnexion : %s (%d joueur(s) en ligne)" % [pseudo_quittant, _sessions.size()])
	for autre in _sessions:
		rpc_id(int(autre), "joueur_quitte", peer_id)
		rpc_id(int(autre), "recoit_message_chat", "Serveur", "%s a débarqué." % pseudo_quittant)

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
	_scene_locale = ""
	_annonces_en_attente.clear()
	etat_rencontres_recu.clear()
	combat_groupe_local = ""
	invitation_en_attente.clear()
	# le groupe de joueurs ne survit pas à la déconnexion
	groupe_local = []
	_maj_panneau_groupe()
	_cacher_invite_groupe()
	_retirer_tous_avatars()
	_cacher_invitation()
	_cacher_invite_duel()
	_fermer_chat(false)
	_chat.hide()
	_chat_log.clear()
	if Personnage.en_ligne:
		_retablir_perso_local()
	if Coffres.en_ligne or CartesTresor.en_ligne:
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
	Personnage.reinitialiser()
	Personnage.charger_perso()

# Les coffres du monde et les croix en ligne quittent la mémoire : la
# sauvegarde locale redevient la référence, comme hors ligne.
func _retablir_ressources_partagees() -> void:
	Coffres.recharger_etat_local()
	CartesTresor.recharger_etat_local()

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
	if perso_json != "":
		_appliquer_perso(perso_json)
	else:
		Personnage.reinitialiser()
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
	if _scene_locale != str(get_tree().current_scene.name):
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
	_chat_log.append_text("[color=#ffd166][b]%s[/b][/color] : %s\n" % [
		nom_recu, texte.replace("[", "&#91;").replace("]", "&#93;")])

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
	if nom == _scene_locale:
		return
	_retirer_tous_avatars()
	_annonces_en_attente.clear()
	etat_rencontres_recu.clear()
	invitation_en_attente.clear()
	_cacher_invitation()
	_scene_locale = nom
	_chat.show()
	_derniere_position_envoyee = joueur.global_position
	if joueur.has_method("_prefixe_visuel_race"):
		rpc_id(1, "annonce_visuel", str(joueur.call("_prefixe_visuel_race")))
	rpc_id(1, "envoie_scene", nom, joueur.global_position.x, joueur.global_position.y)

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

# RPC client : un joueur de la map engage un groupe étiqueté
@rpc("any_peer", "call_remote", "reliable")
func invitation_combat(chef: String, groupe: String) -> void:
	if multiplayer.is_server():
		return
	if combat_groupe_local != "" or not _combat_joinable():
		return
	invitation_en_attente = [chef, groupe]
	_montrer_invitation(chef, groupe)

# RPC client : le combat du chef est terminé, l'invitation tombe
@rpc("any_peer", "call_remote", "reliable")
func fin_combat_distante(chef: String, groupe: String) -> void:
	if multiplayer.is_server():
		return
	if not invitation_en_attente.is_empty() and str(invitation_en_attente[0]) == chef:
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
func invite_duel(pseudo: String) -> void:
	if multiplayer.is_server():
		return
	_montrer_invite_duel(pseudo)

# RPC client : le duel démarre, notre miroir de l'adversaire apparaît
@rpc("any_peer", "call_remote", "reliable")
func debut_duel(pseudo_adv: String, adversaire_id: int, premier: bool) -> void:
	if multiplayer.is_server():
		return
	_demarrer_duel_local(pseudo_adv, adversaire_id, premier)

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

func _demarrer_duel_local(pseudo_adv: String, _adversaire_id: int, premier: bool) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var cm := scene.get_node_or_null("CombatManager")
	if cm == null or bool(cm.get("en_combat")):
		return
	var adversaire := SCRIPT_ADVERSAIRE_PVP.new()
	adversaire.nom = pseudo_adv
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
	emettre_action_duel({
		"t": "profil", "profil": {
			"pseudo": pseudo,
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

func _montrer_invite_duel(pseudo: String) -> void:
	if _panneau_duel == null:
		_construire_invite_duel()
	var etiquette: Label = _panneau_duel.get_meta("etiquette")
	etiquette.text = "%s te défie en duel !" % pseudo
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
	if _temps_sauvegarde < INTERVALLE_SAUVEGARDE:
		return
	_temps_sauvegarde = 0.0
	# pas de perso créé (compte neuf, écran de création ouvert) :
	# ne rien envoyer, sinon le serveur retiendrait un perso vide
	if not Personnage.perso_cree:
		return
	rpc_id(1, "envoie_sauvegarde_perso", JSON.stringify(serialiser_perso()))

# envoi immédiat du perso au serveur : appelé par Personnage.sauvegarder
# à chaque changement important en ligne (hors tick périodique) ; sans
# effet hors ligne ou tant que le perso n'est pas créé
func sauvegarder_perso_immediat() -> void:
	if mode != Mode.CLIENT or not multiplayer.has_multiplayer_peer():
		return
	if not Personnage.perso_cree:
		return
	_temps_sauvegarde = 0.0
	rpc_id(1, "envoie_sauvegarde_perso", JSON.stringify(serialiser_perso()))

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
	# les compagnons de groupe se repèrent en vert sur la map
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
	return {
		"nom": Personnage.nom, "race": Personnage.race_id, "classe": Personnage.classe_id,
		"sexe": Personnage.sexe, "niveau": Personnage.niveau, "xp": Personnage.xp,
		"vie": Personnage.vie, "berry": Personnage.berry,
		"points_statistique": Personnage.points_statistique,
		"points_depenses": Personnage.points_depenses, "equipement": Personnage.equipement,
		"metiers": Personnage.metiers, "barre_sorts": Personnage.barre_sorts,
		"fruit": Personnage.fruit_id, "fruit_xp": Personnage.fruit_xp, "buffs": Personnage.buffs,
		# croix au trésor non fouillées : elles sont personnelles, elles
		# suivent la sauvegarde du perso sur le serveur
		"croix": CartesTresor.croix_serialisables(),
	}

# remplace le perso en mémoire par la version sauvegardée sur le serveur
func _appliquer_perso(perso_json: String) -> void:
	var analyse: Variant = JSON.parse_string(perso_json)
	if analyse == null or not analyse is Dictionary:
		return
	var d: Dictionary = analyse
	Personnage.nom = str(d.get("nom", Personnage.nom))
	Personnage.race_id = str(d.get("race", Personnage.race_id))
	Personnage.classe_id = str(d.get("classe", Personnage.classe_id))
	Personnage.sexe = str(d.get("sexe", Personnage.sexe))
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
	var metiers = d.get("metiers", {})
	if metiers is Dictionary:
		Personnage.metiers = metiers
	var barre = d.get("barre_sorts", [])
	if barre is Array:
		var nouvelle_barre: Array[String] = []
		for id_sort in barre:
			nouvelle_barre.append(str(id_sort))
		Personnage.barre_sorts = nouvelle_barre
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
	Personnage.perso_cree = true
	Personnage.recalculer_stats()
	Personnage.caracteristiques_modifiees.emit()
	# la barre de sorts peut différer de la version locale : le HUD suit
	Personnage.barre_sorts_modifiee.emit()

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

func revenir_accueil(message: String = "") -> void:
	jouer_hors_ligne()
	message_accueil = message
	get_tree().change_scene_to_file.call_deferred(CHEMIN_ACCUEIL)

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
	var panneau := PanelContainer.new()
	panneau.theme = THEME
	panneau.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	panneau.offset_left = 18.0
	panneau.offset_top = -260.0
	panneau.offset_right = 418.0
	panneau.offset_bottom = -140.0
	_chat.add_child(panneau)
	var colonne := VBoxContainer.new()
	panneau.add_child(colonne)
	_chat_log = RichTextLabel.new()
	_chat_log.scroll_following = true
	_chat_log.bbcode_enabled = true
	_chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	colonne.add_child(_chat_log)
	_chat_saisie = LineEdit.new()
	_chat_saisie.placeholder_text = "T pour discuter, Entrée pour envoyer"
	_chat_saisie.visible = false
	_chat_saisie.text_submitted.connect(_on_chat_envoye)
	colonne.add_child(_chat_saisie)
	# panneau des membres de notre groupe de joueurs, au-dessus du chat
	_panneau_groupe = PanelContainer.new()
	_panneau_groupe.theme = THEME
	_panneau_groupe.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_panneau_groupe.offset_left = 18.0
	_panneau_groupe.offset_top = -372.0
	_panneau_groupe.offset_right = 258.0
	_panneau_groupe.offset_bottom = -268.0
	_panneau_groupe.hide()
	_chat.add_child(_panneau_groupe)

# --- groupes de joueurs (côté client) : distincts des équipages ---

# RPC client : un joueur nous invite dans son groupe
@rpc("any_peer", "call_remote", "reliable")
func invite_groupe(pseudo_inviteur: String) -> void:
	if multiplayer.is_server():
		return
	_montrer_invite_groupe(pseudo_inviteur)

# RPC client : composition de notre groupe — panneau des membres et
# pseudos des compagnons en vert sur la map
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

# true si ce pair fait partie de notre groupe
func est_dans_groupe(peer_id: int) -> bool:
	for membre in groupe_local:
		if int(membre.get("peer", 0)) == peer_id:
			return true
	return false

func _maj_panneau_groupe() -> void:
	if _panneau_groupe == null:
		return
	for enfant in _panneau_groupe.get_children():
		enfant.queue_free()
	if groupe_local.is_empty():
		_panneau_groupe.hide()
		return
	var marges := MarginContainer.new()
	for marge in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		marges.add_theme_constant_override(marge, 10)
	_panneau_groupe.add_child(marges)
	var colonne := VBoxContainer.new()
	colonne.add_theme_constant_override("separation", 2)
	marges.add_child(colonne)
	var titre := Label.new()
	titre.text = "GROUPE (%d/%d)" % [groupe_local.size(), GROUPE_TAILLE_MAX]
	titre.add_theme_font_size_override("font_size", 14)
	titre.add_theme_color_override("font_color", Color("#ffd166"))
	colonne.add_child(titre)
	for membre in groupe_local:
		var ligne := Label.new()
		ligne.add_theme_font_size_override("font_size", 14)
		var texte := "• " + str(membre.get("pseudo", "?"))
		if bool(membre.get("chef", false)):
			texte += " (chef)"
			ligne.add_theme_color_override("font_color", Color("#ffd166"))
		else:
			ligne.add_theme_color_override("font_color", Color("#7bd88f"))
		ligne.text = texte
		colonne.add_child(ligne)
	_panneau_groupe.show()

# popup d'invitation de groupe
var _panneau_invite_groupe: PanelContainer

func _montrer_invite_groupe(pseudo_inviteur: String) -> void:
	if _panneau_invite_groupe == null:
		_construire_invite_groupe()
	var etiquette: Label = _panneau_invite_groupe.get_meta("etiquette")
	etiquette.text = "%s t'invite dans son groupe !" % pseudo_inviteur
	_panneau_invite_groupe.show()

func _cacher_invite_groupe() -> void:
	if _panneau_invite_groupe != null:
		_panneau_invite_groupe.hide()

func _construire_invite_groupe() -> void:
	_panneau_invite_groupe = PanelContainer.new()
	_panneau_invite_groupe.theme = THEME
	_panneau_invite_groupe.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_panneau_invite_groupe.offset_top = 230.0
	_chat.add_child(_panneau_invite_groupe)
	var marges := MarginContainer.new()
	for marge in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		marges.add_theme_constant_override(marge, 16)
	_panneau_invite_groupe.add_child(marges)
	var colonne := VBoxContainer.new()
	colonne.add_theme_constant_override("separation", 10)
	marges.add_child(colonne)
	var etiquette := Label.new()
	etiquette.add_theme_font_size_override("font_size", 17)
	colonne.add_child(etiquette)
	_panneau_invite_groupe.set_meta("etiquette", etiquette)
	var boutons := HBoxContainer.new()
	boutons.alignment = BoxContainer.ALIGNMENT_CENTER
	boutons.add_theme_constant_override("separation", 14)
	colonne.add_child(boutons)
	var accepter := Button.new()
	accepter.text = "Rejoindre"
	accepter.custom_minimum_size = Vector2(0, 42)
	accepter.pressed.connect(func() -> void:
		_cacher_invite_groupe()
		rpc_id(1, "reponse_groupe", true))
	boutons.add_child(accepter)
	var refuser := Button.new()
	refuser.text = "Refuser"
	refuser.custom_minimum_size = Vector2(0, 42)
	refuser.pressed.connect(func() -> void:
		_cacher_invite_groupe()
		rpc_id(1, "reponse_groupe", false))
	boutons.add_child(refuser)
	_panneau_invite_groupe.hide()

# popup d'invitation au combat, en haut de l'écran
var _panneau_invitation: PanelContainer

func _montrer_invitation(chef: String, groupe: String) -> void:
	if _panneau_invitation == null:
		_construire_invitation()
	var etiquette: Label = _panneau_invitation.get_meta("etiquette")
	etiquette.text = "%s engage le groupe [%s]" % [chef, groupe]
	_panneau_invitation.show()

func _cacher_invitation() -> void:
	if _panneau_invitation != null:
		_panneau_invitation.hide()

func _construire_invitation() -> void:
	_panneau_invitation = PanelContainer.new()
	_panneau_invitation.theme = THEME
	_panneau_invitation.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_panneau_invitation.offset_top = 96.0
	# le popup vit dans la couche du chat, au-dessus du HUD
	_chat.add_child(_panneau_invitation)
	var marges := MarginContainer.new()
	for marge in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		marges.add_theme_constant_override(marge, 16)
	_panneau_invitation.add_child(marges)
	var colonne := VBoxContainer.new()
	colonne.add_theme_constant_override("separation", 10)
	marges.add_child(colonne)
	var etiquette := Label.new()
	etiquette.add_theme_font_size_override("font_size", 17)
	colonne.add_child(etiquette)
	_panneau_invitation.set_meta("etiquette", etiquette)
	var boutons := HBoxContainer.new()
	boutons.alignment = BoxContainer.ALIGNMENT_CENTER
	boutons.add_theme_constant_override("separation", 14)
	colonne.add_child(boutons)
	var rejoindre := Button.new()
	rejoindre.text = "Rejoindre le combat"
	rejoindre.custom_minimum_size = Vector2(0, 42)
	rejoindre.pressed.connect(_on_invitation_rejoint)
	boutons.add_child(rejoindre)
	var ignorer := Button.new()
	ignorer.text = "Ignorer"
	ignorer.custom_minimum_size = Vector2(0, 42)
	ignorer.pressed.connect(_cacher_invitation)
	boutons.add_child(ignorer)
	_panneau_invitation.hide()

func _on_invitation_rejoint() -> void:
	if not invitation_en_attente.is_empty():
		rejoindre_combat(str(invitation_en_attente[1]))

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if not _chat.visible:
		return
	if event.keycode == KEY_T and not _chat_ouvert and mode == Mode.CLIENT and pseudo != "":
		_chat_ouvert = true
		_chat_saisie.visible = true
		_chat_saisie.grab_focus()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and _chat_ouvert:
		_fermer_chat(false)
		get_viewport().set_input_as_handled()

func _fermer_chat(envoyer: bool) -> void:
	if envoyer and _chat_saisie.text.strip_edges() != "":
		rpc_id(1, "envoie_message_chat", _chat_saisie.text)
	_chat_ouvert = false
	_chat_saisie.text = ""
	_chat_saisie.release_focus()
	_chat_saisie.visible = false

func _on_chat_envoye(_texte: String) -> void:
	_fermer_chat(true)
