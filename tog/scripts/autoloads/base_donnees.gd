# base_donnees.gd — autoload : accès à la base SQLite glo.db
# res:// est en lecture seule une fois le jeu exporté : on copie la base vers
# user:// au premier lancement, puis on ouvre cette copie en lecture/écriture.
# @tool : rend la base accessible dans l'éditeur (sprites des mobs en tool, etc.)
@tool
extends Node

const CHEMIN_SOURCE := "res://donnees/glo.db"
const CHEMIN_TRAVAIL := "user://glo.db"
const ID_PARCHEMIN_REATTRIBUTION := 975

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
	if not db.open_db():
		push_warning("Impossible d’ouvrir la base : %s" % CHEMIN_TRAVAIL)
		return
	if not OS.has_feature("editor"):
		_mettre_a_jour_catalogue()
	# teste l'ouverture sur une vraie requête
	db.query("SELECT COUNT(*) AS total FROM items;")
	disponible = not db.query_result.is_empty()
	if not disponible:
		push_warning("Impossible de lire la base : %s" % CHEMIN_TRAVAIL)

func _mettre_a_jour_catalogue() -> void:
	var plage := "BETWEEN 200 AND 249"
	if not db.query("SELECT COUNT(*) AS total FROM class_skills WHERE skill_id %s;" % plage):
		return
	var importer_sorts := int(db.query_result[0]["total"]) != 50
	if not db.query_with_bindings("SELECT id FROM items WHERE id = ?;", [ID_PARCHEMIN_REATTRIBUTION]):
		return
	var importer_parchemin := db.query_result.is_empty()
	if not importer_sorts and not importer_parchemin:
		return
	# En export, le catalogue embarqué peut se trouver dans le PCK.
	var source := FileAccess.get_file_as_bytes(CHEMIN_SOURCE)
	var catalogue := FileAccess.create_temp(FileAccess.WRITE, "tog-catalogue-", "db")
	if source.is_empty() or catalogue == null:
		push_warning("Impossible de préparer la mise à jour du catalogue.")
		return
	catalogue.store_buffer(source)
	catalogue.flush()
	if not db.query_with_bindings("ATTACH DATABASE ? AS catalogue_embarque;", [catalogue.get_path_absolute()]):
		push_warning("Impossible de rattacher le catalogue embarqué.")
		return
	if importer_sorts and not _importer_sorts_classes(plage):
		push_warning("La mise à jour des sorts de classe a échoué.")
	if importer_parchemin:
		var champs := "id, name, type, subtype, rarity_id, description, base_price, is_droppable, effects_json, icon_path"
		if not db.query_with_bindings(
			"INSERT OR IGNORE INTO items (%s) SELECT %s FROM catalogue_embarque.items WHERE id = ?;"
			% [champs, champs], [ID_PARCHEMIN_REATTRIBUTION]):
			push_warning("La mise à jour du parchemin de réattribution a échoué.")
	db.query("DETACH DATABASE catalogue_embarque;")

func _importer_sorts_classes(plage: String) -> bool:
	# Les écritures concernent uniquement le catalogue et sont rejouables.
	var requetes := [
		"INSERT OR IGNORE INTO skills (id, name, description, type, element, base_damage, base_cooldown, range)"
		+ " SELECT id, name, description, type, element, base_damage, base_cooldown, range"
		+ " FROM catalogue_embarque.skills WHERE id %s;" % plage,
		"INSERT OR IGNORE INTO animations (name, entity_type, entity_id, animation_type, sprite_sheet_path,"
		+ " frame_width, frame_height, frame_count, frame_delay_ms, loop)"
		+ " SELECT name, entity_type, entity_id, animation_type, sprite_sheet_path,"
		+ " frame_width, frame_height, frame_count, frame_delay_ms, loop FROM catalogue_embarque.animations"
		+ " WHERE entity_type = 'skill' AND entity_id %s;" % plage,
		"UPDATE skills SET animation_id = (SELECT id FROM animations WHERE name = 'fx_classe_' || skills.id)"
		+ " WHERE id %s;" % plage,
		"INSERT OR IGNORE INTO skill_status_effects (skill_id, status_effect_id, chance, duration, value)"
		+ " SELECT skill_id, status_effect_id, chance, duration, value"
		+ " FROM catalogue_embarque.skill_status_effects WHERE skill_id %s;" % plage,
		"INSERT OR IGNORE INTO class_skills (class_id, skill_id, unlock_level)"
		+ " SELECT class_id, skill_id, unlock_level FROM catalogue_embarque.class_skills WHERE skill_id %s;" % plage,
	]
	if not db.query("BEGIN IMMEDIATE;"):
		return false
	for requete in requetes:
		if not db.query(requete):
			db.query("ROLLBACK;")
			return false
	if db.query("COMMIT;"):
		return true
	db.query("ROLLBACK;")
	return false

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
