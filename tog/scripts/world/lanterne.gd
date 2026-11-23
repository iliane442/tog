extends "res://scripts/map.gd"

const TERRAIN := preload("res://scripts/world/terrain_lanterne.gd")
const TRAPPE := Vector2i(7, 7)
const PASSERELLE := Vector2i(8, 11)
const ECHELLE := Vector2i(29, 8)
const PORTEE := 52.0

@onready var _terrain: Node2D = $TerrainZone
@onready var _interface: CanvasLayer = $LanterneUI
var _sous_le_pont := false
var _interactions: Dictionary = {}
var _signaletique: Node2D

func _ready() -> void:
	super._ready()
	var camera: Camera2D = $player/Camera2D
	camera.limit_left = -1800
	camera.limit_right = 4600
	camera.limit_top = -1600
	camera.limit_bottom = 2400
	camera.zoom = Vector2(1.25, 1.25)
	_signaletique = Node2D.new()
	_signaletique.z_index = 14
	add_child(_signaletique)
	var case_sol: Vector2i = $ground.local_to_map($player.position)
	if $ground.get_cell_source_id(case_sol) == -1:
		$player.position = $Arrivees/DepuisQuai.position
		$player.target = $player.position
	_sous_le_pont = $player.position.x >= TERRAIN.COULOIR.position.x * TERRAIN.CASE
	_terrain.montrer_interieur(_sous_le_pont)
	_actualiser_interactions()

func a_portee_porte(id: String) -> bool:
	return _sous_le_pont and _distance_case(TERRAIN.PIECES[id]["seuil"]) <= PORTEE

func a_portee_poste(id: String) -> bool:
	return _sous_le_pont and id in Personnage.pieces_navire_ouvertes \
		and _distance_case(TERRAIN.PIECES[id]["poste"]) <= PORTEE

func _distance_case(case_sol: Vector2i) -> float:
	return $player.global_position.distance_to(_centre(case_sol))

func _centre(case_sol: Vector2i) -> Vector2:
	return $ground.to_global($ground.map_to_local(case_sol))

func _unhandled_input(evenement: InputEvent) -> void:
	if $MenuUI.fenetre.visible or not (evenement is InputEventMouseButton and evenement.pressed \
			and evenement.button_index == MOUSE_BUTTON_LEFT):
		return
	var point := get_global_mouse_position()
	for interaction in _interactions.values():
		if interaction["etiquette"].has_point(point) or interaction["sol"].has_point(point):
			$player.rejoindre_interaction(interaction["position"], interaction["action"])
			get_viewport().set_input_as_handled()
			return

func _actualiser_interactions() -> void:
	for etiquette in _signaletique.get_children():
		etiquette.queue_free()
	_interactions.clear()
	if not _sous_le_pont:
		_ajouter_interaction(TRAPPE, "Descendre sous le pont", _changer_etage.bind(true), Vector2(0, -54))
		_ajouter_interaction(PASSERELLE, "Retour au quai", _debarquer, Vector2(82, -33))
		return
	_ajouter_interaction(ECHELLE, "Remonter sur le pont", _changer_etage.bind(false), Vector2(0, -28))
	for id in Personnage.PIECES_NAVIRE:
		var piece: Dictionary = TERRAIN.PIECES[id]
		var nom := str(Personnage.PIECES_NAVIRE[id]["nom"])
		if id in Personnage.pieces_navire_ouvertes:
			_ajouter_interaction(piece["poste"], nom, _utiliser_poste.bind(id), Vector2(0, -45))
		else:
			var prix := int(Personnage.PIECES_NAVIRE[id]["prix"])
			var porte := _centre(piece["porte"])
			var seuil := _centre(piece["seuil"])
			_ajouter_interaction(piece["seuil"], "%s · %s Berry" % [nom, _interface.prix_affiche(prix)],
				_ouvrir_porte.bind(id), porte - seuil + Vector2(0, -17))

func _ajouter_interaction(case_sol: Vector2i, texte: String, action: Callable, decalage: Vector2) -> void:
	var position := _centre(case_sol)
	var etiquette := Label.new()
	etiquette.text = texte
	etiquette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	etiquette.add_theme_font_size_override("font_size", 18)
	etiquette.add_theme_color_override("font_color", Color("#ffe4b4"))
	etiquette.add_theme_color_override("font_outline_color", Color("#191710"))
	etiquette.add_theme_constant_override("outline_size", 7)
	etiquette.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	etiquette.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_signaletique.add_child(etiquette)
	etiquette.size = etiquette.get_combined_minimum_size()
	etiquette.global_position = position + decalage - etiquette.size * 0.5
	_interactions[case_sol] = {
		"etiquette": Rect2(etiquette.global_position, etiquette.size).grow(12.0),
		"sol": Rect2(position - Vector2(33, 30), Vector2(66, 60)),
		"position": position,
		"action": action,
	}

func _changer_etage(descendre: bool) -> void:
	var cible := ECHELLE + Vector2i.DOWN if descendre else TRAPPE + Vector2i.DOWN
	$player._arreter_exploration()
	$player.global_position = _centre(cible)
	$player.target = $player.global_position
	$player/Camera2D.reset_smoothing()
	$player/Camera2D.force_update_scroll()
	_sous_le_pont = descendre
	_terrain.montrer_interieur(descendre)
	_actualiser_interactions()

func _debarquer() -> void:
	var escale := Personnage.escale_navire
	var port := str(escale.get("scene", Personnage.PORT_NAVIRE_DEFAUT))
	if port != scene_file_path and port.begins_with("res://scenes/") and ResourceLoader.exists(port) \
			and not escale.is_empty():
		rejoindre_zone(port, &"", Vector2(float(escale.get("x", INF)), float(escale.get("y", INF))))
	else:
		rejoindre_zone(Personnage.PORT_NAVIRE_DEFAUT, &"DepuisShells")

func _ouvrir_porte(id: String) -> void:
	if not a_portee_porte(id):
		return
	var fiche: Dictionary = Personnage.PIECES_NAVIRE[id]
	var prix := int(fiche["prix"])
	var texte := str(fiche["usage"]) + "\n\nTu as %s Berry." % _interface.prix_affiche(Personnage.berry)
	if id != "atelier" and "atelier" not in Personnage.pieces_navire_ouvertes:
		$DialogueUI.ouvrir_texte(fiche["nom"], texte + " Ouvre d’abord l’atelier de bord.")
	elif Personnage.berry < prix:
		$DialogueUI.ouvrir_texte(fiche["nom"], texte + " Il te manque %s Berry." % _interface.prix_affiche(prix - Personnage.berry))
	else:
		$DialogueUI.ouvrir_choix(fiche["nom"], texte, "Débloquer · %s Berry" % _interface.prix_affiche(prix), _acheter.bind(id))

func _acheter(id: String) -> void:
	if not Personnage.debloquer_piece_navire(id):
		afficher_info_fushia("L’aménagement est indisponible.")
		return
	_terrain.actualiser_pieces()
	$player._preparer_navigation()
	_actualiser_interactions()
	afficher_info_fushia("%s est maintenant accessible." % Personnage.PIECES_NAVIRE[id]["nom"])

func _utiliser_poste(id: String) -> void:
	if not a_portee_poste(id):
		return
	if id == "atelier":
		var metier := str(Personnage.professions().get(Personnage.metier_perso(), {}).get("nom", "Atelier de bord"))
		$DialogueUI.ouvrir_choix(metier, "Que veux-tu faire à l’établi ?", "Recettes et améliorations",
			$MenuUI.ouvrir.bind("metiers"), "Équiper le navire", $MenuUI.ouvrir_equipement_navire)
	else:
		_interface.ouvrir(id)
