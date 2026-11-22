# hotel_ventes.gd — autoload : hôtel des ventes (HDV)
# Vendeurs PNJ proposant des objets contre des Berry, et mises en vente
# pour le joueur : des acheteurs simulés les achètent au fil du temps,
# selon le prix demandé face au prix officiel de l'objet.
extends Node

const CHEMIN_HDV := "user://hdv.cfg"
const NB_OFFRES := 12
const PERIODE_REMPLISSAGE := 300  # secondes entre deux réapprovisionnements du stock
const PERIODE_TIRAGE := 60.0      # secondes entre deux visites d'acheteurs simulés
const COMMISSION := 0.02          # part de l'HDV sur une vente réussie

signal hdv_modifie

# offres des vendeurs de l'HDV : [{item, prix, quantite}]
var offres: Array = []
# mises en vente du joueur : [{item, quantite, prix_unite, date}] —
# en ligne, extraction locale du miroir partagé (mes lignes seulement)
var ventes: Array = []
var _dernier_remplissage := 0.0
# compte connecté : les mises en vente vivent sur le serveur, tout le
# monde les voit et les achète (les offres des vendeurs PNJ restent
# locales à chaque joueur)
var en_ligne := false
# miroir des mises en vente du serveur : [{id, vendeur, item,
# quantite, prix_unite}]
var _miroir_hdventes: Array = []
# dernier message serveur à afficher dans l'onglet HDV
var dernier_message := ""

# --- passage en ligne / hors ligne ---

func basculer_en_ligne() -> void:
	en_ligne = true
	ventes = []
	_miroir_hdventes = []
	dernier_message = ""

func recharger_etat_local() -> void:
	en_ligne = false
	_miroir_hdventes = []
	dernier_message = ""
	_charger()
	hdv_modifie.emit()

# instantané complet des mises en vente du serveur
func appliquer_hdventes(snapshot_json: String) -> void:
	var analyse: Variant = JSON.parse_string(snapshot_json)
	_miroir_hdventes = analyse if analyse is Array else []
	if en_ligne:
		_maj_mes_ventes_en_ligne()
	hdv_modifie.emit()

# message du serveur (confirmation ou refus d'une action en ligne)
func message_serveur(texte: String) -> void:
	if texte == "":
		return
	dernier_message = texte
	hdv_modifie.emit()

# mes mises en vente = mes lignes du miroir (identifiées par compte)
func _maj_mes_ventes_en_ligne() -> void:
	ventes = []
	for mise in _miroir_hdventes:
		if mise is Dictionary and str(mise.get("vendeur", "")) == Reseau.pseudo:
			ventes.append(mise)

# mises en vente des AUTRES joueurs (achetables) : vide hors ligne
func ventes_joueurs() -> Array:
	var autres: Array = []
	if not en_ligne:
		return autres
	for mise in _miroir_hdventes:
		if mise is Dictionary and str(mise.get("vendeur", "")) != Reseau.pseudo:
			autres.append(mise)
	return autres

func _ready() -> void:
	_charger()
	_ajouter_offre_parchemin()
	_verifier_remplissage()
	var minuteur := Timer.new()
	minuteur.wait_time = PERIODE_TIRAGE
	minuteur.autostart = true
	minuteur.timeout.connect(_tirer_ventes)
	add_child(minuteur)

# secondes restantes avant le prochain réapprovisionnement du stock
func secondes_avant_remplissage() -> int:
	return maxi(roundi(_dernier_remplissage + PERIODE_REMPLISSAGE - Time.get_unix_time_from_system()), 0)

func _verifier_remplissage() -> void:
	if Time.get_unix_time_from_system() - _dernier_remplissage >= PERIODE_REMPLISSAGE:
		remplir_stock()

# régénère les offres de vendeurs depuis la table items (objets actifs,
# vendables, au niveau du joueur +2, prix dans une marge du prix officiel)
func remplir_stock() -> void:
	_dernier_remplissage = Time.get_unix_time_from_system()
	offres.clear()
	_ajouter_offre_parchemin()
	if BaseDonnees.disponible:
		for ligne in BaseDonnees.lire(
			"SELECT id, type, base_price FROM items WHERE is_active = 1 AND is_tradable = 1"
			+ " AND id != %d AND base_price > 0 AND min_level <= %d ORDER BY RANDOM() LIMIT %d;"
			% [BaseDonnees.ID_PARCHEMIN_REATTRIBUTION, Personnage.niveau + 2, NB_OFFRES]):
			var type := str(ligne["type"]).to_lower()
			var empilable := type in ["consumable", "consummable", "resource", "ressource"]
			offres.append({
				"item": str(ligne["id"]),
				"prix": maxi(1, roundi(int(ligne["base_price"]) * randf_range(1.0, 1.6))),
				"quantite": randi_range(1, 3) if empilable else 1,
			})
	_sauver()
	hdv_modifie.emit()

func _ajouter_offre_parchemin() -> void:
	var id := str(BaseDonnees.ID_PARCHEMIN_REATTRIBUTION)
	if offres.any(func(offre): return str(offre["item"]) == id):
		return
	var prix := int(Inventaire.details_objet(id).get("prix", 0))
	if prix > 0:
		offres.push_front({"item": id, "prix": prix, "quantite": 1})

# achète une offre de vendeur ; renvoie "" si réussi, sinon la raison
func acheter(index: int) -> String:
	if index < 0 or index >= offres.size():
		return "Offre introuvable"
	var offre: Dictionary = offres[index]
	var total := int(offre["prix"]) * int(offre["quantite"])
	if Personnage.berry < total:
		return "Pas assez de Berry"
	Personnage.ajouter_berry(-total)
	Inventaire.ajouter_objet(str(offre["item"]), int(offre["quantite"]))
	if str(offre["item"]).to_int() != BaseDonnees.ID_PARCHEMIN_REATTRIBUTION:
		offres.remove_at(index)
	_sauver()
	hdv_modifie.emit()
	return ""

# met des objets de l'inventaire en vente ; renvoie "" si accepté
func mettre_en_vente(id: String, quantite: int, prix_unite: int) -> String:
	if quantite < 1:
		return "Quantité invalide"
	if prix_unite < 1:
		return "Prix invalide"
	if int(Inventaire.objets.get(id, 0)) < quantite:
		return "Pas assez de cet objet"
	Inventaire.retirer_objet(id, quantite)
	if en_ligne:
		# les objets partent tout de suite, l'offre part au serveur et
		# devient visible pour tous les joueurs connectés
		Reseau.demander_hdvente("vendre", 0, id, quantite, prix_unite)
		return ""
	ventes.append({
		"item": id,
		"quantite": quantite,
		"prix_unite": prix_unite,
		"date": Time.get_unix_time_from_system(),
	})
	_sauver()
	hdv_modifie.emit()
	return ""

# achète la mise en vente d'un autre joueur ; renvoie "" si la
# demande part au serveur (livraison et débit confirmés par lui)
func acheter_joueur(index: int) -> String:
	var liste := ventes_joueurs()
	if liste.is_empty():
		return "Aucune vente de joueur en cours"
	if index < 0 or index >= liste.size():
		return "Offre introuvable"
	var mise: Dictionary = liste[index]
	var total := int(mise.get("prix_unite", 0)) * int(mise.get("quantite", 0))
	if Personnage.berry < total:
		return "Pas assez de Berry (%d requis)" % total
	Reseau.demander_hdvente("acheter", int(mise.get("id", 0)))
	return ""

# retire une mise en vente : les objets retournent à l'inventaire
func retirer(index: int) -> bool:
	if index < 0 or index >= ventes.size():
		return false
	if en_ligne:
		# le serveur vérifie le propriétaire et renvoie les objets par
		# livraison réseau (l'offre disparaît pour tout le monde)
		var id_offre := int((ventes[index] as Dictionary).get("id", 0))
		if id_offre <= 0:
			return false
		Reseau.demander_hdvente("retirer", id_offre)
		return true
	var mise: Dictionary = ventes[index]
	Inventaire.ajouter_objet(str(mise["item"]), int(mise["quantite"]))
	ventes.remove_at(index)
	_sauver()
	hdv_modifie.emit()
	return true

# tirage périodique : chaque mise en vente reçoit la visite d'un acheteur
# simulé ; plus le prix demandé est proche du prix officiel, plus il achète
func _tirer_ventes() -> void:
	if en_ligne:
		return  # en ligne, de vrais joueurs achètent : pas de simulation
	var vendu := false
	for i in range(ventes.size() - 1, -1, -1):
		var mise: Dictionary = ventes[i]
		if randf() <= _chance_vente(mise):
			var gains: int = floori(
				int(mise["prix_unite"]) * int(mise["quantite"]) * (1.0 - COMMISSION))
			Personnage.ajouter_berry(gains)
			ventes.remove_at(i)
			vendu = true
	if vendu:
		_sauver()
		hdv_modifie.emit()

func _chance_vente(mise: Dictionary) -> float:
	var details := Inventaire.details_objet(str(mise["item"]))
	var prix_officiel := maxi(int(details.get("prix", 0)), 1)
	var rapport: float = float(mise["prix_unite"]) / float(prix_officiel)
	var chance := clampf(0.8 - 0.4 * (rapport - 1.0), 0.05, 0.8)
	if int(details.get("niveau_min", 1)) > Personnage.niveau:
		chance *= 0.2
	return chance

# remet l'HDV à zéro (réinitialisation debug du perso)
func reinitialiser() -> void:
	offres.clear()
	ventes.clear()
	remplir_stock()

func _sauver() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("hdv", "dernier_remplissage", _dernier_remplissage)
	cfg.set_value("hdv", "offres", JSON.stringify(offres))
	cfg.set_value("hdv", "ventes", JSON.stringify(ventes))
	cfg.save(CHEMIN_HDV)

func _charger() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CHEMIN_HDV) != OK:
		return
	_dernier_remplissage = float(cfg.get_value("hdv", "dernier_remplissage", 0.0))
	offres = _liste_propre(JSON.parse_string(str(cfg.get_value("hdv", "offres", "[]"))),
		["item", "prix", "quantite"])
	ventes = _liste_propre(JSON.parse_string(str(cfg.get_value("hdv", "ventes", "[]"))),
		["item", "quantite", "prix_unite", "date"])

# reconstruit un tableau de dictionnaires propre (le JSON rend des réels)
func _liste_propre(brut: Variant, cles: Array) -> Array:
	var resultat: Array = []
	if brut is Array:
		for element in brut:
			if element is Dictionary:
				var propre := {}
				for cle in cles:
					propre[cle] = element.get(cle, 0)
				resultat.append(propre)
	return resultat
