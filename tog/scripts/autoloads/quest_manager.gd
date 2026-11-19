# quest_manager.gd — autoload
extends Node

const CHEMIN_QUETES := "user://quetes.cfg"
const QUETES_FUSHIA := preload("res://scripts/world/quetes_fushia.gd")

var quetes: Dictionary = {
	"chasse_loups": {
		"titre": "Chasse aux loups",
		"description": "Tuez 3 loups dans la forêt.",
		"objectif": 3,
	},
}

var quetes_actives: Dictionary = {}    # id -> progression (persisté)
var quetes_terminees: Dictionary = {}  # id -> true (persisté, impossible de refaire)
var _sources_actives: Dictionary = {}  # id de quête -> objectifs uniques déjà visités

signal quete_acceptee(quest_id: String)
signal quete_progressee(quest_id: String)
signal quete_abandonnee(quest_id: String)
signal quete_terminee(quest_id: String)

func _ready() -> void:
	# les quêtes viennent de la base SQLite ; le dictionnaire au-dessus sert
	# de repli si la base est indisponible
	if BaseDonnees.disponible:
		charger_depuis_base()
	quetes.merge(QUETES_FUSHIA.DEFINITIONS)
	charger_quetes()

func charger_depuis_base() -> void:
	quetes.clear()
	var lignes := BaseDonnees.lire(
		"SELECT id, name, description, required_level, objectives_json, xp_reward, berry_reward, items_reward_json " +
		"FROM quests WHERE is_active = 1;"
	)
	for ligne in lignes:
		# certaines lignes contiennent des JSON corrompus ("[object Object]") :
		# json_tableau() retombe sur [] plutôt que de planter
		var objectifs: Array = BaseDonnees.json_tableau(ligne["objectives_json"])
		var objectif := 1
		if not objectifs.is_empty():
			objectif = int(objectifs[0].get("amount", 1))
		var recompenses: Array = BaseDonnees.json_tableau(ligne["items_reward_json"])
		quetes[str(ligne["id"])] = {
			"titre": ligne["name"],
			"description": ligne["description"],
			"niveau_requis": int(ligne["required_level"]),
			"objectif": objectif,
			"objectifs": objectifs,
			"recompense_xp": int(ligne["xp_reward"]),
			"recompense_berry": int(ligne["berry_reward"]),
			"recompenses_objets": recompenses,
		}

func get_quest(id: String) -> Dictionary:
	# une quête terminée reste lisible (pour un futur historique)
	if quetes_terminees.has(id):
		return quetes.get(id, {})
	return quetes[id]

func accepter_quete(id: String) -> void:
	# une quête déjà terminée ne peut pas être refaite
	if quetes_terminees.has(id) or quetes_actives.has(id):
		return
	quetes_actives[id] = 0
	quete_acceptee.emit(id)
	sauvegarder_quetes()

func progresser(id: String, source: String = "") -> void:
	if quetes_actives.has(id) and quetes_actives[id] < quetes[id].objectif:
		if source != "":
			var sources: Array = _sources_actives.get(id, [])
			if source in sources:
				return
			sources.append(source)
			_sources_actives[id] = sources
		quetes_actives[id] += 1
		quete_progressee.emit(id)
		if est_terminee(id):
			_terminer(id)
		else:
			sauvegarder_quetes()

# termine instantanément une quête (pour le debug)
func terminer_quete(id: String) -> void:
	if quetes_actives.has(id):
		quetes_actives[id] = quetes[id].objectif
		quete_progressee.emit(id)
		_terminer(id)

# verse les récompenses puis déplace la quête vers les terminées
func _terminer(id: String) -> void:
	_distribuer_recompenses(id)
	quetes_actives.erase(id)
	_sources_actives.erase(id)
	quetes_terminees[id] = true
	quete_terminee.emit(id)
	sauvegarder_quetes()

# verse les récompenses (XP, Berry, objets) de la quête terminée
func _distribuer_recompenses(id: String) -> void:
	if not quetes.has(id):
		return
	var quest: Dictionary = quetes[id]
	Personnage.gagner_xp(int(quest.get("recompense_xp", 0)))
	Personnage.ajouter_berry(int(quest.get("recompense_berry", 0)))
	for objet in quest.get("recompenses_objets", []):
		# JSON rend des flottants (1.0) : conversion en entier pour l'id
		var id_objet := int(objet.get("item_id", 0))
		if id_objet != 0:
			Inventaire.ajouter_objet(str(id_objet), int(objet.get("quantity", 1)))

func abandonner_quete(id: String) -> void:
	if quetes_actives.has(id):
		quetes_actives.erase(id)
		_sources_actives.erase(id)
		quete_abandonnee.emit(id)
		sauvegarder_quetes()

# vide toutes les quêtes en cours (réinitialisation debug du perso)
func reinitialiser() -> void:
	quetes_actives.clear()
	quetes_terminees.clear()
	_sources_actives.clear()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CHEMIN_QUETES))

func est_terminee(id: String) -> bool:
	return quetes_actives.has(id) and quetes_actives[id] >= quetes[id].objectif

# terminée lors d'une session précédente
func est_deja_terminee(id: String) -> bool:
	return quetes_terminees.has(id)

func sauvegarder_quetes() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("quetes", "actives", quetes_actives)
	cfg.set_value("quetes", "terminees", quetes_terminees.keys())
	cfg.set_value("quetes", "sources", _sources_actives)
	cfg.save(CHEMIN_QUETES)

func charger_quetes() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CHEMIN_QUETES) != OK:
		return
	_sources_actives = cfg.get_value("quetes", "sources", {})
	var actives = cfg.get_value("quetes", "actives", {})
	if actives is Dictionary:
		for id in actives:
			quetes_actives[str(id)] = int(actives[id])
	var terminees = cfg.get_value("quetes", "terminees", [])
	if terminees is Array:
		for id in terminees:
			quetes_terminees[str(id)] = true
