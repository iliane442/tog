extends Node2D

const SCENE_ENNEMI := preload("res://scenes/ennemy.tscn")
const ESCALE_NAVIRES := preload("res://scripts/world/escale_navires.gd")

@export var renouveler_rencontres := true
@export var mouillage_joueurs := Vector2.INF
@export var mouillage_galions := Vector2.INF
@export var mouillage_en_canal := false

@onready var notification: PanelContainer = $CarteFushia/Notification
@onready var texte_notification: Label = $CarteFushia/Notification/Texte
@onready var carte: CanvasLayer = $CarteFushia
var _animation_notification: Tween
var _changement_zone := false
static var _scene_arrivee := ""
static var _point_arrivee: StringName
static var _position_arrivee := Vector2.INF

func _enter_tree() -> void:
	var terrain := get_node_or_null("TerrainZone")
	if terrain != null:
		terrain.preparer($ground, $cliffs, $Paysage)
		var taille: Vector2 = terrain.dimensions_monde()
		var camera: Camera2D = $player/Camera2D
		camera.limit_left = 0
		camera.limit_top = 0
		camera.limit_right = int(taille.x)
		camera.limit_bottom = int(taille.y)
	if _scene_arrivee == scene_file_path:
		if _position_arrivee.is_finite():
			$player.position = _position_arrivee
		elif not _point_arrivee.is_empty():
			var arrivee := get_node_or_null(NodePath("Arrivees/" + str(_point_arrivee))) as Marker2D
			if arrivee != null:
				$player.position = arrivee.position
		_scene_arrivee = ""
		_point_arrivee = &""
		_position_arrivee = Vector2.INF
	else:
		# retour sur une map sans arrivée précise (lancement du jeu,
		# reconnexion) : le joueur reprend sa dernière position
		# mémorisée sur cette carte
		Reseau.appliquer_position_memorisee(scene_file_path, $player)

func _ready() -> void:
	_styliser_notification()
	_installer_navires_du_port()
	var terrain := get_node_or_null("TerrainZone")
	if terrain != null:
		var mini_carte := $CarteFushia/PanneauCarte/Marges/Colonne/Carte
		mini_carte.texture = terrain.apercu
		mini_carte.dimensions_monde = terrain.dimensions_monde()
	CartesTresor.dessiner_sur_carte.call_deferred()
	if not Personnage.perso_cree:
		carte.hide()
		$CreationPerso.tree_exited.connect(carte.show, CONNECT_ONE_SHOT)
	$MenuUI.menu_ouvert.connect(carte.hide)
	$MenuUI.menu_ouvert.connect($player._arreter_exploration)
	$MenuUI.menu_ouvert.connect($CombatManager._quitter_survol_ennemi)
	$MenuUI.menu_ferme.connect(_afficher_carte_en_exploration)
	$CombatManager.placement_commence.connect(carte.hide)
	$CombatManager.combat_termine.connect(func(_victoire: bool):
		if not $MenuUI.fenetre.visible:
			_afficher_carte_en_exploration())
	for pnj in get_tree().get_nodes_in_group("pnj_fushia"):
		pnj.dialogue_opened.connect($DialogueUI.ouvrir)
	# tous les camps de monstres reviennent : les rencontres de la
	# scène rejoignent les renforts historiques de Fushia
	var sentinelles: Array = []
	for ennemi in get_tree().get_nodes_in_group("fushia_renforts"):
		sentinelles.append(ennemi)
	for ennemi in $Rencontres.get_children():
		if not sentinelles.has(ennemi):
			sentinelles.append(ennemi)
	for ennemi in sentinelles:
		var donnees := {
			"position": ennemi.position, "nom": ennemi.nom, "mob_id": ennemi.mob_id,
			"pv_max": ennemi.pv_max, "degats_attaque": ennemi.degats_attaque,
			"portee_attaque": ennemi.portee_attaque, "pm_max": ennemi.pm_max,
			"attaques_par_tour": ennemi.attaques_par_tour,
			"niveau_personnalise": ennemi.niveau_personnalise,
			"texture_personnalisee": ennemi.texture_personnalisee,
			"groupe": ennemi.groupe,
			"quetes_a_progresser": ennemi.quetes_a_progresser,
		}
		_surveille_renfort(ennemi, donnees)

func _installer_navires_du_port() -> void:
	for capitaine in get_children():
		if not capitaine.is_in_group("capitaines_ferry"):
			continue
		var port := ESCALE_NAVIRES.new()
		port.name = "EscaleNavires"
		add_child(port)
		var bateau := get_node_or_null("Paysage/SloopDuFerry") as Node2D
		if bateau == null:
			bateau = get_node_or_null("Paysage/FerryDesAnges") as Node2D
		var ancrage: Vector2 = capitaine.position + Vector2(270, 360)
		if bateau != null:
			ancrage = bateau.position + Vector2(540, 60)
		var terrain := get_node_or_null("TerrainZone")
		if terrain != null:
			ancrage.y = minf(ancrage.y, terrain.dimensions_monde().y - 32)
		port.installer(self, capitaine.position, mouillage_joueurs if mouillage_joueurs.is_finite() else ancrage,
			mouillage_en_canal, mouillage_galions)
		break

func rejoindre_zone(fichier: String, arrivee: StringName, position_arrivee := Vector2.INF) -> void:
	if _changement_zone or get_tree().paused or $CombatManager.en_combat:
		return
	_changement_zone = true
	_charger_zone.call_deferred(fichier, arrivee, position_arrivee)

func _charger_zone(fichier: String, arrivee: StringName, position_arrivee: Vector2) -> void:
	if get_tree().paused or $CombatManager.en_combat:
		_changement_zone = false
		return
	_scene_arrivee = fichier
	_point_arrivee = arrivee
	_position_arrivee = position_arrivee
	if get_tree().change_scene_to_file(fichier) != OK:
		_changement_zone = false
		_scene_arrivee = ""
		_point_arrivee = &""
		_position_arrivee = Vector2.INF
		afficher_info_fushia("Ce passage est momentanément fermé.")

func _afficher_carte_en_exploration() -> void:
	if not $CombatManager.en_combat:
		carte.show()

func _surveille_renfort(ennemi: Node2D, donnees: Dictionary) -> void:
	if renouveler_rencontres:
		ennemi.connect("vaincu", _faire_revenir_ennemi.bind(donnees), CONNECT_ONE_SHOT)

func _faire_revenir_ennemi(donnees: Dictionary) -> void:
	# un camp nettoyé renais de ses cendres au bout d'une minute ;
	# la naissance attend tout de même que le capitaine ait décampé
	# (la rencontre n'apparaît jamais sur la tête du joueur)
	await get_tree().create_timer(60.0, false).timeout
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

# la récolte doit se lire d'un coup d'œil par-dessus la carte : le
# brun du thème parchemin se fondait dans le décor
func _styliser_notification() -> void:
	var fond := StyleBoxFlat.new()
	fond.bg_color = Color(0.07, 0.045, 0.02, 0.94)
	fond.border_color = Color(1.0, 0.78, 0.32)
	fond.set_border_width_all(2)
	fond.set_corner_radius_all(8)
	fond.content_margin_left = 14.0
	fond.content_margin_right = 14.0
	fond.content_margin_top = 10.0
	fond.content_margin_bottom = 10.0
	notification.add_theme_stylebox_override("panel", fond)
	texte_notification.add_theme_font_size_override("font_size", 22)
	texte_notification.add_theme_color_override("font_color", Color(1.0, 0.94, 0.7))
	texte_notification.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	texte_notification.add_theme_constant_override("outline_size", 6)
