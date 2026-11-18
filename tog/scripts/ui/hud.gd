extends CanvasLayer

const ICONE_DEFAUT_SORT := "res://addons/pixel_ui_fantasy/icons/scroll.png"
const ICONES_SORTS := {
	"attack": "res://addons/pixel_ui_fantasy/icons/sword.png",
	"heal": "res://addons/pixel_ui_fantasy/icons/potion_red.png",
	"defense": "res://addons/pixel_ui_fantasy/icons/shield.png",
	"buff": "res://addons/pixel_ui_fantasy/icons/gem.png",
	"debuff": "res://addons/pixel_ui_fantasy/icons/cross.png",
	"control": "res://addons/pixel_ui_fantasy/icons/cross.png",
}

@onready var panneau_stats: PanelContainer = $PanneauStats
@onready var panneau_sorts: PanelContainer = $BarreDeSorts
@onready var barre_sorts: HBoxContainer = $BarreDeSorts/Colonne/Emplacements
@onready var barre_vie: ProgressBar = $PanneauStats/Colonne/LigneVie/Vie
@onready var barre_xp: ProgressBar = $PanneauStats/Colonne/LigneXP/XP
@onready var ligne_xp: HBoxContainer = $PanneauStats/Colonne/LigneXP
@onready var label_nom: Label = $PanneauStats/Colonne/Nom
@onready var label_vie: Label = $PanneauStats/Colonne/LigneVie/VieTexte
@onready var label_xp: Label = $PanneauStats/Colonne/LigneXP/XPTexte
@onready var ligne_combat: HBoxContainer = $PanneauStats/Colonne/LigneCombat
@onready var label_pa: Label = $PanneauStats/Colonne/LigneCombat/PA
@onready var label_pm: Label = $PanneauStats/Colonne/LigneCombat/PM
@onready var label_etats_joueur: Label = $PanneauStats/Colonne/EtatsJoueur
@onready var boutons_combat: HBoxContainer = $PanneauStats/Colonne/BoutonsCombat
@onready var bouton_placement: Button = $PanneauStats/Colonne/BoutonsCombat/ValiderPlacement
@onready var bouton_fin_tour: Button = $PanneauStats/Colonne/BoutonsCombat/FinTour
@onready var label_berry: Label = $BerryPanel/BerryRow/Berry
@onready var label_action: Label = $BarreDeSorts/Colonne/Entete/Action
@onready var label_quete: Label = $QuestPanel/Marges/Colonne/QuestName
@onready var label_progression_quete: Label = $QuestPanel/Marges/Colonne/QuestProgress
@onready var panneau_quete: PanelContainer = $QuestPanel
@onready var panneau_berry: PanelContainer = $BerryPanel
@onready var navigation_haute: HBoxContainer = $NavTop

var _joueur: Node
var _gestionnaire_combat: Node
var _menu: Node
var _tween_vie: Tween
var _tween_xp: Tween
var _tween_sorts: Tween

func _ready() -> void:
	_joueur = get_tree().current_scene.find_child("player", true, false)
	_gestionnaire_combat = get_tree().current_scene.get_node_or_null("CombatManager")
	if _gestionnaire_combat != null:
		_gestionnaire_combat.placement_commence.connect(_on_placement_commence)
		_gestionnaire_combat.combat_commence.connect(_on_combat_commence)
		_gestionnaire_combat.combat_termine.connect(_afficher_barre_sorts)
		_gestionnaire_combat.ressources_joueur_modifiees.connect(maj_ressources_combat)
		bouton_placement.pressed.connect(Callable(_gestionnaire_combat, "demander_validation_placement"))
		bouton_fin_tour.pressed.connect(Callable(_gestionnaire_combat, "demander_fin_tour"))
	_menu = get_tree().current_scene.get_node_or_null("MenuUI")
	if _menu != null:
		_menu.connect("menu_ouvert", _masquer_hud_menu)
		_menu.connect("menu_ferme", _retour_menu)
		_connecter_navigation(_menu)
	for index in range(barre_sorts.get_child_count()):
		var bouton: Button = barre_sorts.get_child(index) as Button
		bouton.pressed.connect(_on_emplacement_sort_clique.bind(index))
		bouton.mouse_entered.connect(_animer_case.bind(bouton, Vector2(1.08, 1.08)))
		bouton.mouse_exited.connect(_animer_case.bind(bouton, Vector2.ONE))
	Personnage.caracteristiques_modifiees.connect(maj)
	Personnage.barre_sorts_modifiee.connect(maj_barre_sorts)
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
		var id_sort: String = Personnage.barre_sorts[index] if index < Personnage.barre_sorts.size() else ""
		if id_sort != "" and Personnage.sorts.has(id_sort):
			var sort: Dictionary = Personnage.sorts[id_sort]
			bouton.icon = _icone_sort(sort)
			bouton.disabled = false
			bouton.tooltip_text = "%s\n%s\nTouche %s" % [str(sort.get("nom", "Sort")), str(sort.get("description", "")), _raccourci(index)]
		else:
			bouton.icon = null
			bouton.disabled = true
			bouton.tooltip_text = "Ouvre Menu > Sorts pour équiper un sort."

func _icone_sort(sort: Dictionary) -> Texture2D:
	var type_sort: String = str(sort.get("type", "")).to_lower()
	var chemin: String = ICONES_SORTS.get(type_sort, ICONE_DEFAUT_SORT)
	return load(chemin) as Texture2D

func _animer_case(bouton: Control, echelle: Vector2) -> void:
	var tween: Tween = bouton.create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(bouton, "scale", echelle, 0.12)

func _raccourci(index: int) -> String:
	return "0" if index == 9 else str(index + 1)

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

func afficher_message_sort(message: String) -> void:
	label_action.text = message

func _on_placement_commence() -> void:
	_animer_visibilite_sorts(false)
	_synchroniser_etats_joueur()
	_afficher_stats_combat(true)
	bouton_placement.show()
	bouton_fin_tour.hide()
	label_action.text = "Place-toi, puis valide le placement."

func _on_combat_commence() -> void:
	maj_barre_sorts()
	_synchroniser_etats_joueur()
	_afficher_stats_combat(true)
	bouton_placement.hide()
	bouton_fin_tour.show()
	label_action.text = "Touches 1-0 ou clic pour choisir un sort."
	_animer_visibilite_sorts(true)

func maj_ressources_combat(pa: int, pa_max: int, pm: int, pm_max: int) -> void:
	label_pa.text = "PA %d / %d" % [pa, pa_max]
	label_pm.text = "PM %d / %d" % [pm, pm_max]
	ligne_combat.visible = _gestionnaire_combat != null and _gestionnaire_combat.en_combat

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

func _masquer_hud_menu() -> void:
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
	label_action.text = "Touches 1-0 - clic pour utiliser"
	_animer_visibilite_sorts(true)

func _retour_menu() -> void:
	panneau_stats.show()
	panneau_quete.show()
	panneau_berry.show()
	navigation_haute.show()
	if _gestionnaire_combat != null and _gestionnaire_combat.en_combat:
		if _gestionnaire_combat.en_placement:
			_on_placement_commence()
		else:
			_on_combat_commence()
	else:
		_afficher_stats_combat(false)
		_animer_visibilite_sorts(true)

func _animer_visibilite_sorts(afficher: bool) -> void:
	if _tween_sorts != null and _tween_sorts.is_running():
		_tween_sorts.kill()
	if afficher:
		panneau_sorts.show()
		panneau_sorts.modulate.a = 0.0
		panneau_sorts.scale = Vector2(0.96, 0.96)
	_tween_sorts = create_tween().set_parallel(true)
	_tween_sorts.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween_sorts.tween_property(panneau_sorts, "modulate:a", 1.0 if afficher else 0.0, 0.18)
	_tween_sorts.tween_property(panneau_sorts, "scale", Vector2.ONE if afficher else Vector2(0.96, 0.96), 0.18)
	if not afficher:
		_tween_sorts.finished.connect(panneau_sorts.hide)

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if not panneau_sorts.visible or get_tree().paused:
		return
	var index: int = -1
	match event.keycode:
		KEY_1: index = 0
		KEY_2: index = 1
		KEY_3: index = 2
		KEY_4: index = 3
		KEY_5: index = 4
		KEY_6: index = 5
		KEY_7: index = 6
		KEY_8: index = 7
		KEY_9: index = 8
		KEY_0: index = 9
		_: return
	_on_emplacement_sort_clique(index)
	get_viewport().set_input_as_handled()
