extends CharacterBody2D

signal sante_modifiee(vie: int, vie_max: int)

@export var pv_max := 100
@export var nom := "Loup pirate"
@export var degats_attaque := 10
@export var portee_attaque := 2
@export var pm_max := 3
@export var quetes_a_progresser: Array[String] = ["1"]

const ID_ETAT_TEST := 5 # Ralentissement
const DUREE_ETAT_TEST := 2

var pv := 100
var _combat_manager

@onready var zone_detection: Area2D = $ZoneDetection

func _ready() -> void:
	pv = pv_max
	_combat_manager = get_tree().current_scene.get_node_or_null("CombatManager")
	zone_detection.body_entered.connect(_on_zone_body_entered)
	if _combat_manager != null:
		_combat_manager.enregistrer_ennemi(self)
	sante_modifiee.emit(pv, pv_max)

func _on_zone_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and _combat_manager != null:
		_combat_manager.lancer_combat(self)

func recevoir_degats(degats: int) -> void:
	pv = maxi(pv - maxi(degats, 0), 0)
	sante_modifiee.emit(pv, pv_max)
	if pv > 0:
		return
	for quest_id in quetes_a_progresser:
		if QuestManager.quetes_actives.has(quest_id):
			QuestManager.progresser(quest_id)
	if _combat_manager != null:
		_combat_manager.terminer_combat(true)
	queue_free()

func soigner(montant: int) -> void:
	pv = mini(pv + maxi(montant, 0), pv_max)
	sante_modifiee.emit(pv, pv_max)

func jouer_tour(joueur: CharacterBody2D, sol: TileMapLayer) -> void:
	if not is_instance_valid(joueur) or sol == null:
		return
	if _combat_manager != null and _combat_manager.preparer_tour(self):
		_combat_manager.afficher_message("L’ennemi perd son tour.")
		_combat_manager.terminer_tour(self)
		return
	if not is_inside_tree():
		return
	var depart := _case_de(sol, global_position)
	var cible := _case_de(sol, joueur.global_position)
	var distance := absi(depart.x - cible.x) + absi(depart.y - cible.y)
	if distance > portee_attaque:
		var chemin := _calculer_chemin(sol, depart, cible)
		var pm: int = int(_combat_manager.points_mouvement(self, pm_max)) if _combat_manager != null else pm_max
		var pas := mini(pm, chemin.size())
		for index in range(pas):
			var position_cible := sol.to_global(sol.map_to_local(chemin[index]))
			var tween := create_tween()
			tween.tween_property(self, "global_position", position_cible, 0.2)
			await tween.finished
			if not is_inside_tree():
				return
		depart = _case_de(sol, global_position)
		distance = absi(depart.x - cible.x) + absi(depart.y - cible.y)
	if distance <= portee_attaque:
		_appliquer_ralentissement_test(joueur)
		if _combat_manager == null or _combat_manager.precision_reussie(self):
			var degats: int = int(_combat_manager.calculer_degats(self, joueur, degats_attaque)) if _combat_manager != null else degats_attaque
			joueur.recevoir_degats(degats)
	if _combat_manager != null and is_inside_tree():
		_combat_manager.terminer_tour(self)

func _appliquer_ralentissement_test(joueur: Node) -> void:
	if _combat_manager == null:
		return
	var effet: Dictionary = {
		"id": ID_ETAT_TEST,
		"chance": 1.0,
		"duree": DUREE_ETAT_TEST,
		"valeur": 1.0,
	}
	var attaque: Dictionary = {"effets": [effet]}
	_combat_manager.appliquer_effets_sort(joueur, attaque)

func _case_de(sol: TileMapLayer, position_globale: Vector2) -> Vector2i:
	return sol.local_to_map(sol.to_local(position_globale))

func _calculer_chemin(sol: TileMapLayer, depart: Vector2i, cible: Vector2i) -> Array[Vector2i]:
	var file: Array[Vector2i] = [depart]
	var parents: Dictionary = {depart: depart}
	var voisins: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
	var destination := depart
	var meilleure_distance := absi(depart.x - cible.x) + absi(depart.y - cible.y)
	while not file.is_empty():
		var courante: Vector2i = file.pop_front()
		var distance := absi(courante.x - cible.x) + absi(courante.y - cible.y)
		if distance < meilleure_distance:
			meilleure_distance = distance
			destination = courante
		if distance <= portee_attaque:
			destination = courante
			break
		for voisin in voisins:
			var suivante := courante + voisin
			if parents.has(suivante) or sol.get_cell_source_id(suivante) == -1 or suivante == cible:
				continue
			parents[suivante] = courante
			file.append(suivante)
	var chemin: Array[Vector2i] = []
	var case_actuelle := destination
	while case_actuelle != depart:
		if not parents.has(case_actuelle):
			return []
		chemin.push_front(case_actuelle)
		case_actuelle = parents[case_actuelle]
	return chemin
