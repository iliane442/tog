# quest_manager.gd — autoload
extends Node

var quetes: Dictionary = {
	"chasse_loups": {
		"titre": "Chasse aux loups",
		"description": "Tuez 3 loups dans la forêt.",
		"objectif": 3,
	},
}

var quetes_actives: Dictionary = {}  # id -> progression

signal quete_acceptee(quest_id: String)

func get_quest(id: String) -> Dictionary:
	return quetes[id]

func accepter_quete(id: String) -> void:
	if not quetes_actives.has(id):
		quetes_actives[id] = 0
		quete_acceptee.emit(id)

func progresser(id: String) -> void:
	if quetes_actives.has(id):
		quetes_actives[id] += 1

func est_terminee(id: String) -> bool:
	return quetes_actives.has(id) and quetes_actives[id] >= quetes[id].objectif
