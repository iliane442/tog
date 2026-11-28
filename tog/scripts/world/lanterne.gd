extends "res://scripts/map.gd"

const TERRAIN := preload("res://scripts/world/terrain_lanterne.gd")
const ECHELLE := TERRAIN.ECHELLE
const PORTEE := 72.0

@onready var _terrain: Node2D = $TerrainZone
@onready var _interface: CanvasLayer = $LanterneUI
@onready var _sol: TileMapLayer = $ground
var _sous_le_pont := false
var _interactions: Dictionary = {}
var _signaletique: Node2D
var _routes_ui: AcceptDialog

func _ready() -> void:
	super._ready()
	_signaletique = Node2D.new()
	_signaletique.z_index = 14
	add_child(_signaletique)
	var arrivee: Vector2 = $player.global_position
	_sous_le_pont = _position_sous_le_pont(arrivee)
	_actualiser_etage()
	$player.position_depuis_case = _centre
	$player.case_depuis_position = _case_de
	$player.global_position = _terrain.position_monde(arrivee)
	$player.target = $player.global_position
	var minicarte := $CarteFushia/PanneauCarte/Marges/Colonne/Carte
	minicarte.position_vers_plan = position_sur_carte
	Navires.bord_modifie.connect(_actualiser_bord)
	Equipages.equipage_modifie.connect(_actualiser_bord)
	get_viewport().size_changed.connect(_actualiser_camera)
	_actualiser_bord()

func _actualiser_bord() -> void:
	var plan := position_sur_plan($player.global_position)
	_terrain.actualiser_pieces()
	_actualiser_etage()
	var position_monde: Vector2 = _terrain.position_monde(plan)
	if $player.global_position.distance_to(position_monde) > 0.01:
		$player._arreter_exploration()
		$player.global_position = position_monde
		$player.target = position_monde
	$CarteFushia/PanneauCarte/Marges/Colonne/Titre.text = Personnage.NAVIRES.fiche(Navires.modele_a_bord())["nom"]
	$CarteFushia/PanneauCarte/Marges/Colonne/Carte.texture = _terrain.apercu
	$CarteFushia/PanneauCarte/Marges/Colonne/Carte.dimensions_monde = _terrain.dimensions_monde()
	_actualiser_camera()
	var case_actuelle := _case_de($player.global_position)
	if _sol.get_cell_source_id(case_actuelle) == -1:
		$player._arreter_exploration()
		$player.global_position = _centre(_case_libre_proche(case_actuelle))
		$player.target = $player.position
	$player._preparer_navigation()
	_actualiser_interactions()

func a_portee_porte(id: String) -> bool:
	var piece: Dictionary = _terrain.pieces_bord().get(id, {})
	return _sous_le_pont and not piece.is_empty() and _distance_case(piece["seuil"]) <= PORTEE

func a_portee_poste(id: String) -> bool:
	if Navires.modele_a_bord() == "ateliers" and id == "atelier":
		for nom: String in _terrain.pieces_bord():
			if _terrain.metier_atelier(nom) == Personnage.metier_perso() and _pres_du_poste(nom):
				return true
		return false
	return _pres_du_poste(id)

func a_portee_etabli_navire() -> bool:
	if not Navires.est_pilote():
		return false
	if Navires.modele_a_bord() in Personnage.NAVIRES.GALIONS:
		return Navires.modele_a_bord() == "navigation" and _pres_du_poste("atelier")
	return _pres_du_poste("atelier")

func _pres_du_poste(id: String) -> bool:
	var piece: Dictionary = _terrain.pieces_bord().get(id, {})
	return _sous_le_pont and not piece.is_empty() and _terrain.est_ouverte(id) and _distance_case(piece["poste"]) <= PORTEE

func _distance_case(case_sol: Vector2i) -> float:
	return $player.global_position.distance_to(_centre(case_sol))

func _centre(case_sol: Vector2i) -> Vector2:
	return _terrain.position_monde(_sol.map_to_local(case_sol))

func _case_de(position_monde: Vector2) -> Vector2i:
	return _sol.local_to_map(position_sur_plan(position_monde))

func _case_libre_proche(visee: Vector2i) -> Vector2i:
	var proche: Vector2i = ECHELLE + Vector2i.DOWN if _sous_le_pont else _terrain.point_pont("depart")
	var distance := proche.distance_squared_to(visee)
	for cellule in _sol.get_used_cells():
		if (cellule.x >= TERRAIN.COULOIR.position.x) != _sous_le_pont:
			continue
		var ecart := cellule.distance_squared_to(visee)
		if ecart < distance:
			distance = ecart
			proche = cellule
	return proche

func _position_sous_le_pont(position_monde: Vector2) -> bool:
	return position_monde.x >= TERRAIN.COULOIR.position.x * TERRAIN.CASE

# Les sauvegardes et la minicarte utilisent le plan des cases.
func position_sur_plan(position_monde: Vector2) -> Vector2:
	return _terrain.position_plan(position_monde, _sous_le_pont)

func position_sur_carte(position_monde: Vector2) -> Vector2:
	return _terrain.position_plan(position_monde, _position_sous_le_pont(position_monde))

func avatar_sur_mon_etage(position_monde: Vector2) -> bool:
	return _position_sous_le_pont(position_monde) == _sous_le_pont

func _unhandled_input(evenement: InputEvent) -> void:
	if $MenuUI.fenetre.visible or not (evenement is InputEventMouseButton and evenement.pressed \
			and evenement.button_index == MOUSE_BUTTON_LEFT):
		return
	var point := get_global_mouse_position()
	var case_sol := _case_de(point)
	for cle in _interactions:
		var interaction: Dictionary = _interactions[cle]
		if cle == case_sol or interaction["etiquette"].has_point(point):
			$player.rejoindre_interaction(interaction["position"], interaction["action"])
			get_viewport().set_input_as_handled()
			return

func _actualiser_interactions() -> void:
	for etiquette in _signaletique.get_children():
		_signaletique.remove_child(etiquette)
		etiquette.queue_free()
	_interactions.clear()
	if not _sous_le_pont:
		if Navires.peut_utiliser_galion() or Navires.est_pilote():
			_ajouter_interaction(_terrain.point_pont("trappe"), "Descendre sous le pont", _changer_etage.bind(true), Vector2(0, -54))
		_ajouter_interaction(_terrain.point_pont("quai"), "Retour au quai", Navires.debarquer, Vector2(82, -33))
		if Navires.est_pilote():
			_ajouter_interaction(_terrain.point_pont("barre"), "Navigation et invités", _ouvrir_routes, Vector2(-73, -42))
		return
	_ajouter_interaction(ECHELLE, "Remonter sur le pont", _changer_etage.bind(false), Vector2(0, -28))
	var modele := Navires.modele_a_bord()
	var pieces: Dictionary = _terrain.pieces_bord()
	for id: String in pieces:
		var piece: Dictionary = pieces[id]
		var nom := _nom_piece(modele, id)
		if _terrain.est_ouverte(id):
			_ajouter_interaction(piece["poste"], nom, _utiliser_poste.bind(id), Vector2(0, -45))
			if id == "cartes" and id in Personnage.pieces_possibles_navire() and id not in Personnage.pieces_navire_ouvertes:
				var prix := int(Personnage.PIECES_NAVIRE[id]["prix"])
				_ajouter_interaction(piece["seuil"], "Cartes au trésor · %s Berry" % _interface.prix_affiche(prix),
					_ouvrir_porte.bind(id), Vector2(0, -32))
		elif Navires.est_pilote() and id != "cartes":
			var prix := Personnage.NAVIRES.PRIX_ATELIER if modele == "ateliers" else int(Personnage.PIECES_NAVIRE[id]["prix"])
			var porte := _centre(piece["porte"])
			var seuil := _centre(piece["seuil"])
			_ajouter_interaction(piece["seuil"], "%s · %s Berry" % [nom, _interface.prix_affiche(prix)],
				_ouvrir_porte.bind(id), porte - seuil + Vector2(0, -17))

func _nom_piece(modele: String, id: String) -> String:
	if id == "cartes":
		return "Salle de navigation"
	match modele:
		"ateliers":
			var metier: String = _terrain.metier_atelier(id)
			return str(Personnage.professions().get(metier, {}).get("nom", "Atelier %d" % (_terrain.indice_atelier(id) + 1)))
		"stockage":
			return "Cale commune"
		"navigation":
			return "Équipement naval"
		"vie":
			return "Chambre de " + Personnage.nom
	return str(Personnage.PIECES_NAVIRE[id]["nom"])

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
		"position": position,
		"action": action,
	}

func _changer_etage(descendre: bool) -> void:
	var cible: Vector2i = (ECHELLE if descendre else _terrain.point_pont("trappe")) + Vector2i.DOWN
	$player._arreter_exploration()
	_sous_le_pont = descendre
	_actualiser_etage()
	$player.global_position = _centre(cible)
	$player.target = $player.global_position
	_actualiser_camera()
	$player/Camera2D.reset_smoothing()
	$player/Camera2D.force_update_scroll()
	_actualiser_interactions()

func _actualiser_etage() -> void:
	_sol.transform = TERRAIN.projection_etage(_sous_le_pont, _terrain.est_galion())
	_terrain.montrer_interieur(_sous_le_pont)

func _actualiser_camera() -> void:
	var cadre: Rect2 = _terrain.cadre_interieur() if _sous_le_pont else Rect2(-1800, -1600, 6400, 4000)
	var camera: Camera2D = $player/Camera2D
	var pont_galion: bool = _terrain.est_galion() and not _sous_le_pont
	camera.limit_left = floori(cadre.position.x)
	camera.limit_top = floori(cadre.position.y)
	camera.limit_right = ceili(cadre.end.x)
	camera.limit_bottom = ceili(cadre.end.y)
	camera.top_level = pont_galion
	if pont_galion:
		var bateau: Rect2 = _terrain.cadre_galion()
		var vue := get_viewport_rect().size
		camera.position = bateau.get_center() + Vector2.RIGHT * 76.0
		camera.zoom = Vector2.ONE * minf(0.82, minf(vue.x / bateau.size.x, vue.y / bateau.size.y))
	else:
		camera.position = Vector2.ZERO
		camera.zoom = Vector2.ONE * 1.25

func _ouvrir_routes() -> void:
	if not Navires.est_pilote():
		return
	if is_instance_valid(_routes_ui):
		_routes_ui.queue_free()
	_routes_ui = AcceptDialog.new()
	_routes_ui.theme = Navires.theme_fenetre()
	_routes_ui.title = "Navigation et invités"
	_routes_ui.ok_button_text = "Fermer"
	add_child(_routes_ui)
	_routes_ui.get_ok_button().add_theme_color_override("font_color", Color("#f9e4b3"))
	var colonne := VBoxContainer.new()
	_routes_ui.add_child(colonne)
	_ajouter_choix_finition(colonne)
	var port := Navires.port_courant()
	_bouton_routes(colonne, "Choisir une destination", Navires.ouvrir_navigation.bind("barre"))
	if Personnage.en_ligne:
		var defilement := ScrollContainer.new()
		defilement.custom_minimum_size.y = 190
		colonne.add_child(defilement)
		var liste := VBoxContainer.new()
		liste.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		defilement.add_child(liste)
		for entree: Dictionary in Navires.bateaux_au_port(port):
			var pair := int(entree["id"])
			if pair == multiplayer.get_unique_id():
				continue
			var rang := HBoxContainer.new()
			liste.add_child(rang)
			var nom := Label.new()
			nom.text = str(entree["nom"])
			nom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			rang.add_child(nom)
			_bouton_routes(rang, "Inviter à visiter", Navires.demander_invitation.bind(pair, "visiteur"))
			_bouton_routes(rang, "Inviter comme passager", Navires.demander_invitation.bind(pair, "passager"))
	_routes_ui.popup_centered()

func _ajouter_choix_finition(parent: Control) -> void:
	var rang := HBoxContainer.new()
	var titre := Label.new()
	titre.text = "Finition du pont"
	var choix := OptionButton.new()
	choix.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(rang)
	rang.add_child(titre)
	rang.add_child(choix)
	var actuelle := Navires.finition_pont()
	for id: String in Personnage.FINITIONS_PONT.CHOIX:
		choix.add_item(str(Personnage.FINITIONS_PONT.fiche(id)["nom"]))
		var indice := choix.item_count - 1
		choix.set_item_metadata(indice, id)
		if id == actuelle:
			choix.select(indice)
	choix.item_selected.connect(func(indice: int):
		if Navires.changer_finition_pont(str(choix.get_item_metadata(indice))):
			_routes_ui.hide()
		else:
			for i in choix.item_count:
				if choix.get_item_metadata(i) == Navires.finition_pont():
					choix.select(i)
					break)

func _bouton_routes(parent: Control, libelle: String, action: Callable) -> void:
	var bouton := Button.new()
	bouton.text = libelle
	bouton.pressed.connect(func():
		_routes_ui.hide()
		action.call())
	parent.add_child(bouton)

func fermer_interfaces_navire() -> void:
	if is_instance_valid(_routes_ui):
		_routes_ui.hide()
	_interface.fermer()
	$DialogueUI.fermer()
	$MenuUI.fermer()

func _ouvrir_porte(id: String) -> void:
	if not a_portee_porte(id):
		return
	if Navires.modele_a_bord() == "ateliers":
		_interface.ouvrir_choix_atelier(_terrain.indice_atelier(id))
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
	if not _pres_du_poste(id):
		return
	if id == "cartes":
		if id in Personnage.pieces_navire_ouvertes:
			$DialogueUI.ouvrir_choix("Salle de navigation", "Que veux-tu faire ?", "Gérer les Log Pose",
				Navires.ouvrir_navigation.bind("salle"), "Consulter la carte au trésor", _interface.ouvrir.bind("cartes"))
		else:
			Navires.ouvrir_navigation("salle")
		return
	var modele := Navires.modele_a_bord()
	match modele:
		"ateliers":
			var metier: String = _terrain.metier_atelier(id)
			if metier == Personnage.metier_perso():
				$MenuUI.ouvrir("metiers")
			else:
				$DialogueUI.ouvrir_texte(_nom_piece(modele, id), "Cet établi est réservé au métier indiqué.")
			return
		"stockage":
			_interface.ouvrir("cale_commune")
			return
		"navigation":
			if Navires.est_pilote():
				$MenuUI.ouvrir_equipement_navire()
			return
		"vie":
			_interface.ouvrir("chambre")
			return
	if id == "atelier":
		var metier := str(Personnage.professions().get(Personnage.metier_perso(), {}).get("nom", "Atelier de bord"))
		$DialogueUI.ouvrir_choix(metier, "Que veux-tu faire à l’établi ?", "Recettes et améliorations",
			$MenuUI.ouvrir.bind("metiers"), "Équiper le navire", $MenuUI.ouvrir_equipement_navire)
	else:
		_interface.ouvrir(id)
