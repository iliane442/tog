extends CharacterBody2D

@export var speed: float = 300.0
@export var rayon_placement: int = 2
@export var pa_max: int = 6
@export var pm_max: int = 3
# limite de temps d'un tour du joueur, en secondes (0 = pas de limite)
@export var temps_tour: float = 30.0

const LIGNES := {"sud": 0, "ouest": 1, "est": 2, "nord": 3}
const FRAMES_REPOS := 4
const FRAMES_MARCHE := 6
const FPS_REPOS := 6.0
const FPS_MARCHE := 10.0
const VISUELS_RACES := {
	"human": "humain_pirate",
	"mink": "mink_pirate",
	"fishman": "fishman_pirate",
	"giant": "geant_pirate",
}
const VISUELS_FEMININS := {
	"human": "humaine_pirate",
	"mink": "mink_pirate_f",
	"fishman": "femme_poisson_pirate",
	"giant": "geante_pirate",
}
const RACE_DEFAUT := "human"
const SORT_BOULE_DE_FEU := preload("res://scripts/combat/sort.gd")

@onready var sprite: Sprite2D = $Sprite2D

var target := Vector2.ZERO
var _ligne := 0
var _colonne := 0.0
var _texture_repos: Texture2D
var _texture_marche: Texture2D
var _visuel_charge := ""
var _en_deplacement := false
var _occupe := false
var _tour_joueur := false
var _chrono_tour_actif := false
var _temps_tour_restant := 0.0
var _derniere_seconde_tour := -1
var _sort_selectionne := false
var _sort_selectionne_id := "boule_de_feu"
var _sort_preselectionne_combat := ""
var _recharges_sorts: Dictionary = {}  # id_sort -> tours de recharge restants
var _pa := 0
var _pm := 0
var _cases_placement: Array[Vector2i] = []
var _sort_boule_de_feu

var _sol: TileMapLayer
var _deplacement_combat: Tween
var _ennemi
var _overlay
var _combat_manager
var _navigation := AStarGrid2D.new()
var _chemin_exploration: Array[Vector2i] = []
var _action_arrivee: Callable

func _ready() -> void:
	add_to_group("player")
	target = global_position
	_maj_visuels_race(_prefixe_visuel_race())
	_sol = get_tree().current_scene.get_node_or_null("ground") as TileMapLayer
	_preparer_navigation()
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
	_combat_manager.fuite_demandee.connect(_tenter_fuite)
	_combat_manager.placement_valide.connect(_valider_placement)

func _prefixe_visuel_race() -> String:
	var race := str(Personnage.races.get(Personnage.race_id, {}).get("id_technique", RACE_DEFAUT))
	var visuels := VISUELS_FEMININS if Personnage.sexe == "F" else VISUELS_RACES
	return visuels.get(race, VISUELS_RACES[RACE_DEFAUT])

func utiliser_sort_hors_combat(id_sort: String) -> void:
	if _combat_manager != null and _combat_manager.en_combat:
		return
	if not Personnage.sorts.has(id_sort):
		return
	var sort: Dictionary = Personnage.sorts[id_sort]
	var interface_hud := get_tree().current_scene.find_child("HUD", true, false)
	if str(sort.get("type", "")) == "heal":
		var soin := absi(int(sort.get("degats", 0)))
		if soin <= 0:
			if interface_hud != null:
				interface_hud.afficher_message_sort("Ce sort ne peut pas être lancé hors combat.")
			return
		soin += roundi(Personnage.bonus_soin_sort())
		Personnage.soigner(soin)
		if interface_hud != null:
			interface_hud.afficher_message_sort("%s : +%d PV" % [str(sort.get("nom", "Soin")), soin])
		return
	_sort_preselectionne_combat = id_sort
	if interface_hud != null:
		interface_hud.afficher_message_sort("%s prêt — approche un ennemi pour l’utiliser." % str(sort.get("nom", "Sort")))

func _id_technique_race() -> String:
	return str(Personnage.races.get(Personnage.race_id, {}).get("id_technique", RACE_DEFAUT))

func _maj_visuels_race(visuel: String) -> void:
	var prefixe := visuel
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
	_visuel_charge = visuel

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if _combat_manager != null and _combat_manager.en_combat:
		_gerer_clic_combat()
	else:
		_aller_vers(get_global_mouse_position())

func _preparer_navigation() -> void:
	if _sol == null:
		return
	_navigation.region = _sol.get_used_rect()
	_navigation.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_navigation.update()
	_navigation.fill_solid_region(_navigation.region)
	for case in _sol.get_used_cells():
		_navigation.set_point_solid(case, false)

func rejoindre_interaction(destination: Vector2, action: Callable) -> void:
	if _combat_manager != null and _combat_manager.en_combat:
		return
	if global_position.distance_to(destination) <= 72.0:
		_arreter_exploration()
		action.call()
		return
	_aller_vers(destination)
	if _en_deplacement:
		_action_arrivee = action

func _aller_vers(destination: Vector2) -> void:
	_arreter_exploration()
	if _sol == null or not _navigation.region.has_area():
		target = destination
		_en_deplacement = true
		return
	var depart := ma_case()
	if not _navigation.region.has_point(depart) or _navigation.is_point_solid(depart):
		return
	var arrivee := _case_de(destination)
	if not _navigation.region.has_point(arrivee) or _navigation.is_point_solid(arrivee):
		var case_visee := arrivee
		var distance_min := INF
		for case in _sol.get_used_cells():
			var distance := case.distance_squared_to(case_visee)
			if distance < distance_min:
				distance_min = distance
				arrivee = case
	_chemin_exploration = _navigation.get_id_path(depart, arrivee)
	if _chemin_exploration.is_empty():
		return
	# Se recentrer dans la grille avant de longer les obstacles.
	target = _sol.to_global(_sol.map_to_local(_chemin_exploration.pop_front()))
	_en_deplacement = true

func _arreter_exploration() -> void:
	_en_deplacement = false
	_chemin_exploration.clear()
	_action_arrivee = Callable()
	velocity = Vector2.ZERO

func _physics_process(delta: float) -> void:
	var visuel := _prefixe_visuel_race()
	if visuel != _visuel_charge:
		_maj_visuels_race(visuel)
	if _combat_manager != null and _combat_manager.en_combat:
		velocity = Vector2.ZERO
		move_and_slide()
		_animer(_deplacement_combat != null, delta)
		_decompter_tour(delta)
		return
	var direction := target - global_position
	if _en_deplacement and direction.length() <= 4.0:
		if _chemin_exploration.is_empty():
			var action := _action_arrivee
			_arreter_exploration()
			if action.is_valid():
				action.call()
		else:
			target = _sol.to_global(_sol.map_to_local(_chemin_exploration.pop_front()))
			direction = target - global_position
	var en_mouvement := _en_deplacement and direction.length() > 4.0
	if en_mouvement:
		# hors combat, le navire porte son capitaine : ses pièces
		# installées donnent un regain d'allant à l'exploration
		var vitesse := speed
		if _combat_manager == null or not _combat_manager.en_combat:
			vitesse *= 1.0 + Personnage.bonus_vitesse_navire()
		velocity = direction.normalized() * minf(vitesse, direction.length() / delta)
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
	if _sol == null or _combat_manager == null or _combat_manager.conclusion_en_cours:
		return
	var case_cliquee := _case_combat_sous_souris()
	if _combat_manager.en_placement:
		if _cases_placement.has(case_cliquee):
			global_position = _sol.to_global(_sol.map_to_local(case_cliquee))
			_faire_face_a_la_cible()
		return
	if not _tour_joueur or _occupe:
		return
	if _sort_selectionne:
		var sort: Dictionary = Personnage.sorts.get(_sort_selectionne_id, {})
		var cible: Node2D = self
		if _sort_selectionne_id != "boule_de_feu" and _combat_manager.est_allie(sort):
			pass
		else:
			# le clic vise l'ennemi qui occupe la case (sinon le plus proche)
			cible = _combat_manager.ennemi_sur_case(case_cliquee)
			if cible == null:
				cible = _combat_manager.cible_courante()
		if cible != null and is_instance_valid(cible) and case_cliquee == _case_de(cible.global_position):
			if _sort_selectionne_id == "boule_de_feu":
				_lancer_boule_de_feu(cible)
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

func _case_combat_sous_souris() -> Vector2i:
	var viser_ennemi: bool = _sort_selectionne and (_sort_selectionne_id == "boule_de_feu"
		or not _combat_manager.est_allie(Personnage.sorts.get(_sort_selectionne_id, {})))
	return _combat_manager.case_sous_point(get_global_mouse_position(), viser_ennemi)

func ma_case() -> Vector2i:
	return _case_de(global_position)

func _case_de(position_globale: Vector2) -> Vector2i:
	return _sol.local_to_map(_sol.to_local(position_globale))

func _case_libre(case: Vector2i) -> bool:
	if _sol == null or _sol.get_cell_source_id(case) == -1:
		return false
	# aucune case occupée par un ennemi engagé dans le combat n'est libre
	for ennemi in _combat_manager.ennemis_actifs():
		if case == _case_de((ennemi as Node2D).global_position):
			return false
	return true

func _calculer_portee(parents: Dictionary = {}) -> Dictionary:
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
			if _combat_manager != null and not _combat_manager.dans_zone_combat(suivante):
				continue
			distances[suivante] = int(distances[courante]) + 1
			parents[suivante] = courante
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
			if distance >= portee_min and distance <= portee and _sol.get_cell_source_id(case) != -1 and _combat_manager.ligne_de_vue_libre(depart, case):
				cases.append(case)
	return cases

func _on_placement_commence() -> void:
	_tour_joueur = false
	_arreter_chrono_tour()
	_sort_selectionne = false
	_arreter_exploration()
	_sol = _combat_manager.sol_combat()
	_faire_face_a_la_cible()
	_cases_placement.clear()
	var depart := ma_case()
	for x in range(-rayon_placement, rayon_placement + 1):
		for y in range(-rayon_placement, rayon_placement + 1):
			var candidate := depart + Vector2i(x, y)
			if absi(x) + absi(y) <= rayon_placement and _case_libre(candidate):
				_cases_placement.append(candidate)
	if _overlay != null:
		_overlay.definir_sol(_sol, _case_combat_sous_souris)
		_overlay.afficher(_cases_placement)

func _valider_placement() -> void:
	if _combat_manager == null or not _combat_manager.en_placement:
		return
	_cases_placement.clear()
	if _overlay != null:
		_overlay.effacer()
	_combat_manager.valider_placement()

func _faire_face_a_la_cible() -> void:
	var cible: Node2D = _combat_manager.cible_courante()
	if is_instance_valid(cible):
		_ligne = _ligne_cardinale(cible.global_position - global_position)

func _on_combat_commence() -> void:
	# un combat neuf repart sans recharges
	_recharges_sorts.clear()
	if _combat_manager.pvp_actif:
		# duel : pas de jet d'initiative — le joueur qui a défié ouvre
		# toujours (l'autre attend notre fin de tour par le réseau, un
		# jet perdu des deux côtés figeait le duel)
		if _combat_manager.pvp_premier:
			_tour_joueur = true
			_pa = pa_max
			_pm = _combat_manager.points_mouvement(self, pm_max)
			if randf() < Personnage.chance_pm_supplementaire():
				_pm += 1
				_combat_manager.afficher_message("Ta vitesse te donne +1 PM.")
			_maj_affichage()
			_afficher_cases()
			_demarrer_chrono_tour()
			_combat_manager.afficher_message("Le duel commence : à toi de jouer !")
			_combat_manager.definir_combattant_actif(self)
			if _sort_preselectionne_combat != "":
				var sort_choisi := _sort_preselectionne_combat
				_sort_preselectionne_combat = ""
				_selectionner_sort(sort_choisi)
		else:
			# duel : l'adversaire ouvre, on attend son tour complet
			_tour_joueur = false
			_maj_affichage()
			_combat_manager.afficher_message("Le duel commence : %s joue en premier." % _combat_manager._nom_adversaire())
			_combat_manager.definir_combattant_actif(_combat_manager.adversaire_duel())
			_attendre_tour_adverse_pvp()
		return
	if randf() >= Personnage.chance_initiative():
		# initiative perdue (Vitesse) : les ennemis ouvrent le combat
		_combat_manager.afficher_message("L’ennemi prend l’initiative !")
		_tour_joueur = false
		_maj_affichage()
		_jouer_tours_ennemis(_combat_manager.numero_combat, 0.8)
		return
	_tour_joueur = true
	_combat_manager.definir_combattant_actif(self)
	_pa = pa_max
	_pm = _combat_manager.points_mouvement(self, pm_max)
	if randf() < Personnage.chance_pm_supplementaire():
		_pm += 1
		_combat_manager.afficher_message("Ta vitesse te donne +1 PM.")
	_maj_affichage()
	_afficher_cases()
	_demarrer_chrono_tour()
	if _sort_preselectionne_combat != "":
		var sort_choisi := _sort_preselectionne_combat
		_sort_preselectionne_combat = ""
		_selectionner_sort(sort_choisi)

func _on_combat_termine(_victoire: bool) -> void:
	_tour_joueur = false
	_arreter_chrono_tour()
	_sort_selectionne = false
	# plus de combat : plus de recharges, la barre redevient blanche
	_recharges_sorts.clear()
	_cases_placement.clear()
	_sol = get_tree().current_scene.get_node_or_null("ground") as TileMapLayer
	target = global_position
	if _overlay != null:
		_overlay.effacer()
		_overlay.definir_sol(null)
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
	if _combat_manager.conclusion_en_cours:
		return
	if not _combat_manager.sort_autorise(self):
		_combat_manager.afficher_message("Le silence t’empêche de lancer un sort.")
		return
	if id_sort != "boule_de_feu" and not Personnage.sorts.has(id_sort):
		return
	var sort: Dictionary = Personnage.sorts.get(id_sort, {})
	if int(_recharges_sorts.get(id_sort, 0)) > 0:
		_combat_manager.afficher_message("%s se recharge encore (%d tour(s))." % [
			str(sort.get("nom", "Sort")), int(_recharges_sorts[id_sort])])
		return
	var cout: int = int(_sort_boule_de_feu.cout_pa) if id_sort == "boule_de_feu" else int(sort.get("cout_pa", 2))
	var portee: int = int(_sort_boule_de_feu.portee_max) if id_sort == "boule_de_feu" else int(sort.get("portee", 1))
	if _pa < cout:
		_combat_manager.afficher_message("Pas assez de PA pour lancer le sort.")
		return
	_sort_selectionne_id = id_sort
	_sort_selectionne = true
	var cible: Node2D = self if id_sort != "boule_de_feu" and _combat_manager.est_allie(sort) else _combat_manager.cible_courante()
	if _overlay != null:
		_overlay.afficher_sort(_cases_du_sort(portee, 0 if cible == self else 1))
	var distance := 0 if cible == self else _distance_ennemi()
	if cible == null or not is_instance_valid(cible):
		_combat_manager.afficher_message("Aucune cible disponible pour ce sort.")
	elif distance > portee:
		_combat_manager.afficher_message("Cible hors portée : déplace-toi sur une case bleue, puis clique sur la cible.")
	elif cible != self and not _combat_manager.ligne_de_vue_libre(ma_case(), _case_de(cible.global_position)):
		_combat_manager.afficher_message("Ligne de vue bloquée. Déplace-toi sur une case bleue pour changer d’angle.")
	elif _combat_manager.cible_verrouillee() == cible and cible != null:
		# cible verrouillée via les touches de sélection : le sort part
		# directement, sans attendre un clic de confirmation
		if id_sort == "boule_de_feu":
			_lancer_boule_de_feu(cible)
		else:
			_lancer_sort_etat(id_sort, sort, cible)
	else:
		_combat_manager.afficher_message("Sort sélectionné : clique sur %s pour le lancer." % ("toi-même" if cible == self else "l’ennemi"))

func _lancer_sort_etat(_id_sort: String, sort: Dictionary, cible: Node2D) -> bool:
	var cout: int = int(sort.get("cout_pa", 2))
	var portee: int = int(sort.get("portee", 1))
	var distance := 0 if cible == self else _distance_depuis(cible)
	if _pa < cout or distance > portee or (cible != self and not _combat_manager.ligne_de_vue_libre(ma_case(), _case_de(cible.global_position))):
		_combat_manager.afficher_message("Cible hors portée ou ligne de vue bloquée.")
		return false
	if not _combat_manager.precision_reussie(self):
		_jouer_effet_sort(_id_sort, cible, false)
		_pa -= cout
		_demarrer_recharge_sort(_id_sort, sort)
		_combat_manager.afficher_message("Le sort rate sa cible.")
		_emettre_action_duel(_evenement_sort(_id_sort, cible, "manque"))
	else:
		var evenement := _evenement_sort(_id_sort, cible, "sort")
		_jouer_effet_sort(_id_sort, cible)
		var soin := absi(int(sort.get("degats", 0))) if str(sort.get("type", "")) == "heal" else 0
		if soin > 0:
			soin += roundi(Personnage.bonus_soin_sort())
			Personnage.soigner(soin)
			_maj_affichage()
		var degats := 0
		if soin <= 0 and int(sort.get("degats", 0)) > 0:
			degats = _combat_manager.calculer_degats(self, cible, int(sort.get("degats", 0)), str(sort.get("type", "")), int(sort.get("portee", 1)))
			cible.recevoir_degats(degats)
		var etats_appliques: Array = []
		if _combat_manager.en_combat:
			etats_appliques = _combat_manager.appliquer_effets_sort(cible, sort)
		if _combat_manager.pvp_actif or _combat_manager.groupe_actif:
			evenement["nom"] = str(sort.get("nom", "Sort"))
			evenement["etats"] = etats_appliques
			evenement["soin" if cible == self else "degats"] = soin if cible == self else degats
			_emettre_action_duel(evenement)
		_pa -= cout
		_demarrer_recharge_sort(_id_sort, sort)
		_combat_manager.afficher_message("%s lancé." % str(sort.get("nom", "Sort")))
		# le fruit mangé progresse à chaque pouvoir utilisé : ses sorts
		# se débloquent par son niveau (voir Personnage.fruit_xp)
		if Personnage.fruit_id != "":
			for id_debloque in Personnage.utiliser_pouvoir_fruit(_id_sort):
				var nom_nouveau: String = str(Personnage.sorts.get(id_debloque, {}).get("nom", "Nouveau pouvoir"))
				_combat_manager.afficher_message("Ton fruit s'élève : %s débloqué !" % nom_nouveau)
	_sort_selectionne = false
	_maj_affichage()
	_afficher_cases()
	return true

# le sort consommé part en recharge : base_cooldown tours séparent
# deux lancements (1 = jouable à chaque tour, la recharge est
# simplement ignorée)
func _demarrer_recharge_sort(id_sort: String, sort: Dictionary) -> void:
	var recharge := maxi(int(sort.get("recharge", 1)), 1)
	if recharge > 1:
		_recharges_sorts[id_sort] = recharge
	else:
		_recharges_sorts.erase(id_sort)

# recharge restante d'un sort, pour la barre de sorts du HUD
func recharge_restante_sort(id_sort: String) -> int:
	return int(_recharges_sorts.get(id_sort, 0))

# distance de Manhattan jusqu'à une cible précise
func _distance_depuis(cible: Node2D) -> int:
	if cible == null or not is_instance_valid(cible) or _sol == null:
		return 1_000_000
	var depart := ma_case()
	var case_cible := _case_de(cible.global_position)
	return absi(depart.x - case_cible.x) + absi(depart.y - case_cible.y)

# distance jusqu'à l'ennemi engagé le plus proche
func _distance_ennemi() -> int:
	var cible: Node2D = _combat_manager.cible_courante() if _combat_manager != null else null
	if cible == null:
		return 1_000_000
	return _distance_depuis(cible)

func _jouer_effet_sort(id_sort: String, cible: Node2D, touche := true) -> void:
	if not is_instance_valid(cible):
		return
	if cible != self:
		_ligne = _ligne_cardinale(cible.global_position - global_position)
		_animer(false, 0.0)
	_combat_manager.jouer_animation_sort(id_sort, self, cible, touche)

func _evenement_sort(id_sort: String, cible: Node2D, type: String) -> Dictionary:
	var evenement := {"t": type, "id": id_sort, "cible": "soi" if cible == self else "adv"}
	if cible != self:
		# Le nom de nœud reste stable quand la liste des ennemis change.
		evenement["cible_nom"] = cible.name
		evenement["index"] = _combat_manager.ennemis_actifs().find(cible)
	return evenement

func _lancer_boule_de_feu(cible_visée: Node2D = null) -> bool:
	var cible: Node2D = cible_visée
	if cible == null or not is_instance_valid(cible):
		cible = _combat_manager.cible_courante()
	if cible == null or not is_instance_valid(cible) or _pa < _sort_boule_de_feu.cout_pa:
		_combat_manager.afficher_message("Le sort ne peut pas être lancé pour le moment.")
		return false
	var case_ennemi := _case_de(cible.global_position)
	var depart := ma_case()
	var distance := _distance_depuis(cible)
	if distance < _sort_boule_de_feu.portee_min or distance > _sort_boule_de_feu.portee_max:
		_combat_manager.afficher_message("Ennemi hors portée : déplace-toi sur une case bleue.")
		return false
	if not _combat_manager.ligne_de_vue_libre(depart, case_ennemi):
		_combat_manager.afficher_message("La ligne de vue vers l’ennemi est bloquée.")
		return false
	_pa -= _sort_boule_de_feu.cout_pa
	if _combat_manager.precision_reussie(self):
		var evenement := _evenement_sort("boule_de_feu", cible, "sort")
		_jouer_effet_sort("boule_de_feu", cible)
		var degats: int = _combat_manager.calculer_degats(self, cible, int(_sort_boule_de_feu.degats), "attack", int(_sort_boule_de_feu.portee_max))
		cible.recevoir_degats(degats)
		evenement["nom"] = "Boule de feu"
		evenement["degats"] = degats
		_emettre_action_duel(evenement)
		_combat_manager.effacer_message()
	else:
		_jouer_effet_sort("boule_de_feu", cible, false)
		_combat_manager.afficher_message("La boule de feu rate sa cible.")
		_emettre_action_duel(_evenement_sort("boule_de_feu", cible, "manque"))
	_sort_selectionne = false
	if _overlay != null:
		_overlay.effacer()
	_maj_affichage()
	_afficher_cases()
	return true

# en duel ou en combat de groupe, une action résolue part aux autres
# joueurs pour être rejouée
func _emettre_action_duel(evenement: Dictionary) -> void:
	if _combat_manager == null:
		return
	var reseau := get_tree().root.get_node_or_null("/root/Reseau")
	if reseau == null:
		return
	if _combat_manager.pvp_actif:
		reseau.call("emettre_action_duel", evenement)
	elif _combat_manager.groupe_actif:
		reseau.call("emettre_action_groupe", evenement)

func _deplacer_case_par_case(destination: Vector2i, cout: int) -> void:
	if _occupe or cout <= 0 or cout > _pm:
		return
	var parents := {}
	var portee := _calculer_portee(parents)
	if int(portee.get(destination, 0)) != cout:
		return
	var trajet: Array[Vector2i] = []
	var case := destination
	var depart := ma_case()
	while case != depart:
		trajet.push_front(case)
		case = parents[case]
	_occupe = true
	_pm -= cout
	if _combat_manager.pvp_actif or _combat_manager.groupe_actif:
		var trajet_reseau: Array = []
		for etape in trajet:
			trajet_reseau.append([etape.x, etape.y])
		_emettre_action_duel({"t": "deplacement", "trajet": trajet_reseau})
	_combat_manager.effacer_message()
	if _overlay != null:
		_overlay.effacer()
	_maj_affichage()
	_deplacement_combat = create_tween()
	for etape in trajet:
		var position_etape := _sol.to_global(_sol.map_to_local(etape))
		_deplacement_combat.tween_callback(func():
			_ligne = _ligne_cardinale(position_etape - global_position))
		_deplacement_combat.tween_property(self, "global_position", position_etape, 0.12)
	_deplacement_combat.finished.connect(_fin_deplacement_combat)

func _fin_deplacement_combat() -> void:
	_deplacement_combat = null
	_occupe = false
	_afficher_cases()

func arreter_deplacement_combat() -> void:
	if _deplacement_combat != null:
		_deplacement_combat.kill()
		_deplacement_combat = null
	_occupe = false

# ============================================================
#  CHRONOMETRE DE TOUR
# ============================================================

# le tour du joueur est limité en temps (temps_tour secondes, 0 pour
# désactiver) : à zéro, le tour se termine tout seul — en duel, la fin
# part au réseau exactement comme une fin manuelle, un joueur absent
# ne bloque plus son adversaire ; le décompte se met en pause pendant
# les animations (déplacements, sorts) pour ne pas voler du temps de
# jeu au joueur actif
func _demarrer_chrono_tour() -> void:
	_chrono_tour_actif = temps_tour > 0.0
	_temps_tour_restant = temps_tour
	_derniere_seconde_tour = -1
	_maj_affichage_chrono()

func _arreter_chrono_tour() -> void:
	_chrono_tour_actif = false
	_temps_tour_restant = 0.0
	_derniere_seconde_tour = -1
	if _combat_manager != null:
		_combat_manager.maj_temps_tour(-1)

func _decompter_tour(delta: float) -> void:
	if not _chrono_tour_actif or not _tour_joueur or _occupe:
		return
	if _combat_manager != null and _combat_manager.conclusion_en_cours:
		return
	_temps_tour_restant -= delta
	_maj_affichage_chrono()
	if _temps_tour_restant <= 0.0:
		_arreter_chrono_tour()
		if _combat_manager != null:
			_combat_manager.afficher_message("Temps écoulé : fin de ton tour !")
		_fin_du_tour()

# le HUD ne suit que les secondes entières : une mise à jour par
# changement de seconde, pas à chaque frame
func _maj_affichage_chrono() -> void:
	if _combat_manager == null or not _chrono_tour_actif:
		return
	var seconde := maxi(int(ceilf(_temps_tour_restant)), 0)
	if seconde != _derniere_seconde_tour:
		_derniere_seconde_tour = seconde
		_combat_manager.maj_temps_tour(seconde)

func _fin_du_tour() -> void:
	if _combat_manager == null or not _combat_manager.en_combat or not _tour_joueur or _occupe:
		return
	if _combat_manager.conclusion_en_cours:
		return
	var numero: int = _combat_manager.numero_combat
	_tour_joueur = false
	_arreter_chrono_tour()
	_sort_selectionne = false
	if _overlay != null:
		_overlay.effacer()
	_combat_manager.terminer_tour(self)
	# duel/groupe : notre tour fini part aux autres avant d'attendre le leur
	if _combat_manager.pvp_actif or _combat_manager.groupe_actif:
		_emettre_action_duel({"t": "fin_tour"})
	# suivi des tours : on sait toujours qui joue
	if _combat_manager.pvp_actif:
		_combat_manager.afficher_message("Au tour de %s…" % _combat_manager._nom_adversaire())
		_combat_manager.definir_combattant_actif(_combat_manager.adversaire_duel())
	else:
		_combat_manager.afficher_message("Les ennemis jouent…")
	_jouer_tours_ennemis(numero, 0.5)

# fuit le combat : toujours réussie pendant le placement, un duel ou
# un combat de groupe se dissout, contre des ennemis elle se joue à
# la chance (agilité) et un échec coûte le tour
func _tenter_fuite() -> void:
	if _combat_manager == null or not _combat_manager.en_combat or _occupe:
		return
	if _combat_manager.conclusion_en_cours:
		return
	# en plein combat contre des ennemis, on ne fuit que pendant son tour
	if not _combat_manager.en_placement and not _tour_joueur:
		_combat_manager.afficher_message("Tu ne peux fuir que pendant ton tour !")
		return
	# placement, duel ou combat de groupe : partir dissout l'engagement
	if _combat_manager.en_placement or _combat_manager.pvp_actif or _combat_manager.groupe_actif:
		_combat_manager.afficher_message("Tu prends la fuite !")
		_combat_manager.terminer_combat(false, _combat_manager.pvp_actif)
		return
	if randf() < Personnage.chance_fuite():
		_combat_manager.afficher_message("Tu prends la fuite !")
		_combat_manager.terminer_combat(false)
		return
	_combat_manager.afficher_message("Tu échoues à fuir !")
	_fin_du_tour()

# sequence : le tour de chaque ennemi engagé, l'un après l'autre, puis
# le tour du joueur (pause avant sa reprise)
func _jouer_tours_ennemis(numero: int, pause: float) -> void:
	for ennemi in _combat_manager.ennemis_actifs():
		if not is_inside_tree() or not _combat_manager.en_combat or numero != _combat_manager.numero_combat:
			return
		# c'est le tour de cet ennemi (marqueur sur l'arène, ligne
		# surlignée dans le roster)
		_combat_manager.definir_combattant_actif(ennemi)
		await (ennemi as Node2D).jouer_tour(self, _sol)
	await get_tree().create_timer(pause, false).timeout
	_commencer_mon_tour(numero)

# en duel, quand c'est l'adversaire qui ouvre : son tour complet nous
# parvient par le réseau, joué sur notre miroir de lui
func _attendre_tour_adverse_pvp() -> void:
	_jouer_tours_ennemis(_combat_manager.numero_combat, 0.3)

func _commencer_mon_tour(numero: int) -> void:
	if not is_inside_tree() or _combat_manager == null or not _combat_manager.en_combat or numero != _combat_manager.numero_combat:
		return
	if _combat_manager.conclusion_en_cours:
		return
	var tour_bloque: bool = _combat_manager.preparer_tour(self)
	if tour_bloque:
		_combat_manager.terminer_tour(self)
		_combat_manager.afficher_message("Tu es immobilisé et perds ton tour.")
		_tour_joueur = true
		await get_tree().create_timer(0.3).timeout
		if _combat_manager.en_combat and numero == _combat_manager.numero_combat:
			_fin_du_tour()
		return
	# chaque reprise de notre tour fait descendre les recharges d'un cran
	for id_recharge in _recharges_sorts.keys():
		_recharges_sorts[id_recharge] = maxi(int(_recharges_sorts[id_recharge]) - 1, 0)
	_tour_joueur = true
	_pa = pa_max
	_pm = _combat_manager.points_mouvement(self, pm_max)
	if randf() < Personnage.chance_pm_supplementaire():
		_pm += 1
		_combat_manager.afficher_message("Ta vitesse te donne +1 PM.")
	_maj_affichage()
	_afficher_cases()
	_demarrer_chrono_tour()
	# suivi des tours : les ennemis ont fini, c'est de nouveau à nous
	_combat_manager.afficher_message("À toi de jouer !")
	_combat_manager.definir_combattant_actif(self)

func recevoir_degats(degats: int) -> void:
	Personnage.blesser(maxi(degats, 0))
	_maj_affichage()
	if Personnage.vie <= 0 and _combat_manager != null:
		if _combat_manager.groupe_actif:
			_emettre_action_duel({"t": "tombe"})
		_combat_manager.terminer_sur_impact(false, self)

func _maj_affichage() -> void:
	if _combat_manager != null:
		_combat_manager.mettre_a_jour_stats(Personnage.vie, Personnage.vie_max, _pa, pa_max, _pm, pm_max)
