# coffres.gd — autoload : état des coffres (persistance) et tirage du loot
extends Node

const CHEMIN_ETAT := "user://coffres.cfg"

# ordre croissant des raretés d'objets (ids de la table `rarities`)
# commun(1) < peu commun(5) < rare(2) < épique(3) < légendaire(4) < mythique(6)
const PALIERS := [1, 5, 2, 3, 4, 6]

# position max dans PALIERS (incluse) des objets tirables selon la rareté du coffre
# coffre commun -> commun ; rare -> rare ; épique -> épique ; légendaire -> légendaire
const PLAFOND_COFFRE := {1: 1, 2: 3, 3: 4, 4: 5}
# nombre d'objets tirés (min, max) selon la rareté du coffre
const NOMBRE_OBJETS := {1: [2, 2], 2: [3, 3], 3: [3, 4], 4: [4, 4]}
# chance de tirer un objet d'un cran au-dessus du plafond (jackpot)
const PROBA_JACKPOT := 0.10
# chance qu'un coffre contienne un fruit du démon : tirage dédié, à part
# du système de raretés (les fruits sont is_droppable = 0 et ne figurent
# donc pas dans le tirage normal) et réservé aux coffres légendaires.
# Une variable pour pouvoir être ajustée/testée en cours de partie.
var proba_fruit := 1.0 / 10000.0
# sous-type des items-coffres (table `items`, type "coffre") -> rareté du coffre
const SOUS_TYPES_COFFRE := {
	"commun": 1, "rare": 2, "épique": 3, "légendaire": 4,
}
# rareté du coffre qui peut contenir un fruit du démon
const RARETE_COFFRE_LEGENDAIRE := 4
# types d'objets tirés en plusieurs exemplaires
const TYPES_EMPILABLES := ["consumable", "ressource"]

signal coffre_modifie(coffre_id: String)

var _etat := {}  # coffre_id -> {"ouvert": bool, "contenu": Array[{"id": String, "qte": int}]}

func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CHEMIN_ETAT) == OK and cfg.has_section("coffres"):
		for id in cfg.get_section_keys("coffres"):
			_etat[str(id)] = cfg.get_value("coffres", id)

func _sauver() -> void:
	var cfg := ConfigFile.new()
	for id in _etat:
		cfg.set_value("coffres", id, _etat[id])
	cfg.save(CHEMIN_ETAT)

func est_ouvert(coffre_id: String) -> bool:
	return _etat.has(coffre_id) and _etat[coffre_id].get("ouvert", false)

# copie du contenu restant du coffre : [{"id": String, "qte": int}, ...]
func contenu(coffre_id: String) -> Array:
	if _etat.has(coffre_id):
		return _etat[coffre_id].get("contenu", []).duplicate()
	return []

# première ouverture : marque le coffre ouvert et tire (une seule fois) son contenu
func ouvrir(coffre_id: String, rarete_coffre: int) -> Array:
	if not _etat.has(coffre_id):
		_etat[coffre_id] = {"ouvert": true, "contenu": _tirer_contenu(rarete_coffre)}
	else:
		_etat[coffre_id]["ouvert"] = true
	_sauver()
	coffre_modifie.emit(coffre_id)
	return contenu(coffre_id)

# ouvre n exemplaires d'un même coffre (lot acheté, ouverture groupée)
# sous un même état temporaire : le contenu est la somme des tirages
func ouvrir_lot(coffre_id: String, rarete_coffre: int, nombre: int) -> Array:
	var contenu_lot := []
	for _i in range(maxi(1, nombre)):
		contenu_lot.append_array(_tirer_contenu(rarete_coffre))
	_etat[coffre_id] = {"ouvert": true, "contenu": contenu_lot}
	_sauver()
	coffre_modifie.emit(coffre_id)
	return contenu_lot.duplicate()

# retire du coffre l'objet à cet index et le renvoie
func prendre_objet(coffre_id: String, index: int) -> Dictionary:
	if not _etat.has(coffre_id):
		return {}
	var restant: Array = _etat[coffre_id]["contenu"]
	if index < 0 or index >= restant.size():
		return {}
	var prise: Dictionary = restant[index]
	restant.remove_at(index)
	_sauver()
	coffre_modifie.emit(coffre_id)
	return prise

# retire tout le contenu du coffre et le renvoie
func vider(coffre_id: String) -> Array:
	if not _etat.has(coffre_id):
		return []
	var prises: Array = _etat[coffre_id]["contenu"].duplicate()
	_etat[coffre_id]["contenu"] = []
	_sauver()
	coffre_modifie.emit(coffre_id)
	return prises

# remet tous les coffres à zéro (réinitialisation debug du perso)
func reinitialiser() -> void:
	_etat.clear()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CHEMIN_ETAT))
	coffre_modifie.emit("")

# rareté de coffre (int) depuis le sous-type de l'item-coffre ; 0 si inconnu
func rarete_depuis_sous_type(sous_type: String) -> int:
	return SOUS_TYPES_COFFRE.get(sous_type.to_lower(), 0)

# --- tirage du loot ---

func _tirer_contenu(rarete_coffre: int) -> Array:
	var bornes: Array = NOMBRE_OBJETS.get(rarete_coffre, [2, 2])
	var n := randi_range(int(bornes[0]), int(bornes[1]))
	var objets_tires := []
	for _i in n:
			var prise := _tirer_objet(rarete_coffre)
			if not prise.is_empty():
				objets_tires.append(prise)
	# fruits du démon : uniquement dans les coffres légendaires (rareté 4)
	if rarete_coffre == RARETE_COFFRE_LEGENDAIRE:
		var fruit := _tirer_fruit()
		if not fruit.is_empty():
			objets_tires.append(fruit)
	return objets_tires

# fruit du démon : avec une chance de proba_fruit par ouverture de coffre
# légendaire (voir _tirer_contenu), un exemplaire d'un fruit disponible
# est ajouté au contenu. Un fruit
# déjà consommé (registre unique_items), déjà détenu par le joueur ou
# déjà présent dans un autre coffre ne peut plus sortir : il n'existe
# qu'un exemplaire de chaque par monde.
func _tirer_fruit() -> Dictionary:
	if not BaseDonnees.disponible:
		return {}
	if randf() >= proba_fruit:
		return {}
	# ids déjà attribués : contenu non ramassé des autres coffres
	var pris := {}
	for id_coffre in _etat:
		for prise in _etat[id_coffre].get("contenu", []):
			var id_item := str(prise.get("id", ""))
			if id_item != "":
				pris[id_item] = true
	var ids: Array[String] = []
	for ligne in BaseDonnees.lire(
		"SELECT id FROM items"
		+ " WHERE type = 'fruit_demon' AND is_active = 1"
		+ " AND id NOT IN (SELECT item_id FROM unique_items WHERE is_consumed = 1);"):
		var id := str(ligne["id"])
		# fruit mangé : il n'existe plus qu'un exemplaire par monde
		if id == Personnage.fruit_id:
			continue
		if not Inventaire.objets.has(id) and not pris.has(id):
			ids.append(id)
	if ids.is_empty():
		return {}
	return {"id": ids[randi() % ids.size()], "qte": 1}

func _tirer_objet(rarete_coffre: int) -> Dictionary:
	if not BaseDonnees.disponible:
		return {}
	var pos_plafond: int = PLAFOND_COFFRE.get(rarete_coffre, 1)
	# jackpot : un cran au-dessus du plafond du coffre
	if randf() < PROBA_JACKPOT:
		pos_plafond = mini(pos_plafond + 1, PALIERS.size() - 1)
	var rarete := _tirer_rarete(PALIERS.slice(0, pos_plafond))
	if rarete == 0:
		return {}
	var lignes := BaseDonnees.lire(
		"SELECT id, type FROM items"
		+ " WHERE is_active = 1 AND is_droppable = 1 AND rarity_id = %d;" % rarete)
	if lignes.is_empty():
		return {}
	var ligne: Dictionary = lignes[randi() % lignes.size()]
	var qte := 1
	if TYPES_EMPILABLES.has(str(ligne.get("type", ""))):
		qte = randi_range(1, 3)
	return {"id": str(ligne["id"]), "qte": qte}

# tire une rareté parmi les ids donnés, pondéré par la colonne `probability`
func _tirer_rarete(ids: Array) -> int:
	if ids.is_empty():
		return 0
	var liste := PackedStringArray()
	for id in ids:
		liste.append(str(id))
	var lignes := BaseDonnees.lire(
		"SELECT id, probability FROM rarities WHERE id IN (%s);" % ", ".join(liste))
	if lignes.is_empty():
		return int(ids[0])
	var total := 0.0
	for ligne in lignes:
		total += float(ligne.get("probability", 0.0))
	if total <= 0.0:
		return int(ids[randi() % ids.size()])
	var tirage := randf() * total
	for ligne in lignes:
		tirage -= float(ligne.get("probability", 0.0))
		if tirage <= 0.0:
			return int(ligne["id"])
	return int(lignes[lignes.size() - 1]["id"])
