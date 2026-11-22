# boutique_ui.gd — fenêtre d'achat de coffres chez Shanksette (CanvasLayer BoutiqueUI)
extends CanvasLayer

const ICONE_DEFAUT := "res://addons/pixel_ui_fantasy/icons/chest.png"

@onready var fenetre: PanelContainer = $Fenetre
@onready var label_argent: Label = $Fenetre/VBox/Argent
@onready var liste: VBoxContainer = $Fenetre/VBox/Defilement/Liste
@onready var popup: Label = $Fenetre/VBox/Popup
@onready var btn_fermer: Button = $Fenetre/VBox/Boutons/Fermer

var _tween_popup: Tween

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	fenetre.visible = false
	btn_fermer.pressed.connect(fermer)
	popup.modulate.a = 0.0

func ouvrir() -> void:
	fenetre.visible = true
	_rafraichir()
	get_tree().paused = true

func fermer() -> void:
	fenetre.visible = false
	get_tree().paused = false

func _unhandled_input(event: InputEvent) -> void:
	if fenetre.visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		fermer()
		get_viewport().set_input_as_handled()

func _rafraichir() -> void:
	label_argent.text = "Berry : %d" % Personnage.berry
	for enfant in liste.get_children():
		enfant.queue_free()
	for ligne in _offres():
		liste.add_child(_creer_ligne(str(ligne["id"]), int(ligne["base_price"])))

# les coffres en vente : tous les items actifs de type "coffre", du moins cher au plus cher
func _offres() -> Array:
	return BaseDonnees.lire(
		"SELECT id, base_price FROM items"
		+ " WHERE type = 'coffre' AND is_active = 1 ORDER BY base_price;")

func _creer_ligne(id: String, prix: int) -> HBoxContainer:
	var details := Inventaire.details_objet(id)
	var ligne := HBoxContainer.new()
	ligne.add_theme_constant_override("separation", 14)
	ligne.custom_minimum_size = Vector2(0, 48)

	var icone := TextureRect.new()
	icone.custom_minimum_size = Vector2(36, 36)
	icone.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icone.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icone.texture = _icone(details)
	ligne.add_child(icone)

	var nom := Label.new()
	nom.text = Inventaire.nom_objet(id)
	nom.add_theme_color_override("font_color", details["couleur_rarete"])
	nom.add_theme_font_size_override("font_size", 19)
	nom.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nom.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	ligne.add_child(nom)

	var prix_label := Label.new()
	prix_label.text = "%d Berry" % prix
	prix_label.add_theme_font_size_override("font_size", 19)
	prix_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ligne.add_child(prix_label)

	# quantité achetable d'un coup, plafonnée à ce que la bourse suit
	var quantite := SpinBox.new()
	quantite.min_value = 1
	quantite.max_value = maxi(1, mini(99, floori(float(Personnage.berry) / float(prix))))
	quantite.value = 1
	quantite.custom_minimum_size = Vector2(84, 0)
	quantite.tooltip_text = "Quantité à acheter"
	ligne.add_child(quantite)

	var bouton := Button.new()
	bouton.text = "Acheter"
	bouton.disabled = Personnage.berry < prix
	bouton.pressed.connect(_acheter.bind(id, prix, quantite))
	quantite.value_changed.connect(func(_valeur: float) -> void:
		bouton.disabled = Personnage.berry < prix * int(quantite.value))
	ligne.add_child(bouton)
	return ligne

func _acheter(id: String, prix: int, quantite: SpinBox) -> void:
	var nombre := maxi(1, int(quantite.value))
	var total := prix * nombre
	if Personnage.berry < total:
		return
	Personnage.ajouter_berry(-total)
	Inventaire.ajouter_objet(id, nombre)
	if nombre > 1:
		_annonce("Acheté : %s ×%d (%d Berry)" % [Inventaire.nom_objet(id), nombre, total])
	else:
		_annonce("Acheté : %s" % Inventaire.nom_objet(id))
	_rafraichir()

func _annonce(texte: String) -> void:
	popup.text = texte
	popup.modulate.a = 1.0
	if _tween_popup != null and _tween_popup.is_valid():
		_tween_popup.kill()
	_tween_popup = create_tween()
	_tween_popup.tween_interval(1.2)
	_tween_popup.tween_property(popup, "modulate:a", 0.0, 0.5)

func _icone(details: Dictionary) -> Texture2D:
	var chemin: String = details.get("chemin_icone", "")
	if chemin != "" and ResourceLoader.exists(chemin):
		return load(chemin)
	return load(ICONE_DEFAUT)
