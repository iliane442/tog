# equipages.gd — autoload : équipages (guildes de joueurs), alliances, flottes
# Prévu pour un MMO : les membres sont des joueurs identifiés par le nom de
# leur personnage (unique par compte). Les données vivent dans une base
# SQLite dédiée, séparée de la base de contenu glo.db réimportable.
#
# Rangs : capitaine (le fondateur), vice-capitaine (peut recruter, virer,
# gérer les alliances, la caisse et la description), matelot.
extends Node

const MEMBRES_MAX := 20        # capitaine compris
const DESCRIPTION_MAX := 200   # caractères
const GALIONS_MAX := 10
const PRIX_GALION := 100000
const NAVIRES := preload("res://scripts/world/catalogue_navires.gd")
const MONTANT_MAX := 999999999
const CHEMIN_BASE := "user://equipages.db"
# le serveur MMO porte les équipages en ligne dans sa propre base, sur
# la même machine que le jeu solo elle ne doit jamais toucher la même
const CHEMIN_BASE_SERVEUR := "user://mmo_equipages.db"

const RANG_CAPITAINE := "capitaine"
const RANG_VICE := "vice-capitaine"
const RANG_MATELOT := "matelot"

# état de l'équipage du joueur local :
# {id, nom, capitaine, niveau, caisse, galions, description, mon_rang}
# (vide si le joueur n'est ni capitaine ni membre d'un équipage)
var mon_equipage: Dictionary = {}
var db: SQLite
var disponible := false
var _base_serveur := false
var _comptes_lies := false

# compte connecté : l'équipage vit sur le serveur, l'état local n'est
# plus lu ni écrit (les lectures servent le miroir reçu par le réseau)
var en_ligne := false
# serveur uniquement : nom du personnage du joueur à l'origine de
# l'action en cours (les données identifient les joueurs par le nom
# de leur personnage)
var joueur_courant := ""
# dernier message serveur à afficher dans l'onglet Équipage (erreur
# ou confirmation d'une opération en ligne)
var dernier_message := ""
# miroirs de l'état serveur (en ligne) : membres, journal, autres
# équipages, flotte — servis par les lectures ci-dessous
var _miroir_membres: Array = []
var _miroir_journal: Array = []
var _miroir_autres: Array = []
var _miroir_flotte: Dictionary = {}
var _miroir_membres_flotte: Array = []

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
# (le joueur est identifié par le nom de son personnage, en ligne
# comme en solo)
func _recharger_mon_equipage() -> void:
	mon_equipage = {}
	if en_ligne and joueur_courant == "":
		return  # en ligne, l'état vient du serveur (instantanés réseau)
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
		"galions": int(ligne.get("galions", 0)),
		"description": str(ligne.get("description", "")),
		"mon_rang": RANG_CAPITAINE if capitaine else str(ligne.get("mon_rang", RANG_MATELOT)),
	}

# le joueur local : le nom de son personnage, en ligne comme en solo —
# côté serveur, celui du joueur à l'origine de l'action en cours
func _joueur() -> String:
	if joueur_courant != "":
		return joueur_courant
	# l'identité des équipages est le nom du personnage (unique en
	# ligne, vérifié à la création)
	return Personnage.nom

func suis_capitaine() -> bool:
	return not mon_equipage.is_empty() and str(mon_equipage["capitaine"]) == _joueur()

func suis_vice_capitaine() -> bool:
	return not mon_equipage.is_empty() and str(mon_equipage.get("mon_rang", "")) == RANG_VICE

# le capitaine et le vice-capitaine peuvent gérer l'équipage
func puis_je_gerer() -> bool:
	return suis_capitaine() or suis_vice_capitaine()

# --- passage en ligne / hors ligne ---

# le serveur MMO porte les équipages en ligne : sa base est dédiée pour
# ne jamais mélanger avec le fichier du jeu solo de la même machine
func basculer_serveur(chemin_comptes: String) -> void:
	if db != null:
		db.close_db()
	db = SQLite.new()
	db.path = CHEMIN_BASE_SERVEUR
	db.open_db()
	_creer_schema()
	db.query("SELECT COUNT(*) AS total FROM equipages;")
	disponible = not db.query_result.is_empty()
	_base_serveur = true
	_comptes_lies = _ecrire("ATTACH DATABASE '%s' AS comptes;" % _echapper(ProjectSettings.globalize_path(chemin_comptes)))
	if disponible:
		_recharger_mon_equipage()

# compte connecté : l'état reçu du serveur rempli les miroirs, la base
# locale n'est plus lue ni écrite (elle redevient la référence en solo)
func basculer_en_ligne() -> void:
	en_ligne = true
	joueur_courant = ""
	mon_equipage = {}
	_miroir_membres = []
	_miroir_journal = []
	_miroir_autres = []
	_miroir_flotte = {}
	_miroir_membres_flotte = []

# retour hors ligne : la base locale redevient la référence
func recharger_etat_local() -> void:
	en_ligne = false
	joueur_courant = ""
	dernier_message = ""
	_miroir_membres = []
	_miroir_journal = []
	_miroir_autres = []
	_miroir_flotte = {}
	_miroir_membres_flotte = []
	_recharger_mon_equipage()
	equipage_modifie.emit()

# instantané complet de mon équipage, envoyé par le serveur après chaque
# opération : tout l'onglet Équipage se resynchronise
func appliquer_snapshot(snapshot_json: String) -> void:
	var analyse: Variant = JSON.parse_string(snapshot_json)
	if not analyse is Dictionary:
		return
	var d: Dictionary = analyse
	var equipage: Variant = d.get("equipage", {})
	mon_equipage = equipage if equipage is Dictionary else {}
	_miroir_membres = d.get("membres", []) if d.get("membres", []) is Array else []
	_miroir_journal = d.get("journal", []) if d.get("journal", []) is Array else []
	_miroir_autres = d.get("autres", []) if d.get("autres", []) is Array else []
	var flotte: Variant = d.get("flotte", {})
	_miroir_flotte = flotte if flotte is Dictionary else {}
	_miroir_membres_flotte = d.get("membres_flotte", []) if d.get("membres_flotte", []) is Array else []
	equipage_modifie.emit()

# message du serveur (confirmation ou reflet d'une opération) : affiché
# par l'onglet Équipage au prochain rafraîchissement
func message_serveur(texte: String) -> void:
	if texte == "":
		return
	dernier_message = texte
	equipage_modifie.emit()

# --- Fondation et dissolution ---

func creer(nom: String) -> String:
	if en_ligne:
		if not mon_equipage.is_empty():
			return "Vous faites déjà partie d'un équipage"
		var nom_en_ligne := nom.strip_edges()
		if nom_en_ligne.length() < 2:
			return "Nom trop court"
		if nom_en_ligne.length() > 30:
			return "Nom trop long (30 caractères max)"
		Reseau.demander_equipage("creer", nom_en_ligne)
		return ""
	if not disponible:
		return "Base des équipages indisponible"
	if not mon_equipage.is_empty():
		return "Vous faites déjà partie d'un équipage"
	var nom_propre := nom.strip_edges()
	if nom_propre.length() < 2:
		return "Nom trop court"
	if nom_propre.length() > 30:
		return "Nom trop long (30 caractères max)"
	if not _ecrire("INSERT INTO equipages (nom, capitaine) VALUES ('%s', '%s');" % [
			_echapper(nom_propre), _echapper(_joueur())]):
		return "Ce nom d'équipage est déjà pris"
	_recharger_mon_equipage()
	_journaliser("%s fonde l'équipage." % _joueur())
	equipage_modifie.emit()
	return ""

# dissoudre l'équipage (capitaine uniquement) : membres virés, alliance
# rompue, journal effacé, flotte supprimée si elle se vide
func dissoudre() -> void:
	if en_ligne:
		if suis_capitaine():
			Reseau.demander_equipage("dissoudre", "")
		return
	if not suis_capitaine():
		return
	var id_equipage := int(mon_equipage["id"])
	var requetes: Array[String] = [
		"DELETE FROM equipages_membres WHERE equipage_id = %d;" % id_equipage,
		"DELETE FROM equipages_journal WHERE equipage_id = %d;" % id_equipage,
		"DELETE FROM equipages_diplomatie WHERE equipage_a = %d OR equipage_b = %d;" % [id_equipage, id_equipage],
		"DELETE FROM galions_equipage WHERE equipage_id = %d;" % id_equipage,
	]
	requetes.append_array(_requetes_depart_alliance(id_equipage))
	requetes.append("DELETE FROM equipages WHERE id = %d;" % id_equipage)
	if not _transaction(requetes):
		message_serveur("Impossible de dissoudre l’équipage.")
		return
	mon_equipage = {}
	equipage_modifie.emit()

# quitter l'équipage (simple membre, vice-capitaine compris)
func quitter() -> void:
	if en_ligne:
		if not mon_equipage.is_empty() and not suis_capitaine():
			Reseau.demander_equipage("quitter", "")
		return
	if mon_equipage.is_empty() or suis_capitaine():
		return
	var rang := str(mon_equipage.get("mon_rang", RANG_MATELOT))
	if not _retirer_membre(_joueur()):
		return
	if rang == RANG_VICE:
		_journaliser("Le vice-capitaine %s quitte l'équipage." % _joueur())
	else:
		_journaliser("%s quitte l'équipage." % _joueur())
	mon_equipage = {}
	equipage_modifie.emit()

# --- Membres ---

# membres du groupe hors capitaine : [{nom_joueur, rang}]
func liste_membres() -> Array:
	if en_ligne:
		return _miroir_membres.duplicate(true)
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
	if en_ligne:
		# en ligne, le recrutement devient une invitation : le serveur
		# pré-vérifie et la cible reçoit une popup à accepter
		var erreur_invitation := _valider_recrutement(nom)
		if erreur_invitation != "":
			return erreur_invitation
		Reseau.demander_equipage("ajouter", nom.strip_edges())
		return "Invitation envoyée"
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

# contrôles de recrutement communs (rang, places, nom), sans toucher la
# base : ils lisent l'état en mémoire, serveur comme client
func _valider_recrutement(nom: String) -> String:
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
	if en_ligne:
		if not puis_je_gerer():
			return "Seul le capitaine ou le vice-capitaine vire"
		Reseau.demander_equipage("virer", nom.strip_edges())
		return ""
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
	if not _retirer_membre(nom_propre):
		return "Échec du virement"
	if str(lignes[0]["rang"]) == RANG_VICE:
		_journaliser("%s révoque le vice-capitaine %s." % [_joueur(), nom_propre])
	else:
		_journaliser("%s vire %s de l'équipage." % [_joueur(), nom_propre])
	equipage_modifie.emit()
	return ""

func _retirer_membre(nom: String) -> bool:
	var id := int(mon_equipage["id"])
	return _transaction([
		"UPDATE galions_equipage SET pilote = NULL WHERE equipage_id = %d AND pilote = '%s';" % [id, _echapper(nom)],
		"DELETE FROM equipages_membres WHERE equipage_id = %d AND nom_joueur = '%s';" % [id, _echapper(nom)],
	])

# --- Rangs ---

# nomme un membre vice-capitaine (un seul à la fois) ; capitaine uniquement
func nommer_vice(nom: String) -> String:
	if en_ligne:
		if not suis_capitaine():
			return "Seul le capitaine nomme le vice-capitaine"
		Reseau.demander_equipage("nommer_vice", nom.strip_edges())
		return ""
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
	if en_ligne:
		if not suis_capitaine():
			return "Seul le capitaine peut destituer le vice-capitaine"
		Reseau.demander_equipage("destituer_vice", "")
		return ""
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

# Dépôt depuis la bourse personnelle, accessible à tout membre.
func deposer_berry(montant: int) -> String:
	if mon_equipage.is_empty():
		return "Vous n’êtes pas dans un équipage."
	if not montant_valide(montant):
		return "Montant invalide."
	if Personnage.berry < montant:
		return "Pas assez de Berry dans votre bourse."
	if en_ligne:
		Reseau.demander_equipage("deposer", "", montant)
		return ""
	var erreur := echanger_bourse(montant)
	if erreur.is_empty():
		Personnage.ajouter_berry(-montant)
		equipage_modifie.emit()
	return erreur

func retirer_berry(montant: int) -> String:
	if not puis_je_gerer():
		return "Seul le capitaine ou le vice-capitaine peut effectuer un retrait."
	if not montant_valide(montant):
		return "Montant invalide."
	if int(mon_equipage["caisse"]) < montant:
		return "Caisse insuffisante (%d Berry)." % int(mon_equipage["caisse"])
	if en_ligne:
		Reseau.demander_equipage("retirer", "", montant)
		return ""
	var erreur := echanger_bourse(-montant)
	if erreur.is_empty():
		Personnage.ajouter_berry(montant)
		equipage_modifie.emit()
	return erreur

func montant_valide(montant: int) -> bool:
	return montant > 0 and montant <= MONTANT_MAX

# Le solde du compte en ligne et le journal sont écrits avec la caisse.
func echanger_bourse(delta_caisse: int, id_compte: int = 0, profil_json: String = "") -> String:
	if mon_equipage.is_empty():
		return "Vous n’êtes pas dans un équipage."
	if not montant_valide(absi(delta_caisse)):
		return "Montant invalide."
	if delta_caisse < 0 and not puis_je_gerer():
		return "Seul le capitaine ou le vice-capitaine peut effectuer un retrait."
	var caisse := int(mon_equipage["caisse"])
	if caisse + delta_caisse < 0:
		return "Caisse insuffisante (%d Berry)." % caisse
	var id_equipage := int(mon_equipage["id"])
	var message := "%s dépose %d Berry à la caisse." if delta_caisse > 0 else "%s retire %d Berry de la caisse."
	var a_ecrire: Array[String] = [
		"UPDATE equipages SET caisse = caisse + (%d) WHERE id = %d;" % [delta_caisse, id_equipage],
		_requete_journal(id_equipage, message % [_joueur(), absi(delta_caisse)]),
	]
	if id_compte > 0:
		if not _comptes_lies:
			return "La caisse est momentanément indisponible."
		a_ecrire.append("UPDATE comptes.mmo_persos SET donnees = '%s', maj_le = datetime('now') WHERE compte_id = %d;" %
			[_echapper(profil_json), id_compte])
	if not _transaction(a_ecrire):
		return "Impossible de modifier la caisse."
	mon_equipage["caisse"] = caisse + delta_caisse
	return ""

func virer_berry(id_cible: int, montant: int) -> String:
	if not puis_je_gerer():
		return "Seul le capitaine ou le vice-capitaine peut faire un virement."
	if not montant_valide(montant):
		return "Montant invalide."
	var id_equipage := int(mon_equipage["id"])
	if id_cible <= 0 or id_cible == id_equipage:
		return "Choisissez un autre équipage."
	var caisse := int(mon_equipage["caisse"])
	if caisse < montant:
		return "Caisse insuffisante (%d Berry)." % caisse
	if en_ligne:
		Reseau.demander_equipage("virement", str(id_cible), montant)
		return ""
	var nom_cible := nom_equipage(id_cible)
	if nom_cible.is_empty():
		return "Équipage destinataire introuvable."
	if not _transaction([
		"UPDATE equipages SET caisse = caisse - %d WHERE id = %d;" % [montant, id_equipage],
		"UPDATE equipages SET caisse = caisse + %d WHERE id = %d;" % [montant, id_cible],
		_requete_journal(id_equipage, "%s vire %d Berry à « %s »." % [_joueur(), montant, nom_cible]),
		_requete_journal(id_cible, "« %s » a versé %d Berry dans la caisse." % [mon_equipage["nom"], montant]),
	]):
		return "Le virement a échoué."
	mon_equipage["caisse"] = caisse - montant
	equipage_modifie.emit()
	return ""

func acheter_galions(quantite: int, modele: String = "ateliers") -> String:
	if not puis_je_gerer():
		return "Seul le capitaine ou le vice-capitaine peut acheter des galions."
	if modele not in NAVIRES.GALIONS:
		return "Choisis un modèle de galion."
	if quantite < 1 or quantite > GALIONS_MAX:
		return "Quantité invalide."
	var galions := int(mon_equipage.get("galions", 0))
	if galions + quantite > GALIONS_MAX:
		return "La flotte ne peut pas dépasser %d galions." % GALIONS_MAX
	var prix := quantite * PRIX_GALION
	var caisse := int(mon_equipage["caisse"])
	if caisse < prix:
		return "Caisse insuffisante. L’achat coûte %d Berry." % prix
	if en_ligne:
		Reseau.demander_equipage("acheter_galions", modele, quantite)
		return ""
	var id_equipage := int(mon_equipage["id"])
	var requetes: Array[String] = [
		"UPDATE equipages SET caisse = caisse - %d, galions = galions + %d WHERE id = %d;" %
			[prix, quantite, id_equipage],
		_requete_journal(id_equipage, "%s achète %d × %s pour %d Berry." % [_joueur(), quantite, NAVIRES.fiche(modele)["nom"], prix]),
	]
	for _indice in range(quantite):
		requetes.append("INSERT INTO galions_equipage (equipage_id, modele) VALUES (%d, '%s');" % [id_equipage, modele])
	if not _transaction(requetes):
		return "Impossible d’acheter les galions."
	mon_equipage["caisse"] = caisse - prix
	mon_equipage["galions"] = galions + quantite
	equipage_modifie.emit()
	return ""

func liste_galions() -> Array:
	if mon_equipage.is_empty():
		return []
	if en_ligne:
		return mon_equipage.get("flotte_navires", [])
	return _lire("SELECT id, modele, COALESCE(pilote, '') AS pilote FROM galions_equipage WHERE equipage_id = %d ORDER BY id;" % int(mon_equipage["id"]))

func galion_du_joueur(nom: String) -> Dictionary:
	if en_ligne:
		for galion: Dictionary in liste_galions():
			if galion["pilote"] == nom:
				return galion
		return {}
	var lignes := _lire("SELECT id, equipage_id, modele, pilote, donnees FROM galions_equipage WHERE pilote = '%s';" % _echapper(nom))
	return {} if lignes.is_empty() else lignes[0]

func assigner_galion(id: int, pilote: String) -> String:
	if not suis_capitaine():
		return "Seul le capitaine assigne les galions."
	if en_ligne:
		Reseau.demander_equipage("assigner_galion", pilote, id)
		return ""
	var equipage := int(mon_equipage["id"])
	if pilote != "" and pilote not in noms_de_l_equipage(equipage):
		return "Ce joueur ne fait pas partie de l’équipage."
	var galions := _lire("SELECT modele, pilote FROM galions_equipage WHERE id = %d AND equipage_id = %d;" % [id, equipage])
	if galions.is_empty() or galions[0]["modele"] not in NAVIRES.GALIONS:
		return "Ce galion doit être choisi avant son attribution."
	var requetes: Array[String] = []
	var valeur := "NULL"
	if pilote != "":
		valeur = "'%s'" % _echapper(pilote)
		requetes.append("UPDATE galions_equipage SET pilote = NULL WHERE equipage_id = %d AND pilote = %s;" % [equipage, valeur])
	requetes.append("UPDATE galions_equipage SET pilote = %s WHERE id = %d;" % [valeur, id])
	if not _transaction(requetes):
		return "L’attribution du galion a échoué."
	equipage_modifie.emit()
	return ""

func choisir_galion(id: int, modele: String) -> String:
	if not suis_capitaine() or modele not in NAVIRES.GALIONS:
		return "Le capitaine choisit le modèle du galion."
	if en_ligne:
		Reseau.demander_equipage("choisir_galion", modele, id)
		return ""
	var ligne := _lire("SELECT id FROM galions_equipage WHERE id = %d AND equipage_id = %d AND modele = '';" % [id, int(mon_equipage["id"])])
	if ligne.is_empty() or not _ecrire("UPDATE galions_equipage SET modele = '%s' WHERE id = %d;" % [modele, id]):
		return "Ce galion possède déjà un modèle."
	equipage_modifie.emit()
	return ""

func donnees_galion(galion: Dictionary) -> Dictionary:
	var donnees: Variant = JSON.parse_string(str(galion.get("donnees", "{}")))
	return donnees if donnees is Dictionary else {}

func enregistrer_galion(galion: Dictionary, donnees: Dictionary, compte := 0, profil: Dictionary = {}) -> bool:
	var requetes: Array[String] = [
		"UPDATE galions_equipage SET donnees = '%s' WHERE id = %d;" % [_echapper(JSON.stringify(donnees)), int(galion["id"])],
	]
	if compte != 0:
		if not _comptes_lies:
			return false
		requetes.append("UPDATE comptes.mmo_persos SET donnees = '%s', maj_le = datetime('now') WHERE compte_id = %d;" %
			[_echapper(JSON.stringify(profil)), compte])
	return _transaction(requetes)

# --- Description ---

func changer_description(texte: String) -> String:
	if en_ligne:
		if not puis_je_gerer():
			return "Seul le capitaine ou le vice-capitaine modifie la description"
		if texte.strip_edges().length() > DESCRIPTION_MAX:
			return "Description trop longue (%d caractères max)" % DESCRIPTION_MAX
		Reseau.demander_equipage("description", texte)
		return ""
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

# --- Aides serveur ---

# ids des équipages de la flotte d'un équipage donné (lui compris s'il
# en fait partie) — le serveur s'en sert pour rafraîchir les membres de
# flotte concernés par une alliance ou une rupture
func equipages_de_la_flotte_de(id_equipage: int) -> Array:
	var ids: Array = []
	for ligne in _lire(
			"SELECT ef2.equipage_id FROM equipage_flotte ef2"
			+ " WHERE ef2.flotte_id = (SELECT flotte_id FROM equipage_flotte"
			+ " WHERE equipage_id = %d);" % id_equipage):
		ids.append(int(ligne["equipage_id"]))
	return ids

# noms de personnages de tous les membres d'un équipage, capitaine
# compris — le serveur les résout en pairs en ligne pour diffuser
func noms_de_l_equipage(id_equipage: int) -> Array:
	var noms: Array = []
	for ligne in _lire("SELECT capitaine FROM equipages WHERE id = %d;" % id_equipage):
		noms.append(str(ligne["capitaine"]))
	for ligne in _lire(
			"SELECT nom_joueur FROM equipages_membres WHERE equipage_id = %d;"
			% id_equipage):
		noms.append(str(ligne["nom_joueur"]))
	return noms

# nom d'un équipage par son id (message d'alliance du serveur)
func nom_equipage(id_equipage: int) -> String:
	var lignes := _lire("SELECT nom FROM equipages WHERE id = %d;" % id_equipage)
	if lignes.is_empty():
		return ""
	return str(lignes[0]["nom"])

# --- Journal de bord ---

# ajoute une entrée au journal de l'équipage courant
func _journaliser(message: String) -> void:
	if mon_equipage.is_empty():
		return
	_ecrire(_requete_journal(int(mon_equipage["id"]), message))

func _requete_journal(id_equipage: int, message: String) -> String:
	return "INSERT INTO equipages_journal (equipage_id, message) VALUES (%d, '%s');" % [id_equipage, _echapper(message)]

# dernières entrées du journal : [{heure, message}], plus récentes d'abord
# (l'heure est découpée côté GDScript : le "%" de strftime casserait
# le formatage des requêtes)
func liste_journal(limite: int = 10) -> Array:
	if en_ligne:
		return _miroir_journal.duplicate(true)
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
	if en_ligne:
		return _miroir_flotte.duplicate(true)
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
	if en_ligne:
		return _miroir_membres_flotte.duplicate(true)
	var flotte := ma_flotte()
	if flotte.is_empty():
		return []
	return _lire(
		"SELECT e.id, e.nom, e.capitaine FROM equipages e"
		+ " JOIN equipage_flotte ef ON ef.equipage_id = e.id"
		+ " WHERE ef.flotte_id = %d ORDER BY e.nom;" % int(flotte["id"]))

# Annuaire des autres équipages avec effectifs et état diplomatique.
func autres_equipages() -> Array:
	if en_ligne:
		return _miroir_autres.duplicate(true)
	if not disponible:
		return []
	var id_equipage := int(mon_equipage.get("id", 0))
	return _lire((
		"SELECT e.id, e.nom, e.capitaine, e.niveau,"
		+ " COALESCE(d.etat, '') AS etat, COALESCE(d.initiateur, 0) AS initiateur,"
		+ " 1 + (SELECT COUNT(*) FROM equipages_membres m WHERE m.equipage_id = e.id) AS membres"
		+ " FROM equipages e LEFT JOIN equipages_diplomatie d"
		+ " ON d.equipage_a = MIN(e.id, %d) AND d.equipage_b = MAX(e.id, %d)"
		+ " WHERE e.id != %d ORDER BY e.nom;") % [id_equipage, id_equipage, id_equipage])

func proposer_alliance(id_cible: int) -> String:
	if not puis_je_gerer():
		return "Seul le capitaine ou le vice-capitaine gère les alliances."
	var id_equipage := int(mon_equipage["id"])
	if id_cible <= 0 or id_cible == id_equipage:
		return "Choisissez un autre équipage."
	if en_ligne:
		Reseau.demander_equipage("alliance", str(id_cible))
		return ""
	var nom_cible := nom_equipage(id_cible)
	if nom_cible.is_empty():
		return "Équipage introuvable."
	var erreur := _verifier_alliance(id_equipage, id_cible)
	if not erreur.is_empty():
		return erreur
	if not _base_serveur:
		return _conclure_alliance(id_equipage, id_cible, nom_cible)
	if not _relation_entre(id_equipage, id_cible).is_empty():
		return "Une demande d’alliance est déjà en attente."
	if not _transaction([
		"INSERT INTO equipages_diplomatie VALUES (%d, %d, %d, 'proposition');" %
			[mini(id_equipage, id_cible), maxi(id_equipage, id_cible), id_equipage],
		_requete_journal(id_equipage, "Demande d’alliance envoyée à « %s »." % nom_cible),
		_requete_journal(id_cible, "« %s » propose une alliance." % mon_equipage["nom"]),
	]):
		return "Impossible d’envoyer la demande d’alliance."
	equipage_modifie.emit()
	return ""

func repondre_alliance(id_cible: int, accepter: bool) -> String:
	if not puis_je_gerer():
		return "Seul le capitaine ou le vice-capitaine gère les alliances."
	if en_ligne:
		Reseau.demander_equipage("accepter_alliance" if accepter else "refuser_alliance", str(id_cible))
		return ""
	var id_equipage := int(mon_equipage["id"])
	var relation := _relation_entre(id_equipage, id_cible)
	if relation.get("etat", "") != "proposition":
		return "Cette proposition n’est plus disponible."
	if accepter:
		if int(relation["initiateur"]) != id_cible:
			return "Seul l’équipage destinataire peut accepter l’alliance."
		var erreur := _verifier_alliance(id_equipage, id_cible)
		if not erreur.is_empty():
			return erreur
		return _conclure_alliance(id_equipage, id_cible, nom_equipage(id_cible))
	var action := "retire sa proposition d’alliance" if int(relation["initiateur"]) == id_equipage else "refuse l’alliance"
	if not _transaction([
		_requete_supprimer_relation(id_equipage, id_cible),
		_requete_journal(id_cible, "« %s » %s." % [mon_equipage["nom"], action]),
	]):
		return "Impossible de fermer la proposition."
	equipage_modifie.emit()
	return ""

func declarer_guerre(id_cible: int) -> String:
	if not puis_je_gerer():
		return "Seul le capitaine ou le vice-capitaine peut déclarer une guerre."
	var id_equipage := int(mon_equipage["id"])
	if id_cible <= 0 or id_cible == id_equipage:
		return "Choisissez un autre équipage."
	if est_allie(id_cible):
		return "Quittez l’alliance avant de déclarer la guerre à cet équipage."
	if en_ligne:
		Reseau.demander_equipage("guerre", str(id_cible))
		return ""
	var nom_cible := nom_equipage(id_cible)
	if nom_cible.is_empty():
		return "Équipage introuvable."
	if _relation_entre(id_equipage, id_cible).get("etat", "") == "guerre":
		return "Vos équipages sont déjà en guerre."
	if not _transaction([
		_requete_supprimer_relation(id_equipage, id_cible),
		"INSERT INTO equipages_diplomatie VALUES (%d, %d, %d, 'guerre');" %
			[mini(id_equipage, id_cible), maxi(id_equipage, id_cible), id_equipage],
		_requete_journal(id_equipage, "Guerre déclarée à « %s »." % nom_cible),
		_requete_journal(id_cible, "« %s » vous déclare la guerre." % mon_equipage["nom"]),
	]):
		return "Impossible de déclarer la guerre."
	equipage_modifie.emit()
	return ""

func lever_guerre(id_cible: int) -> String:
	if not puis_je_gerer():
		return "Seul le capitaine ou le vice-capitaine peut lever une guerre."
	if en_ligne:
		Reseau.demander_equipage("lever_guerre", str(id_cible))
		return ""
	var id_equipage := int(mon_equipage["id"])
	var relation := _relation_entre(id_equipage, id_cible)
	if relation.get("etat", "") != "guerre" or int(relation["initiateur"]) != id_equipage:
		return "Seul l’équipage qui a déclaré la guerre peut la lever."
	if not _transaction([
		_requete_supprimer_relation(id_equipage, id_cible),
		_requete_journal(id_equipage, "Fin de la guerre contre « %s »." % nom_equipage(id_cible)),
		_requete_journal(id_cible, "« %s » a levé sa déclaration de guerre." % mon_equipage["nom"]),
	]):
		return "Impossible de lever la guerre."
	equipage_modifie.emit()
	return ""

func _relation_entre(id_a: int, id_b: int) -> Dictionary:
	var lignes := _lire("SELECT initiateur, etat FROM equipages_diplomatie WHERE equipage_a = %d AND equipage_b = %d;" %
		[mini(id_a, id_b), maxi(id_a, id_b)])
	return {} if lignes.is_empty() else lignes[0]

func _requete_supprimer_relation(id_a: int, id_b: int) -> String:
	return "DELETE FROM equipages_diplomatie WHERE equipage_a = %d AND equipage_b = %d;" % [mini(id_a, id_b), maxi(id_a, id_b)]

func _verifier_alliance(id_equipage: int, id_cible: int) -> String:
	if est_allie(id_cible):
		return "Alliance déjà conclue."
	var membres := equipages_de_la_flotte_de(id_equipage)
	var membres_cible := equipages_de_la_flotte_de(id_cible)
	if not membres.is_empty() and not membres_cible.is_empty():
		return "Les deux équipages sont déjà dans des alliances différentes."
	if membres.is_empty():
		membres = [id_equipage]
	if membres_cible.is_empty():
		membres_cible = [id_cible]
	for id: int in membres:
		for autre: int in membres_cible:
			if _relation_entre(id, autre).get("etat", "") == "guerre":
				return "Une guerre en cours empêche cette alliance."
	return ""

func _conclure_alliance(id_equipage: int, id_cible: int, nom_cible: String) -> String:
	var flotte := ma_flotte()
	var flotte_cible := _lire("SELECT flotte_id FROM equipage_flotte WHERE equipage_id = %d;" % id_cible)
	var a_ecrire: Array[String] = []
	if flotte.is_empty() and flotte_cible.is_empty():
		var nom_base := "Flotte " + str(mon_equipage["nom"])
		var nom_flotte := nom_base
		var numero := 1
		while not _lire("SELECT 1 FROM flottes WHERE nom = '%s';" % _echapper(nom_flotte)).is_empty():
			numero += 1
			nom_flotte = "%s (%d)" % [nom_base, numero]
		a_ecrire.append("INSERT INTO flottes (nom) VALUES ('%s');" % _echapper(nom_flotte))
		a_ecrire.append("INSERT INTO equipage_flotte (equipage_id, flotte_id)"
			+ " SELECT id, (SELECT MAX(id) FROM flottes) FROM equipages WHERE id IN (%d, %d);" % [id_equipage, id_cible])
	else:
		var id_flotte := int(flotte["id"]) if not flotte.is_empty() else int(flotte_cible[0]["flotte_id"])
		var nouveau := id_cible if not flotte.is_empty() else id_equipage
		a_ecrire.append("INSERT INTO equipage_flotte (equipage_id, flotte_id) VALUES (%d, %d);" % [nouveau, id_flotte])
	var membres := "SELECT equipage_id FROM equipage_flotte WHERE flotte_id = (SELECT flotte_id FROM equipage_flotte WHERE equipage_id = %d)" % id_equipage
	a_ecrire.append("DELETE FROM equipages_diplomatie WHERE etat = 'proposition' AND equipage_a IN (%s) AND equipage_b IN (%s);" % [membres, membres])
	a_ecrire.append(_requete_journal(id_equipage, "Alliance conclue avec « %s »." % nom_cible))
	a_ecrire.append(_requete_journal(id_cible, "Alliance conclue avec « %s »." % mon_equipage["nom"]))
	if not _transaction(a_ecrire):
		return "Impossible de conclure l’alliance."
	equipage_modifie.emit()
	return ""

func rompre_alliance() -> String:
	if not puis_je_gerer():
		return "Seul le capitaine ou le vice-capitaine peut rompre l’alliance."
	if ma_flotte().is_empty():
		return "Votre équipage n’est dans aucune alliance."
	if en_ligne:
		Reseau.demander_equipage("rompre", "")
		return ""
	var id_equipage := int(mon_equipage["id"])
	var a_ecrire := _requetes_depart_alliance(id_equipage)
	a_ecrire.append(_requete_journal(id_equipage, "%s quitte l’alliance." % _joueur()))
	if not _transaction(a_ecrire):
		return "Impossible de quitter l’alliance."
	equipage_modifie.emit()
	return ""

# Une alliance à un seul équipage se dissout.
func _requetes_depart_alliance(id_equipage: int) -> Array[String]:
	var lignes := _lire("SELECT flotte_id FROM equipage_flotte WHERE equipage_id = %d;" % id_equipage)
	if lignes.is_empty():
		return []
	var id_flotte := int(lignes[0]["flotte_id"])
	return [
		"DELETE FROM equipage_flotte WHERE equipage_id = %d;" % id_equipage,
		"DELETE FROM equipage_flotte WHERE flotte_id = %d AND (SELECT COUNT(*) FROM equipage_flotte WHERE flotte_id = %d) <= 1;" %
			[id_flotte, id_flotte],
		"DELETE FROM flottes WHERE id = %d AND NOT EXISTS (SELECT 1 FROM equipage_flotte WHERE flotte_id = %d);" %
			[id_flotte, id_flotte],
	]

# mon équipage est-il allié à l'équipage donné ?
func est_allie(id_equipage: int) -> bool:
	if en_ligne:
		for equipage_allie in _miroir_membres_flotte:
			if int(equipage_allie.get("id", -1)) == id_equipage:
				return true
		return false
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
	db.query(
		"CREATE TABLE IF NOT EXISTS equipages_diplomatie ("
		+ " equipage_a INTEGER NOT NULL REFERENCES equipages(id),"
		+ " equipage_b INTEGER NOT NULL REFERENCES equipages(id),"
		+ " initiateur INTEGER NOT NULL,"
		+ " etat TEXT NOT NULL CHECK (etat IN ('proposition', 'guerre')),"
		+ " CHECK (equipage_a < equipage_b AND initiateur IN (equipage_a, equipage_b)),"
		+ " PRIMARY KEY (equipage_a, equipage_b));")
	_ajouter_colonne_si_absente("equipages", "galions",
		"INTEGER NOT NULL DEFAULT 0 CHECK (galions BETWEEN 0 AND %d)" % GALIONS_MAX)
	# bases créées avant ces colonnes : migration douce
	_ajouter_colonne_si_absente("equipages", "caisse", "INTEGER NOT NULL DEFAULT 0")
	_ajouter_colonne_si_absente("equipages", "description", "TEXT NOT NULL DEFAULT ''")
	_ajouter_colonne_si_absente("equipages_membres", "rang", "VARCHAR(20) NOT NULL DEFAULT 'matelot'")
	db.query("CREATE TABLE IF NOT EXISTS galions_equipage ("
		+ " id INTEGER PRIMARY KEY AUTOINCREMENT, equipage_id INTEGER NOT NULL REFERENCES equipages(id),"
		+ " modele TEXT NOT NULL DEFAULT '', pilote TEXT UNIQUE, donnees TEXT NOT NULL DEFAULT '{}');")
	db.query("CREATE INDEX IF NOT EXISTS galions_par_equipage ON galions_equipage(equipage_id);")
	# Les anciens galions comptabilisés deviennent des navires à spécialiser.
	db.query("WITH RECURSIVE suite(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM suite WHERE n < %d)" % GALIONS_MAX
		+ " INSERT INTO galions_equipage (equipage_id)"
		+ " SELECT e.id FROM equipages e JOIN suite"
		+ " ON suite.n <= e.galions - (SELECT COUNT(*) FROM galions_equipage g WHERE g.equipage_id = e.id);")

func _ajouter_colonne_si_absente(table: String, colonne: String, definition: String) -> void:
	db.query("PRAGMA table_info(%s);" % table)
	for ligne in db.query_result:
		if str(ligne["name"]) == colonne:
			return
	db.query("ALTER TABLE %s ADD COLUMN %s %s;" % [table, colonne, definition])

func _lire(requete: String) -> Array:
	if not disponible or not db.query(requete):
		return []
	return db.query_result

func _ecrire(requete: String) -> bool:
	if not disponible:
		return false
	return db.query(requete)

func _transaction(requetes: Array[String]) -> bool:
	if not _ecrire("BEGIN IMMEDIATE;"):
		return false
	for requete in requetes:
		if not _ecrire(requete):
			_ecrire("ROLLBACK;")
			return false
	if _ecrire("COMMIT;"):
		return true
	_ecrire("ROLLBACK;")
	return false

# échappe les apostrophes d'un texte pour l'insérer dans une requête
func _echapper(texte: String) -> String:
	return texte.replace("'", "''")
