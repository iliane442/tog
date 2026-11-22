# equipages.gd — autoload : équipages (guildes de joueurs), alliances, flottes
# Prévu pour un MMO : les membres sont des joueurs identifiés par leur nom,
# et les données vivent dans une base SQLite dédiée (user://equipages.db),
# séparée de la base de contenu glo.db réimportable. L'acceptation des
# invitations et des alliances sera portée par le serveur quand le réseau
# existera ; en attendant, l'écriture locale sert de prototype.
#
# Rangs : capitaine (le fondateur), vice-capitaine (peut recruter, virer,
# gérer les alliances, la caisse et la description), matelot.
extends Node

const MEMBRES_MAX := 20        # capitaine compris
const DESCRIPTION_MAX := 200   # caractères
const CHEMIN_BASE := "user://equipages.db"

const RANG_CAPITAINE := "capitaine"
const RANG_VICE := "vice-capitaine"
const RANG_MATELOT := "matelot"

# état de l'équipage du joueur local :
# {id, nom, capitaine, niveau, caisse, description, mon_rang}
# (vide si le joueur n'est ni capitaine ni membre d'un équipage)
var mon_equipage: Dictionary = {}
var db: SQLite
var disponible := false

signal equipage_modifie

func _ready() -> void:
	db = SQLite.new()
	db.path = CHEMIN_BASE
	db.open_db()
	_creer_schema()
	# teste l'ouverture sur une vraie requête
	db.query("SELECT COUNT(*) AS total FROM equipages;")
	disponible = not db.query_result.is_empty()
	if not disponible:
		push_warning("Impossible de lire la base des équipages : %s" % CHEMIN_BASE)
		return
	_recharger_mon_equipage()

func _exit_tree() -> void:
	if db != null:
		db.close_db()

# --- État local ---

# peuple l'équipage du joueur local : capitaine ou simple membre
# (le joueur local est identifié par le nom du personnage ; ce sera le
# compte du serveur en MMO)
func _recharger_mon_equipage() -> void:
	mon_equipage = {}
	if not disponible:
		return
	var nom := _joueur()
	var lignes := _lire("SELECT * FROM equipages WHERE capitaine = '%s';" % _echapper(nom))
	var capitaine := not lignes.is_empty()
	if lignes.is_empty():
		lignes = _lire(
			"SELECT e.*, m.rang AS mon_rang FROM equipages e"
			+ " JOIN equipages_membres m ON m.equipage_id = e.id"
			+ " WHERE m.nom_joueur = '%s';" % _echapper(nom))
	if lignes.is_empty():
		return
	var ligne: Dictionary = lignes[0]
	mon_equipage = {
		"id": int(ligne["id"]),
		"nom": str(ligne["nom"]),
		"capitaine": str(ligne["capitaine"]),
		"niveau": int(ligne["niveau"]),
		"caisse": int(ligne.get("caisse", 0)),
		"description": str(ligne.get("description", "")),
		"mon_rang": RANG_CAPITAINE if capitaine else str(ligne.get("mon_rang", RANG_MATELOT)),
	}

func _joueur() -> String:
	return Personnage.nom

func suis_capitaine() -> bool:
	return not mon_equipage.is_empty() and str(mon_equipage["capitaine"]) == _joueur()

func suis_vice_capitaine() -> bool:
	return not mon_equipage.is_empty() and str(mon_equipage.get("mon_rang", "")) == RANG_VICE

# le capitaine et le vice-capitaine peuvent gérer l'équipage
func puis_je_gerer() -> bool:
	return suis_capitaine() or suis_vice_capitaine()

# --- Fondation et dissolution ---

func creer(nom: String) -> String:
	if not disponible:
		return "Base des équipages indisponible"
	if not mon_equipage.is_empty():
		return "Vous faites déjà partie d'un équipage"
	var nom_propre := nom.strip_edges()
	if nom_propre.length() < 2:
		return "Nom trop court"
	if nom_propre.length() > 30:
		return "Nom trop long (30 caractères max)"
	if not _ecrire("INSERT INTO equipages (nom, capitaine) VALUES ('%s', '%s') ON CONFLICT(nom) DO NOTHING;" % [
			_echapper(nom_propre), _echapper(_joueur())]):
		return "Impossible de créer l'équipage"
	if int(_lire("SELECT changes() AS ajouts;")[0]["ajouts"]) == 0:
		return "Ce nom d'équipage est déjà pris"
	_recharger_mon_equipage()
	_journaliser("%s fonde l'équipage." % _joueur())
	equipage_modifie.emit()
	return ""

# dissoudre l'équipage (capitaine uniquement) : membres virés, alliance
# rompue, journal effacé, flotte supprimée si elle se vide
func dissoudre() -> void:
	if not suis_capitaine():
		return
	var id_equipage := int(mon_equipage["id"])
	_ecrire("DELETE FROM equipages_membres WHERE equipage_id = %d;" % id_equipage)
	_ecrire("DELETE FROM equipages_journal WHERE equipage_id = %d;" % id_equipage)
	_retirer_de_la_flotte(id_equipage)
	_ecrire("DELETE FROM equipages WHERE id = %d;" % id_equipage)
	mon_equipage = {}
	equipage_modifie.emit()

# quitter l'équipage (simple membre, vice-capitaine compris)
func quitter() -> void:
	if mon_equipage.is_empty() or suis_capitaine():
		return
	var rang := str(mon_equipage.get("mon_rang", RANG_MATELOT))
	_ecrire("DELETE FROM equipages_membres WHERE equipage_id = %d AND nom_joueur = '%s';" % [
		int(mon_equipage["id"]), _echapper(_joueur())])
	if rang == RANG_VICE:
		_journaliser("Le vice-capitaine %s quitte l'équipage." % _joueur())
	else:
		_journaliser("%s quitte l'équipage." % _joueur())
	mon_equipage = {}
	equipage_modifie.emit()

# --- Membres ---

# membres du groupe hors capitaine : [{nom_joueur, rang}]
func liste_membres() -> Array:
	if mon_equipage.is_empty():
		return []
	return _lire(
		"SELECT nom_joueur, rang FROM equipages_membres WHERE equipage_id = %d"
		% int(mon_equipage["id"]))

func nb_membres() -> int:
	if mon_equipage.is_empty():
		return 0
	return 1 + liste_membres().size()  # capitaine compris

func places_libres() -> int:
	return maxi(MEMBRES_MAX - nb_membres(), 0)

# ajoute un joueur à l'équipage ; renvoie "" si réussi, sinon la raison.
# en MMO, cette écriture sera remplacée par une invitation à accepter.
func ajouter_membre(nom: String) -> String:
	if not puis_je_gerer():
		return "Seul le capitaine ou le vice-capitaine recrute"
	if places_libres() <= 0:
		return "Équipage complet (%d membres)" % MEMBRES_MAX
	var nom_propre := nom.strip_edges()
	if nom_propre.length() < 2:
		return "Nom trop court"
	if nom_propre.length() > 30:
		return "Nom trop long (30 caractères max)"
	if nom_propre.to_lower() == str(mon_equipage["capitaine"]).to_lower():
		return "C'est déjà le capitaine"
	if _deja_engage(nom_propre):
		return "Ce joueur fait déjà partie d'un équipage"
	if not _ecrire("INSERT INTO equipages_membres (equipage_id, nom_joueur, rang) VALUES (%d, '%s', '%s');" % [
			int(mon_equipage["id"]), _echapper(nom_propre), RANG_MATELOT]):
		return "Ce joueur est déjà dans l'équipage"
	_journaliser("%s recrute %s dans l'équipage." % [_joueur(), nom_propre])
	equipage_modifie.emit()
	return ""

# un joueur est-il déjà capitaine ou membre d'un équipage ?
func _deja_engage(nom: String) -> bool:
	var nom_echappe := _echapper(nom)
	for ligne in _lire("SELECT id FROM equipages WHERE capitaine = '%s';" % nom_echappe):
		return true
	for ligne in _lire("SELECT id FROM equipages_membres WHERE nom_joueur = '%s';" % nom_echappe):
		return true
	return false

# vire un membre ; le capitaine ne peut pas être viré
func virer(nom: String) -> String:
	if not puis_je_gerer():
		return "Seul le capitaine ou le vice-capitaine vire"
	var nom_propre := nom.strip_edges()
	if nom_propre.to_lower() == str(mon_equipage["capitaine"]).to_lower():
		return "Le capitaine ne peut pas être viré"
	var lignes := _lire(
		"SELECT rang FROM equipages_membres WHERE equipage_id = %d AND nom_joueur = '%s';" % [
			int(mon_equipage["id"]), _echapper(nom_propre)])
	if lignes.is_empty():
		return "Membre introuvable"
	if not _ecrire("DELETE FROM equipages_membres WHERE equipage_id = %d AND nom_joueur = '%s';" % [
			int(mon_equipage["id"]), _echapper(nom_propre)]):
		return "Échec du virement"
	if str(lignes[0]["rang"]) == RANG_VICE:
		_journaliser("%s révoque le vice-capitaine %s." % [_joueur(), nom_propre])
	else:
		_journaliser("%s vire %s de l'équipage." % [_joueur(), nom_propre])
	equipage_modifie.emit()
	return ""

# --- Rangs ---

# nomme un membre vice-capitaine (un seul à la fois) ; capitaine uniquement
func nommer_vice(nom: String) -> String:
	if not suis_capitaine():
		return "Seul le capitaine nomme le vice-capitaine"
	var nom_propre := nom.strip_edges()
	var lignes := _lire(
		"SELECT id FROM equipages_membres WHERE equipage_id = %d AND nom_joueur = '%s';" % [
			int(mon_equipage["id"]), _echapper(nom_propre)])
	if lignes.is_empty():
		return "Membre introuvable"
	_ecrire("UPDATE equipages_membres SET rang = '%s' WHERE equipage_id = %d AND rang = '%s';" % [
		RANG_MATELOT, int(mon_equipage["id"]), RANG_VICE])
	_ecrire("UPDATE equipages_membres SET rang = '%s' WHERE equipage_id = %d AND nom_joueur = '%s';" % [
		RANG_VICE, int(mon_equipage["id"]), _echapper(nom_propre)])
	_journaliser("%s nomme %s vice-capitaine." % [_joueur(), nom_propre])
	equipage_modifie.emit()
	return ""

# redescend le vice-capitaine au rang de matelot ; capitaine uniquement
func destituer_vice() -> String:
	if not suis_capitaine():
		return "Seul le capitaine peut destituer le vice-capitaine"
	var lignes := _lire(
		"SELECT nom_joueur FROM equipages_membres WHERE equipage_id = %d AND rang = '%s';" % [
			int(mon_equipage["id"]), RANG_VICE])
	if lignes.is_empty():
		return "Aucun vice-capitaine en place"
	var ancien := str(lignes[0]["nom_joueur"])
	_ecrire("UPDATE equipages_membres SET rang = '%s' WHERE equipage_id = %d AND rang = '%s';" % [
		RANG_MATELOT, int(mon_equipage["id"]), RANG_VICE])
	_journaliser("%s destitue %s de son rang de vice-capitaine." % [_joueur(), ancien])
	equipage_modifie.emit()
	return ""

# le rang d'un membre ("matelot" par défaut si inconnu)
func rang_de(nom: String) -> String:
	for ligne in liste_membres():
		if str(ligne["nom_joueur"]) == nom:
			return str(ligne["rang"])
	return RANG_MATELOT

# --- Caisse commune ---

# verse des Berry à la caisse (n'importe quel membre)
func deposer_berry(montant: int) -> String:
	if mon_equipage.is_empty():
		return "Vous n'êtes pas dans un équipage"
	if montant <= 0:
		return "Montant invalide"
	if Personnage.berry < montant:
		return "Pas assez de Berry"
	Personnage.ajouter_berry(-montant)
	var id_equipage := int(mon_equipage["id"])
	_ecrire("UPDATE equipages SET caisse = caisse + %d WHERE id = %d;" % [
		montant, id_equipage])
	mon_equipage["caisse"] = int(mon_equipage["caisse"]) + montant
	_journaliser("%s dépose %d Berry à la caisse." % [_joueur(), montant])
	equipage_modifie.emit()
	return ""

# retire des Berry de la caisse vers la bourse du joueur (gestion, auto : capitaine ou vice)
func retirer_berry(montant: int) -> String:
	if not puis_je_gerer():
		return "Seul le capitaine ou le vice-capitaine retire de la caisse"
	if montant <= 0:
		return "Montant invalide"
	if int(mon_equipage["caisse"]) < montant:
		return "Caisse insuffisante (%d Berry)" % int(mon_equipage["caisse"])
	var id_equipage := int(mon_equipage["id"])
	_ecrire("UPDATE equipages SET caisse = caisse - %d WHERE id = %d;" % [
		montant, id_equipage])
	Personnage.ajouter_berry(montant)
	mon_equipage["caisse"] = int(mon_equipage["caisse"]) - montant
	_journaliser("%s retire %d Berry de la caisse." % [_joueur(), montant])
	equipage_modifie.emit()
	return ""

# --- Description ---

func changer_description(texte: String) -> String:
	if not puis_je_gerer():
		return "Seul le capitaine ou le vice-capitaine modifie la description"
	var texte_propre := texte.strip_edges()
	if texte_propre.length() > DESCRIPTION_MAX:
		return "Description trop longue (%d caractères max)" % DESCRIPTION_MAX
	if texte_propre == str(mon_equipage.get("description", "")):
		return ""
	_ecrire("UPDATE equipages SET description = '%s' WHERE id = %d;" % [
		_echapper(texte_propre), int(mon_equipage["id"])])
	mon_equipage["description"] = texte_propre
	_journaliser("%s met à jour la description de l'équipage." % _joueur())
	equipage_modifie.emit()
	return ""

# --- Journal de bord ---

# ajoute une entrée au journal de l'équipage courant
func _journaliser(message: String) -> void:
	if mon_equipage.is_empty():
		return
	_ecrire("INSERT INTO equipages_journal (equipage_id, message) VALUES (%d, '%s');" % [
		int(mon_equipage["id"]), _echapper(message)])

# dernières entrées du journal : [{heure, message}], plus récentes d'abord
# (l'heure est découpée côté GDScript : le "%" de strftime casserait
# le formatage des requêtes)
func liste_journal(limite: int = 10) -> Array:
	if mon_equipage.is_empty():
		return []
	var entrees: Array = []
	for ligne in _lire(
		"SELECT message, date_evenement FROM equipages_journal"
		+ " WHERE equipage_id = %d ORDER BY id DESC LIMIT %d;" % [
			int(mon_equipage["id"]), limite]):
		entrees.append({
			"heure": str(ligne["date_evenement"]).substr(11, 5),
			"message": str(ligne["message"]),
		})
	return entrees

# --- Alliances et flotte ---

# la flotte dont fait partie mon équipage : {id, nom} ou vide
func ma_flotte() -> Dictionary:
	if mon_equipage.is_empty():
		return {}
	var lignes := _lire(
		"SELECT f.id, f.nom FROM flottes f"
		+ " JOIN equipage_flotte ef ON ef.flotte_id = f.id"
		+ " WHERE ef.equipage_id = %d;" % int(mon_equipage["id"]))
	if lignes.is_empty():
		return {}
	return {"id": int(lignes[0]["id"]), "nom": str(lignes[0]["nom"])}

# équipages membres de ma flotte (moi compris si je suis en flotte)
func membres_de_ma_flotte() -> Array:
	var flotte := ma_flotte()
	if flotte.is_empty():
		return []
	return _lire(
		"SELECT e.id, e.nom, e.capitaine FROM equipages e"
		+ " JOIN equipage_flotte ef ON ef.equipage_id = e.id"
		+ " WHERE ef.flotte_id = %d ORDER BY e.nom;" % int(flotte["id"]))

# tous les autres équipages du monde (pour proposer des alliances)
func autres_equipages() -> Array:
	if not disponible:
		return []
	var requete := "SELECT id, nom, capitaine, niveau FROM equipages"
	if not mon_equipage.is_empty():
		requete += " WHERE id != %d" % int(mon_equipage["id"])
	requete += " ORDER BY nom;"
	return _lire(requete)

func nb_membres_de(id_equipage: int) -> int:
	var lignes := _lire(
		"SELECT COUNT(*) AS total FROM equipages_membres WHERE equipage_id = %d;" % id_equipage)
	if lignes.is_empty():
		return 1
	return 1 + int(lignes[0]["total"])  # capitaine compris

# conclut une alliance avec un autre équipage : les deux équipages
# rejoignent la même flotte ; renvoie "" si réussi. En MMO, la proposition
# devra être acceptée par le capitaine adverse.
func proposer_alliance(id_cible: int) -> String:
	if mon_equipage.is_empty():
		return "Vous n'êtes pas engagé dans un équipage"
	if not puis_je_gerer():
		return "Seul le capitaine ou le vice-capitaine gère les alliances"
	var lignes := _lire("SELECT id, nom FROM equipages WHERE id = %d;" % id_cible)
	if lignes.is_empty():
		return "Équipage introuvable"
	var nom_cible := str(lignes[0]["nom"])
	var ma_flotte_avant := ma_flotte()
	var lignes_cible := _lire(
		"SELECT f.id, f.nom FROM flottes f"
		+ " JOIN equipage_flotte ef ON ef.flotte_id = f.id"
		+ " WHERE ef.equipage_id = %d;" % id_cible)
	var flotte_cible: Dictionary = {}
	if not lignes_cible.is_empty():
		flotte_cible = {"id": int(lignes_cible[0]["id"]), "nom": str(lignes_cible[0]["nom"])}
	if not ma_flotte_avant.is_empty() and not flotte_cible.is_empty():
		if int(ma_flotte_avant["id"]) == int(flotte_cible["id"]):
			return "Alliance déjà conclue"
		return "Les deux équipages sont déjà dans des flottes différentes"
	# les deux équipages sans flotte : la première alliance fonde la leur
	if ma_flotte_avant.is_empty() and flotte_cible.is_empty():
		var nom_flotte := "Flotte " + str(mon_equipage["nom"])
		if not _ecrire("INSERT INTO flottes (nom) VALUES ('%s');" % _echapper(nom_flotte)):
			return "Une flotte homonyme existe déjà"
		var id_flotte := _dernier_id()
		_ecrire("INSERT INTO equipage_flotte (equipage_id, flotte_id) VALUES (%d, %d);" % [
			int(mon_equipage["id"]), id_flotte])
		_ecrire("INSERT INTO equipage_flotte (equipage_id, flotte_id) VALUES (%d, %d);" % [
			id_cible, id_flotte])
	elif flotte_cible.is_empty():
		# la cible rejoint ma flotte
		_ecrire("INSERT INTO equipage_flotte (equipage_id, flotte_id) VALUES (%d, %d);" % [
			id_cible, int(ma_flotte_avant["id"])])
	else:
		# je rejoins la flotte de la cible
		_ecrire("INSERT INTO equipage_flotte (equipage_id, flotte_id) VALUES (%d, %d);" % [
			int(mon_equipage["id"]), int(flotte_cible["id"])])
	_journaliser("Alliance conclue avec « %s »." % nom_cible)
	equipage_modifie.emit()
	return ""

# rompt l'alliance de mon équipage : il quitte sa flotte ; la flotte se
# dissout si elle se vide
func rompre_alliance() -> String:
	if mon_equipage.is_empty():
		return "Vous n'êtes pas engagé dans un équipage"
	if not puis_je_gerer():
		return "Seul le capitaine ou le vice-capitaine rompt l'alliance"
	if ma_flotte().is_empty():
		return "Votre équipage n'est pas en flotte"
	_retirer_de_la_flotte(int(mon_equipage["id"]))
	_journaliser("%s rompt l'alliance de l'équipage." % _joueur())
	equipage_modifie.emit()
	return ""

# retire un équipage de sa flotte et supprime la flotte vidée
func _retirer_de_la_flotte(id_equipage: int) -> void:
	var lignes := _lire(
		"SELECT flotte_id FROM equipage_flotte WHERE equipage_id = %d;" % id_equipage)
	if lignes.is_empty():
		return
	var id_flotte := int(lignes[0]["flotte_id"])
	_ecrire("DELETE FROM equipage_flotte WHERE equipage_id = %d;" % id_equipage)
	var restants := _lire(
		"SELECT COUNT(*) AS total FROM equipage_flotte WHERE flotte_id = %d;" % id_flotte)
	if not restants.is_empty() and int(restants[0]["total"]) == 0:
		_ecrire("DELETE FROM flottes WHERE id = %d;" % id_flotte)

# mon équipage est-il allié à l'équipage donné ?
func est_allie(id_equipage: int) -> bool:
	var flotte := ma_flotte()
	if flotte.is_empty():
		return false
	for ligne in _lire(
		"SELECT 1 AS present FROM equipage_flotte"
		+ " WHERE equipage_id = %d AND flotte_id = %d;" % [id_equipage, int(flotte["id"])]):
		return true
	return false

# remet l'équipage du joueur local à zéro (réinitialisation debug du perso)
func reinitialiser() -> void:
	if not mon_equipage.is_empty():
		if suis_capitaine():
			dissoudre()
		else:
			quitter()
	mon_equipage = {}
	equipage_modifie.emit()

# --- Accès à la base ---

func _creer_schema() -> void:
	db.query(
		"CREATE TABLE IF NOT EXISTS equipages ("
		+ " id INTEGER PRIMARY KEY AUTOINCREMENT,"
		+ " nom VARCHAR(30) NOT NULL UNIQUE,"
		+ " capitaine VARCHAR(50) NOT NULL,"
		+ " niveau INTEGER NOT NULL DEFAULT 1,"
		+ " caisse INTEGER NOT NULL DEFAULT 0,"
		+ " description TEXT NOT NULL DEFAULT '',"
		+ " cree_le TIMESTAMP DEFAULT CURRENT_TIMESTAMP);")
	db.query(
		"CREATE TABLE IF NOT EXISTS equipages_membres ("
		+ " id INTEGER PRIMARY KEY AUTOINCREMENT,"
		+ " equipage_id INTEGER NOT NULL,"
		+ " nom_joueur VARCHAR(50) NOT NULL,"
		+ " rang VARCHAR(20) NOT NULL DEFAULT 'matelot',"
		+ " UNIQUE (equipage_id, nom_joueur),"
		+ " FOREIGN KEY (equipage_id) REFERENCES equipages(id));")
	db.query(
		"CREATE TABLE IF NOT EXISTS flottes ("
		+ " id INTEGER PRIMARY KEY AUTOINCREMENT,"
		+ " nom VARCHAR(40) NOT NULL UNIQUE);")
	db.query(
		"CREATE TABLE IF NOT EXISTS equipage_flotte ("
		+ " equipage_id INTEGER PRIMARY KEY,"
		+ " flotte_id INTEGER NOT NULL,"
		+ " FOREIGN KEY (equipage_id) REFERENCES equipages(id),"
		+ " FOREIGN KEY (flotte_id) REFERENCES flottes(id));")
	db.query(
		"CREATE TABLE IF NOT EXISTS equipages_journal ("
		+ " id INTEGER PRIMARY KEY AUTOINCREMENT,"
		+ " equipage_id INTEGER NOT NULL,"
		+ " message TEXT NOT NULL,"
		+ " date_evenement TIMESTAMP DEFAULT CURRENT_TIMESTAMP,"
		+ " FOREIGN KEY (equipage_id) REFERENCES equipages(id));")
	# bases créées avant ces colonnes : migration douce
	_ajouter_colonne_si_absente("equipages", "caisse", "INTEGER NOT NULL DEFAULT 0")
	_ajouter_colonne_si_absente("equipages", "description", "TEXT NOT NULL DEFAULT ''")
	_ajouter_colonne_si_absente("equipages_membres", "rang", "VARCHAR(20) NOT NULL DEFAULT 'matelot'")

func _ajouter_colonne_si_absente(table: String, colonne: String, definition: String) -> void:
	db.query("PRAGMA table_info(%s);" % table)
	for ligne in db.query_result:
		if str(ligne["name"]) == colonne:
			return
	db.query("ALTER TABLE %s ADD COLUMN %s %s;" % [table, colonne, definition])

func _lire(requete: String) -> Array:
	if not disponible:
		return []
	db.query(requete)
	return db.query_result

func _ecrire(requete: String) -> bool:
	if not disponible:
		return false
	return db.query(requete)

func _dernier_id() -> int:
	db.query("SELECT last_insert_rowid() AS id;")
	if db.query_result.is_empty():
		return 0
	return int(db.query_result[0]["id"])

# échappe les apostrophes d'un texte pour l'insérer dans une requête
func _echapper(texte: String) -> String:
	return texte.replace("'", "''")
