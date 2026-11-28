extends Node2D

const CATALOGUE := preload("res://scripts/world/catalogue_navires.gd")
const CHALOUPE := preload("res://assets/world/kit_cartes/bourg_port/barque_de_peche.png")
const NAVIRE_DU_ROUX := "res://scenes/navire_du_roux.tscn"

var _scene: Node
var _quai: Vector2
var _sprite: Sprite2D
var _etiquette_chaloupe: Label
var _dialogue: AcceptDialog

func installer(carte: Node, quai: Vector2, mouillage: Vector2) -> void:
	_scene = carte
	_quai = quai
	global_position = mouillage
	z_index = 4
	add_to_group("entites_minicarte")

	_sprite = Sprite2D.new()
	_sprite.texture = CHALOUPE
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.scale = Vector2.ONE * 0.86
	add_child(_sprite)

	_etiquette_chaloupe = Label.new()
	_etiquette_chaloupe.text = "Chaloupe"
	_etiquette_chaloupe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_etiquette_chaloupe.add_theme_font_size_override("font_size", 19)
	_etiquette_chaloupe.add_theme_color_override("font_color", Color("#ffedbd"))
	var fond := StyleBoxFlat.new()
	fond.bg_color = Color("#183240e8")
	fond.set_corner_radius_all(4)
	fond.content_margin_left = 8
	fond.content_margin_right = 8
	fond.content_margin_top = 2
	fond.content_margin_bottom = 2
	_etiquette_chaloupe.add_theme_stylebox_override("normal", fond)
	add_child(_etiquette_chaloupe)
	_etiquette_chaloupe.size = _etiquette_chaloupe.get_combined_minimum_size()
	_etiquette_chaloupe.position = Vector2(-_etiquette_chaloupe.size.x * 0.5, -65)

func repere_minicarte() -> Dictionary:
	return {"categorie": "voyages", "nom": "Chaloupe", "role": "Embarquement"}

func _unhandled_input(evenement: InputEvent) -> void:
	if not (evenement is InputEventMouseButton and evenement.pressed and evenement.button_index == MOUSE_BUTTON_LEFT):
		return
	var survol := _sprite.get_rect().grow(8).has_point(_sprite.get_local_mouse_position()) \
		or _etiquette_chaloupe.get_global_rect().grow(6).has_point(get_global_mouse_position())
	if survol and approcher():
		get_viewport().set_input_as_handled()

func approcher() -> bool:
	if not Personnage.perso_cree or not Navires.peut_traverser(_scene) or _scene.get_node("MenuUI").fenetre.visible:
		return false
	_scene.get_node("player").rejoindre_interaction(_quai, ouvrir)
	return true

func ouvrir() -> void:
	if not Navires.peut_traverser(_scene):
		return
	if is_instance_valid(_dialogue):
		_dialogue.queue_free()
	_dialogue = AcceptDialog.new()
	_dialogue.theme = Navires.theme_fenetre()
	_dialogue.title = "Chaloupe"
	_dialogue.ok_button_text = "Fermer"
	add_child(_dialogue)
	_dialogue.get_ok_button().add_theme_color_override("font_color", Color("#f9e4b3"))
	var colonne := VBoxContainer.new()
	colonne.custom_minimum_size = Vector2(500, 0)
	colonne.add_theme_constant_override("separation", 9)
	_dialogue.add_child(colonne)
	var modele := Personnage.modele_bateau()
	_etiquette(colonne, str(CATALOGUE.fiche(modele)["nom"]))
	_bouton(colonne, "Rejoindre mon bateau", Navires.embarquer)
	if _scene.scene_file_path == Personnage.PORT_NAVIRE_DEFAUT:
		_bouton(colonne, "Rejoindre le navire de Shanks", _scene.rejoindre_zone.bind(NAVIRE_DU_ROUX, &"DepuisChaloupe"))

	var en_vente := CATALOGUE.modele_vendu(_scene.scene_file_path)
	if en_vente != "" and Personnage.modele_bateau_perso != en_vente:
		var fiche := CATALOGUE.fiche(en_vente)
		var texte := "Acheter %s · %d Berry" % [fiche["nom"], fiche["prix"]]
		var prix := CATALOGUE.prix_achat(Personnage.modele_bateau_perso, _scene.scene_file_path)
		_bouton(colonne, texte, Navires.acheter_personnel).disabled = prix <= 0
		_etiquette(colonne, "%d piles dans la cale · %d solidité · %d%% résistance aux tempêtes" % [
			fiche["cale"], fiche["solidite"], fiche["tempete"]])

	if Personnage.en_ligne:
		var defilement := ScrollContainer.new()
		defilement.custom_minimum_size.y = 230
		colonne.add_child(defilement)
		var liste := VBoxContainer.new()
		liste.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		defilement.add_child(liste)
		for navire: Dictionary in Navires.bateaux_au_port(_scene.scene_file_path):
			var pilote := int(navire["id"])
			if pilote == multiplayer.get_unique_id():
				continue
			var fiche := CATALOGUE.fiche(str(navire["modele"]))
			var rang := HBoxContainer.new()
			liste.add_child(rang)
			_etiquette(rang, "%s · %s" % [navire["nom"], fiche["nom"]]).size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_bouton(rang, "Rejoindre", Navires.embarquer.bind(pilote))
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
