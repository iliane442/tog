# coffres_ui.gd — fenêtre de loot des coffres (CanvasLayer CoffreUI)
# Une seule fenêtre, mais elle accumule plusieurs coffres ouverts à la suite :
# chaque coffre (ou coffre d'inventaire) devient une section avec son titre.
# Révélation d'un objet : sa rareté s'affiche, puis son type, puis l'objet
# lui-même. « Suivant » dévoile un objet à la fois, « Tout afficher » tout
# en cascade.
extends CanvasLayer

const ICONE_DEFAUT := "res://addons/pixel_ui_fantasy/icons/chest.png"
const NOMS_RARETE := {
	1: "Coffre commun",
	2: "Coffre rare",
	3: "Coffre épique",
	4: "Coffre légendaire",
}
const COULEURS_RARETE := {
	1: Color(0.38, 0.38, 0.38),
	2: Color(0.0, 0.50, 1.0),
	3: Color(0.50, 0.0, 1.0),
	4: Color(1.0, 0.68, 0.0),
}
# rythme de la révélation en trois étapes (rareté -> type -> objet)
const DUREE_ETAPE := 0.4    # durée du fondu de chaque étape
const PAUSE_ETAPE := 0.45   # attente entre les étapes
const DECALAGE_LOT := 0.6   # décalage entre objets pour « Tout afficher »

@onready var fenetre: PanelContainer = $Fenetre
@onready var titre: Label = $Fenetre/VBox/Titre
@onready var liste: VBoxContainer = $Fenetre/VBox/Defilement/Liste
@onready var label_vide: Label = $Fenetre/VBox/Vide
@onready var popup: Label = $Fenetre/VBox/Popup
@onready var btn_suivant: Button = $Fenetre/VBox/Boutons/Suivant
@onready var btn_tout_afficher: Button = $Fenetre/VBox/Boutons/ToutAfficher
@onready var btn_tout: Button = $Fenetre/VBox/Boutons/ToutPrendre
@onready var btn_fermer: Button = $Fenetre/VBox/Boutons/Fermer

# coffres actuellement affichés :
# {"titre", "couleur", "coffre_id", "mode_inv", "reveles"} — "reveles" est le
# nombre d'objets déjà révélés dans cette section (les suivants restent cachés)
var _sources: Array = []
# "index_source:index_objet" -> {"ligne", "intro" : intro de la ligne,
#   "rarete": libellé rareté, "type": libellé type}
var _infos_lignes := {}
var _tweens_revelation: Array = []
var _tween_popup: Tween

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	fenetre.visible = false
	btn_suivant.pressed.connect(_on_suivant)
	btn_tout_afficher.pressed.connect(_on_tout_afficher)
	btn_tout.pressed.connect(_on_tout_prendre)
	btn_fermer.pressed.connect(fermer)
	# monde partagé : nos prises online ne sont créditées qu'après
	# confirmation du serveur (annonce à la réception), et les prises
	# des autres joueurs retirent les objets de la fenêtre ouverte
	Coffres.prise_distante.connect(_sur_prise_distante)
	Coffres.coffre_modifie.connect(_sur_coffre_modifie)
	popup.modulate.a = 0.0

# prises confirmées par le serveur (objet demandé ou vidage) : annonce
# et rafraîchissement une fois créditées à l'inventaire
func _sur_prise_distante(prises: Array) -> void:
	if not fenetre.visible:
		return
	_annonce_pris(prises)
	_rafraichir()

# un coffre affiché évolue (état serveur, prise par un autre joueur) :
# la fenêtre reflète son contenu restant
func _sur_coffre_modifie(coffre_id: String) -> void:
	if not fenetre.visible:
		return
	for source in _sources:
		if str(source["coffre_id"]) == str(coffre_id):
			_rafraichir()
			return

# coffre posé sur la carte
func ouvrir(coffre: Node2D, contenu: Array) -> void:
	_ajouter_source(
		NOMS_RARETE.get(coffre.rarete, NOMS_RARETE[1]),
		COULEURS_RARETE.get(coffre.rarete, COULEURS_RARETE[1]),
		coffre.coffre_id, contenu, false)

# coffre ouvert depuis l'inventaire : reliquat emporté à la fermeture
func ouvrir_contenu(texte: String, coffre_id: String, contenu: Array, rarete := 0) -> void:
	var couleur: Color = COULEURS_RARETE.get(rarete, Color(0.3, 0.25, 0.2))
	_ajouter_source(texte, couleur, coffre_id, contenu, true)

func _ajouter_source(texte: String, couleur: Color, coffre_id: String, contenu: Array, mode_inv: bool) -> void:
	if contenu.is_empty() and _sources.is_empty():
		# coffre vide et aucun affichage en cours : juste la mention
		titre.text = texte
		fenetre.visible = true
		label_vide.visible = true
		btn_tout.visible = false
		btn_suivant.visible = false
		btn_tout_afficher.visible = false
		get_tree().paused = true
		return
	if contenu.is_empty():
		return  # rien à ajouter aux sections déjà affichées
	for source in _sources:
		if source["coffre_id"] == coffre_id:
			return  # ce coffre est déjà affiché
	_sources.append({
		"titre": texte, "couleur": couleur,
		"coffre_id": coffre_id, "mode_inv": mode_inv,
		"reveles": 0,
	})
	if not fenetre.visible:
		titre.text = "Butin"
		fenetre.visible = true
		fenetre.modulate.a = 0.0
		var t := create_tween()
		t.tween_property(fenetre, "modulate:a", 1.0, 0.12)
	titre.text = "Butin (%d coffre%s)" % [_sources.size(), "s" if _sources.size() > 1 else ""]
	_rafraichir()
	# le premier objet du coffre qui vient d'arriver se révèle tout seul
	var source = _sources[_sources.size() - 1]
	_reveler(_sources.size() - 1, int(source["reveles"]))
	source["reveles"] = int(source["reveles"]) + 1
	get_tree().paused = true

func fermer() -> void:
	_tuer_tweens()
	# les coffres d'inventaire : ce qui n'est pas pris part quand même
	for source in _sources:
		if source["mode_inv"]:
			_virer_source_dans_inventaire(source)
	_sources.clear()
	fenetre.visible = false
	get_tree().paused = false

func _unhandled_input(event: InputEvent) -> void:
	if fenetre.visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		fermer()
		get_viewport().set_input_as_handled()

func _tuer_tweens() -> void:
	for t in _tweens_revelation:
		if t is Tween and t.is_valid():
			t.kill()
	_tweens_revelation.clear()

# reconstruit les sections ; chaque source garde son compteur d'objets révélés
func _rafraichir() -> void:
	_tuer_tweens()
	for enfant in liste.get_children():
		enfant.queue_free()
	_infos_lignes.clear()
	var nb_lignes := 0
	for i in range(_sources.size()):
		var source: Dictionary = _sources[i]
		var contenu := Coffres.contenu(source["coffre_id"])
		source["reveles"] = mini(int(source["reveles"]), contenu.size())
		if contenu.is_empty():
			continue
		liste.add_child(_creer_entete(source))
		var index := 0
		for prise in contenu:
			var ligne := _creer_ligne(prise, i, index)
			var visible_avant := index < int(source["reveles"])
			if visible_avant:
				_completer_ligne(i, index)
			else:
				ligne.modulate.a = 0.0
				ligne.disabled = true
			liste.add_child(ligne)
			index += 1
			nb_lignes += 1
	label_vide.visible = nb_lignes == 0
	btn_tout.visible = nb_lignes > 0
	_maj_boutons_revelation()

# une ligne déjà révélée : intro complète, quantité et objet affichés
func _completer_ligne(index_source: int, index_objet: int) -> void:
	var infos: Dictionary = _infos_lignes.get("%d:%d" % [index_source, index_objet], {})
	if infos.is_empty():
		return
	infos["ligne"].modulate.a = 1.0
	infos["ligne"].disabled = false
	infos["intro"].modulate.a = 1.0
	infos["intro"].text = "%s — %s" % [infos["rarete"], infos["type"]]
	infos["qte"].modulate.a = 1.0
	infos["objet"].modulate.a = 1.0

# « Suivant » : dévoile l'objet suivant de la première section non épuisée
func _on_suivant() -> void:
	for i in range(_sources.size()):
		var source: Dictionary = _sources[i]
		var nb := Coffres.contenu(source["coffre_id"]).size()
		if int(source["reveles"]) < nb:
			_reveler(i, int(source["reveles"]))
			source["reveles"] = int(source["reveles"]) + 1
			_maj_boutons_revelation()
			return
	_annonce_texte("Tout est déjà affiché.", Color(0.4, 0.35, 0.3))

# « Tout afficher » : même révélation en cascade, objet après objet
func _on_tout_afficher() -> void:
	var rang := 0
	for i in range(_sources.size()):
		var source: Dictionary = _sources[i]
		var nb := Coffres.contenu(source["coffre_id"]).size()
		while int(source["reveles"]) < nb:
			_reveler(i, int(source["reveles"]), DECALAGE_LOT * rang)
			source["reveles"] = int(source["reveles"]) + 1
			rang += 1
	_maj_boutons_revelation()

# séquence d'un objet : 1. la rareté, 2. le type, 3. la quantité, 4. le nom
func _reveler(index_source: int, index_objet: int, decalage := 0.0) -> void:
	var infos: Dictionary = _infos_lignes.get("%d:%d" % [index_source, index_objet], {})
	if infos.is_empty():
		return
	var ligne: Button = infos["ligne"]
	var intro: Label = infos["intro"]
	ligne.modulate.a = 1.0
	ligne.disabled = true
	intro.text = str(infos["rarete"])
	intro.modulate.a = 0.0
	infos["qte"].modulate.a = 0.0
	infos["objet"].modulate.a = 0.0
	var t := create_tween()
	_tweens_revelation.append(t)
	t.tween_interval(decalage)
	# étape 1 : la rareté
	t.tween_property(intro, "modulate:a", 1.0, DUREE_ETAPE)
	t.tween_interval(PAUSE_ETAPE)
	# étape 2 : le type complète l'intro (petit flash au passage)
	t.tween_callback(func() -> void:
		intro.text = "%s — %s" % [infos["rarete"], infos["type"]]
		intro.modulate.a = 0.6)
	t.tween_property(intro, "modulate:a", 1.0, DUREE_ETAPE * 0.4)
	t.tween_interval(PAUSE_ETAPE)
	# étape 3 : la quantité
	t.tween_property(infos["qte"], "modulate:a", 1.0, DUREE_ETAPE)
	t.tween_interval(PAUSE_ETAPE)
	# étape 4 : l'objet lui-même (icône + nom), ligne cliquable
	t.tween_callback(func() -> void: ligne.disabled = false)
	t.tween_property(infos["objet"], "modulate:a", 1.0, DUREE_ETAPE)

# visibilité des boutons Suivant / Tout afficher selon ce qui reste caché
func _maj_boutons_revelation() -> void:
	var reste_cache := false
	for source in _sources:
		if int(source["reveles"]) < Coffres.contenu(source["coffre_id"]).size():
			reste_cache = true
			break
	btn_suivant.visible = reste_cache
	btn_tout_afficher.visible = reste_cache

func _creer_entete(source: Dictionary) -> Label:
	var entete := Label.new()
	entete.add_theme_font_size_override("font_size", 26)
	entete.add_theme_color_override("font_color", source["couleur"])
	entete.text = source["titre"]
	return entete

func _creer_ligne(prise: Dictionary, index_source: int, index: int) -> Button:
	var id := str(prise["id"])
	var details := Inventaire.details_objet(id)

	var bouton := Button.new()
	bouton.custom_minimum_size = Vector2(0, 84)
	bouton.alignment = HORIZONTAL_ALIGNMENT_LEFT
	bouton.pressed.connect(_on_ligne_presee.bind(index_source, index))

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 2)
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 20.0
	vbox.offset_top = 10.0
	vbox.offset_right = -14.0
	vbox.offset_bottom = -10.0

	# introduction : rareté puis type s'y affichent avant l'objet
	var intro := Label.new()
	intro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	intro.add_theme_font_size_override("font_size", 19)
	intro.add_theme_color_override("font_color", details["couleur_rarete"])
	intro.modulate.a = 0.0
	intro.text = ""
	vbox.add_child(intro)

	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 22)
	vbox.add_child(hbox)

	# groupe objet (icône + nom) : révélé en dernier, après la quantité
	var groupe_objet := HBoxContainer.new()
	groupe_objet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	groupe_objet.add_theme_constant_override("separation", 22)
	groupe_objet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	groupe_objet.modulate.a = 0.0
	hbox.add_child(groupe_objet)

	var icone := TextureRect.new()
	icone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icone.custom_minimum_size = Vector2(56, 56)
	icone.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icone.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icone.texture = _icone(details)
	groupe_objet.add_child(icone)

	var nom := Label.new()
	nom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nom.text = Inventaire.nom_objet(id)
	nom.add_theme_color_override("font_color", details["couleur_rarete"])
	nom.add_theme_font_size_override("font_size", 28)
	nom.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nom.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	groupe_objet.add_child(nom)

	var qte := Label.new()
	qte.mouse_filter = Control.MOUSE_FILTER_IGNORE
	qte.text = "x%d" % int(prise["qte"])
	qte.add_theme_font_size_override("font_size", 28)
	qte.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	qte.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	qte.custom_minimum_size = Vector2(80, 0)
	qte.modulate.a = 0.0
	hbox.add_child(qte)

	bouton.add_child(vbox)
	_infos_lignes["%d:%d" % [index_source, index]] = {
		"ligne": bouton,
		"intro": intro,
		"qte": qte,
		"objet": groupe_objet,
		"rarete": str(details.get("rarete", "")),
		"type": str(details.get("type", "")).capitalize(),
	}
	return bouton

func _on_ligne_presee(index_source: int, index: int) -> void:
	if index_source < 0 or index_source >= _sources.size():
		return
	var source: Dictionary = _sources[index_source]
	if index >= int(source["reveles"]):
		return  # objet pas encore révélé
	var prise := Coffres.prendre_objet(source["coffre_id"], index)
	if prise.is_empty():
		return
	Inventaire.ajouter_objet(str(prise["id"]), int(prise["qte"]))
	_annonce_pris([prise])
	_rafraichir()

func _on_tout_prendre() -> void:
	if _sources.is_empty():
		return
	var prises := []
	for source in _sources:
		prises.append_array(Coffres.vider(source["coffre_id"]))
	# un seul passage inventaire : un gros lot ne déclenche plus
	# des centaines d'écritures et de mises à jour d'interface
	Inventaire.ajouter_lot(prises)
	if not prises.is_empty():
		_annonce_pris(prises)
	_rafraichir()

# emporte le reste d'un coffre d'inventaire sans annonce
func _virer_source_dans_inventaire(source: Dictionary) -> void:
	Inventaire.ajouter_lot(Coffres.vider(source["coffre_id"]))

func _annonce_texte(texte: String, couleur: Color) -> void:
	popup.text = texte
	popup.add_theme_color_override("font_color", couleur)
	popup.modulate.a = 1.0
	if _tween_popup != null and _tween_popup.is_valid():
		_tween_popup.kill()
	_tween_popup = create_tween()
	_tween_popup.tween_interval(1.2)
	_tween_popup.tween_property(popup, "modulate:a", 0.0, 0.5)

func _annonce_pris(prises: Array) -> void:
	var noms := []
	var couleurs := []
	for prise in prises:
		var id := str(prise["id"])
		noms.append("%s x%d" % [Inventaire.nom_objet(id), int(prise["qte"])])
		couleurs.append(Inventaire.details_objet(id)["couleur_rarete"])
	var noms_texte := PackedStringArray()
	for nom in noms:
		noms_texte.append(nom)
	if noms_texte.size() > 3:
		popup.text = "Pris : %d objets" % noms_texte.size()
	else:
		popup.text = "Pris : " + " ; ".join(noms_texte)
	popup.add_theme_color_override("font_color", couleurs[couleurs.size() - 1])
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
