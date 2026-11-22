@tool
extends "res://scripts/combat/ennemy.gd"

const CROIX := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

var _tours_avant_foudre := 1
var _cases_foudre: Array[Vector2i] = []
var _sort_charge := ""
var _overlay_foudre: Node

func jouer_tour(joueur: CharacterBody2D, sol: TileMapLayer) -> void:
	if not is_instance_valid(joueur) or sol == null or not is_instance_valid(_combat_manager):
		return
	if _cases_foudre.is_empty() and _tours_avant_foudre > 0:
		_tours_avant_foudre -= 1
		await super.jouer_tour(joueur, sol)
		return
	if _combat_manager.preparer_tour(self) or not _combat_manager.sort_autorise(self):
		_effacer_foudre()
		_tours_avant_foudre = 1
		_combat_manager.afficher_message("La charge électrique d’Ener est interrompue.")
	elif _cases_foudre.is_empty():
		_charger_foudre(joueur, sol)
	else:
		_declencher_foudre(joueur, sol)
	if _combat_manager.en_combat:
		_combat_manager.terminer_tour(self)

func _charger_foudre(joueur: CharacterBody2D, sol: TileMapLayer) -> void:
	var centre := _case_de(sol, joueur.global_position)
	_cases_foudre = [centre]
	var mamaragan := pv * 2 <= pv_max
	if mamaragan:
		for voisin in CROIX:
			var case := centre + Vector2i(voisin)
			if sol.get_cell_source_id(case) != -1:
				_cases_foudre.append(case)
	_sort_charge = "137" if mamaragan else "103"
	_overlay_foudre = get_tree().current_scene.get_node("Overlay")
	_overlay_foudre.afficher_danger(_cases_foudre)
	_combat_manager.afficher_message(
		"Ener prépare %s. Quitte les cases marquées avant son prochain tour."
		% ("Mamaragan" if mamaragan else "El Thor"))

func _declencher_foudre(joueur: CharacterBody2D, sol: TileMapLayer) -> void:
	var cases := _cases_foudre.duplicate()
	var sort := _sort_charge
	var mamaragan := sort == "137"
	var case_joueur := _case_de(sol, joueur.global_position)
	_effacer_foudre()
	_tours_avant_foudre = 1 if mamaragan else 2
	var frappe := Marker2D.new()
	sol.add_child(frappe)
	for case in cases:
		if case == case_joueur:
			continue
		frappe.position = sol.map_to_local(case)
		_combat_manager.jouer_animation_sort(sort, self, frappe)
	frappe.queue_free()
	if cases.has(case_joueur):
		_combat_manager.jouer_animation_sort(sort, self, joueur)
		var base := roundi(degats_attaque * (1.60 if mamaragan else 1.40))
		var degats := int(_combat_manager.calculer_degats(self, joueur, base))
		joueur.recevoir_degats(degats)
		_nombre_flottant(joueur, "-%d" % degats, "degats")
	else:
		_combat_manager.afficher_message("Tu as évité la foudre d’Ener.")

func _jouer_animation_attaque(cible: Node2D) -> void:
	if is_instance_valid(_combat_manager):
		_combat_manager.jouer_animation_sort("102", self, cible)

func _effacer_foudre() -> void:
	_cases_foudre.clear()
	_sort_charge = ""
	if is_instance_valid(_overlay_foudre):
		_overlay_foudre.afficher_danger(_cases_foudre)

func assouplir() -> void:
	super.assouplir()
	_effacer_foudre()
	_tours_avant_foudre = 1

func _exit_tree() -> void:
	_effacer_foudre()

func _butin_specifique() -> Array:
	return [
		{"item_id": 852, "probability": 1.0, "min_quantity": 3, "max_quantity": 3},
		{"item_id": 282, "probability": 1.0, "min_quantity": 1, "max_quantity": 1},
	]
