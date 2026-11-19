# base_donnees.gd — autoload : accès à la base SQLite glo.db
# res:// est en lecture seule une fois le jeu exporté : on copie la base vers
# user:// au premier lancement, puis on ouvre cette copie en lecture/écriture.
# @tool : rend la base accessible dans l'éditeur (sprites des mobs en tool, etc.)
@tool
extends Node

const CHEMIN_SOURCE := "res://donnees/glo.db"
const CHEMIN_TRAVAIL := "user://glo.db"

var db: SQLite
var disponible := false

func _ready() -> void:
	if OS.has_feature("editor"):
		# en développement : re-synchroniser à chaque lancement pour voir
		# les mises à jour de la base embarquée ; en export, copie unique
		_copier_base(CHEMIN_SOURCE, CHEMIN_TRAVAIL)
	elif not FileAccess.file_exists(CHEMIN_TRAVAIL):
		_copier_base(CHEMIN_SOURCE, CHEMIN_TRAVAIL)
	db = SQLite.new()
	db.path = CHEMIN_TRAVAIL
	db.open_db()
	# teste l'ouverture sur une vraie requête
	db.query("SELECT COUNT(*) AS total FROM items;")
	disponible = not db.query_result.is_empty()
	if not disponible:
		push_warning("Impossible de lire la base : %s" % CHEMIN_TRAVAIL)

func lire(requete: String) -> Array:
	if not disponible:
		return []
	db.query(requete)
	return db.query_result

# parse un champ JSON en tableau ; tolère NULL, vide ou corrompu
# ("[object Object]") sans lever d'erreur, en rendant [].
# Les nombres entiers arrivent en float depuis le JSON (1.0) : on les
# restitue en int pour qu'ils correspondent aux ids de la base.
func json_tableau(valeur: Variant) -> Array:
	if valeur == null:
		return []
	var epure := str(valeur).strip_edges()
	if not epure.begins_with("[") or epure.contains("object Object"):
		return []
	var brut: Variant = JSON.parse_string(epure)
	if not brut is Array:
		return []
	if brut.is_empty():
		return []
	var propre: Array = []
	for element in brut:
		if element is float and element == floor(element):
			propre.append(int(element))
		else:
			propre.append(element)
	return propre

# réimporte la base embarquée (écrase la copie user://, donc les données du
# joueur enregistrées dedans seraient perdues ; à appeler volontairement)
func reimporter() -> void:
	disponible = false
	if db != null:
		db.close_db()
	if _copier_base(CHEMIN_SOURCE, CHEMIN_TRAVAIL):
		db.open_db()
		db.query("SELECT COUNT(*) AS total FROM items;")
		disponible = not db.query_result.is_empty()

func _copier_base(source: String, cible: String) -> bool:
	var lecteur := FileAccess.open(source, FileAccess.READ)
	if lecteur == null:
		push_warning("Base de données introuvable : %s" % source)
		return false
	var octets := lecteur.get_buffer(lecteur.get_length())
	lecteur.close()
	var ecrivain := FileAccess.open(cible, FileAccess.WRITE)
	if ecrivain == null:
		push_warning("Écriture impossible : %s" % cible)
		return false
	ecrivain.store_buffer(octets)
	ecrivain.close()
	return true
