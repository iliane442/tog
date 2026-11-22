extends CanvasLayer

const SCRIPT_PARAMETRES_TOUCHES := preload("res://scripts/ui/parametres_touches.gd")
const ICONES_SORTS := preload("res://scripts/ui/icones_sorts.gd")

@onready var panneau_stats: PanelContainer = $PanneauStats
@onready var panneau_sorts: PanelContainer = $BarreDeSorts
@onready var barre_sorts: HBoxContainer = $BarreDeSorts/Colonne/Emplacements
@onready var barre_vie: ProgressBar = $PanneauStats/Colonne/LigneVie/Vie
@onready var ligne_bouclier: HBoxContainer = $PanneauStats/Colonne/LigneBouclier
@onready var barre_bouclier: ProgressBar = $PanneauStats/Colonne/LigneBouclier/Bouclier
@onready var label_bouclier: Label = $PanneauStats/Colonne/LigneBouclier/BouclierTexte
@onready var barre_xp: ProgressBar = $PanneauStats/Colonne/LigneXP/XP
@onready var ligne_xp: HBoxContainer = $PanneauStats/Colonne/LigneXP
@onready var label_nom: Label = $PanneauStats/Colonne/Nom
@onready var label_vie: Label = $PanneauStats/Colonne/LigneVie/VieTexte
@onready var label_xp: Label = $PanneauStats/Colonne/LigneXP/XPTexte
@onready var ligne_combat: HBoxContainer = $PanneauStats/Colonne/LigneCombat
@onready var label_pa: Label = $PanneauStats/Colonne/LigneCombat/PA
@onready var label_pm: Label = $PanneauStats/Colonne/LigneCombat/PM
@onready var label_temps_tour: Label = $PanneauStats/Colonne/LigneCombat/Timer
@onready var label_etats_joueur: Label = $PanneauStats/Colonne/EtatsJoueur
@onready var boutons_combat: HBoxContainer = $PanneauStats/Colonne/BoutonsCombat
@onready var bouton_fin_tour: Button = $PanneauStats/Colonne/BoutonsCombat/FinTour
@onready var bouton_fuir: Button = $PanneauStats/Colonne/BoutonsCombat/Fuir
@onready var label_berry: Label = $BerryPanel/BerryRow/Berry
@onready var label_action: Label = $BarreDeSorts/Colonne/Entete/Action
@onready var label_quete: Label = $QuestPanel/Marges/Colonne/QuestName
@onready var label_progression_quete: Label = $QuestPanel/Marges/Colonne/QuestProgress
@onready var panneau_quete: PanelContainer = $QuestPanel
@onready var panneau_berry: PanelContainer = $BerryPanel
@onready var cadre_du_monde: NinePatchRect = $CadreDuMonde
@onready var navigation_haute: HBoxContainer = $NavTop
@onready var bouton_touches: Button = $NavTop/Touches

var _joueur: Node
var _gestionnaire_combat: Node
var _menu: Node
var _parametres_touches: CanvasLayer
var _tween_vie: Tween
var _tween_xp: Tween
var _tween_sorts: Tween

# barre d'objets (consommables) : même place que la barre de sorts, une
# seule des deux s'affiche — le bouton ⇄ des en-têtes intervertit
var panneau_objets: PanelContainer
var barre_objets_emplacements: HBoxContainer
var label_action_objets: Label
var bouton_bascule_sorts: Button
var bouton_bascule_objets: Button
var barre_objets_active := false
var _barres_visibles := true

const ICONES_OBJETS_PAR_TYPE := {
	"consumable": "res://addons/pixel_ui_fantasy/icons/potion_red.png",
}
const ICONE_OBJET_DEFAUT := "res://addons/pixel_ui_fantasy/icons/chest.png"

func _ready() -> void:
	_joueur = get_tree().current_scene.find_child("player", true, false)
	_gestionnaire_combat = get_tree().current_scene.get_node_or_null("CombatManager")
	if _gestionnaire_combat != null:
		_gestionnaire_combat.placement_commence.connect(_on_placement_commence)
		_gestionnaire_combat.combat_commence.connect(_on_combat_commence)
		_gestionnaire_combat.combat_termine.connect(_afficher_barre_sorts)
		_gestionnaire_combat.ressources_joueur_modifiees.connect(maj_ressources_combat)
		_gestionnaire_combat.tour_actif_change.connect(_maj_bouton_fin_tour)
		bouton_fin_tour.pressed.connect(_on_bouton_fin_tour_presse)
		bouton_fuir.pressed.connect(_on_bouton_fuir_presse)
	_menu = get_tree().current_scene.get_node_or_null("MenuUI")
	if _menu != null:
		_menu.get_node("Fenetre").visibility_changed.connect(_actualiser_visibilite_menu)
		_connecter_navigation(_menu)
	bouton_touches.pressed.connect(_basculer_parametres_touches)
	for index in range(barre_sorts.get_child_count()):
		var bouton: Button = barre_sorts.get_child(index) as Button
		bouton.pressed.connect(_on_emplacement_sort_clique.bind(index))
		bouton.mouse_entered.connect(_animer_case.bind(bouton, Vector2(1.08, 1.08)))
		bouton.mouse_exited.connect(_animer_case.bind(bouton, Vector2.ONE))
	Personnage.caracteristiques_modifiees.connect(maj)
	Personnage.barre_sorts_modifiee.connect(maj_barre_sorts)
	Personnage.barre_objets_modifiee.connect(maj_barre_objets)
	Inventaire.inventaire_modifie.connect(maj_barre_objets, CONNECT_DEFERRED)
	Touches.touches_modifiees.connect(maj_barre_sorts)
	Touches.touches_modifiees.connect(maj_barre_objets)
	_construire_barre_objets()
	QuestManager.quete_acceptee.connect(maj_quete)
	QuestManager.quete_progressee.connect(maj_quete)
	QuestManager.quete_abandonnee.connect(maj_quete)
	QuestManager.quete_terminee.connect(maj_quete)
	maj()
	maj_barre_sorts()
	maj_quete()
	if _gestionnaire_combat != null and _gestionnaire_combat.en_combat:
		if _gestionnaire_combat.en_placement:
			_on_placement_commence()
		else:
			_on_combat_commence()
			# le combat est déjà en cours : reprendre l'état du bouton
			# de fin de tour selon le combattant en cours
			if _gestionnaire_combat.has_method("combattant_actif"):
				_maj_bouton_fin_tour(_gestionnaire_combat.combattant_actif())

func _connecter_navigation(menu: Node) -> void:
	var sections: Dictionary = {
		"Personnage": "personnage",
		"Sorts": "sorts",
		"Quetes": "quetes",
		"Inventaire": "inventaire",
		"Wiki": "wiki",
		"Metiers": "metiers",
		"Hotel": "hotel",
		"Equipage": "equipage",
	}
	for nom_bouton: String in sections:
		var bouton: Button = $NavTop.get_node(nom_bouton) as Button
		bouton.pressed.connect(Callable(menu, "ouvrir").bind(str(sections[nom_bouton])))
	$NavTop/Menu.pressed.connect(_ouvrir_menu_principal.bind(menu))

func _ouvrir_menu_principal(menu: Node) -> void:
	var fenetre_menu: Control = menu.get_node("Fenetre") as Control
	if fenetre_menu.visible:
		menu.call("fermer")
	else:
		menu.call("ouvrir")

func maj() -> void:
	barre_vie.max_value = maxi(Personnage.vie_max, 1)
	barre_xp.max_value = maxi(Personnage.xp_prochain_niveau(), 1)
	_animer_valeur(barre_vie, float(Personnage.vie), true)
	_animer_valeur(barre_xp, float(Personnage.xp), false)
	# jauge de bouclier au-dessus des PV, visible seulement quand il
	# reste des points ; elle est cotée sur les PV max pour lire
	# d'un coup d'œil le poids du bouclier face à la vie
	var points_bouclier := maxi(Personnage.bouclier, 0)
	ligne_bouclier.visible = points_bouclier > 0
	if points_bouclier > 0:
		barre_bouclier.max_value = maxi(Personnage.vie_max, 1)
		barre_bouclier.value = mini(points_bouclier, maxi(Personnage.vie_max, 1))
		label_bouclier.text = "%d pts" % points_bouclier
	label_nom.text = "%s - Niv. %d" % [Personnage.nom, Personnage.niveau]
	label_vie.text = "%d / %d" % [Personnage.vie, Personnage.vie_max]
	label_xp.text = "%d / %d XP" % [Personnage.xp, Personnage.xp_prochain_niveau()]
	label_berry.text = "%s Berry" % _formater_nombre(Personnage.berry)

func maj_quete(_quest_id: String = "") -> void:
	var ids_actifs: Array = QuestManager.quetes_actives.keys()
	if ids_actifs.is_empty():
		label_quete.text = "Aucune quête en cours"
		label_progression_quete.text = "Ouvre le carnet pour consulter tes quêtes."
		return
	var id_quete: String = str(ids_actifs[0])
	var quete: Dictionary = QuestManager.quetes.get(id_quete, {})
	var objectif: int = maxi(int(quete.get("objectif", 1)), 1)
	var progression: int = int(QuestManager.quetes_actives.get(id_quete, 0))
	label_quete.text = str(quete.get("titre", "Quête"))
	label_progression_quete.text = "%d / %d - %s" % [progression, objectif, str(quete.get("description", ""))]

func _animer_valeur(barre: ProgressBar, valeur: float, vie: bool) -> void:
	var animation: Tween = _tween_vie if vie else _tween_xp
	if animation != null and animation.is_running():
		animation.kill()
	animation = create_tween()
	animation.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	animation.tween_property(barre, "value", valeur, 0.28)
	if vie:
		_tween_vie = animation
	else:
		_tween_xp = animation

func _formater_nombre(nombre: int) -> String:
	var texte: String = str(nombre)
	var resultat: String = ""
	for index in range(texte.length()):
		if index > 0 and (texte.length() - index) % 3 == 0:
			resultat += " "
		resultat += texte.substr(index, 1)
	return resultat

func maj_barre_sorts() -> void:
	for index in range(barre_sorts.get_child_count()):
		var bouton: Button = barre_sorts.get_child(index) as Button
		bouton.get_node("Badge").text = _raccourci(index)
		var id_sort: String = Personnage.barre_sorts[index] if index < Personnage.barre_sorts.size() else ""
		if id_sort != "" and Personnage.sorts.has(id_sort):
			var sort: Dictionary = Personnage.sorts[id_sort]
			bouton.icon = ICONES_SORTS.pour_sort(id_sort, str(sort.get("type", "")))
			bouton.disabled = false
			# sort en recharge : grisé, la durée restante rend le
			# bouton muet mais visible
			var recharge := 0
			if _joueur != null and is_instance_valid(_joueur) and _joueur.has_method("recharge_restante_sort"):
				recharge = int(_joueur.call("recharge_restante_sort", id_sort))
			bouton.modulate = Color(0.45, 0.45, 0.5) if recharge > 0 else Color.WHITE
			# la caractéristique qui renforce ce sort suit son type :
			# Force pour toutes les attaques, Intelligence pour les soins
			var stat_boost: String = Personnage.stat_booster_sort(sort)
			var texte_boost := ""
			if stat_boost != "":
				texte_boost = "Boost : %s (actuel : +%d)\n" % [stat_boost, roundi(Personnage.bonus_sort_actuel(sort))]
			var texte_recharge := ""
			if recharge > 0:
				texte_recharge = "En recharge : %d tour(s)\n" % recharge
			bouton.tooltip_text = "%s\n%s\n%s%sTouche %s" % [
				str(sort.get("nom", "Sort")), str(sort.get("description", "")),
				texte_boost, texte_recharge, _raccourci(index)]
		else:
			bouton.icon = null
			bouton.disabled = true
			bouton.modulate = Color.WHITE
			bouton.tooltip_text = "Ouvre Menu > Sorts pour équiper un sort."

func _animer_case(bouton: Control, echelle: Vector2) -> void:
	var tween: Tween = bouton.create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(bouton, "scale", echelle, 0.12)

func _raccourci(index: int) -> String:
	return Touches.libelle_action("sort_%d" % (index + 1))

func _on_emplacement_sort_clique(index: int) -> void:
	if index < Personnage.barre_sorts.size():
		_utiliser_sort(Personnage.barre_sorts[index])

func _utiliser_sort(id_sort: String) -> void:
	if _joueur == null or not is_instance_valid(_joueur):
		return
	if _gestionnaire_combat != null and _gestionnaire_combat.en_combat:
		if _gestionnaire_combat.en_placement:
			afficher_message_sort("Valide d'abord ton placement pour utiliser un sort.")
			return
		_gestionnaire_combat.demander_sort(id_sort)
		return
	if _joueur.has_method("utiliser_sort_hors_combat"):
		_joueur.call("utiliser_sort_hors_combat", id_sort)

# le même bouton sert aux deux phases : valider son placement
# pendant la phase de placement, finir son tour pendant le combat
func _on_bouton_fin_tour_presse() -> void:
	if _gestionnaire_combat == null:
		return
	if _gestionnaire_combat.en_placement:
		_gestionnaire_combat.demander_validation_placement()
	elif _gestionnaire_combat.en_combat:
		_gestionnaire_combat.demander_fin_tour()

func _on_bouton_fuir_presse() -> void:
	if _gestionnaire_combat == null:
		return
	if _gestionnaire_combat.en_combat:
		_gestionnaire_combat.demander_fuite()

func afficher_message_sort(message: String) -> void:
	_label_action_actif().text = message

# le bouton de fin de tour ne sert que pendant le tour du joueur
# local : pendant le placement il reste affiché (il valide le
# placement), pendant les tours des ennemis ou celui de l'adversaire
# distant il disparaît
func _maj_bouton_fin_tour(combattant: Node2D) -> void:
	if _gestionnaire_combat == null or _gestionnaire_combat.en_placement:
		return
	# le bouton de fuite suit le même rythme : jamais pendant le tour
	# d'un ennemi ou celui de l'adversaire distant
	var mon_tour: bool = _gestionnaire_combat.en_combat and combattant != null and combattant == _joueur
	bouton_fin_tour.visible = mon_tour
	bouton_fuir.visible = mon_tour

func _on_placement_commence() -> void:
	_animer_visibilite_sorts(false)
	_synchroniser_etats_joueur()
	_afficher_stats_combat(true)
	bouton_fin_tour.text = "Placement OK"
	bouton_fin_tour.show()
	bouton_fuir.show()
	_label_action_actif().text = "Place-toi, puis valide le placement : %s" % [
		Touches.libelle_action("fin_tour")]

func _on_combat_commence() -> void:
	maj_barre_sorts()
	maj_barre_objets()
	_synchroniser_etats_joueur()
	_afficher_stats_combat(true)
	bouton_fin_tour.text = "Fin du tour"
	bouton_fin_tour.show()
	bouton_fuir.show()
	_label_action_actif().text = "Sorts : %s | cible : %s / %s | fin du tour : %s | fuir : %s" % [
		Touches.libelle_action("sort_1"),
		Touches.libelle_action("cible_suivante"),
		Touches.libelle_action("cible_precedente"),
		Touches.libelle_action("fin_tour"),
		Touches.libelle_action("fuir"),
	]
	_animer_visibilite_sorts(true)

func maj_ressources_combat(pa: int, pa_max: int, pm: int, pm_max: int) -> void:
	label_pa.text = "PA %d / %d" % [pa, pa_max]
	label_pm.text = "PM %d / %d" % [pm, pm_max]
	ligne_combat.visible = _gestionnaire_combat != null and _gestionnaire_combat.en_combat
	# le joueur vient d'agir ou de reprendre son tour : les recharges
	# de sorts ont pu bouger, la barre suit
	maj_barre_sorts()

# compte à rebours du tour du joueur : effacé quand ce n'est pas son
# tour, rouge pendant les cinq dernières secondes
func maj_temps_tour(secondes: int) -> void:
	if secondes < 0:
		label_temps_tour.text = ""
		label_temps_tour.remove_theme_color_override("font_color")
		return
	label_temps_tour.text = "%d s" % secondes
	if secondes <= 5:
		label_temps_tour.add_theme_color_override("font_color", Color("#e53935"))
	else:
		label_temps_tour.remove_theme_color_override("font_color")

func maj_etats_joueur(texte: String) -> void:
	if not is_node_ready():
		call_deferred("maj_etats_joueur", texte)
		return
	label_etats_joueur.text = "ETATS : Aucun" if texte == "Aucun" else "ETATS SUBIS\n" + texte
	var nombre_lignes: int = 1
	if texte != "Aucun":
		nombre_lignes = 1
		for ligne_etat: String in texte.split("\n"):
			nombre_lignes += maxi(int(ceilf(float(ligne_etat.length()) / 30.0)), 1)
	var hauteur_etats: float = maxf(54.0, float(nombre_lignes * 20))
	label_etats_joueur.custom_minimum_size.y = hauteur_etats
	if _gestionnaire_combat != null and _gestionnaire_combat.en_combat:
		panneau_stats.offset_top = -234.0 - hauteur_etats

func _synchroniser_etats_joueur() -> void:
	if _gestionnaire_combat != null and _gestionnaire_combat.has_method("etats_joueur_texte"):
		maj_etats_joueur(str(_gestionnaire_combat.call("etats_joueur_texte")))

func _afficher_stats_combat(actif: bool) -> void:
	ligne_combat.visible = actif
	label_etats_joueur.visible = actif
	boutons_combat.visible = actif
	ligne_xp.visible = not actif
	panneau_stats.offset_top = -234.0 - label_etats_joueur.custom_minimum_size.y if actif else -190.0

func _actualiser_visibilite_menu() -> void:
	if _menu.get_node("Fenetre").visible:
		_masquer_hud_menu()
	else:
		_retour_menu()

func _masquer_hud_menu() -> void:
	cadre_du_monde.hide()
	_animer_visibilite_sorts(false)
	panneau_stats.hide()
	panneau_quete.hide()
	panneau_berry.hide()
	navigation_haute.hide()

func _afficher_barre_sorts(_victoire: bool) -> void:
	_afficher_stats_combat(false)
	if _menu != null and bool((_menu.get_node("Fenetre") as Control).visible):
		return
	maj_barre_sorts()
	maj_barre_objets()
	_label_action_actif().text = "Touches 1-0 - clic pour utiliser"
	_animer_visibilite_sorts(true)

func _retour_menu() -> void:
	cadre_du_monde.show()
	panneau_stats.show()
	panneau_quete.show()
	panneau_berry.show()
	navigation_haute.show()
	if _gestionnaire_combat != null and _gestionnaire_combat.en_combat:
		if _gestionnaire_combat.en_placement:
			_on_placement_commence()
		else:
			_on_combat_commence()
			# le combat est déjà en cours : reprendre l'état du bouton
			# de fin de tour selon le combattant en cours
			if _gestionnaire_combat.has_method("combattant_actif"):
				_maj_bouton_fin_tour(_gestionnaire_combat.combattant_actif())
	else:
		_afficher_stats_combat(false)
		_animer_visibilite_sorts(true)

# ouvre/ferme le panneau de réassignation des touches
func _basculer_parametres_touches() -> void:
	if _parametres_touches != null and is_instance_valid(_parametres_touches):
		_parametres_touches.queue_free()
		_parametres_touches = null
		return
	_parametres_touches = SCRIPT_PARAMETRES_TOUCHES.new()
	_parametres_touches.theme_panneau = panneau_sorts.theme
	_parametres_touches.fermee.connect(_on_parametres_touches_ferme)
	add_child(_parametres_touches)

func _on_parametres_touches_ferme() -> void:
	_parametres_touches = null

# anime la barre active (sorts ou objets selon la bascule) ; l'autre
# barre reste cachée : elles partagent la même place, en bas de l'écran
func _animer_visibilite_sorts(afficher: bool) -> void:
	_barres_visibles = afficher
	_appliquer_visibilite_barres()

func _appliquer_visibilite_barres() -> void:
	if panneau_objets == null:
		return
	var actif: PanelContainer = panneau_objets if barre_objets_active else panneau_sorts
	var inactif: PanelContainer = panneau_sorts if barre_objets_active else panneau_objets
	inactif.hide()
	if _tween_sorts != null and _tween_sorts.is_running():
		_tween_sorts.kill()
	if _barres_visibles:
		actif.show()
		actif.modulate.a = 0.0
		actif.scale = Vector2(0.96, 0.96)
	_tween_sorts = create_tween().set_parallel(true)
	_tween_sorts.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween_sorts.tween_property(actif, "modulate:a", 1.0 if _barres_visibles else 0.0, 0.18)
	_tween_sorts.tween_property(actif, "scale", Vector2.ONE if _barres_visibles else Vector2(0.96, 0.96), 0.18)
	if not _barres_visibles:
		_tween_sorts.finished.connect(actif.hide)

# intervertit la barre du bas : sorts ou objets
func basculer_barres_bas() -> void:
	barre_objets_active = not barre_objets_active
	maj_barre_sorts()
	maj_barre_objets()
	_appliquer_visibilite_barres()

# construit la barre d'objets en miroir de la barre de sorts : mêmes
# ancrages bas de l'écran, dix emplacements avec le même badge de
# touche, et le bouton ⇄ dans l'en-tête des deux barres
func _construire_barre_objets() -> void:
	panneau_objets = PanelContainer.new()
	panneau_objets.name = "BarreDObjets"
	panneau_objets.theme = panneau_sorts.theme
	panneau_objets.theme_type_variation = panneau_sorts.theme_type_variation
	panneau_objets.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panneau_objets.add_theme_stylebox_override("panel", panneau_sorts.get_theme_stylebox("panel"))
	# même place que la barre de sorts : ancres et marges identiques
	for ancre in ["anchor_left", "anchor_right", "anchor_top", "anchor_bottom",
			"offset_left", "offset_right", "offset_top", "offset_bottom"]:
		panneau_objets.set(ancre, panneau_sorts.get(ancre))
	add_child(panneau_objets)
	var colonne := VBoxContainer.new()
	colonne.add_theme_constant_override("separation", 2)
	panneau_objets.add_child(colonne)
	var entete := HBoxContainer.new()
	colonne.add_child(entete)
	var titre := Label.new()
	titre.theme_type_variation = "Ribbon"
	titre.add_theme_font_size_override("font_size", 18)
	titre.text = "BARRE D'OBJETS"
	entete.add_child(titre)
	bouton_bascule_objets = Button.new()
	bouton_bascule_objets.text = "⇄ Sorts"
	bouton_bascule_objets.tooltip_text = "Intervertir la barre d'objets et la barre de sorts."
	bouton_bascule_objets.pressed.connect(basculer_barres_bas)
	entete.add_child(bouton_bascule_objets)
	label_action_objets = Label.new()
	label_action_objets.text = "Touches 1-0 - clic pour utiliser"
	label_action_objets.add_theme_font_size_override("font_size", 18)
	label_action_objets.add_theme_color_override("font_color", label_action.get_theme_color("font_color"))
	label_action_objets.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label_action_objets.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label_action_objets.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	entete.add_child(label_action_objets)
	barre_objets_emplacements = HBoxContainer.new()
	barre_objets_emplacements.alignment = BoxContainer.ALIGNMENT_CENTER
	barre_objets_emplacements.add_theme_constant_override("separation", 5)
	colonne.add_child(barre_objets_emplacements)
	for index in range(Personnage.TAILLE_BARRE_OBJETS):
		var bouton := Button.new()
		bouton.custom_minimum_size = Vector2(58, 58)
		bouton.expand_icon = true
		bouton.icon_alignment = 1
		bouton.tooltip_text = "Objet %d" % (index + 1)
		bouton.disabled = true
		bouton.pressed.connect(_on_emplacement_objet_clique.bind(index))
		var modele := barre_sorts.get_child(index) as Button
		bouton.theme_type_variation = modele.theme_type_variation
		for etat in ["normal", "hover", "pressed", "disabled"]:
			bouton.add_theme_stylebox_override(etat, modele.get_theme_stylebox(etat))
		var badge := Label.new()
		badge.name = "Badge"
		badge.label_settings = modele.get_node("Badge").label_settings
		badge.text = str((index + 1) % 10)
		badge.offset_left = 2.0
		badge.offset_top = 0.0
		badge.offset_right = 26.0
		badge.offset_bottom = 24.0
		badge.add_theme_font_size_override("font_size", 15)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bouton.add_child(badge)
		barre_objets_emplacements.add_child(bouton)
	# bouton ⇄ dans l'en-tête de la barre de sorts, entre titre et action
	var entete_sorts := panneau_sorts.get_node("Colonne/Entete") as HBoxContainer
	bouton_bascule_sorts = Button.new()
	bouton_bascule_sorts.text = "⇄ Objets"
	bouton_bascule_sorts.tooltip_text = "Intervertir la barre de sorts et la barre d'objets."
	bouton_bascule_sorts.pressed.connect(basculer_barres_bas)
	entete_sorts.add_child(bouton_bascule_sorts)
	entete_sorts.move_child(bouton_bascule_sorts, 1)
	panneau_objets.hide()
	maj_barre_objets()

# remplit les emplacements de la barre d'objets : icône, quantité et
# info-bulle pour les consommables placés, emplacement grisé sinon
func maj_barre_objets() -> void:
	if barre_objets_emplacements == null:
		return
	for index in range(barre_objets_emplacements.get_child_count()):
		var bouton: Button = barre_objets_emplacements.get_child(index) as Button
		bouton.get_node("Badge").text = _raccourci(index)
		var id: String = Personnage.barre_objets[index] if index < Personnage.barre_objets.size() else ""
		var possede := int(Inventaire.objets.get(id, 0)) > 0
		if id != "" and possede:
			var details := Inventaire.details_objet(id)
			bouton.icon = _icone_objet_barre(details)
			bouton.disabled = false
			var quantite := int(Inventaire.objets[id])
			var texte_quantite := " (x%d)" % quantite if quantite > 1 else ""
			bouton.tooltip_text = "%s%s\nClic : consommer — Maj+clic : retirer de la barre\nTouche %s" % [
				Inventaire.nom_objet(id), texte_quantite, _raccourci(index)]
		else:
			bouton.icon = null
			bouton.disabled = true
			bouton.tooltip_text = "Ouvre Menu > Inventaire pour placer un consommable."

func _icone_objet_barre(details: Dictionary) -> Texture2D:
	var chemin: String = details.get("chemin_icone", "")
	if chemin == "" or not ResourceLoader.exists(chemin):
		chemin = ICONES_OBJETS_PAR_TYPE.get(str(details.get("type", "")).to_lower(), ICONE_OBJET_DEFAUT)
	if not ResourceLoader.exists(chemin):
		chemin = ICONE_OBJET_DEFAUT
	return load(chemin)

# clic (ou touche 1-0) sur un emplacement d'objet : consomme le
# consommable ; Maj+clic le retire de la barre sans le consommer
func _on_emplacement_objet_clique(index: int) -> void:
	var avec_maj := Input.is_key_pressed(KEY_SHIFT)
	if index >= Personnage.barre_objets.size():
		return
	var id := Personnage.barre_objets[index]
	if avec_maj:
		Personnage.retirer_objet_barre(id)
		afficher_message_sort("%s retiré de la barre." % Inventaire.nom_objet(id))
		return
	if int(Inventaire.objets.get(id, 0)) <= 0:
		return
	var details := Inventaire.details_objet(id)
	# parchemin de réattribution : une décision trop lourde pour un
	# clic de barre, l'inventaire la confirme
	if bool(details.get("effets", {}).get(Personnage.EFFET_REATTRIBUTION, false)):
		afficher_message_sort("Ouvre l'inventaire pour ce parchemin.")
		return
	if _gestionnaire_combat != null and _gestionnaire_combat.en_combat \
			and _gestionnaire_combat.en_placement:
		afficher_message_sort("Valide d'abord ton placement.")
		return
	var message := Personnage.utiliser_objet(id)
	if message != "":
		afficher_message_sort(message)
	else:
		afficher_message_sort("%s consommé !" % Inventaire.nom_objet(id))

# le texte d'action s'écrit dans l'en-tête de la barre visible
func _label_action_actif() -> Label:
	if barre_objets_active and label_action_objets != null:
		return label_action_objets
	return label_action

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if get_tree().paused or not navigation_haute.visible or (_parametres_touches != null and is_instance_valid(_parametres_touches)):
		return
	var action: String = Touches.action_de_evenement(event)
	if action == "":
		return
	if action.begins_with("sort_"):
		# les touches 1-0 pilotent la barre visible : sorts ou objets
		var panneau_actif: Control = panneau_objets if barre_objets_active else panneau_sorts
		if not panneau_actif.visible:
			return
		if barre_objets_active:
			_on_emplacement_objet_clique(int(action.substr(5)) - 1)
		else:
			_on_emplacement_sort_clique(int(action.substr(5)) - 1)
		get_viewport().set_input_as_handled()
		return
	if _gestionnaire_combat == null or not _gestionnaire_combat.en_combat:
		return
	match action:
		"fin_tour":
			# la même touche sert aux deux phases : valider son placement
			# pendant la phase de placement, finir son tour pendant le
			# combat (comme le bouton)
			if _gestionnaire_combat.en_placement:
				_gestionnaire_combat.demander_validation_placement()
			else:
				_gestionnaire_combat.demander_fin_tour()
			get_viewport().set_input_as_handled()
		"cible_suivante":
			_gestionnaire_combat.cible_suivante()
			get_viewport().set_input_as_handled()
		"cible_precedente":
			_gestionnaire_combat.cible_precedente()
			get_viewport().set_input_as_handled()
		"fuir":
			_gestionnaire_combat.demander_fuite()
			get_viewport().set_input_as_handled()
