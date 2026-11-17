extends CharacterBody2D

@export var speed: float = 300.0
@export var distance_placement: int = 5
@export var rayon_placement: int = 2
@export var pa_max: int = 6
@export var pm_max: int = 3

const LIGNES := {"sud": 0, "ouest": 1, "est": 2, "nord": 3}
const FRAMES_REPOS := 4
const FRAMES_MARCHE := 6
const FPS_REPOS := 6.0
const FPS_MARCHE := 10.0
const VISUELS_RACES := {
	"human": "humain_pirate",
	"mink": "mink_pirate",
	"fishman": "fishman_pirate",
}
const RACE_DEFAUT := "human"
const SORT_BOULE_DE_FEU := preload("res://scripts/combat/sort.gd")

@onready var sprite: Sprite2D = $Sprite2D

var target := Vector2.ZERO
var _ligne := 0
var _colonne := 0.0
var _texture_repos: Texture2D
var _texture_marche: Texture2D
var _race_chargee := ""
var _en_deplacement := false
var _occupe := false
var _tour_joueur := false
var _sort_selectionne := false
var _sort_selectionne_id := "boule_de_feu"
var _pa := 0
var _pm := 0
var _cases_placement: Array[Vector2i] = []
var _sort_boule_de_feu

var _sol: TileMapLayer
var _obstacles: TileMapLayer
var _ennemi
var _overlay
var _combat_manager

func _ready() -> void:
	add_to_group("player")
	target = global_position
	_maj_visuels_race()
	_sol = get_tree().current_scene.get_node_or_null("ground") as TileMapLayer
	_obstacles = get_tree().current_scene.get_node_or_null("cliffs") as TileMapLayer
	_ennemi = get_tree().current_scene.find_child("ennemy", true, false)
	_overlay = get_tree().current_scene.find_child("Overlay", true, false)
	_combat_manager = get_tree().current_scene.get_node_or_null("CombatManager")
	_sort_boule_de_feu = SORT_BOULE_DE_FEU.new()
	_sort_boule_de_feu.nom = "Boule de feu"
	_sort_boule_de_feu.cout_pa = 3
	_sort_boule_de_feu.portee_min = 1
	_sort_boule_de_feu.portee_max = 3
	_sort_boule_de_feu.degats = 20
	_pa = pa_max
	_pm = pm_max
	_connecter_combat()
	_maj_affichage()

func _connecter_combat() -> void:
	if _combat_manager == null:
		return
	_combat_manager.initialiser(self, _ennemi)
	_combat_manager.placement_commence.connect(_on_placement_commence)
	_combat_manager.combat_commence.connect(_on_combat_commence)
	_combat_manager.combat_termine.connect(_on_combat_termine)
	_combat_manager.sort_demandee.connect(_selectionner_sort)
	_combat_manager.fin_tour_demandee.connect(_fin_du_tour)
	_combat_manager.placement_valide.connect(_valider_placement)

func _id_technique_race() -> String:
	return str(Personnage.races.get(Personnage.race_id, {}).get("id_technique", RACE_DEFAUT))

func _maj_visuels_race() -> void:
	var race := _id_technique_race()
	var prefixe: String = VISUELS_RACES.get(race, RACE_DEFAUT)
	var repos := "res://assets/sprites/%s/%s_idle.png" % [prefixe, prefixe]
	var marche := "res://assets/sprites/%s/%s_walk.png" % [prefixe, prefixe]
	if not (ResourceLoader.exists(repos) and ResourceLoader.exists(marche)):
		prefixe = VISUELS_RACES[RACE_DEFAUT]
		repos = "res://assets/sprites/%s/%s_idle.png" % [prefixe, prefixe]
		marche = "res://assets/sprites/%s/%s_walk.png" % [prefixe, prefixe]
	_texture_repos = load(repos)
	_texture_marche = load(marche)
	sprite.texture = _texture_marche
	sprite.hframes = FRAMES_MARCHE
	_race_chargee = race

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if _combat_manager != null and _combat_manager.en_combat:
		_gerer_clic_combat()
	else:
		target = get_global_mouse_position()
		_en_deplacement = true

func _physics_process(delta: float) -> void:
	var race := _id_technique_race()
	if race != _race_chargee:
		_maj_visuels_race()
	if _combat_manager != null and _combat_manager.en_combat:
		velocity = Vector2.ZERO
		move_and_slide()
		_animer(false, delta)
		return
	var direction := target - global_position
	var en_mouvement := _en_deplacement and direction.length() > 5.0
	if en_mouvement:
		velocity = direction.normalized() * speed
		_ligne = _ligne_cardinale(direction)
	else:
		velocity = Vector2.ZERO
		_en_deplacement = false
	move_and_slide()
	_animer(en_mouvement, delta)

func _animer(en_mouvement: bool, delta: float) -> void:
	var feuille := _texture_marche if en_mouvement else _texture_repos
	var colonnes := FRAMES_MARCHE if en_mouvement else FRAMES_REPOS
	_colonne = fmod(_colonne + delta * (FPS_MARCHE if en_mouvement else FPS_REPOS), float(colonnes))
	if sprite.texture != feuille:
		sprite.texture = feuille
		sprite.hframes = colonnes
	sprite.frame = _ligne * colonnes + int(_colonne)

func _ligne_cardinale(direction: Vector2) -> int:
	if absf(direction.x) > absf(direction.y):
		return LIGNES["est"] if direction.x > 0.0 else LIGNES["ouest"]
	return LIGNES["nord"] if direction.y < 0.0 else LIGNES["sud"]

func _gerer_clic_combat() -> void:
	if _sol == null or _combat_manager == null:
		return
	var case_cliquee := _sol.local_to_map(_sol.get_local_mouse_position())
	if _combat_manager.en_placement:
		if _cases_placement.has(case_cliquee):
			global_position = _sol.to_global(_sol.map_to_local(case_cliquee))
		return
	if not _tour_joueur or _occupe:
		return
	if _sort_selectionne:
		var sort: Dictionary = Personnage.sorts.get(_sort_selectionne_id, {})
		var cible: Node2D = self if _sort_selectionne_id != "boule_de_feu" and _combat_manager.est_allie(sort) else _ennemi
		if cible != null and is_instance_valid(cible) and case_cliquee == _case_de(cible.global_position):
			if _sort_selectionne_id == "boule_de_feu":
				_lancer_boule_de_feu()
			else:
				_lancer_sort_etat(_sort_selectionne_id, sort, cible)
			return
		var portee_deplacement := _calculer_portee()
		if case_cliquee != ma_case() and portee_deplacement.has(case_cliquee):
			_combat_manager.effacer_message()
			_deplacer_case_par_case(case_cliquee, int(portee_deplacement[case_cliquee]))
		return
	var portee := _calculer_portee()
	if case_cliquee != ma_case() and portee.has(case_cliquee):
		_deplacer_case_par_case(case_cliquee, int(portee[case_cliquee]))

func ma_case() -> Vector2i:
	return _case_de(global_position)

func _case_de(position_globale: Vector2) -> Vector2i:
	return _sol.local_to_map(_sol.to_local(position_globale))

func _case_libre(case: Vector2i) -> bool:
	if _sol == null or _sol.get_cell_source_id(case) == -1:
		return false
	return _ennemi == null or not is_instance_valid(_ennemi) or case != _case_de(_ennemi.global_position)

func _calculer_portee() -> Dictionary:
	var distances := {ma_case(): 0}
	var file: Array[Vector2i] = [ma_case()]
	var voisins: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
	while not file.is_empty():
		var courante: Vector2i = file.pop_front()
		if int(distances[courante]) >= _pm:
			continue
		for voisin in voisins:
			var suivante := courante + voisin
			if distances.has(suivante) or not _case_libre(suivante):
				continue
			distances[suivante] = int(distances[courante]) + 1
			file.append(suivante)
	return distances

func _cases_du_sort(portee_max: int = -1, portee_min: int = 1) -> Array[Vector2i]:
	var cases: Array[Vector2i] = []
	var depart := ma_case()
	var portee: int = int(_sort_boule_de_feu.portee_max) if portee_max < 0 else portee_max
	for x in range(-portee, portee + 1):
		for y in range(-portee, portee + 1):
			var distance := absi(x) + absi(y)
			var case := depart + Vector2i(x, y)
			if distance >= portee_min and distance <= portee and _sol.get_cell_source_id(case) != -1:
				cases.append(case)
	return cases

func _ligne_de_vue_libre(depart: Vector2i, arrivee: Vector2i) -> bool:
	if _sol == null:
		return true
	var x := depart.x
	var y := depart.y
	var dx := absi(arrivee.x - x)
	var dy := absi(arrivee.y - y)
	var sx := 1 if x < arrivee.x else -1
	var sy := 1 if y < arrivee.y else -1
	var erreur := dx - dy
	while x != arrivee.x or y != arrivee.y:
		var double_erreur := 2 * erreur
		if double_erreur > -dy:
			erreur -= dy
			x += sx
		if double_erreur < dx:
			erreur += dx
			y += sy
		if x == arrivee.x and y == arrivee.y:
			break
		var case_intermediaire := Vector2i(x, y)
		if _sol.get_cell_source_id(case_intermediaire) == -1:
			return false
		if _obstacles != null and _obstacles.get_cell_source_id(case_intermediaire) != -1:
			return false
	return true

func _on_placement_commence() -> void:
	_tour_joueur = false
	_sort_selectionne = false
	_en_deplacement = false
	velocity = Vector2.ZERO
	_cases_placement.clear()
	if _sol == null or _ennemi == null or not is_instance_valid(_ennemi):
		_combat_manager.valider_placement()
		return
	var case_ennemi := _case_de(_ennemi.global_position)
	var depart := ma_case()
	var meilleure_case := depart
	var meilleure_difference := 1_000_000
	for x in range(-distance_placement, distance_placement + 1):
		for y in range(-distance_placement, distance_placement + 1):
			var candidate := case_ennemi + Vector2i(x, y)
			if not _case_libre(candidate):
				continue
			var difference := absi(x) + absi(y) - distance_placement
			if absi(difference) < meilleure_difference:
				meilleure_difference = absi(difference)
				meilleure_case = candidate
	global_position = _sol.to_global(_sol.map_to_local(meilleure_case))
	for x in range(-rayon_placement, rayon_placement + 1):
		for y in range(-rayon_placement, rayon_placement + 1):
			var candidate := meilleure_case + Vector2i(x, y)
			if absi(x) + absi(y) <= rayon_placement and _case_libre(candidate):
				_cases_placement.append(candidate)
	if _overlay != null:
		_overlay.afficher(_cases_placement)

func _valider_placement() -> void:
	if _combat_manager == null or not _combat_manager.en_placement:
		return
	_cases_placement.clear()
	if _overlay != null:
		_overlay.effacer()
	_combat_manager.valider_placement()

func _on_combat_commence() -> void:
	_tour_joueur = true
	_pa = pa_max
	_pm = pm_max
	_maj_affichage()
	_afficher_cases()

func _on_combat_termine(_victoire: bool) -> void:
	_tour_joueur = false
	_sort_selectionne = false
	_cases_placement.clear()
	if _overlay != null:
		_overlay.effacer()
	_maj_affichage()

func _afficher_cases() -> void:
	if _overlay == null or _sol == null or _combat_manager == null or not _combat_manager.en_combat:
		return
	var cases: Array[Vector2i] = []
	for case in _calculer_portee():
		if case != ma_case():
			cases.append(case)
	_overlay.afficher(cases)
	if _sort_selectionne:
		var portee: int = int(_sort_boule_de_feu.portee_max)
		var portee_min := 1
		if _sort_selectionne_id != "boule_de_feu":
			var sort: Dictionary = Personnage.sorts.get(_sort_selectionne_id, {})
			portee = int(sort.get("portee", 1))
			if _combat_manager.est_allie(sort):
				portee_min = 0
		_overlay.afficher_sort(_cases_du_sort(portee, portee_min))

func _selectionner_boule_de_feu() -> void:
	_selectionner_sort("boule_de_feu")

func _selectionner_sort(id_sort: String) -> void:
	if _combat_manager == null or not _combat_manager.en_combat or not _tour_joueur:
		return
	if not _combat_manager.sort_autorise(self):
		_combat_manager.afficher_message("Le silence t’empêche de lancer un sort.")
		return
	if id_sort != "boule_de_feu" and not Personnage.sorts.has(id_sort):
		return
	var sort: Dictionary = Personnage.sorts.get(id_sort, {})
	var cout: int = int(_sort_boule_de_feu.cout_pa) if id_sort == "boule_de_feu" else int(sort.get("cout_pa", 2))
	var portee: int = int(_sort_boule_de_feu.portee_max) if id_sort == "boule_de_feu" else int(sort.get("portee", 1))
	if _pa < cout:
		_combat_manager.afficher_message("Pas assez de PA pour lancer le sort.")
		return
	_sort_selectionne_id = id_sort
	_sort_selectionne = true
	var cible: Node2D = self if id_sort != "boule_de_feu" and _combat_manager.est_allie(sort) else _ennemi
	if _overlay != null:
		_overlay.afficher_sort(_cases_du_sort(portee, 0 if cible == self else 1))
	var distance := 0 if cible == self else _distance_ennemi()
	if cible == null or not is_instance_valid(cible):
		_combat_manager.afficher_message("Aucune cible disponible pour ce sort.")
	elif distance > portee:
		_combat_manager.afficher_message("Cible hors portée : déplace-toi sur une case bleue, puis clique sur la cible.")
	elif cible != self and not _ligne_de_vue_libre(ma_case(), _case_de(cible.global_position)):
		_combat_manager.afficher_message("Ligne de vue bloquée. Déplace-toi sur une case bleue pour changer d’angle.")
	else:
		_combat_manager.afficher_message("Sort sélectionné : clique sur %s pour le lancer." % ("toi-même" if cible == self else "l’ennemi"))

func _lancer_sort_etat(_id_sort: String, sort: Dictionary, cible: Node2D) -> bool:
	var cout: int = int(sort.get("cout_pa", 2))
	var portee: int = int(sort.get("portee", 1))
	var distance := 0 if cible == self else _distance_ennemi()
	if _pa < cout or distance > portee or (cible != self and not _ligne_de_vue_libre(ma_case(), _case_de(cible.global_position))):
		_combat_manager.afficher_message("Cible hors portée ou ligne de vue bloquée.")
		return false
	if not _combat_manager.precision_reussie(self):
		_pa -= cout
		_combat_manager.afficher_message("Le sort rate sa cible.")
	else:
		if str(sort.get("type", "")) == "heal":
			Personnage.soigner(absi(int(sort.get("degats", 0))))
			_maj_affichage()
		elif int(sort.get("degats", 0)) > 0:
			cible.recevoir_degats(_combat_manager.calculer_degats(self, cible, int(sort.get("degats", 0))))
		if _combat_manager.en_combat:
			_combat_manager.appliquer_effets_sort(cible, sort)
		_pa -= cout
		_combat_manager.afficher_message("%s lancé." % str(sort.get("nom", "Sort")))
	_sort_selectionne = false
	_maj_affichage()
	_afficher_cases()
	return true

func _distance_ennemi() -> int:
	if _ennemi == null or not is_instance_valid(_ennemi) or _sol == null:
		return 1_000_000
	var depart := ma_case()
	var cible := _case_de(_ennemi.global_position)
	return absi(depart.x - cible.x) + absi(depart.y - cible.y)

func _lancer_boule_de_feu() -> bool:
	if _ennemi == null or not is_instance_valid(_ennemi) or _pa < _sort_boule_de_feu.cout_pa:
		_combat_manager.afficher_message("Le sort ne peut pas être lancé pour le moment.")
		return false
	var case_ennemi := _case_de(_ennemi.global_position)
	var depart := ma_case()
	var distance := _distance_ennemi()
	if distance < _sort_boule_de_feu.portee_min or distance > _sort_boule_de_feu.portee_max:
		_combat_manager.afficher_message("Ennemi hors portée : déplace-toi sur une case bleue.")
		return false
	if not _ligne_de_vue_libre(depart, case_ennemi):
		_combat_manager.afficher_message("La ligne de vue vers l’ennemi est bloquée.")
		return false
	_pa -= _sort_boule_de_feu.cout_pa
	if _combat_manager.precision_reussie(self):
		_ennemi.recevoir_degats(_combat_manager.calculer_degats(self, _ennemi, _sort_boule_de_feu.degats))
		_combat_manager.effacer_message()
	else:
		_combat_manager.afficher_message("La boule de feu rate sa cible.")
	_sort_selectionne = false
	if _overlay != null:
		_overlay.effacer()
	_maj_affichage()
	_afficher_cases()
	return true

func _deplacer_case_par_case(destination: Vector2i, cout: int) -> void:
	if cout <= 0 or cout > _pm:
		return
	_occupe = true
	_pm -= cout
	_combat_manager.effacer_message()
	if _overlay != null:
		_overlay.effacer()
	_maj_affichage()
	var position_cible := _sol.to_global(_sol.map_to_local(destination))
	var tween := create_tween()
	tween.tween_property(self, "global_position", position_cible, 0.12 * cout)
	await tween.finished
	_occupe = false
	_afficher_cases()

func _fin_du_tour() -> void:
	if _combat_manager == null or not _combat_manager.en_combat or not _tour_joueur or _occupe:
		return
	_tour_joueur = false
	_sort_selectionne = false
	if _overlay != null:
		_overlay.effacer()
	_combat_manager.terminer_tour(self)
	if _ennemi != null and is_instance_valid(_ennemi):
		await _ennemi.jouer_tour(self, _sol)
	await get_tree().create_timer(0.5).timeout
	if not is_inside_tree() or not _combat_manager.en_combat:
		return
	var tour_bloque: bool = _combat_manager.preparer_tour(self)
	if tour_bloque:
		_combat_manager.terminer_tour(self)
		_combat_manager.afficher_message("Tu es immobilisé et perds ton tour.")
		_tour_joueur = true
		await get_tree().create_timer(0.3).timeout
		_fin_du_tour()
		return
	_tour_joueur = true
	_pa = pa_max
	_pm = _combat_manager.points_mouvement(self, pm_max)
	_maj_affichage()
	_afficher_cases()

func recevoir_degats(degats: int) -> void:
	Personnage.blesser(maxi(degats, 0))
	_maj_affichage()
	if Personnage.vie <= 0 and _combat_manager != null:
		_combat_manager.terminer_combat(false)

func _maj_affichage() -> void:
	if _combat_manager != null:
		_combat_manager.mettre_a_jour_stats(Personnage.vie, Personnage.vie_max, _pa, pa_max, _pm, pm_max)
