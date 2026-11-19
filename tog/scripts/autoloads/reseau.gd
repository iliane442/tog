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
const THEME := preload("res://themes/theme_pirate.tres")
const SCRIPT_AVATAR := preload("res://scripts/serveur/joueur_distant.gd")
const CHEMIN_PREF := "user://serveur.cfg"
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

# --- client : interface de connexion ---
var _ui: CanvasLayer
var _champ_adresse: LineEdit
var _champ_pseudo: LineEdit
var _champ_mdp: LineEdit
var _label_message: Label
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
var _temps_relais := 0.0
var _limiteurs := {}          # peer_id -> {position: ms, chat: ms}

func _ready() -> void:
	# l'écran de connexion met le jeu en pause : le réseau et l'interface
	# continuent de tourner pendant que le monde attend derrière
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.connected_to_server.connect(_on_connecte_au_serveur)
	multiplayer.connection_failed.connect(_on_echec_connexion)
	multiplayer.server_disconnected.connect(_on_serveur_perdu)
	_construire_interface()
	_construire_chat()
	charger_preferences()
	afficher_interface()

func _process(delta: float) -> void:
	if mode == Mode.CLIENT and pseudo != "":
		_client_envoyer_position(delta)
		_client_sauvegarde_periodique(delta)
		_client_annoncer_scene()
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
	masquer_interface()
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
	for autre in _sessions:
		if int(autre) == peer_id:
			continue
		rpc_id(int(autre), "joueur_rejoint", peer_id, str(session["pseudo"]),
			float(position.x), float(position.y), bool(session.get("en_combat", false)))

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
	var paquet: Array = []
	for peer_id in _positions_a_relais.keys():
		var position: Vector2 = _positions_a_relais[peer_id]
		paquet.append({"id": peer_id, "x": position.x, "y": position.y})
		_positions_a_relais.erase(peer_id)
	for autre in _sessions:
		if not bool(_sessions[autre]["annonce"]):
			continue
		rpc_id(int(autre), "maj_positions", paquet)

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
	rpc_id(peer_id, "reponse_authentification", true, "Bienvenue %s !" % nom_pseudo, "")
	_annoncer_presents_au_nouveau(peer_id)
	# première connexion : le perso du client devient la référence serveur
	rpc_id(peer_id, "demande_import_perso")

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
	_annoncer_presents_au_nouveau(peer_id)

# les joueurs déjà annoncés partent vers le nouveau ; le nouveau ne
# sera annoncé aux autres qu'à sa première position connue
func _annoncer_presents_au_nouveau(peer_id: int) -> void:
	for autre in _sessions:
		if int(autre) == peer_id or not bool(_sessions[autre]["annonce"]):
			continue
		rpc_id(peer_id, "joueur_rejoint", int(autre), str(_sessions[autre]["pseudo"]),
			float(_sessions[autre]["position"].x), float(_sessions[autre]["position"].y),
			bool(_sessions[autre].get("en_combat", false)))

func _valider_identifiants(nom_pseudo: String, mdp: String) -> String:
	if nom_pseudo.length() < 3 or nom_pseudo.length() > 16:
		return "Pseudo : 3 à 16 caractères."
	if mdp.length() < 4:
		return "Mot de passe : 4 caractères minimum."
	for caractere in nom_pseudo:
		if not CARACTERES_PSEUDO.contains(caractere):
			return "Pseudo : lettres, chiffres, - _ et espaces seulement."
	return ""

# RPC serveur : le client fournit son perso (première connexion)
@rpc("any_peer", "call_remote", "reliable")
func envoie_import_perso(donnees_json: String) -> void:
	if not multiplayer.is_server():
		return
	var session := _pair_authentifie()
	if session.is_empty() or JSON.parse_string(donnees_json) == null:
		return
	var compte := _compte(str(session["pseudo"]))
	if compte.is_empty():
		return
	_ecrire_perso_serveur(int(compte["id"]), donnees_json)
	print("Perso importé pour %s" % session["pseudo"])

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
func envoie_position(x: float, y: float) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not _sessions.has(peer_id):
		return
	if _trop_tot(peer_id, "position", 30):
		return
	_annoncer_si_premiere_position(peer_id, Vector2(x, y))
	_positions_a_relais[peer_id] = Vector2(x, y)

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
func envoie_scene(nom_scene: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not _sessions.has(peer_id):
		return
	nom_scene = nom_scene.strip_edges().substr(0, 64)
	_sessions[peer_id]["scene"] = nom_scene
	# l'etat du monde de cette map part au nouvel arrivant
	rpc_id(peer_id, "etat_rencontres", _cles_vaincues(nom_scene))

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
	# commande /joueurs : la liste revient en privé
	if texte == "/joueurs":
		var pseudos: Array = []
		for autre in _sessions:
			pseudos.append(str(_sessions[int(autre)]["pseudo"]))
		rpc_id(peer_id, "recoit_message_chat", "Serveur",
			"En ligne (%d) : %s" % [pseudos.size(), ", ".join(pseudos)])
		return
	print("Chat <%s> %s" % [nom_envoyeur, texte])
	for autre in _sessions:
		rpc_id(int(autre), "recoit_message_chat", nom_envoyeur, texte)

# NETTOYAGE : un pair se déconnecte
func _nettoyer_session(peer_id: int) -> void:
	if not _sessions.has(peer_id):
		return
	_liberer_combats(peer_id)
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
		adresse = morceaux[0]
		port = int(morceaux[1])
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

# envoie (ou renvoie) la requête d'authentification au serveur
func _envoyer_requete_auth() -> void:
	if _action_en_attente == "inscription":
		rpc_id(1, "demande_inscription", _champ_pseudo.text.strip_edges(), _champ_mdp.text)
	elif _action_en_attente == "connexion":
		rpc_id(1, "demande_connexion", _champ_pseudo.text.strip_edges(), _champ_mdp.text)
	_attente_auth = 0.0
	_tentatives_auth += 1

# cadence l'envoi : 0,25 s après la connexion puis reprise toutes les
# 2 s si aucune réponse n'arrive (paquet perdu au handshake)
func _client_piloter_auth(delta: float) -> void:
	_attente_auth += delta
	if _tentatives_auth == 0:
		if _attente_auth >= 0.25:
			_envoyer_requete_auth()
	elif _attente_auth >= 2.0:
		if _tentatives_auth >= 4:
			var pair := multiplayer.multiplayer_peer
			if pair != null:
				pair.close()
			mode = Mode.HORS_LIGNE
			_message_interface("Le serveur ne répond pas.")
			_action_en_attente = ""
		else:
			_envoyer_requete_auth()

# déconnexion volontaire : ferme le pair et remet le client hors ligne
func fermer_connexion() -> void:
	var peer := multiplayer.multiplayer_peer
	if peer != null:
		peer.close()
	multiplayer.multiplayer_peer = null
	multiplayer.clear()
	pseudo = ""
	mode = Mode.HORS_LIGNE
	_action_en_attente = ""
	_scene_locale = ""
	_retirer_tous_avatars()
	get_tree().paused = false

func _on_echec_connexion() -> void:
	mode = Mode.HORS_LIGNE
	_action_en_attente = ""
	_message_interface("Impossible de joindre le serveur.")

func _on_serveur_perdu() -> void:
	pseudo = ""
	mode = Mode.HORS_LIGNE
	_action_en_attente = ""
	_scene_locale = ""
	_retirer_tous_avatars()
	afficher_interface()
	_message_interface("Connexion au serveur perdue.")

# RPC client : réponse d'inscription/connexion (le perso suit si connu)
@rpc("any_peer", "call_remote", "reliable")
func reponse_authentification(ok: bool, message: String, perso_json: String) -> void:
	if multiplayer.is_server():
		return
	authentification_resultat.emit(ok, message)
	_action_en_attente = ""
	_tentatives_auth = 0
	if not ok:
		_message_interface(message)
		# refusé : la connexion est refermée, la prochaine tentative
		# repartira d'un pair propre
		var pair := multiplayer.multiplayer_peer
		if pair != null:
			pair.close()
		multiplayer.multiplayer_peer = null
		multiplayer.clear()
		mode = Mode.HORS_LIGNE
		return
	pseudo = _champ_pseudo.text.strip_edges()
	sauvegarder_preferences()
	if perso_json != "":
		_appliquer_perso(perso_json)
	masquer_interface()
	print("Connecté en tant que %s." % pseudo)

# RPC client : le serveur demande le perso local (première fois)
@rpc("any_peer", "call_remote", "reliable")
func demande_import_perso() -> void:
	if multiplayer.is_server():
		return
	rpc_id(1, "envoie_import_perso", JSON.stringify(serialiser_perso()))

# RPC client : un joueur arrive (avatar visible)
@rpc("any_peer", "call_remote", "reliable")
func joueur_rejoint(peer_id: int, nom_recu: String, x: float, y: float, en_combat: bool) -> void:
	if multiplayer.is_server():
		return
	if get_tree().current_scene == null:
		_annonces_en_attente.append(
			{"id": peer_id, "nom": nom_recu, "x": x, "y": y, "combat": en_combat})
		return
	_maj_avatar(peer_id, nom_recu, Vector2(x, y))
	if _avatars.has(peer_id):
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
			Vector2(float(entree["x"]), float(entree["y"])))
		if _avatars.has(int(entree["id"])):
			(_avatars[int(entree["id"])] as Node2D).maj_combat(bool(entree["combat"]))

# RPC client : l'etat de combat d'un joueur change
@rpc("any_peer", "call_remote", "reliable")
func etre_en_combat(peer_id: int, actif: bool) -> void:
	if multiplayer.is_server():
		return
	if _avatars.has(peer_id):
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
		if id_distant == identifiant or not _avatars.has(id_distant):
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
	if joueur.global_position.distance_to(_derniere_position_envoyee) < 4.0:
		return
	_derniere_position_envoyee = joueur.global_position
	rpc_id(1, "envoie_position", float(joueur.global_position.x), float(joueur.global_position.y))

# le joueur change de map : la nouvelle scene part au serveur, qui
# renvoie l'etat des rencontres vaincues a cet endroit
func _client_annoncer_scene() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var nom := str(scene.name)
	if nom == _scene_locale:
		return
	_scene_locale = nom
	rpc_id(1, "envoie_scene", nom)

# RPC client : etat du monde recu (rencontres deja vaincues sur la map)
@rpc("any_peer", "call_remote", "reliable")
func etat_rencontres(cles: Array) -> void:
	if multiplayer.is_server():
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

func _maj_avatar(peer_id: int, nom_recu: String, position: Vector2, creer_si_absent := true) -> void:
	if peer_id == multiplayer.get_unique_id():
		return
	if not creer_si_absent and not _avatars.has(peer_id):
		return
	if not _avatars.has(peer_id):
		var conteneur := _conteneur_avatars()
		if conteneur == null:
			return
		var avatar := SCRIPT_AVATAR.new()
		avatar.pseudo = nom_recu
		avatar.global_position = position
		conteneur.add_child(avatar)
		_avatars[peer_id] = avatar
		return
	(_avatars[peer_id] as Node2D).viser(position)

func _retirer_avatar(peer_id: int) -> void:
	if not _avatars.has(peer_id):
		return
	var avatar: Node = _avatars[peer_id]
	_avatars.erase(peer_id)
	if avatar != null and is_instance_valid(avatar):
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
	Personnage.perso_cree = true
	Personnage.recalculer_stats()
	Personnage.caracteristiques_modifiees.emit()

# ============================================================
#  INTERFACE DE CONNEXION
# ============================================================

func _construire_interface() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 50
	_ui.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_ui)
	var fond := ColorRect.new()
	fond.color = Color(0.05, 0.05, 0.1, 0.96)
	fond.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(fond)
	var panneau := PanelContainer.new()
	panneau.theme = THEME
	panneau.custom_minimum_size = Vector2(480, 0)
	_ui.add_child(panneau)
	panneau.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	var marges := MarginContainer.new()
	for marge in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		marges.add_theme_constant_override(marge, 28)
	panneau.add_child(marges)
	var colonne := VBoxContainer.new()
	colonne.add_theme_constant_override("separation", 12)
	marges.add_child(colonne)
	var titre := Label.new()
	titre.text = "BANDE DE PIRATES EN LIGNE"
	titre.add_theme_font_size_override("font_size", 22)
	colonne.add_child(titre)
	_champ_adresse = _ajouter_saisie(colonne, "Adresse du serveur")
	_champ_pseudo = _ajouter_saisie(colonne, "Pseudo")
	_champ_mdp = _ajouter_saisie(colonne, "Mot de passe")
	_champ_mdp.secret = true
	_label_message = Label.new()
	_label_message.text = "Crée un compte ou connecte-toi pour jouer en ligne,"
	_label_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	colonne.add_child(_label_message)
	var boutons := HBoxContainer.new()
	boutons.add_theme_constant_override("separation", 12)
	colonne.add_child(boutons)
	boutons.add_child(_bouton_action("Créer un compte", "inscription"))
	boutons.add_child(_bouton_action("Se connecter", "connexion"))
	var hors_ligne := Button.new()
	hors_ligne.text = "Jouer hors ligne"
	hors_ligne.custom_minimum_size = Vector2(0, 44)
	hors_ligne.pressed.connect(jouer_hors_ligne)
	colonne.add_child(hors_ligne)

func _ajouter_saisie(colonne: VBoxContainer, libelle: String) -> LineEdit:
	var etiquette := Label.new()
	etiquette.text = libelle
	colonne.add_child(etiquette)
	var champ := LineEdit.new()
	champ.custom_minimum_size = Vector2(0, 40)
	colonne.add_child(champ)
	return champ

func _bouton_action(texte: String, action: String) -> Button:
	var bouton := Button.new()
	bouton.text = texte
	bouton.custom_minimum_size = Vector2(0, 44)
	bouton.pressed.connect(_demarrer_action.bind(action))
	return bouton

func _demarrer_action(action: String) -> void:
	if _champ_pseudo.text.strip_edges() == "" or _champ_mdp.text == "":
		_message_interface("Pseudo et mot de passe requis.")
		return
	_action_en_attente = action
	_message_interface("Connexion au serveur...")
	if not demarrer_client(_champ_adresse.text):
		_action_en_attente = ""
		mode = Mode.HORS_LIGNE
		_message_interface("Adresse du serveur introuvable.")
		return
	# la requête partira dans _on_connecte_au_serveur une fois le pair établi

func jouer_hors_ligne() -> void:
	mode = Mode.HORS_LIGNE
	masquer_interface()

# le monde tourne derrière l'écran de connexion : on le met en pause
func afficher_interface() -> void:
	_ui.show()
	get_tree().paused = true

func masquer_interface() -> void:
	_ui.hide()
	get_tree().paused = false

func _message_interface(message: String) -> void:
	_label_message.text = message

func charger_preferences() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CHEMIN_PREF) != OK:
		return
	_champ_adresse.text = str(cfg.get_value("serveur", "adresse", "127.0.0.1:%d" % PORT_DEFAUT))
	_champ_pseudo.text = str(cfg.get_value("serveur", "pseudo", ""))

func sauvegarder_preferences() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("serveur", "adresse", _champ_adresse.text.strip_edges())
	cfg.set_value("serveur", "pseudo", _champ_pseudo.text.strip_edges())
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
	if _ui != null and _ui.visible:
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
