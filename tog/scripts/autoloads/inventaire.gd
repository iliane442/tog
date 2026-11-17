# inventaire.gd — autoload
extends Node

var objets: Dictionary = {}  # id -> quantité

# Noms affichés dans l'inventaire (déclarez vos objets ici)
var noms: Dictionary = {
	"potion": "Potion de soin",
	"epee": "Épée",
}

signal inventaire_modifie

# items déjà rencontrés par le joueur (id -> true) — alimente le wiki d'objets
const CHEMIN_CONNUS := "user://items_connus.cfg"
var items_connus: Dictionary = {}

func _ready() -> void:
	_charger_connus()
	if BaseDonnees.disponible:
		charger_noms_depuis_base()
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

func est_connu(id: String) -> bool:
	return items_connus.has(id)

func _ajouter_objets_depart() -> void:
	# Objets de départ pour tester le menu — ids de la table `items`
	ajouter_objet("12", 3)  # Potion de soin
	ajouter_objet("1", 1)   # Épée en bois
	ajouter_objet("3", 1)   # Katana

# remet l'inventaire aux objets de départ (réinitialisation debug du perso)
func reinitialiser() -> void:
	objets.clear()
	items_connus.clear()
	_sauver_connus()
	inventaire_modifie.emit()
	_ajouter_objets_depart()

func charger_noms_depuis_base() -> void:
	noms.clear()
	for ligne in BaseDonnees.lire("SELECT id, name FROM items;"):
		noms[str(ligne["id"])] = ligne["name"]

func ajouter_objet(id: String, quantite: int = 1) -> void:
	objets[id] = objets.get(id, 0) + quantite
	_marquer_connu(id)
	inventaire_modifie.emit()

func retirer_objet(id: String, quantite: int = 1) -> void:
	if not objets.has(id):
		return
	objets[id] -= quantite
	if objets[id] <= 0:
		objets.erase(id)
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
		"chemin_icone": "", "prix": 0, "niveau_min": 1,
	}
	if BaseDonnees.disponible and id.is_valid_int():
		var lignes := BaseDonnees.lire(
			"SELECT i.type, i.subtype, i.description, i.base_price, i.min_level,"
			+ " i.effects_json, i.rarity_id, i.icon_path,"
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
