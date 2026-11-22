extends Control

signal combat_demande(pair: int)
signal groupe_quitte
signal invitation_repondue(acceptee: bool)
signal combat_accepte
signal combat_ignore

const FOND := Color("#142433")
const FOND_RANGEES := Color("#203549")
const BORDURE := Color("#577484")
const CADRE := Color("#b98f57")
const TEXTE := Color("#fff3db")
const TEXTE_SECONDAIRE := Color("#b7cedb")
const ALLIE := Color("#8de8e5")
const COMBAT := Color("#ffd386")

var _panneau: PanelContainer
var _compteur: Label
var _membres: VBoxContainer
var _boutons_rejoindre: Array[Button] = []
var _invite_groupe: PanelContainer
var _invite_combat: PanelContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_creer_panneau()
	var invitations := VBoxContainer.new()
	add_child(invitations)
	invitations.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	invitations.offset_left = -230
	invitations.offset_right = 230
	invitations.offset_top = 84
	invitations.add_theme_constant_override("separation", 10)
	invitations.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_invite_combat = _creer_invitation(invitations, "Combat à rejoindre", COMBAT,
		"Rejoindre le combat", "Ignorer", combat_accepte.emit, combat_ignore.emit)
	_invite_groupe = _creer_invitation(invitations, "Invitation de groupe", ALLIE,
		"Accepter", "Refuser", invitation_repondue.emit.bind(true), invitation_repondue.emit.bind(false))

func _creer_panneau() -> void:
	_panneau = PanelContainer.new()
	_panneau.name = "PanneauGroupe"
	_panneau.position = Vector2(20, 158)
	_panneau.custom_minimum_size.x = 390
	var cadre := _style(FOND, CADRE, 12, 12)
	cadre.set_border_width_all(2)
	_panneau.add_theme_stylebox_override("panel", cadre)
	add_child(_panneau)
	var colonne := VBoxContainer.new()
	colonne.add_theme_constant_override("separation", 8)
	_panneau.add_child(colonne)
	var entete := HBoxContainer.new()
	entete.add_theme_constant_override("separation", 10)
	colonne.add_child(entete)
	var titre := _etiquette("Groupe", TEXTE, 27)
	titre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entete.add_child(titre)
	_compteur = _etiquette("", ALLIE, 18)
	_compteur.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	entete.add_child(_compteur)
	var quitter := _bouton("Quitter")
	quitter.tooltip_text = "Quitter le groupe"
	quitter.pressed.connect(groupe_quitte.emit)
	entete.add_child(quitter)
	_membres = VBoxContainer.new()
	_membres.add_theme_constant_override("separation", 5)
	colonne.add_child(_membres)
	_panneau.hide()

func afficher_membres(membres: Array, id_local: int, limite: int, peut_rejoindre: bool) -> void:
	for enfant in _membres.get_children():
		_membres.remove_child(enfant)
		enfant.queue_free()
	_boutons_rejoindre.clear()
	_panneau.visible = not membres.is_empty()
	if membres.is_empty():
		return
	_compteur.text = "%d / %d" % [membres.size(), limite]
	for membre: Dictionary in membres:
		_ajouter_membre(membre, id_local)
	actualiser_actions_combat(peut_rejoindre)
	_panneau.reset_size()

func _ajouter_membre(membre: Dictionary, id_local: int) -> void:
	var pair := int(membre.get("peer", 0))
	var local := pair == id_local
	var chef := bool(membre.get("chef", false))
	var combat := bool(membre.get("combat", false))
	var nom := str(membre.get("pseudo", "?"))
	var accent := COMBAT if combat else (ALLIE if local else BORDURE)
	var cadre := PanelContainer.new()
	cadre.add_theme_stylebox_override("panel", _style(FOND_RANGEES, accent, 9, 5))
	_membres.add_child(cadre)
	var ligne := HBoxContainer.new()
	ligne.add_theme_constant_override("separation", 8)
	cadre.add_child(ligne)
	var infos := VBoxContainer.new()
	infos.add_theme_constant_override("separation", 1)
	infos.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ligne.add_child(infos)
	var titre := _etiquette(nom, TEXTE, 22)
	titre.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	infos.add_child(titre)
	var statut := PackedStringArray()
	if chef:
		statut.append("Chef")
	if local:
		statut.append("Vous")
	statut.append("En combat" if combat else "En exploration")
	infos.add_child(_etiquette(" · ".join(statut), COMBAT if combat else TEXTE_SECONDAIRE, 17))
	cadre.tooltip_text = nom
	if combat and not local:
		var rejoindre := _bouton("Rejoindre", COMBAT)
		rejoindre.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rejoindre.tooltip_text = "Rejoindre le combat de %s" % nom
		rejoindre.pressed.connect(combat_demande.emit.bind(pair))
		ligne.add_child(rejoindre)
		_boutons_rejoindre.append(rejoindre)

func actualiser_actions_combat(peut_rejoindre: bool) -> void:
	for bouton in _boutons_rejoindre:
		bouton.disabled = not peut_rejoindre

func montrer_invite_groupe(nom: String) -> void:
	_montrer_invitation(_invite_groupe, "%s t'invite dans son groupe." % nom)

func montrer_invite_combat(nom: String) -> void:
	_montrer_invitation(_invite_combat, "%s a engagé un combat." % nom)

func cacher_invite_groupe() -> void:
	_invite_groupe.hide()

func cacher_invite_combat() -> void:
	_invite_combat.hide()

func _montrer_invitation(panneau: PanelContainer, texte: String) -> void:
	var message: Label = panneau.get_node("Contenu/Message")
	message.text = texte
	panneau.show()

func _creer_invitation(parent: VBoxContainer, titre: String, accent: Color,
		action: String, annulation: String, confirmer: Callable, annuler: Callable) -> PanelContainer:
	var panneau := PanelContainer.new()
	panneau.add_theme_stylebox_override("panel", _style(FOND, accent, 14, 10))
	parent.add_child(panneau)
	var contenu := VBoxContainer.new()
	contenu.name = "Contenu"
	contenu.add_theme_constant_override("separation", 6)
	panneau.add_child(contenu)
	contenu.add_child(_etiquette(titre, accent, 23))
	var message := _etiquette("", TEXTE, 19)
	message.name = "Message"
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	contenu.add_child(message)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	contenu.add_child(actions)
	var principal := _bouton(action, accent)
	principal.pressed.connect(confirmer)
	actions.add_child(principal)
	var secondaire := _bouton(annulation)
	secondaire.pressed.connect(annuler)
	actions.add_child(secondaire)
	panneau.hide()
	return panneau

func _etiquette(texte: String, couleur: Color, taille: int) -> Label:
	var etiquette := Label.new()
	etiquette.text = texte
	etiquette.add_theme_color_override("font_color", couleur)
	etiquette.add_theme_font_size_override("font_size", taille)
	return etiquette

func _bouton(texte: String, accent: Color = Color.TRANSPARENT) -> Button:
	var bouton := Button.new()
	bouton.text = texte
	bouton.custom_minimum_size.y = 33
	bouton.add_theme_font_size_override("font_size", 18)
	var principal := accent.a > 0.0
	var fond := accent if principal else FOND_RANGEES
	var bord := accent if principal else BORDURE
	var couleur := FOND if principal else TEXTE
	bouton.add_theme_stylebox_override("normal", _style(fond, bord, 10, 4))
	bouton.add_theme_stylebox_override("hover", _style(fond.lightened(0.17), TEXTE, 10, 4))
	bouton.add_theme_stylebox_override("pressed", _style(fond.darkened(0.1), TEXTE, 10, 4))
	bouton.add_theme_stylebox_override("disabled", _style(FOND, BORDURE, 10, 4))
	bouton.add_theme_color_override("font_color", couleur)
	bouton.add_theme_color_override("font_hover_color", couleur)
	bouton.add_theme_color_override("font_pressed_color", couleur)
	bouton.add_theme_color_override("font_focus_color", couleur)
	bouton.add_theme_color_override("font_disabled_color", TEXTE_SECONDAIRE)
	return bouton

func _style(fond: Color, bordure: Color, marge_x: int, marge_y: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fond
	style.border_color = bordure
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	style.content_margin_left = marge_x
	style.content_margin_right = marge_x
	style.content_margin_top = marge_y
	style.content_margin_bottom = marge_y
	return style
