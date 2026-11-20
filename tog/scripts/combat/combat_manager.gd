extends Node

signal combat_commence
signal combat_termine(victoire: bool)
signal placement_commence
signal sort_demandee(id_sort: String)
signal fin_tour_demandee
signal placement_valide
signal ressources_joueur_modifiees(pa: int, pa_max: int, pm: int, pm_max: int)

const ARENE_COMBAT := preload("res://scripts/combat/arene_combat.gd")
const POSITION_ARENE := Vector2(-16384, -16384)

var en_combat := false
var en_placement := false
var numero_combat := 0
var _arene: ARENE_COMBAT
var _camera_exploration: Camera2D
var _positions_exploration := {}
var _joueur: Node
# ennemis engagés dans le combat en cours (le plus proche du joueur
# reste disponible via _ennemi / ennemi_actuel pour l'interface)
var _ennemis: Array = []
# ennemis rencontrés sur la carte hors combat
var _ennemis_connus: Array = []
# ennemis étiquetés par groupe (voir ennemy.gd) : détecter un membre
# propose sa rencontre entière ; « Combattre » engage l'union des
# propositions
var _propositions: Array = []
# ennemis dont la zone de détection chevauche actuellement le joueur
var _detecteurs: Array = []
var _ennemi
var _cible_fiche: Node
# cible verrouillée via les touches de sélection (null = plus proche)
var _cible_selectionnee: Node
# monde partagé : étiquette du groupe combattu ("" si aucun)
var groupe_combat := ""
var pvp_actif := false        # un duel contre un joueur distant est en cours
var pvp_premier := false      # le duel a commencé par notre tour
var _pvp_adversaire: SCRIPT_ADVERSAIRE_PVP   # miroir du joueur distant dans notre arène
var _ui: CanvasLayer
var _fiche_ennemi: PanelContainer
var _barre_vie_ennemi: ProgressBar
var _label_nom_ennemi: Label
var _label_vie_ennemi: Label
var _label_stats_ennemi: Label
var _label_etats_ennemi: Label
var _souris_sur_ennemi := false
var _bouton_combattre: Button
var _etats_actifs: Dictionary = {}
var _hasard := RandomNumberGenerator.new()
const SCENE_COMBAT_UI := preload("res://scenes/combat_ui.tscn")
const SCRIPT_ADVERSAIRE_PVP := preload("res://scripts/combat/adversaire_pvp.gd")

func _ready() -> void:
	_hasard.randomize()
	if _joueur == null:
		_joueur = get_tree().current_scene.find_child("player", true, false)
	_construire_interface()
	for ennemi in _ennemis_connus:
		_connecter_survol_ennemi(ennemi)
	_maj_ennemi_principal()
	mettre_a_jour_stats(Personnage.vie, Personnage.vie_max, 6, 6, 3, 3)

func initialiser(joueur: Node, ennemi: Node) -> void:
	_joueur = joueur
	enregistrer_ennemi(ennemi)

# tout ennemi présent sur la carte est connu : il participe aux combats
# de groupe (détection, ciblage au clic) même hors de son voisinage
func enregistrer_ennemi(ennemi: Node) -> void:
	if ennemi == null or not is_instance_valid(ennemi):
		return
	if not _ennemis_connus.has(ennemi):
		_ennemis_connus.append(ennemi)
	_connecter_survol_ennemi(ennemi)
	_maj_ennemi_principal()

# l'ennemi principal : le plus proche du joueur — sert de cible par
# défaut à l'interface (distances, overlays, sorts alliés)
func _maj_ennemi_principal() -> void:
	# les vaincus et disparus quittent le groupe
	_ennemis = _ennemis.filter(func(e: Node) -> bool: return is_instance_valid(e) and int(e.get("pv")) > 0)
	# le principal est l'engagé le plus proche du joueur (hors combat :
	# le plus proche des ennemis connus)
	_ennemi = ennemi_proche()

func ennemi_actuel() -> Node:
	return _ennemi

# ennemis engagés dans le combat, vivants et encore valides
func ennemis_actifs() -> Array:
	var actifs := []
	for ennemi in _ennemis:
		if ennemi != null and is_instance_valid(ennemi) and int(ennemi.get("pv")) > 0:
			actifs.append(ennemi)
	return actifs

# l'ennemi engagé qui occupe cette case (null si aucun)
func ennemi_sur_case(case_sol: Vector2i) -> Node:
	var sol := sol_combat()
	if sol == null:
		return null
	for ennemi in ennemis_actifs():
		if sol.local_to_map(sol.to_local((ennemi as Node2D).global_position)) == case_sol:
			return ennemi
	return null

# l'ennemi le plus proche du joueur (engagés d'abord, connus sinon)
func ennemi_proche() -> Node:
	if _joueur == null or not is_instance_valid(_joueur):
		return null
	var meilleure: Node = null
	var meilleure_distance := -1
	for ennemi in ennemis_actifs() if en_combat else _ennemis_connus:
		if ennemi == null or not is_instance_valid(ennemi) or int(ennemi.get("pv")) <= 0:
			continue
		var e := ennemi as Node2D
		var distance: float = _joueur.global_position.distance_to(e.global_position)
		if meilleure == null or distance < meilleure_distance:
			meilleure = ennemi
			meilleure_distance = distance
	return meilleure

# la cible par défaut des sorts : la cible verrouillée au clavier si
# elle est encore valide, l'ennemi le plus proche sinon
func cible_courante() -> Node:
	if _cible_selectionnee != null and is_instance_valid(_cible_selectionnee) and int(_cible_selectionnee.get("pv")) > 0:
		return _cible_selectionnee
	return ennemi_proche()

# la cible explicitement verrouillée (null si le joueur n'en a pas
# choisi une via les touches)
func cible_verrouillee() -> Node:
	if _cible_selectionnee != null and is_instance_valid(_cible_selectionnee) and int(_cible_selectionnee.get("pv")) > 0:
		return _cible_selectionnee
	return null

# fait tourner la sélection de cible parmi les ennemis engagés
func cible_suivante() -> void:
	_cycle_cible(1)

func cible_precedente() -> void:
	_cycle_cible(-1)

func _cycle_cible(sens: int) -> void:
	if not en_combat or en_placement:
		return
	var actifs := ennemis_actifs()
	if actifs.size() < 2:
		return
	var cible := cible_courante()
	var index := 0
	if cible != null:
		index = maxi(actifs.find(cible), 0)
	index = int(fposmod(float(index + sens), float(actifs.size())))
	_cible_selectionnee = actifs[index]
	# la fiche de l'ennemi survolé suit la sélection
	_survol_ennemi(_cible_selectionnee)
	_actualiser_fiche_ennemi()

func sol_combat() -> TileMapLayer:
	return _arene.sol if _arene != null else null

func dans_zone_combat(case: Vector2i) -> bool:
	return _arene != null and Rect2i(Vector2i.ZERO, _arene.dimensions).has_point(case)

func ligne_de_vue_libre(depart: Vector2i, arrivee: Vector2i) -> bool:
	var sol := sol_combat()
	if sol == null:
		return false
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
		if sol.get_cell_source_id(Vector2i(x, y)) == -1:
			return false
	return true

func _construire_interface() -> void:
	var ui_existante := get_node_or_null("CombatUI")
	if ui_existante == null:
		_ui = SCENE_COMBAT_UI.instantiate() as CanvasLayer
		if _ui == null:
			push_warning("Impossible de charger l'interface de combat.")
			return
		_ui.name = "CombatUI"
		add_child(_ui)
	else:
		_ui = ui_existante as CanvasLayer
	if _ui == null:
		push_warning("La scène de combat ne contient pas de CanvasLayer CombatUI.")
		return
	_fiche_ennemi = _ui.get_node("FicheEnnemi") as PanelContainer
	_label_nom_ennemi = _ui.get_node("FicheEnnemi/Marges/Colonne/Nom") as Label
	_barre_vie_ennemi = _ui.get_node("FicheEnnemi/Marges/Colonne/LigneVie/Vie") as ProgressBar
	_label_vie_ennemi = _ui.get_node("FicheEnnemi/Marges/Colonne/LigneVie/VieTexte") as Label
	_label_stats_ennemi = _ui.get_node("FicheEnnemi/Marges/Colonne/Stats") as Label
	_label_etats_ennemi = _ui.get_node("FicheEnnemi/Marges/Colonne/Etats") as Label
	_fiche_ennemi.hide()
	_actualiser_fiche_ennemi()
	# bouton de proposition de combat (affiché par proposer_combat quand
	# le joueur s'approche d'un ennemi)
	_bouton_combattre = Button.new()
	_bouton_combattre.text = "Combattre"
	_bouton_combattre.custom_minimum_size = Vector2(160, 44)
	_bouton_combattre.pressed.connect(_on_bouton_combattre_presse)
	_ui.add_child(_bouton_combattre)
	_bouton_combattre.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_bouton_combattre.offset_top -= 110.0
	_bouton_combattre.offset_bottom -= 110.0
	_bouton_combattre.hide()

# branche la fiche de survol sur un ennemi donné (mouse_entered avec
# bind pour que la fiche suive n'importe lequel des ennemis)
func _connecter_survol_ennemi(ennemi: Node) -> void:
	if ennemi == null or not is_instance_valid(ennemi):
		return
	var cible := ennemi
	var survol_entree := Callable(self, "_survol_ennemi").bind(cible)
	var survol_sortie := Callable(self, "_quitter_survol_ennemi").bind(cible)
	if ennemi.has_signal("mouse_entered") and not ennemi.is_connected("mouse_entered", survol_entree):
		ennemi.connect("mouse_entered", survol_entree)
	if ennemi.has_signal("mouse_exited") and not ennemi.is_connected("mouse_exited", survol_sortie):
		ennemi.connect("mouse_exited", survol_sortie)
	var maj_sante := Callable(self, "_sante_ennemi_modifiee").bind(cible)
	if ennemi.has_signal("sante_modifiee") and not ennemi.is_connected("sante_modifiee", maj_sante):
		ennemi.connect("sante_modifiee", maj_sante)

func _survol_ennemi(ennemi: Node = null) -> void:
	_souris_sur_ennemi = true
	if ennemi != null:
		_cible_fiche = ennemi
	if not en_combat or _fiche_ennemi == null:
		return
	if ennemi == null and _cible_fiche == null:
		return
	_actualiser_fiche_ennemi()
	_fiche_ennemi.show()
	_positionner_fiche_ennemi()

func _quitter_survol_ennemi(_ennemi_survole: Node = null) -> void:
	_souris_sur_ennemi = false
	if _fiche_ennemi != null:
		_fiche_ennemi.hide()

# la fiche se met à jour pour l'ennemi survolé (ou vu au dernier survol)
func _sante_ennemi_modifiee(_vie: int, _vie_max: int, ennemi: Node = null) -> void:
	if ennemi != null and _cible_fiche != ennemi:
		return
	_actualiser_fiche_ennemi()

func _actualiser_fiche_ennemi() -> void:
	var cible: Node = _cible_fiche if _cible_fiche != null else ennemi_actuel()
	if _fiche_ennemi == null or cible == null or not is_instance_valid(cible):
		return
	var nom_ennemi: String = str(cible.get("nom"))
	if nom_ennemi.is_empty():
		nom_ennemi = "Ennemi"
	var vie_max: int = maxi(int(cible.get("pv_max")), 1)
	var vie: int = clampi(int(cible.get("pv")), 0, vie_max)
	_label_nom_ennemi.text = nom_ennemi
	_barre_vie_ennemi.max_value = vie_max
	_barre_vie_ennemi.value = vie
	_label_vie_ennemi.text = "%d / %d" % [vie, vie_max]
	_label_stats_ennemi.text = "ATTAQUE : %d\nPORTEE : %d cases\nDEPLACEMENT : %d PM" % [
		int(cible.get("degats_attaque")),
		int(cible.get("portee_attaque")),
		int(cible.get("pm_max")),
	]
	_label_etats_ennemi.text = _texte_etats_cible(cible)

func _texte_etats_cible(cible: Node) -> String:
	if cible == null or not is_instance_valid(cible):
		return "Aucun"
	var effets: Dictionary = _etats_actifs.get(cible.get_instance_id(), {})
	if effets.is_empty():
		return "Aucun"
	var lignes: Array[String] = []
	for id_texte in effets:
		var definition: Dictionary = Personnage.etats.get(int(id_texte), {})
		var nom_etat: String = str(definition.get("nom", "Etat %d" % int(id_texte)))
		var effet_actif: Dictionary = effets[id_texte]
		var piles: int = int(effet_actif.get("piles", 1))
		var duree: int = int(effet_actif.get("duree", 1))
		var duree_texte: String = "1 tour" if duree == 1 else "%d tours" % duree
		var piles_texte: String = " x%d" % piles if piles > 1 else ""
		lignes.append("%s - %s%s" % [nom_etat, duree_texte, piles_texte])
	return "\n".join(lignes)

func _positionner_fiche_ennemi() -> void:
	if _fiche_ennemi == null or not _fiche_ennemi.visible:
		return
	var taille_vue: Vector2 = get_viewport().get_visible_rect().size
	var taille_fiche: Vector2 = _fiche_ennemi.size
	if taille_fiche == Vector2.ZERO:
		taille_fiche = _fiche_ennemi.custom_minimum_size
	var souris: Vector2 = get_viewport().get_mouse_position()
	var position_fiche: Vector2 = souris + Vector2(18, 18)
	if position_fiche.x + taille_fiche.x > taille_vue.x:
		position_fiche.x = souris.x - taille_fiche.x - 18
	if position_fiche.y + taille_fiche.y > taille_vue.y:
		position_fiche.y = souris.y - taille_fiche.y - 18
	_fiche_ennemi.position = position_fiche

func _process(_delta: float) -> void:
	if _fiche_ennemi != null and _fiche_ennemi.visible:
		_positionner_fiche_ennemi()

# un ennemi détecte le joueur : sa rencontre entière rejoint les
# propositions — y compris les membres placés hors des zones de
# détection (le combat est contre un groupe, pas un voisinage)
func proposer_combat(ennemi: Node) -> void:
	if en_combat or ennemi == null or not is_instance_valid(ennemi):
		return
	if int(ennemi.get("pv")) <= 0:
		return
	if not _detecteurs.has(ennemi):
		_detecteurs.append(ennemi)
	_maj_propositions()

func annuler_proposition_combat(ennemi: Node) -> void:
	if not _detecteurs.has(ennemi):
		return
	_detecteurs.erase(ennemi)
	_maj_propositions()

# propositions = union des rencontres des ennemis qui détectent le
# joueur ; le bouton annonce l'effectif réel du combat
func _maj_propositions() -> void:
	_propositions = []
	for detecteur in _detecteurs:
		for membre in _groupe_de(detecteur):
			if int(membre.get("pv")) > 0 and not _propositions.has(membre):
				_propositions.append(membre)
	if en_combat:
		return
	if _propositions.is_empty():
		_bouton_combattre.hide()
	else:
		_bouton_combattre.text = "Combattre" if _propositions.size() == 1 else "Combattre (x%d)" % _propositions.size()
		_bouton_combattre.show()

# la rencontre d'un ennemi : lui seul si son groupe n'est pas étiqueté
# (comportement historique), tous les ennemis connus de même étiquette
# sinon
func _groupe_de(ennemi: Node) -> Array:
	var etiquette := _etiquette_de(ennemi)
	if etiquette.is_empty():
		return [ennemi]
	var membres := []
	for connu in _ennemis_connus:
		if connu == null or not is_instance_valid(connu) or int(connu.get("pv")) <= 0:
			continue
		if _etiquette_de(connu) == etiquette:
			membres.append(connu)
	return membres

func _etiquette_de(entite: Node) -> String:
	if entite == null or not is_instance_valid(entite):
		return ""
	var etiquette = entite.get("groupe")
	if etiquette == null:
		return ""
	return str(etiquette)

func _on_bouton_combattre_presse() -> void:
	var groupe := _propositions.duplicate()
	_propositions.clear()
	_bouton_combattre.hide()
	lancer_combat(groupe)

# engage un combat : contre le groupe d'ennemis donné (tableau), ou
# l'ennemi le plus proche du joueur si rien n'est fourni
func lancer_combat(groupe = null) -> void:
	if en_combat:
		return
	_bouton_combattre.hide()
	_propositions.clear()
	var ennemis: Array = []
	if groupe is Array:
		for ennemi in groupe:
			if is_instance_valid(ennemi) and int(ennemi.get("pv")) > 0 and not ennemis.has(ennemi):
				ennemis.append(ennemi)
	elif groupe is Node2D and is_instance_valid(groupe) and int(groupe.get("pv")) > 0:
		ennemis.append(groupe)
	if ennemis.is_empty():
		var proche := ennemi_proche()
		if proche == null:
			push_warning("Combat impossible : joueur ou ennemi introuvable.")
			return
		ennemis.append(proche)
	if _joueur == null:
		push_warning("Combat impossible : joueur introuvable.")
		return
	_camera_exploration = get_viewport().get_camera_2d()
	_arene = ARENE_COMBAT.new()
	_arene.index_plan = _hasard.randi_range(0, ARENE_COMBAT.PLANS.size() - 1)
	_arene.position = POSITION_ARENE
	add_child(_arene)
	var places := _arene.cases_ennemis()
	if ennemis.size() > places.size():
		_quitter_arene()
		afficher_message("Il n’y a pas assez de place dans l’arène pour cette rencontre.")
		return
	_ennemis = ennemis
	_etats_actifs.clear()
	numero_combat += 1
	en_combat = true
	en_placement = true
	_placer_dans_arene(_joueur, _arene.case_joueur())
	for i in _ennemis.size():
		var ennemi: Node2D = _ennemis[i]
		_connecter_survol_ennemi(ennemi)
		_placer_dans_arene(ennemi, places[i])
	_arene.activer_camera()
	_maj_ennemi_principal()
	_mettre_a_jour_etiquette_etats()
	_actualiser_fiche_ennemi()
	if _souris_sur_ennemi:
		_survol_ennemi()
	placement_commence.emit()
	# monde partagé : annoncer le combat contre ce groupe (lookup au
	# runtime : Reseau n'est pas chargé dans l'éditeur)
	groupe_combat = ""
	for ennemi in _ennemis:
		var etiquette := _etiquette_de(ennemi)
		if etiquette != "":
			groupe_combat = etiquette
			break
	if groupe_combat != "":
		var reseau := get_tree().root.get_node_or_null("/root/Reseau")
		if reseau != null:
			reseau.call("debut_combat_local", groupe_combat)

# duel contre un joueur distant : l'arène utilise le même plan des deux
# côtés (grilles identiques), l'adversaire est un miroir dont les
# actions nous parviennent par le réseau, et l'issue est annoncée par le
# serveur quand l'un des deux tombe
func lancer_duel(adversaire: SCRIPT_ADVERSAIRE_PVP, premier: bool) -> void:
	if en_combat or adversaire == null or not is_instance_valid(adversaire):
		return
	_bouton_combattre.hide()
	_propositions.clear()
	if _joueur == null or not is_instance_valid(_joueur):
		push_warning("Duel impossible : joueur introuvable.")
		return
	_camera_exploration = get_viewport().get_camera_2d()
	_arene = ARENE_COMBAT.new()
	_arene.index_plan = 0
	_arene.position = POSITION_ARENE
	add_child(_arene)
	pvp_actif = true
	pvp_premier = premier
	_pvp_adversaire = adversaire
	_ennemis = [adversaire]
	_etats_actifs.clear()
	numero_combat += 1
	en_combat = true
	en_placement = true
	_placer_dans_arene(_joueur, _arene.case_joueur())
	_connecter_survol_ennemi(adversaire)
	_placer_dans_arene(adversaire, _arene.cases_ennemis()[0])
	_arene.activer_camera()
	_maj_ennemi_principal()
	_mettre_a_jour_etiquette_etats()
	_actualiser_fiche_ennemi()
	placement_commence.emit()

# une action de l'adversaire distant, relayée par le serveur, rejouée
# sur notre grille : profil, déplacements, sorts résolus chez lui
# (dégâts, soins, états) et fin de son tour
func pvp_action_recue(evenement: Dictionary) -> void:
	if not pvp_actif:
		return
	var type := str(evenement.get("t", ""))
	var adversaire := _adversaire_valide()
	match type:
		"profil":
			if adversaire != null:
				adversaire.appliquer_profil(evenement.get("profil", {}))
		"deplacement":
			var sol := sol_combat()
			if adversaire != null and sol != null:
				adversaire.rejouer_trajet(evenement.get("trajet", []), sol)
		"manque":
			afficher_message("%s rate son sort." % _nom_adversaire())
		"sort":
			_rejouer_sort_distant(evenement)
		"fin_tour":
			if adversaire != null:
				adversaire.terminer_tour_distant()
	_mettre_a_jour_etiquette_etats()

func _adversaire_valide() -> SCRIPT_ADVERSAIRE_PVP:
	if _pvp_adversaire != null and is_instance_valid(_pvp_adversaire):
		return _pvp_adversaire
	return null

func _nom_adversaire() -> String:
	var adversaire := _adversaire_valide()
	if adversaire == null:
		return "L'adversaire"
	return str(adversaire.get("nom"))

# le sort a été entièrement résolu côté lanceur : on applique ici les
# conséquences sur la victime locale (nous ou notre miroir de lui)
func _rejouer_sort_distant(evenement: Dictionary) -> void:
	var cible_moi := str(evenement.get("cible", "adv")) == "adv"
	var cible: Node = _joueur if cible_moi else _adversaire_valide()
	if cible == null or not is_instance_valid(cible):
		return
	if _joueur != null and str(evenement.get("id", "")) != "":
		_joueur.call("_jouer_effet_sort", str(evenement.get("id", "")), cible)
	var soin := int(evenement.get("soin", 0))
	if soin > 0:
		if cible == _joueur:
			Personnage.soigner(soin)
			_joueur.call("_maj_affichage")
		elif cible.has_method("soigner"):
			cible.soigner(soin)
	var degats := int(evenement.get("degats", 0))
	if degats > 0 and cible == _joueur:
		_joueur.recevoir_degats(degats)   # gère aussi notre mort locale
	var etats: Array = evenement.get("etats", [])
	if not etats.is_empty():
		pvp_appliquer_etats(cible, etats)
	var nom_sort := str(evenement.get("nom", "un sort"))
	afficher_message("%s lance %s." % [_nom_adversaire(), nom_sort])

# états appliqués chez le lanceur, rejoués ici à l'identique (pas de
# nouveaux jets de dés : les valeurs font foi)
func pvp_appliquer_etats(cible: Node, etats: Array) -> void:
	if cible == null or not is_instance_valid(cible) or etats.is_empty():
		return
	var par_cible: Dictionary = _etats_actifs.get(cible.get_instance_id(), {})
	for etat in etats:
		var id_etat := int(etat.get("id", 0))
		if id_etat <= 0:
			continue
		par_cible[str(id_etat)] = {
			"duree": maxi(int(etat.get("duree", 1)), 1),
			"valeur": float(etat.get("valeur", 0.0)),
			"piles": maxi(int(etat.get("piles", 1)), 1),
			"frais": cible == _joueur,
		}
		if id_etat == 8 or id_etat == 9:
			_deplacer_par_etat(cible, int(float(etat.get("valeur", 1.0))), id_etat == 8)
	_etats_actifs[cible.get_instance_id()] = par_cible

# un ennemi du groupe est vaincu : le combat continue tant qu'il en
# reste un debout
func ennemi_vaincu(ennemi: Node) -> void:
	_ennemis.erase(ennemi)
	_ennemis_connus.erase(ennemi)
	_detecteurs.erase(ennemi)
	if ennemi == _cible_selectionnee:
		_cible_selectionnee = null
	if ennemi == _ennemi:
		_maj_ennemi_principal()
	if _propositions.has(ennemi):
		_propositions.erase(ennemi)
	if not en_combat:
		_maj_propositions()
	if en_combat and ennemis_actifs().is_empty():
		terminer_combat(true)

func _placer_dans_arene(entite: Node2D, case: Vector2i) -> void:
	_positions_exploration[entite] = entite.global_position
	var sol := sol_combat()
	entite.global_position = sol.to_global(sol.map_to_local(case))

func _quitter_arene() -> void:
	for entite in _positions_exploration:
		if is_instance_valid(entite):
			entite.arreter_deplacement_combat()
			entite.global_position = _positions_exploration[entite]
	_positions_exploration.clear()
	if is_instance_valid(_camera_exploration):
		_camera_exploration.make_current()
		_camera_exploration.reset_smoothing()
		_camera_exploration.force_update_scroll()
	_camera_exploration = null
	_arene.hide()
	_arene.queue_free()
	_arene = null

func valider_placement() -> void:
	if not en_combat or not en_placement:
		return
	en_placement = false
	combat_commence.emit()

func terminer_combat(victoire: bool) -> void:
	if not en_combat:
		return
	en_combat = false
	en_placement = false
	if pvp_actif:
		# notre défaite est annoncée au serveur, qui préviendra le
		# vainqueur ; une victoire locale n'est que l'echo du réseau
		if not victoire:
			var reseau_defaite := get_tree().root.get_node_or_null("/root/Reseau")
			if reseau_defaite != null:
				reseau_defaite.call("declarer_defaite_duel")
		pvp_actif = false
		if is_instance_valid(_pvp_adversaire):
			_pvp_adversaire.queue_free()
		_pvp_adversaire = null
	if groupe_combat != "":
		var reseau := get_tree().root.get_node_or_null("/root/Reseau")
		if reseau != null:
			reseau.call("fin_combat_local", groupe_combat)
		groupe_combat = ""
	_quitter_arene()
	_etats_actifs.clear()
	_ennemis.clear()
	_propositions.clear()
	_detecteurs.clear()
	_cible_selectionnee = null
	_bouton_combattre.hide()
	_mettre_a_jour_etiquette_etats()
	if _fiche_ennemi != null:
		_fiche_ennemi.hide()
	ressources_joueur_modifiees.emit(0, 0, 0, 0)
	combat_termine.emit(victoire)

func mettre_a_jour_stats(_vie: int, _vie_max: int, pa: int, pa_max: int, pm: int, pm_max: int) -> void:
	ressources_joueur_modifiees.emit(pa, pa_max, pm, pm_max)
	_actualiser_fiche_ennemi()
	_mettre_a_jour_etiquette_etats()

func afficher_message(message: String) -> void:
	var interface_hud: Node = get_tree().current_scene.find_child("HUD", true, false)
	if interface_hud != null and interface_hud.has_method("afficher_message_sort"):
		interface_hud.call("afficher_message_sort", message)

func effacer_message() -> void:
	var interface_hud: Node = get_tree().current_scene.find_child("HUD", true, false)
	if interface_hud != null and interface_hud.has_method("afficher_message_sort"):
		interface_hud.call("afficher_message_sort", "Sorts au clavier | clic : cible ou deplacement")

func demander_sort(id_sort: String) -> void:
	if en_combat and not en_placement:
		sort_demandee.emit(id_sort)

func demander_validation_placement() -> void:
	if en_combat and en_placement:
		placement_valide.emit()

func demander_fin_tour() -> void:
	if en_combat and not en_placement:
		fin_tour_demandee.emit()

func est_allie(sort: Dictionary) -> bool:
	return str(sort.get("type", "")) in ["buff", "defense", "heal", "healing"]

func appliquer_effets_sort(cible: Node, sort: Dictionary) -> Array:
	var appliques: Array = []
	if cible == null or not is_instance_valid(cible):
		return appliques
	var effets: Array = sort.get("effets", [])
	for effet in effets:
		if _hasard.randf() > float(effet.get("chance", 1.0)):
			continue
		var id_etat := int(effet.get("id", 0))
		if id_etat <= 0:
			continue
		var etat: Dictionary = Personnage.etats.get(id_etat, {})
		var par_cible: Dictionary = _etats_actifs.get(cible.get_instance_id(), {})
		var cle := str(id_etat)
		var existant: Dictionary = par_cible.get(cle, {})
		var piles := int(existant.get("piles", 0))
		if piles == 0:
			piles = 1
		elif bool(etat.get("empilable", false)):
			piles = mini(piles + 1, int(etat.get("max_stacks", 1)))
		par_cible[cle] = {"duree": maxi(int(effet.get("duree", 1)), 1), "valeur": float(effet.get("valeur", 0.0)), "piles": piles, "frais": cible == _joueur}
		_etats_actifs[cible.get_instance_id()] = par_cible
		appliques.append({"id": id_etat,
			"duree": maxi(int(effet.get("duree", 1)), 1),
			"valeur": float(effet.get("valeur", 0.0)),
			"piles": piles})
		if id_etat == 8 or id_etat == 9:
			_deplacer_par_etat(cible, int(effet.get("valeur", 1.0)), id_etat == 8)
	_mettre_a_jour_etiquette_etats()
	return appliques

func a_etat(cible: Node, id_etat: int) -> bool:
	if cible == null or not is_instance_valid(cible):
		return false
	return _etats_actifs.get(cible.get_instance_id(), {}).has(str(id_etat))

func preparer_tour(cible: Node) -> bool:
	if cible == null or not is_instance_valid(cible):
		return false
	var par_cible: Dictionary = _etats_actifs.get(cible.get_instance_id(), {})
	var bloque := par_cible.has("1") or par_cible.has("4")
	for id_texte in par_cible:
		var id_etat := int(id_texte)
		var effet: Dictionary = par_cible[id_texte]
		var montant := int(round(float(effet.get("valeur", 0.0)) * float(effet.get("piles", 1))))
		if id_etat == 2 or id_etat == 3:
			_recevoir_degats(cible, maxi(montant, 1))
		elif id_etat == 12:
			_soigner_cible(cible, _soin_regeneration(cible, float(effet.get("valeur", 0.0))))
		if not is_instance_valid(cible):
			return true
	return bloque

func terminer_tour(cible: Node) -> void:
	if cible == null or not is_instance_valid(cible):
		return
	var id_cible := cible.get_instance_id()
	var par_cible: Dictionary = _etats_actifs.get(id_cible, {})
	for cle in par_cible.keys():
		var effet: Dictionary = par_cible[cle]
		if bool(effet.get("frais", false)):
			effet["frais"] = false
		else:
			effet["duree"] = int(effet.get("duree", 1)) - 1
			if int(effet["duree"]) <= 0:
				par_cible.erase(cle)
	if par_cible.is_empty():
		_etats_actifs.erase(id_cible)
	else:
		_etats_actifs[id_cible] = par_cible
	_mettre_a_jour_etiquette_etats()

func _mettre_a_jour_etiquette_etats() -> void:
	_actualiser_fiche_ennemi()
	var interface_hud: Node = get_tree().current_scene.find_child("HUD", true, false)
	if interface_hud != null and interface_hud.has_method("maj_etats_joueur"):
		interface_hud.call("maj_etats_joueur", _texte_etats_cible(_joueur))

func etats_joueur_texte() -> String:
	return _texte_etats_cible(_joueur)

func calculer_degats(lanceur: Node, cible: Node, degats_base: int, type_sort: String = "", portee_sort: int = 1) -> int:
	var degats := float(maxi(degats_base, 0))
	if lanceur == _joueur:
		degats += float(Personnage.attaque)
		degats += Personnage.bonus_degats_sort(type_sort, portee_sort)
	if a_etat(lanceur, 13):
		degats *= 1.0 + float(_valeur_etat(lanceur, 13)) * _piles_etat(lanceur, 13)
	if a_etat(lanceur, 16) and _hasard.randf() < float(_valeur_etat(lanceur, 16)):
		degats *= 1.5
	if a_etat(cible, 10):
		return 0
	if a_etat(cible, 11):
		degats *= 1.0 - float(_valeur_etat(cible, 11))
	if a_etat(cible, 14):
		degats *= 1.0 - float(_valeur_etat(cible, 14))
	if a_etat(cible, 3):
		degats *= 1.2
	if a_etat(cible, 17):
		degats *= 1.0 + float(_valeur_etat(cible, 17)) * _piles_etat(cible, 17)
	if cible == _joueur:
		degats -= float(Personnage.defense)
	elif _pvp_adversaire != null and is_instance_valid(_pvp_adversaire) and cible == _pvp_adversaire:
		degats -= float(_pvp_adversaire.defense_pvp)
	return maxi(int(round(degats)), 0)

func precision_reussie(lanceur: Node) -> bool:
	var precision := 0.9
	if lanceur == _joueur:
		precision += Personnage.bonus_precision()
	if a_etat(lanceur, 6):
		precision *= maxf(0.0, 1.0 - float(_valeur_etat(lanceur, 6)) * float(_piles_etat(lanceur, 6)))
	if a_etat(lanceur, 15):
		precision += float(_valeur_etat(lanceur, 15))
	return _hasard.randf() <= clampf(precision, 0.1, 1.0)

func sort_autorise(cible: Node) -> bool:
	return not a_etat(cible, 7)

func points_mouvement(cible: Node, points: int) -> int:
	return maxi(points - (1 if a_etat(cible, 5) else 0), 1)

func _valeur_etat(cible: Node, id_etat: int) -> float:
	return float(_etats_actifs.get(cible.get_instance_id(), {}).get(str(id_etat), {}).get("valeur", 0.0))

func _piles_etat(cible: Node, id_etat: int) -> int:
	return int(_etats_actifs.get(cible.get_instance_id(), {}).get(str(id_etat), {}).get("piles", 1))

func _recevoir_degats(cible: Node, montant: int) -> void:
	if cible.has_method("recevoir_degats"):
		cible.recevoir_degats(montant)

func _soigner_cible(cible: Node, montant: int) -> void:
	if cible == _joueur:
		Personnage.soigner(montant)
		_joueur.call("_maj_affichage")
	elif cible.has_method("soigner"):
		cible.soigner(montant)

func _soin_regeneration(cible: Node, proportion: float) -> int:
	if cible == _joueur:
		return maxi(int(round(float(Personnage.vie_max) * proportion)), 1)
	return maxi(int(round(float(cible.get("pv_max")) * proportion)), 1)

func _deplacer_par_etat(cible: Node, nombre: int, repousser: bool) -> void:
	var entite := cible as Node2D
	if entite == null:
		return
	var sol := sol_combat()
	if sol == null or nombre <= 0:
		return
	var lanceur: Node2D = null
	if cible == _joueur:
		lanceur = ennemi_proche() as Node2D
	else:
		lanceur = _joueur as Node2D
	if lanceur == null or not is_instance_valid(lanceur):
		return
	var depart := sol.local_to_map(sol.to_local(entite.global_position))
	var origine := sol.local_to_map(sol.to_local(lanceur.global_position))
	var delta := depart - origine
	var axe := Vector2i.RIGHT if absi(delta.x) >= absi(delta.y) else Vector2i.DOWN
	if (absi(delta.x) >= absi(delta.y) and delta.x < 0) or (absi(delta.x) < absi(delta.y) and delta.y < 0):
		axe = -axe
	if not repousser:
		axe = -axe
	var destination := depart
	for _i in range(nombre):
		var suivante := destination + axe
		if sol.get_cell_source_id(suivante) == -1 or not dans_zone_combat(suivante):
			break
		var occupee_par_groupe := false
		for ennemi in ennemis_actifs():
			if suivante == sol.local_to_map(sol.to_local((ennemi as Node2D).global_position)):
				occupee_par_groupe = true
				break
		if occupee_par_groupe or (cible != _joueur and suivante == sol.local_to_map(sol.to_local((_joueur as Node2D).global_position))):
			break
		destination = suivante
	entite.global_position = sol.to_global(sol.map_to_local(destination))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F:
			lancer_combat()
		elif event.keycode == KEY_G:
			terminer_combat(false)
