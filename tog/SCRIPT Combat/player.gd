extends CharacterBody2D

@export var speed: float = 200.0
@export var pv_max: int = 50
@export var pa_max: int = 6
@export var pm_max: int = 3
@export var distance_placement: int = 5
@export var rayon_placement: int = 2

var pv: int = 50
var pa: int = 6
var pm: int = 3
var cases_placement: Array[Vector2i] = []
var target: Vector2 = Vector2.ZERO
var en_deplacement: bool = false
var occupe: bool = false
var sort_selectionne := false
var tour_joueur: bool = true
var cout_boule_de_feu := 3
var degats_boule_de_feu := 20
var portee_boule_de_feu := 3

@onready var barre_vie_joueur: ProgressBar = get_tree().current_scene.find_child("BarreVieJoueur", true, false)
@onready var combat_manager: Node = get_tree().current_scene.get_node("CombatManager")
@onready var stats_label: Label = get_tree().current_scene.find_child("StatsLabel", true, false)
@onready var sol: TileMapLayer = get_tree().current_scene.get_node("ground")
@onready var ennemi: Node2D = get_tree().current_scene.find_child("ennemy", true, false)
@onready var overlay: Node2D = get_tree().current_scene.find_child("Overlay", true, false)
@onready var bouton_boule_de_feu: Button = get_tree().current_scene.find_child("BoutonBouleDeFeu", true, false)
@onready var eau: TileMapLayer = get_tree().current_scene.get_node("water")
@onready var bouton_fin_tour: Button = get_tree().current_scene.find_child("BoutonFinTour", true, false)
@onready var bouton_pret: Button = get_tree().current_scene.find_child("BoutonPret", true, false)

func _ready() -> void:
	bouton_fin_tour.hide()
	combat_manager.placement_commence.connect(_on_placement_commence)
	bouton_pret.pressed.connect(_valider_placement)
	bouton_pret.hide()
	pv = pv_max
	barre_vie_joueur.max_value = pv_max
	barre_vie_joueur.value = pv
	pa = pa_max
	pm = pm_max
	combat_manager.combat_commence.connect(_on_combat_commence)
	combat_manager.combat_termine.connect(_on_combat_termine)
	bouton_boule_de_feu.pressed.connect(_selectionner_boule_de_feu)
	bouton_fin_tour.pressed.connect(_fin_du_tour)
	bouton_fin_tour.disabled = true
	_maj_affichage()

func _on_combat_commence() -> void:
	bouton_fin_tour.show()
	bouton_fin_tour.disabled = false
	pa = pa_max
	pm = pm_max
	tour_joueur = true
	sort_selectionne = false
	bouton_fin_tour.disabled = false
	velocity = Vector2.ZERO
	en_deplacement = false
	_maj_affichage()
	print("DEBUT COMBAT, ma case : ", ma_case())
	print("Sol sous moi (-1 = rien) : ", sol.get_cell_source_id(ma_case()))
	print("Nombre de cases atteignables : ", calculer_portee().size())
	_afficher_cases()

func _on_combat_termine() -> void:
	bouton_fin_tour.hide()
	bouton_fin_tour.disabled = true
	cases_placement.clear()
	bouton_pret.hide()
	tour_joueur = false
	sort_selectionne = false
	bouton_fin_tour.disabled = true
	overlay.effacer()
	_maj_affichage()

func _maj_affichage() -> void:
	if combat_manager.en_combat:
		stats_label.text = "PV : %d / %d     PA : %d / %d     PM : %d / %d" % [pv, pv_max, pa, pa_max, pm, pm_max]
	else:
		stats_label.text = "PV : %d / %d" % [pv, pv_max]

# ---------- Cases ----------
func ma_case() -> Vector2i:
	return sol.local_to_map(sol.to_local(global_position))



func case_libre(c: Vector2i) -> bool:
	# Vérifier qu'il y a du sol
	if sol.get_cell_source_id(c) == -1:
		return false

	# Empêcher de marcher sur l'ennemi
	if ennemi != null and is_instance_valid(ennemi):
		var case_ennemi: Vector2i = sol.local_to_map(
			sol.to_local(ennemi.global_position)
		)

		if c == case_ennemi:
			return false

	return true



# Retourne { case : nombre de pas pour y arriver }
func calculer_portee() -> Dictionary:
	var depart: Vector2i = ma_case()
	var distances: Dictionary = {}
	distances[depart] = 0
	var file: Array[Vector2i] = [depart]
	var voisins: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while not file.is_empty():
		var courante: Vector2i = file.pop_front()
		if distances[courante] >= pm:
			continue
		for v in voisins:
			var suivante: Vector2i = courante + v
			if distances.has(suivante) or not case_libre(suivante):
				continue
			distances[suivante] = distances[courante] + 1
			file.append(suivante)
	return distances
	

func calculer_portee_sort() -> Array[Vector2i]:
	var cases: Array[Vector2i] = []
	var depart: Vector2i = ma_case()

	for x in range(-portee_boule_de_feu, portee_boule_de_feu + 1):
		for y in range(-portee_boule_de_feu, portee_boule_de_feu + 1):
			var distance = abs(x) + abs(y)

			if distance == 0 or distance > portee_boule_de_feu:
				continue

			var c = depart + Vector2i(x, y)

			if sol.get_cell_source_id(c) != -1:
				cases.append(c)

	return cases


func _afficher_cases() -> void:
	var liste: Array[Vector2i] = []
	var depart: Vector2i = ma_case()
	var portee: Dictionary = calculer_portee()

	for c in portee.keys():
		if c != depart:
			liste.append(c)

	print("CASES BLEUES CALCULÉES : ", liste.size())
	print("OVERLAY TROUVÉ : ", overlay)

	overlay.afficher(liste)


# ---------- Clic ----------

func ligne_de_vue_libre(depart: Vector2i, arrivee: Vector2i) -> bool:
	var x0 = depart.x
	var y0 = depart.y
	var x1 = arrivee.x
	var y1 = arrivee.y

	var dx = abs(x1 - x0)
	var dy = abs(y1 - y0)

	var sx = 1 if x0 < x1 else -1
	var sy = 1 if y0 < y1 else -1

	var erreur = dx - dy

	while x0 != x1 or y0 != y1:
		var e2 = 2 * erreur

		if e2 > -dy:
			erreur -= dy
			x0 += sx

		if e2 < dx:
			erreur += dx
			y0 += sy

		# La case de destination n'est pas testée
		if x0 == x1 and y0 == y1:
			break

		if eau.get_cell_source_id(Vector2i(x0, y0)) != -1:
			return false

	return true


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return

	if combat_manager.en_combat:
		
		if combat_manager.en_placement:
			var case_cliquee: Vector2i = sol.local_to_map(
				sol.get_local_mouse_position()
			)

			if case_cliquee in cases_placement:
				global_position = sol.to_global(
					sol.map_to_local(case_cliquee)
				)
				print("CASE DE PLACEMENT CHOISIE : ", case_cliquee)

			return

		if occupe or not tour_joueur:
			return

		var case_cliquee: Vector2i = sol.local_to_map(sol.get_local_mouse_position())

		# Si un sort est sélectionné
		if sort_selectionne:
			if ennemi != null and is_instance_valid(ennemi):
				var case_ennemi = sol.local_to_map(
					sol.to_local(ennemi.global_position)
				)

				if case_cliquee == case_ennemi:
					_lancer_boule_de_feu()
					return

			print("Clique sur l'ennemi pour lancer le sort")
			return

		# Déplacement : uniquement des PM
		var portee: Dictionary = calculer_portee()

		if case_cliquee != ma_case() and portee.has(case_cliquee):
			_deplacer_case_par_case(case_cliquee, portee[case_cliquee])

	else:
		target = get_global_mouse_position()
		en_deplacement = true

# ---------- Déplacement libre (hors combat) ----------
func _physics_process(_delta: float) -> void:
	if combat_manager.en_combat:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	if en_deplacement:
		var direction: Vector2 = target - global_position
		if direction.length() > 5.0:
			velocity = direction.normalized() * speed
		else:
			velocity = Vector2.ZERO
			en_deplacement = false
	else:
		velocity = Vector2.ZERO
	move_and_slide()




func _selectionner_boule_de_feu() -> void:
	if not combat_manager.en_combat:
		print("Pas de combat en cours")
		return

	if not tour_joueur:
		print("Ce n'est pas ton tour !")
		return

	if pa < cout_boule_de_feu:
		print("Pas assez de PA !")
		return

	sort_selectionne = true
	overlay.effacer()

	var cases_sort: Array[Vector2i] = calculer_portee_sort()
	print("CASES ROUGES CALCULÉES : ", cases_sort.size())
	overlay.afficher_sort(cases_sort)

	print("BOULE DE FEU SÉLECTIONNÉE !")


func _lancer_boule_de_feu() -> void:
	if ennemi == null or not is_instance_valid(ennemi):
		print("Aucun ennemi disponible")
		return

	if pa < cout_boule_de_feu:
		print("Pas assez de PA !")
		return

	var case_joueur = ma_case()
	var case_ennemi = sol.local_to_map(
		sol.to_local(ennemi.global_position)
	)

	var distance = abs(case_joueur.x - case_ennemi.x) + abs(case_joueur.y - case_ennemi.y)

	if distance > portee_boule_de_feu:
		print("Ennemi trop éloigné !")
		return

	# Le sort peut toucher l'ennemi
	pa -= cout_boule_de_feu
	ennemi.recevoir_degats(degats_boule_de_feu)

	sort_selectionne = false
	overlay.effacer()
	_maj_affichage()
	_afficher_cases()

	print("BOULE DE FEU LANCÉE !")

	
	
func _deplacer_case_par_case(destination: Vector2i, cout: int) -> void:
	occupe = true
	overlay.effacer()

	# On consomme uniquement les PM
	pm -= cout
	print("AVANT DÉPLACEMENT : PA = ", pa, " | PM = ", pm)
	_maj_affichage()

	var pos_destination: Vector2 = sol.to_global(sol.map_to_local(destination))

	var tween: Tween = create_tween()
	tween.tween_property(self, "global_position", pos_destination, 0.12 * cout)

	await tween.finished

	occupe = false

	if combat_manager.en_combat:
		_afficher_cases()



func _fin_du_tour() -> void:
	if not combat_manager.en_combat or not tour_joueur or occupe:
		return

	tour_joueur = false
	bouton_fin_tour.hide()
	sort_selectionne = false
	overlay.effacer()
	bouton_fin_tour.disabled = true

	print("FIN DU TOUR DU JOUEUR")
	print("TOUR DE L'ENNEMI")

	# L'ennemi effectue son attaque
	if ennemi != null and is_instance_valid(ennemi):
		await ennemi.jouer_tour()

	# Petite pause avant le prochain tour
	await get_tree().create_timer(1.0).timeout

	if not is_inside_tree() or not combat_manager.en_combat:
		return

	_debut_tour_joueur()
																																				
func _debut_tour_joueur() -> void:
	bouton_fin_tour.show()
	tour_joueur = true
	pa = pa_max
	pm = pm_max

	_maj_affichage()
	_afficher_cases()
	bouton_fin_tour.disabled = false

	print("NOUVEAU TOUR DU JOUEUR")
	
	
	


func recevoir_degats(degats: int) -> void:
	pv = max(pv - degats, 0)

	# Actualiser la barre de vie du joueur
	barre_vie_joueur.value = pv

	# Actualiser les statistiques
	_maj_affichage()

	print("JOUEUR TOUCHÉ !")
	print("PV restants : ", pv, " / ", pv_max)

	if pv <= 0:
		print("JOUEUR KO !")
		
		
func _on_placement_commence() -> void:
	tour_joueur = false
	sort_selectionne = false
	en_deplacement = false
	velocity = Vector2.ZERO
	bouton_fin_tour.disabled = true

	# Position actuelle de l'ennemi
	var case_ennemi: Vector2i = sol.local_to_map(
		sol.to_local(ennemi.global_position)
	)

	# Chercher une case de départ à distance
	var meilleure_case: Vector2i = ma_case()
	var meilleure_distance: int = 999999

	for x in range(-distance_placement, distance_placement + 1):
		for y in range(-distance_placement, distance_placement + 1):
			var candidate: Vector2i = case_ennemi + Vector2i(x, y)

			if not case_libre(candidate):
				continue

			var distance: int = abs(x) + abs(y)
			var difference: int = abs(distance - distance_placement)

			if difference < meilleure_distance:
				meilleure_distance = difference
				meilleure_case = candidate

	# Téléportation automatique
	global_position = sol.to_global(
		sol.map_to_local(meilleure_case)
	)

	# Calcul de la zone de placement
	cases_placement.clear()

	for x in range(-rayon_placement, rayon_placement + 1):
		for y in range(-rayon_placement, rayon_placement + 1):
			if abs(x) + abs(y) > rayon_placement:
				continue

			var candidate: Vector2i = meilleure_case + Vector2i(x, y)

			if case_libre(candidate):
				cases_placement.append(candidate)

	overlay.effacer()
	overlay.afficher(cases_placement)

	bouton_pret.show()
	_maj_affichage()

	print("PLACEMENT AUTOMATIQUE ACTIVÉ")


func _valider_placement() -> void:
	if not combat_manager.en_placement:
		return

	bouton_pret.hide()
	cases_placement.clear()
	overlay.effacer()

	combat_manager.valider_placement()
