extends Node2D

const SCENE_ENNEMI := preload("res://scenes/ennemy.tscn")

@onready var notification: PanelContainer = $CarteFushia/Notification
@onready var texte_notification: Label = $CarteFushia/Notification/Texte
@onready var carte: CanvasLayer = $CarteFushia
var _animation_notification: Tween

func _ready() -> void:
	if not Personnage.perso_cree:
		carte.hide()
		$CreationPerso.tree_exited.connect(carte.show, CONNECT_ONE_SHOT)
	$MenuUI.menu_ouvert.connect(carte.hide)
	$MenuUI.menu_ferme.connect(_afficher_carte_en_exploration)
	$CombatManager.placement_commence.connect(carte.hide)
	$CombatManager.combat_termine.connect(func(_victoire: bool):
		if not $MenuUI.fenetre.visible:
			_afficher_carte_en_exploration())
	for pnj in get_tree().get_nodes_in_group("pnj_fushia"):
		pnj.dialogue_opened.connect($DialogueUI.ouvrir)
	for ennemi in get_tree().get_nodes_in_group("fushia_renforts"):
		var donnees := {
			"position": ennemi.position, "nom": ennemi.nom, "mob_id": ennemi.mob_id,
			"pv_max": ennemi.pv_max, "degats_attaque": ennemi.degats_attaque,
			"portee_attaque": ennemi.portee_attaque, "pm_max": ennemi.pm_max,
			"quetes_a_progresser": ennemi.quetes_a_progresser,
		}
		_surveille_renfort(ennemi, donnees)

func _afficher_carte_en_exploration() -> void:
	if not $CombatManager.en_combat:
		carte.show()

func _surveille_renfort(ennemi: Node2D, donnees: Dictionary) -> void:
	ennemi.connect("vaincu", _faire_revenir_ennemi.bind(donnees), CONNECT_ONE_SHOT)

func _faire_revenir_ennemi(donnees: Dictionary) -> void:
	await get_tree().create_timer(45.0, false).timeout
	var joueur: Node2D = $player
	while joueur.position.distance_to(donnees["position"]) < 125.0:
		await get_tree().create_timer(5.0, false).timeout
	var ennemi := SCENE_ENNEMI.instantiate() as Node2D
	for propriete in donnees:
		ennemi.set(propriete, donnees[propriete])
	$Rencontres.add_child(ennemi)
	_surveille_renfort(ennemi, donnees)

func afficher_info_fushia(texte: String) -> void:
	if _animation_notification != null:
		_animation_notification.kill()
	texte_notification.text = texte
	notification.modulate.a = 1.0
	notification.show()
	_animation_notification = create_tween()
	_animation_notification.tween_interval(2.1)
	_animation_notification.tween_property(notification, "modulate:a", 0.0, 0.28)
	_animation_notification.tween_callback(notification.hide)
