
extends CharacterBody2D
@export var degats_attaque: int = 10
@export var portee_attaque: int = 2
@export var pm_max: int = 3
@onready var barre_vie: ProgressBar = $BarreVie

@export var pv_max: int = 100
var pv: int = 100

func _ready():
	pv = pv_max
	barre_vie.max_value = pv_max
	barre_vie.value = pv
	print("ENNEMI PRÊT")
	var trouve := false

	for enfant in get_children():
		if enfant is Area2D:
			trouve = true
			print("Zone trouvée : ", enfant.name)
			enfant.body_entered.connect(_on_zone_body_entered)

	if not trouve:
		print("PROBLÈME : aucune Area2D dans ennemy")


func _on_zone_body_entered(body):
	print("Quelqu'un est entré : ", body.name)

	if body == self:
		return

	if body.is_in_group("joueur"):
		print("C'est le joueur, je lance le combat")
		get_tree().current_scene.get_node("CombatManager").lancer_combat()


func recevoir_degats(degats: int):
	pv -= degats
	pv = max(pv, 0)

	barre_vie.max_value = pv_max
	barre_vie.value = pv

	print("ENNEMI : ", pv, " / ", pv_max, " PV")

	if pv <= 0:
		print("ENNEMI ÉLIMINÉ")
		queue_free()
		


func jouer_tour() -> void:
	var scene = get_tree().current_scene
	var joueur = scene.find_child("player", true, false)
	var sol: TileMapLayer = scene.get_node("ground")

	if joueur == null or not is_instance_valid(joueur):
		return

	var case_ennemi: Vector2i = sol.local_to_map(
		sol.to_local(global_position)
	)

	var case_joueur: Vector2i = sol.local_to_map(
		sol.to_local(joueur.global_position)
	)

	var distance: int = (
		abs(case_ennemi.x - case_joueur.x)
		+ abs(case_ennemi.y - case_joueur.y)
	)

	print("TOUR ENNEMI — Distance : ", distance)

	# Si l'ennemi est trop loin, il avance
	if distance > portee_attaque:
		var chemin: Array[Vector2i] = calculer_chemin_vers_joueur(
			sol, case_ennemi, case_joueur
		)

		var pas: int = min(pm_max, chemin.size())

		for i in range(pas):
			var destination: Vector2i = chemin[i]
			var position_cible: Vector2 = sol.to_global(
				sol.map_to_local(destination)
			)

			var tween: Tween = create_tween()
			tween.tween_property(
				self, "global_position", position_cible, 0.2
			)
			await tween.finished

			if not is_inside_tree():
				return

		print("ENNEMI : déplacement de ", pas, " case(s)")

	# Recalculer la distance après le déplacement
	case_ennemi = sol.local_to_map(
		sol.to_local(global_position)
	)

	distance = (
		abs(case_ennemi.x - case_joueur.x)
		+ abs(case_ennemi.y - case_joueur.y)
	)

	if distance <= portee_attaque:
		print("L'ENNEMI ATTAQUE !")
		joueur.recevoir_degats(degats_attaque)
	else:
		print("Le joueur est encore trop loin.")

		
		
func calculer_chemin_vers_joueur(
	sol: TileMapLayer,
	case_depart: Vector2i,
	case_joueur: Vector2i
) -> Array[Vector2i]:

	var file: Array[Vector2i] = [case_depart]
	var parents: Dictionary = {case_depart: case_depart}

	var voisins: Array[Vector2i] = [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1)
	]

	var destination: Vector2i = case_depart
	var meilleure_distance: int = (
		abs(case_depart.x - case_joueur.x)
		+ abs(case_depart.y - case_joueur.y)
	)

	while not file.is_empty():
		var courante: Vector2i = file.pop_front()

		var distance: int = (
			abs(courante.x - case_joueur.x)
			+ abs(courante.y - case_joueur.y)
		)

		if distance < meilleure_distance:
			meilleure_distance = distance
			destination = courante

		# On a trouvé une case à portée d'attaque
		if distance <= portee_attaque:
			destination = courante
			break

		for direction in voisins:
			var suivante: Vector2i = courante + direction

			if parents.has(suivante):
				continue

			# Ne pas marcher hors du sol
			if sol.get_cell_source_id(suivante) == -1:
				continue

			# Ne pas marcher sur le joueur
			if suivante == case_joueur:
				continue

			parents[suivante] = courante
			file.append(suivante)

	var chemin: Array[Vector2i] = []
	var case_actuelle: Vector2i = destination

	while case_actuelle != case_depart:
		chemin.push_front(case_actuelle)
		case_actuelle = parents[case_actuelle]

	return chemin
