extends AcceptDialog

const MARITIME := preload("res://scripts/world/navigation_maritime.gd")

var _poste := ""
var _liste: VBoxContainer
var _message: Label
var _echeance_meteo := 0
var _selection_fusion: Array[String] = []

func _ready() -> void:
	theme = Navires.theme_fenetre()
	transient = true
	exclusive = true
	ok_button_text = "Fermer"
	get_ok_button().add_theme_color_override("font_color", Color("#f9e4b3"))
	confirmed.connect(queue_free)
	canceled.connect(queue_free)

	var colonne := VBoxContainer.new()
	colonne.custom_minimum_size = Vector2(690, 560)
	colonne.add_theme_constant_override("separation", 10)
	add_child(colonne)
	var defilement := ScrollContainer.new()
	defilement.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	defilement.size_flags_vertical = Control.SIZE_EXPAND_FILL
	colonne.add_child(defilement)
	_liste = VBoxContainer.new()
	_liste.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_liste.add_theme_constant_override("separation", 8)
	defilement.add_child(_liste)
	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	colonne.add_child(_message)

	Navires.navigation_modifiee.connect(_actualiser)
	Navires.message_recu.connect(_afficher_message)
	var minuteur := Timer.new()
	add_child(minuteur)
	minuteur.timeout.connect(_actualiser_meteo)
	minuteur.start(1.0)

func ouvrir(poste: String) -> void:
	_poste = poste
	title = "Salle de navigation" if poste == "salle" else "Navigation"
	_actualiser()
	popup_centered()

func _actualiser_meteo() -> void:
	if visible and int(Time.get_unix_time_from_system()) >= _echeance_meteo:
		_actualiser()

func _actualiser() -> void:
	var timestamp := int(Time.get_unix_time_from_system())
	_echeance_meteo = timestamp - posmod(timestamp, MARITIME.DUREE_METEO) + MARITIME.DUREE_METEO
	for enfant in _liste.get_children():
		_liste.remove_child(enfant)
		enfant.queue_free()
	var navigation := Personnage.navigation_maritime
	var equipe: bool = MARITIME.CLASSIQUE in navigation["equipement"]
	var cap := str(navigation["cap"])
	var indication := "Log Pose classique à équiper" if not equipe else (
		"Log Pose classique à étalonner" if cap.is_empty() else "Cap du Log Pose classique · " + MARITIME.nom_port(cap))
	_etiquette("%s   |   %d Berry" % [indication, Personnage.berry])
	if _poste == "salle":
		_equipement(navigation)
	_cartes(equipe, cap)
	_traversees(navigation, equipe)
	if _poste == "salle" and Personnage.metier_perso() == MARITIME.METIER_NAVIGATEUR:
		_ligne("Atelier du navigateur", "Recettes de navigation", _ouvrir_recettes)
		_fusions()

func _ouvrir_recettes() -> void:
	Navires.fermer_navigation()
	get_tree().current_scene.get_node("MenuUI").ouvrir("metiers")

func _equipement(navigation: Dictionary) -> void:
	var poses: Array = navigation["equipement"]
	var capacite := int(navigation["capacite"])
	_etiquette("Log Pose équipés · %d/%d" % [poses.size(), capacite])
	for id: String in poses:
		_ligne(Inventaire.nom_objet(id), "Retirer", Navires.agir_navigation.bind("retirer", [id]))
	for id: String in Inventaire.objets:
		if MARITIME.est_log_pose(id) and id not in poses:
			_ligne(Inventaire.nom_objet(id), "Équiper", Navires.agir_navigation.bind("equiper", [id]),
				poses.size() >= capacite)
	if capacite < MARITIME.MAX_EMPLACEMENTS:
		var prix := MARITIME.prix_emplacement(capacite)
		_ligne("Emplacement supplémentaire", "%d Berry" % prix,
			Navires.agir_navigation.bind("emplacement"), Personnage.berry < prix)

func _cartes(equipe: bool, cap: String) -> void:
	var destinations: Array[String] = []
	var depart := MARITIME.identifiant(Navires.port_courant())
	for port: String in MARITIME.PORTS:
		if port != depart and port != cap and Inventaire.objets.has(MARITIME.carte(port)):
			destinations.append(port)
	if destinations.is_empty():
		return
	_etiquette("Cartes marines")
	for port: String in destinations:
		_ligne(MARITIME.nom_port(port), "Étalonner avec la carte", Navires.agir_navigation.bind("carte", [port]), not equipe)

func _traversees(navigation: Dictionary, equipe: bool) -> void:
	var origine := Navires.port_courant()
	var depart := MARITIME.identifiant(origine)
	if depart.is_empty():
		return
	var stats := Personnage.stats_bateau()
	var voisins := MARITIME.voisins(depart)
	_etiquette("Traversées")
	var affichage := false
	for port: String in MARITIME.PORTS:
		if port == depart:
			continue
		if MARITIME.cap_accessible(navigation, port):
			var devis := Navires.devis_navigation(origine, port, stats)
			var prix := int(devis["prix"])
			_ligne("%s · %s" % [MARITIME.nom_port(port), devis["meteo"]], "Partir · %d Berry" % prix,
				Navires.naviguer.bind(port, prix), Personnage.berry < prix)
			affichage = true
		elif _poste == "quai" and port in voisins:
			var prix := MARITIME.cout_etalonnage(port)
			_ligne(MARITIME.nom_port(port), "Étalonner · %d Berry" % prix,
				Navires.agir_navigation.bind("etalonnage", [port]), not equipe or Personnage.berry < prix)
			affichage = true
	if not affichage:
		_etiquette("Règle un cap au quai ou équipe un Log Pose éternel.")

func _fusions() -> void:
	var eternels: Array[String] = []
	for port: String in MARITIME.PORTS:
		if Inventaire.objets.has(MARITIME.eternel(port)):
			eternels.append(port)
	if eternels.size() < 3:
		_selection_fusion.clear()
		return
	_selection_fusion = _selection_fusion.filter(func(port: String) -> bool: return port in eternels)
	_etiquette("Fusion de Log Pose éternels")
	var choix := ItemList.new()
	choix.custom_minimum_size.y = 128
	choix.select_mode = ItemList.SELECT_MULTI
	_liste.add_child(choix)
	for port: String in eternels:
		var indice := choix.add_item(MARITIME.nom_port(port))
		if port in _selection_fusion:
			choix.select(indice, false)
	var bouton := Button.new()
	_liste.add_child(bouton)
	_libelle_fusion(bouton)
	choix.multi_selected.connect(func(indice: int, selectionne: bool):
		var port := eternels[indice]
		if selectionne:
			if _selection_fusion.size() >= 10:
				choix.deselect(indice)
			elif port not in _selection_fusion:
				_selection_fusion.append(port)
		else:
			_selection_fusion.erase(port)
		_libelle_fusion(bouton))
	bouton.pressed.connect(func():
		Navires.agir_navigation("fusion", _selection_fusion.duplicate()))

func _libelle_fusion(bouton: Button) -> void:
	var nombre := _selection_fusion.size()
	bouton.disabled = nombre < 3
	if nombre <= 3:
		bouton.text = "Fabriquer un Log Pose à trois aiguilles (%d/3)" % nombre
	else:
		bouton.text = "Fabriquer un cadre de Log Pose (%d destinations)" % nombre

func _etiquette(texte: String) -> void:
	var etiquette := Label.new()
	etiquette.text = texte
	_liste.add_child(etiquette)

func _ligne(texte: String, action: String, rappel: Callable, desactive := false) -> void:
	var ligne := HBoxContainer.new()
	_liste.add_child(ligne)
	var nom := Label.new()
	nom.text = texte
	nom.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ligne.add_child(nom)
	var bouton := Button.new()
	bouton.text = action
	bouton.disabled = desactive
	bouton.pressed.connect(rappel)
	ligne.add_child(bouton)

func _afficher_message(texte: String) -> void:
	_message.text = texte
