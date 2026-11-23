# inventaire.gd — autoload
extends Node

var objets: Dictionary = {}  # id -> quantité
var _cales_navire: Dictionary = {}

# Noms affichés dans l'inventaire (déclarez vos objets ici)
var noms: Dictionary = {
	"potion": "Potion de soin",
	"epee": "Épée",
}

signal inventaire_modifie

# items déjà rencontrés par le joueur (id -> true) — alimente le wiki d'objets
const CHEMIN_CONNUS := "user://items_connus.cfg"
var items_connus: Dictionary = {}

# sauvegarde du contenu de l'inventaire (id -> quantité)
const CHEMIN_SAUVEGARDE := "user://inventaire.cfg"

func _ready() -> void:
	_charger_connus()
	if BaseDonnees.disponible:
		charger_noms_depuis_base()
	if not _charger_objets():
		_ajouter_objets_depart()

func _charger_connus() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CHEMIN_CONNUS) != OK:
		return
	for id in cfg.get_value("connus", "ids", PackedStringArray([])):
		items_connus[str(id)] = true

func _sauver_connus() -> void:
	var cfg := ConfigFile.new()
	var ids := PackedStringArray(items_connus.keys())
	cfg.set_value("connus", "ids", ids)
	cfg.save(CHEMIN_CONNUS)

# tout objet qui entre dans l'inventaire est désormais connu du joueur
func _marquer_connu(id: String) -> void:
	if id != "" and not items_connus.has(id):
		items_connus[id] = true
		_sauver_connus()

# variante sans écriture fichier pour les ajouts en lot
func _marquer_connu_sans_sauver(id: String) -> void:
	if id != "" and not items_connus.has(id):
		items_connus[id] = true

func est_connu(id: String) -> bool:
	return items_connus.has(id)

func _ajouter_objets_depart() -> void:
	# Objets de départ pour tester le menu — ids de la table `items`
	ajouter_objet("12", 3)  # Potion de soin
	ajouter_objet("1", 1)   # Épée en bois
	ajouter_objet("3", 1)   # Katana

# charge l'inventaire sauvegardé ; faux si aucune sauvegarde exploitable
func _charger_objets() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(CHEMIN_SAUVEGARDE) != OK:
		return false
	objets = cfg.get_value("inventaire", "objets", {}).duplicate()
	var cales: Variant = cfg.get_value("inventaire", "cales_navire", {})
	if cales is Dictionary:
		_cales_navire = cales
	return cfg.has_section_key("inventaire", "objets")

func _sauver_objets() -> Error:
	var cfg := ConfigFile.new()
	cfg.set_value("inventaire", "objets", objets)
	cfg.set_value("inventaire", "cales_navire", _cales_navire)
	var temporaire := CHEMIN_SAUVEGARDE + ".tmp"
	var erreur := cfg.save(temporaire)
	if erreur != OK:
		return erreur
	return DirAccess.rename_absolute(temporaire, CHEMIN_SAUVEGARDE)

func _proprietaire_cale() -> String:
	if Personnage.en_ligne:
		return JSON.stringify([Reseau.adresse_preferee, Reseau.pseudo.to_lower()])
	return "solo"

func objets_en_cale() -> Dictionary:
	var cale: Variant = _cales_navire.get(_proprietaire_cale(), {})
	return cale.duplicate() if cale is Dictionary else {}

func dans_sac_ou_cale(id: String) -> bool:
	return objets.has(id) or _cales_navire.get(_proprietaire_cale(), {}).has(id)

func transferer_cale(id: String, quantite: int, depot: bool) -> bool:
	if not ("cale" in Personnage.pieces_navire_ouvertes) or not Personnage.a_portee_poste_navire("cale"):
		return false
	var cle := _proprietaire_cale()
	var cale := objets_en_cale()
	var source := objets if depot else cale
	var destination := cale if depot else objets
	var disponible := int(source.get(id, 0))
	if quantite <= 0 or quantite > disponible:
		return false
	var objets_avant := objets.duplicate()
	if quantite == disponible:
		source.erase(id)
	else:
		source[id] = disponible - quantite
	destination[id] = int(destination.get(id, 0)) + quantite
	var cale_avant: Dictionary = _cales_navire.get(cle, {})
	_cales_navire[cle] = cale
	if _sauver_objets() != OK:
		objets = objets_avant
		_cales_navire[cle] = cale_avant
		return false
	inventaire_modifie.emit()
	return true

# remet l'inventaire aux objets de départ (réinitialisation debug du perso)
func reinitialiser() -> void:
	objets.clear()
	_cales_navire.erase(_proprietaire_cale())
	items_connus.clear()
	_sauver_connus()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CHEMIN_SAUVEGARDE))
	inventaire_modifie.emit()
	_ajouter_objets_depart()

func charger_noms_depuis_base() -> void:
	noms.clear()
	for ligne in BaseDonnees.lire("SELECT id, name FROM items;"):
		noms[str(ligne["id"])] = ligne["name"]

func ajouter_objet(id: String, quantite: int = 1) -> void:
	objets[id] = objets.get(id, 0) + quantite
	_marquer_connu(id)
	_sauver_objets()
	inventaire_modifie.emit()

# ajoute plusieurs prises d'un coup (vidage de coffre par ex.) :
# une seule écriture fichier et un seul signal, contrairement à des
# ajouter_objet en série qui figeaient le jeu sur les gros lots
func ajouter_lot(prises: Array) -> void:
	if prises.is_empty():
		return
	for prise in prises:
		if prise is Dictionary:
			var id := str(prise.get("id", ""))
			if id != "":
				objets[id] = int(objets.get(id, 0)) + int(prise.get("qte", 1))
				_marquer_connu_sans_sauver(id)
	_sauver_objets()
	_sauver_connus()
	inventaire_modifie.emit()

func retirer_objet(id: String, quantite: int = 1) -> void:
	if not objets.has(id):
		return
	objets[id] -= quantite
	if objets[id] <= 0:
		objets.erase(id)
	_sauver_objets()
	inventaire_modifie.emit()

func nom_objet(id: String) -> String:
	return noms.get(id, id)

# détails complets d'un objet pour le menu (base lue une seule fois par id)
var _cache_details: Dictionary = {}

func details_objet(id: String) -> Dictionary:
	if _cache_details.has(id):
		return _cache_details[id]
	var details := {
		"id_rarete": 1, "rarete": "", "couleur_rarete": Color.GRAY,
		"type": "", "sous_type": "", "description": "", "effets": {},
		"chemin_icone": "", "prix": 0, "niveau_min": 1, "classe_requise": "",
	}
	if BaseDonnees.disponible and id.is_valid_int():
		var lignes := BaseDonnees.lire(
			"SELECT i.type, i.subtype, i.description, i.base_price, i.min_level,"
			+ " i.effects_json, i.rarity_id, i.icon_path, i.required_class,"
			+ " r.display_name AS rarete, r.color AS couleur"
			+ " FROM items i LEFT JOIN rarities r ON r.id = i.rarity_id"
			+ " WHERE i.id = %d;" % id.to_int())
		if not lignes.is_empty():
			var ligne: Dictionary = lignes[0]
			details["type"] = ligne.get("type", "")
			details["sous_type"] = ligne.get("subtype", "")
			details["description"] = str(ligne.get("description", ""))
			details["prix"] = int(ligne.get("base_price", 0))
			details["niveau_min"] = int(ligne.get("min_level", 1))
			var classe_req: Variant = ligne.get("required_class", "")
			if classe_req != null:
				details["classe_requise"] = str(classe_req)
			details["id_rarete"] = int(ligne.get("rarity_id", 1))
			details["rarete"] = str(ligne.get("rarete", ""))
			details["couleur_rarete"] = Color.from_string(str(ligne.get("couleur", "#808080")), Color.GRAY)
			var chemin: String = str(ligne.get("icon_path", ""))
			if chemin != "":
				details["chemin_icone"] = chemin if chemin.begins_with("res://") else "res://" + chemin
			var effets: Variant = JSON.parse_string(str(ligne.get("effects_json", "{}")))
			if effets is Dictionary:
				details["effets"] = effets
	_cache_details[id] = details
	return details
