extends CanvasLayer

const THEME := preload("res://themes/theme_pirate.tres")
const TAILLE_CASE := 64.0

var _fond: ColorRect
var _titre: Label
var _contenu: VBoxContainer
var _message: Label
var _sac: ItemList
var _cale: ItemList
var _quantite: SpinBox
var _bouton_depot: Button
var _bouton_retrait: Button
var _liste_trophees: OptionButton
var _carte: TextureRect
var _marques: Control
var _dimensions_port := Vector2.ZERO
var _port := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fond = ColorRect.new()
	_fond.color = Color(0.035, 0.065, 0.09, 0.78)
	_fond.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fond.hide()
	add_child(_fond)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fond.add_child(centre)
	var panneau := PanelContainer.new()
	panneau.theme = THEME
	centre.add_child(panneau)
	var marges := MarginContainer.new()
	for cote in ["left", "right", "top", "bottom"]:
		marges.add_theme_constant_override("margin_" + cote, 24)
	panneau.add_child(marges)
	var colonne := VBoxContainer.new()
	colonne.custom_minimum_size.x = 760
	colonne.add_theme_constant_override("separation", 12)
	marges.add_child(colonne)
	var entete := HBoxContainer.new()
	colonne.add_child(entete)
	_titre = Label.new()
	_titre.add_theme_font_size_override("font_size", 31)
	_titre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entete.add_child(_titre)
	_bouton(entete, "Fermer", fermer)
	_contenu = VBoxContainer.new()
	_contenu.add_theme_constant_override("separation", 10)
	colonne.add_child(_contenu)
	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.hide()
	colonne.add_child(_message)

func ouvrir(id: String) -> void:
	if not Personnage.a_portee_poste_navire(id):
		return
	for enfant in _contenu.get_children():
		_contenu.remove_child(enfant)
		enfant.queue_free()
	_message.hide()
	_titre.text = Personnage.PIECES_NAVIRE[id]["nom"]
	match id:
		"cale": _ouvrir_cale()
		"cabine": _ouvrir_cabine()
		"cartes": _ouvrir_cartes()
	get_tree().paused = true
	_fond.show()

func fermer() -> void:
	if _fond.visible:
		_fond.hide()
		get_tree().paused = false

func _input(evenement: InputEvent) -> void:
	if _fond.visible and evenement is InputEventKey and evenement.pressed and evenement.keycode == KEY_ESCAPE:
		fermer()
		get_viewport().set_input_as_handled()

func prix_affiche(prix: int) -> String:
	var chiffres := str(prix)
	if chiffres.length() > 3:
		chiffres = chiffres.insert(chiffres.length() - 3, " ")
	return chiffres

func _ouvrir_cale() -> void:
	var listes := HBoxContainer.new()
	listes.add_theme_constant_override("separation", 14)
	_contenu.add_child(listes)
	_sac = _liste_stock(listes, "Sac")
	_cale = _liste_stock(listes, "Coffre de la cale")
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	_contenu.add_child(actions)
	_etiquette(actions, "Quantité")
	_quantite = SpinBox.new()
	_quantite.min_value = 1
	_quantite.max_value = 1
	_quantite.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(_quantite)
	_bouton_depot = _bouton(actions, "Déposer", _transferer.bind(true))
	_bouton_retrait = _bouton(actions, "Retirer", _transferer.bind(false))
	_sac.item_selected.connect(_selection_stock.bind(true))
	_cale.item_selected.connect(_selection_stock.bind(false))
	_actualiser_stock()

func _liste_stock(parent: Control, titre: String) -> ItemList:
	var colonne := VBoxContainer.new()
	colonne.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(colonne)
	_etiquette(colonne, titre)
	var liste := ItemList.new()
	liste.custom_minimum_size = Vector2(360, 315)
	liste.fixed_icon_size = Vector2i(26, 26)
	colonne.add_child(liste)
	return liste

func _remplir_stock(liste: ItemList, objets: Dictionary) -> void:
	liste.clear()
	var ids := objets.keys()
	ids.sort_custom(func(a, b): return Inventaire.nom_objet(a).naturalnocasecmp_to(Inventaire.nom_objet(b)) < 0)
	for id in ids:
		var ligne := liste.add_item("%s  ×%d" % [Inventaire.nom_objet(id), int(objets[id])], _icone(id))
		liste.set_item_metadata(ligne, id)
	if liste.item_count == 0:
		liste.add_item("Vide", null, false)

func _actualiser_stock() -> void:
	_remplir_stock(_sac, Inventaire.objets)
	_remplir_stock(_cale, Inventaire.objets_en_cale())
	_bouton_depot.disabled = true
	_bouton_retrait.disabled = true
	_quantite.max_value = 1
	_quantite.value = 1

func _selection_stock(index: int, dans_sac: bool) -> void:
	var liste := _sac if dans_sac else _cale
	var autre := _cale if dans_sac else _sac
	var id: String = liste.get_item_metadata(index)
	var objets := Inventaire.objets if dans_sac else Inventaire.objets_en_cale()
	autre.deselect_all()
	_quantite.max_value = int(objets.get(id, 1))
	_quantite.value = 1
	_bouton_depot.disabled = not dans_sac
	_bouton_retrait.disabled = dans_sac
	_message.hide()

func _transferer(depot: bool) -> void:
	var liste := _sac if depot else _cale
	var selection := liste.get_selected_items()
	if selection.is_empty():
		return
	var id: String = liste.get_item_metadata(selection[0])
	var quantite := int(_quantite.value)
	if Inventaire.transferer_cale(id, quantite, depot):
		_actualiser_stock()
		_afficher_message("%s ×%d %s." % [Inventaire.nom_objet(id), quantite, "déposé dans la cale" if depot else "récupéré"])
	else:
		_afficher_message("Le transfert n’a pas abouti.")

func _ouvrir_cabine() -> void:
	_etiquette(_contenu, "Journal de bord")
	var entrees := PackedStringArray(["Corbin m’a confié la Lanterne à Fushia. J’ai désormais un pont et un fanal où revenir entre deux escales."])
	for id in QuestManager.quetes_terminees:
		if QuestManager.quetes.has(id):
			entrees.append("✓  " + str(QuestManager.quetes[id]["titre"]))
	var journal := RichTextLabel.new()
	journal.custom_minimum_size.y = 265
	journal.add_theme_font_size_override("normal_font_size", 19)
	journal.text = "\n\n".join(entrees)
	_contenu.add_child(journal)
	var actions := HBoxContainer.new()
	_contenu.add_child(actions)
	_etiquette(actions, "Trophée exposé")
	_liste_trophees = OptionButton.new()
	_liste_trophees.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(_liste_trophees)
	_liste_trophees.add_item("Aucun trophée")
	_liste_trophees.set_item_metadata(0, "")
	var objets := Inventaire.objets_en_cale()
	objets.merge(Inventaire.objets)
	for id in objets:
		var nom := Inventaire.nom_objet(id)
		if nom.to_lower().contains("trophée"):
			var index := _liste_trophees.item_count
			_liste_trophees.add_icon_item(_icone(id), nom)
			_liste_trophees.set_item_metadata(index, id)
			if id == Personnage.trophee_navire:
				_liste_trophees.select(index)
	_liste_trophees.item_selected.connect(_exposer)

func _exposer(index: int) -> void:
	Personnage.trophee_navire = _liste_trophees.get_item_metadata(index)
	Personnage.sauvegarder()
	get_tree().current_scene.get_node("TerrainZone").queue_redraw()

func _ouvrir_cartes() -> void:
	_port = str(Personnage.escale_navire.get("scene", Personnage.PORT_NAVIRE_DEFAUT))
	_etiquette(_contenu, "Escale · " + _port.get_file().get_basename().replace("_", " ").capitalize())
	_carte = TextureRect.new()
	_carte.custom_minimum_size.y = 340
	_carte.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_carte.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_carte.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_carte.texture = _carte_port()
	_contenu.add_child(_carte)
	_marques = Control.new()
	_marques.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_marques.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_carte.add_child(_marques)
	_marques.draw.connect(_dessiner_marques)
	_carte.gui_input.connect(_sur_carte)
	var actions := HBoxContainer.new()
	_contenu.add_child(actions)
	var indices := 0
	for croix in CartesTresor.croix_persistantes():
		if croix["scene"] == _port:
			indices += 1
	_etiquette(actions, "%d indice(s) au trésor · Clique sur la carte pour poser un repère." % indices).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bouton(actions, "Effacer le repère", _effacer_repere)

func _carte_port() -> Texture2D:
	_dimensions_port = Vector2.ZERO
	if not _port.begins_with("res://scenes/") or _port == Personnage.SCENE_NAVIRE or not ResourceLoader.exists(_port):
		return null
	var scene := (load(_port) as PackedScene).instantiate()
	var mini := scene.get_node_or_null("CarteFushia/PanneauCarte/Marges/Colonne/Carte") as TextureRect
	var texture := mini.texture if mini != null else null
	if mini != null:
		_dimensions_port = mini.dimensions_monde
	var terrain := scene.get_node_or_null("TerrainZone")
	if terrain != null and terrain.has_method("_construire_textures"):
		terrain._construire_textures()
		_dimensions_port = terrain.dimensions_monde()
		texture = terrain.apercu
	scene.free()
	return texture

func _rect_carte() -> Rect2:
	if _carte.texture == null:
		return Rect2()
	var taille := _carte.texture.get_size()
	taille *= minf(_carte.size.x / taille.x, _carte.size.y / taille.y)
	return Rect2((_carte.size - taille) * 0.5, taille)

func _dessiner_marques() -> void:
	var rect := _rect_carte()
	if not rect.has_area() or _dimensions_port.x <= 0 or _dimensions_port.y <= 0:
		return
	for croix in CartesTresor.croix_persistantes():
		if croix["scene"] == _port:
			var case_sol := Vector2(croix["case_sol"]) + Vector2(0.5, 0.5)
			var point := rect.position + case_sol * TAILLE_CASE / _dimensions_port * rect.size
			var couleur := Color("#f0bded")
			_marques.draw_line(point - Vector2(5, 5), point + Vector2(5, 5), couleur, 3)
			_marques.draw_line(point - Vector2(5, -5), point + Vector2(5, -5), couleur, 3)
	var repere := Personnage.repere_navire
	if repere.get("scene", "") == _port:
		var point := rect.position + Vector2(repere["x"], repere["y"]) / _dimensions_port * rect.size
		_marques.draw_circle(point, 7, Color("#281e14"))
		_marques.draw_circle(point, 5, Color("#ffda70"))

func _sur_carte(evenement: InputEvent) -> void:
	if not (evenement is InputEventMouseButton and evenement.pressed and evenement.button_index == MOUSE_BUTTON_LEFT):
		return
	var rect := _rect_carte()
	if not rect.has_point(evenement.position):
		return
	var position_monde: Vector2 = (evenement.position - rect.position) / rect.size * _dimensions_port
	Personnage.repere_navire = {"scene": _port, "x": position_monde.x, "y": position_monde.y}
	Personnage.sauvegarder()
	_marques.queue_redraw()
	_afficher_message("Le repère apparaîtra sur la carte de ton escale.")

func _effacer_repere() -> void:
	Personnage.repere_navire = {}
	Personnage.sauvegarder()
	_marques.queue_redraw()
	_message.hide()

func _afficher_message(texte: String) -> void:
	_message.text = texte
	_message.show()

func _icone(id: String) -> Texture2D:
	var chemin := str(Inventaire.details_objet(id).get("chemin_icone", ""))
	return load(chemin) as Texture2D if not chemin.is_empty() and ResourceLoader.exists(chemin) else null

func _etiquette(parent: Control, texte: String) -> Label:
	var etiquette := Label.new()
	etiquette.text = texte
	parent.add_child(etiquette)
	return etiquette

func _bouton(parent: Control, texte: String, action: Callable) -> Button:
	var bouton := Button.new()
	bouton.text = texte
	bouton.pressed.connect(action)
	parent.add_child(bouton)
	return bouton
