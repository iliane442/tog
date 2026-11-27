extends Node2D

const CATALOGUE := preload("res://scripts/world/catalogue_navires.gd")
const SHADER_MER := preload("res://assets/shaders/mer_alabasta.gdshader")
const TEXTURE_MER := preload("res://assets/world/alabasta/terrain/mer.png")
const ECART_GALIONS := 64.0
const GALIONS_PAR_RANGEE := 4

var _quai: Vector2
var _mouillage: Vector2
var _mouillage_galions: Vector2
var _canal := false
var _navires := []
var _rectangles: Dictionary = {}
var _places: Dictionary = {}
var _dialogue: AcceptDialog
var _scene: Node
var _camera: Camera2D
var _limites_port: Vector2
var _rade: ColorRect

func installer(carte: Node, quai: Vector2, mouillage: Vector2, canal: bool, mouillage_galions := Vector2.INF) -> void:
	_scene = carte
	_quai = quai
	_mouillage = mouillage
	_mouillage_galions = mouillage_galions if mouillage_galions.is_finite() else _mouillage + Vector2(65, 190)
	_canal = canal
	_camera = carte.get_node("player/Camera2D")
	_limites_port = Vector2(_camera.limit_right, _camera.limit_bottom)
	z_index = 4
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	Navires.port_modifie.connect(_actualiser)
	Personnage.caracteristiques_modifiees.connect(_actualiser)
	_actualiser()

func _local() -> int:
	return multiplayer.get_unique_id()

func _actualiser() -> void:
	var presents := Navires.bateaux_au_port(_scene.scene_file_path).duplicate()
	var trouve := false
	for indice in presents.size():
		var navire: Dictionary = presents[indice]
		if int(navire["id"]) == _local():
			navire = navire.duplicate()
			navire["modele"] = Personnage.modele_bateau()
			presents[indice] = navire
			trouve = true
			break
	if not trouve and Personnage.perso_cree:
		presents.push_front({"id": _local(), "nom": Personnage.nom, "modele": Personnage.modele_bateau()})
	if presents != _navires:
		_navires = presents
		_repartir_amarres()
		queue_redraw()

func _repartir_amarres() -> void:
	_places.clear()
	_rectangles.clear()
	var petits := []
	var galions: Array[int] = []
	for i in _navires.size():
		if str(_navires[i]["modele"]) in CATALOGUE.GALIONS:
			galions.append(i)
		else:
			petits.append(i)

	var premier := 0
	var y := _mouillage_galions.y
	var dimensions := _limites_port
	while premier < galions.size():
		var fin := mini(premier + GALIONS_PAR_RANGEE, galions.size())
		# Le premier navire reste près du quai. Les suivants prennent place
		# alternativement de chaque côté avec assez d'espace pour leur coque.
		var x_centre := _mouillage_galions.x
		var x_gauche := x_centre
		var x_droite := x_centre
		var hauteur := 0.0
		var places := []
		for i in range(premier, fin):
			var indice := galions[i]
			var taille := _taille_navire(indice)
			var x := x_centre
			if i == premier:
				x_gauche -= taille.x * 0.5 + ECART_GALIONS
				x_droite += taille.x * 0.5 + ECART_GALIONS
			elif (i - premier) % 2 == 1:
				x = x_gauche - taille.x * 0.5
				x_gauche -= taille.x + ECART_GALIONS
			else:
				x = x_droite + taille.x * 0.5
				x_droite += taille.x + ECART_GALIONS
			places.append([indice, x, taille])
			hauteur = maxf(hauteur, taille.y)
		if premier != 0:
			y += hauteur + ECART_GALIONS
		var decalage := maxf(0.0, -x_gauche)
		for place in places:
			_poser_navire(int(place[0]), Vector2(float(place[1]) + decalage, y), place[2], true)
		dimensions.x = maxf(dimensions.x, x_droite + decalage)
		dimensions.y = maxf(dimensions.y, y + ECART_GALIONS)
		premier = fin

	var facteur := 1.0 if petits.size() <= 5 else 0.70
	var colonnes := [0, -1, 1, -2, 2]
	for i in petits.size():
		var colonne: int = colonnes[i % colonnes.size()]
		var ligne := floori(float(i) / colonnes.size())
		var position := _mouillage + Vector2(colonne * 332, ligne * 275) * facteur
		if _canal:
			position = _mouillage + Vector2(floori(i / 4.0) * 148, (i % 4) * -244)
		var indice: int = petits[i]
		var taille := _taille_navire(indice) * facteur * (0.65 if _canal else 1.0)
		if not galions.is_empty():
			position = _degager_amarrage(position, taille)
			dimensions.y = maxf(dimensions.y, position.y + ECART_GALIONS)
		_poser_navire(indice, position, taille)
	_etendre_rade(dimensions)

func _degager_amarrage(position: Vector2, taille: Vector2) -> Vector2:
	var autres := _places.values()
	autres.sort_custom(func(a: Rect2, b: Rect2) -> bool: return a.position.x > b.position.x)
	var zone := Rect2(position - Vector2(taille.x * 0.5, taille.y), taille)
	var bas := zone.end.y
	for autre: Rect2 in autres:
		bas = maxf(bas, autre.end.y)
		if zone.grow(18.0).intersects(autre):
			zone.position.x = autre.position.x - taille.x - 18.0
	if zone.position.x < 0.0:
		return Vector2(position.x, bas + taille.y + 18.0)
	return Vector2(zone.get_center().x, zone.end.y)

func _taille_navire(indice: int) -> Vector2:
	var fiche := CATALOGUE.fiche(str(_navires[indice]["modele"]))
	var texture: Texture2D = fiche["sprite"]
	var largeur := float(fiche["taille"])
	return Vector2(largeur, largeur * texture.get_height() / texture.get_width())

func _poser_navire(indice: int, position: Vector2, taille: Vector2, galion := false) -> void:
	var zone := Rect2(position - Vector2(taille.x * 0.5, taille.y), taille)
	_places[indice] = zone
	# Les voiles d'un grand vaisseau peuvent passer devant le décor du
	# quai. La zone d'embarquement reste sur le pont et la coque.
	var hauteur_interaction := taille.y * 0.42 if galion else taille.y
	_rectangles[int(_navires[indice]["id"])] = Rect2(
		position - Vector2(taille.x * 0.5, hauteur_interaction), Vector2(taille.x, hauteur_interaction))

func _etendre_rade(dimensions: Vector2) -> void:
	_camera.limit_right = ceili(dimensions.x)
	_camera.limit_bottom = ceili(dimensions.y)
	var terrain := _scene.get_node_or_null("TerrainZone")
	if terrain != null and terrain.has_method("etendre_mer_du_port"):
		terrain.etendre_mer_du_port(dimensions)
		return
	if dimensions == _limites_port:
		if is_instance_valid(_rade):
			_rade.hide()
		return
	if not is_instance_valid(_rade):
		_rade = ColorRect.new()
		_rade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rade.z_as_relative = false
		_rade.z_index = -40
		var materiau := ShaderMaterial.new()
		materiau.shader = SHADER_MER
		materiau.set_shader_parameter("mer", TEXTURE_MER)
		_rade.material = materiau
		add_child(_rade)
	_rade.size = dimensions
	_rade.material.set_shader_parameter("dimensions", dimensions)
	_rade.show()

func _draw() -> void:
	for indice in _places:
		var navire: Dictionary = _navires[indice]
		var fiche := CATALOGUE.fiche(str(navire["modele"]))
		var texture: Texture2D = fiche["sprite"]
		var zone: Rect2 = _places[indice]
		draw_texture_rect(texture, zone, false, fiche["teinte"])
		var police := ThemeDB.get_fallback_font()
		var nom := str(navire["nom"])
		var ancre := Vector2(zone.get_center().x, zone.end.y)
		var legende := ancre + Vector2(-police.get_string_size(nom, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x * 0.5, 10)
		draw_string_outline(police, legende, nom, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, Color("#183240"))
		draw_string(police, legende, nom, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#ffedbd"))

func _unhandled_input(evenement: InputEvent) -> void:
	if not (evenement is InputEventMouseButton and evenement.pressed and evenement.button_index == MOUSE_BUTTON_LEFT):
		return
	if not Navires.peut_traverser(_scene) or _scene.get_node("MenuUI").fenetre.visible:
		return
	for pilote: int in _rectangles:
		if _rectangles[pilote].has_point(get_local_mouse_position()):
			var joueur := _scene.get_node("player")
			joueur.rejoindre_interaction(_quai, _ouvrir_bateau.bind(pilote))
			get_viewport().set_input_as_handled()
			return

func _ouvrir_bateau(pilote: int) -> void:
	if pilote == _local():
		Navires.embarquer()
	else:
		Navires.embarquer(pilote)

func ouvrir() -> void:
	if is_instance_valid(_dialogue):
		_dialogue.queue_free()
	_dialogue = AcceptDialog.new()
	_dialogue.theme = Navires.theme_fenetre()
	_dialogue.title = "Navires du port"
	_dialogue.ok_button_text = "Fermer"
	add_child(_dialogue)
	_dialogue.get_ok_button().add_theme_color_override("font_color", Color("#f9e4b3"))
	var colonne := VBoxContainer.new()
	colonne.custom_minimum_size = Vector2(500, 0)
	colonne.add_theme_constant_override("separation", 9)
	_dialogue.add_child(colonne)
	var modele := Personnage.modele_bateau()
	_etiquette(colonne, "%s · %d Berry par traversée" % [CATALOGUE.fiche(modele)["nom"], CATALOGUE.fiche(modele)["entretien"]])
	_bouton(colonne, "Monter à bord", Navires.embarquer)
	var en_vente := CATALOGUE.modele_vendu(_scene.scene_file_path)
	if en_vente != "" and Personnage.modele_bateau_perso != en_vente:
		var fiche := CATALOGUE.fiche(en_vente)
		var texte := "Acheter %s · %d Berry" % [fiche["nom"], fiche["prix"]]
		var prix := CATALOGUE.prix_achat(Personnage.modele_bateau_perso, _scene.scene_file_path)
		_bouton(colonne, texte, Navires.acheter_personnel).disabled = prix <= 0
		_etiquette(colonne, "%d piles dans la cale · %d Berry par traversée" % [fiche["cale"], fiche["entretien"]])
	if Personnage.en_ligne:
		var defilement := ScrollContainer.new()
		defilement.custom_minimum_size.y = 230
		colonne.add_child(defilement)
		var liste := VBoxContainer.new()
		liste.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		defilement.add_child(liste)
		for navire: Dictionary in _navires:
			var pilote := int(navire["id"])
			if pilote == _local():
				continue
			var fiche := CATALOGUE.fiche(str(navire["modele"]))
			var rang := HBoxContainer.new()
			liste.add_child(rang)
			_etiquette(rang, "%s · %s" % [navire["nom"], fiche["nom"]]).size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_bouton(rang, "Monter", _ouvrir_bateau.bind(pilote))
			_bouton(rang, "Inviter à visiter", Navires.demander_invitation.bind(pilote, "visiteur"))
			_bouton(rang, "Inviter comme passager", Navires.demander_invitation.bind(pilote, "passager"))
	_dialogue.popup_centered()

func fermer() -> void:
	if is_instance_valid(_dialogue):
		_dialogue.hide()

func _etiquette(parent: Control, texte: String) -> Label:
	var label := Label.new()
	label.text = texte
	parent.add_child(label)
	return label

func _bouton(parent: Control, texte: String, action: Callable) -> Button:
	var bouton := Button.new()
	bouton.text = texte
	bouton.pressed.connect(func():
		fermer()
		action.call())
	parent.add_child(bouton)
	return bouton
