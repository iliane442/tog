# menu.gd — sur le CanvasLayer MenuUI
# Barre de raccourcis en bas de l'écran (style Dofus) :
# Menu, Personnage, Sorts, Quêtes, Inventaire.
# Échap ou M ouvre et referme aussi l'interface.
extends CanvasLayer

var section_actuelle: String = ""
# répartition en cours, pas encore validée (cle -> points en attente)
var points_en_attente: Dictionary = {}

@onready var fenetre: Panel = $Fenetre
@onready var btn_menu: Button = $BoutonMenu
@onready var barre_cascade: HBoxContainer = $BarreCascade
@onready var titre: Label = $Fenetre/Entete/Titre
@onready var grille: GridContainer = $Fenetre/Corps/ContenuInventaire/DefilementInventaire/Grille
@onready var label_vide: Label = $Fenetre/Corps/ContenuInventaire/Vide
@onready var liste_quetes: VBoxContainer = $Fenetre/Corps/ContenuQuetes/DefilementQuetes/ListeQuetes
@onready var label_aucune_quete: Label = $Fenetre/Corps/ContenuQuetes/Aucune
@onready var liste_sorts: VBoxContainer = $Fenetre/Corps/ContenuSorts/DefilementSorts/ListeSorts
@onready var label_nom: Label = $Fenetre/Corps/ContenuPersonnage/Nom
@onready var label_race_classe: Label = $Fenetre/Corps/ContenuPersonnage/RaceClasse
@onready var label_niveau: Label = $Fenetre/Corps/ContenuPersonnage/Niveau
@onready var label_xp: Label = $Fenetre/Corps/ContenuPersonnage/XP
@onready var label_vie: Label = $Fenetre/Corps/ContenuPersonnage/Vie
@onready var label_argent: Label = $Fenetre/Corps/ContenuPersonnage/Argent
@onready var label_points: Label = $Fenetre/Corps/ContenuPersonnage/Points
@onready var btn_valider: Button = $Fenetre/Corps/ContenuPersonnage/ActionsStats/BtnValider
@onready var btn_reinitialiser: Button = $Fenetre/Corps/ContenuPersonnage/ActionsStats/BtnReinitialiser
@onready var btn_effacer_perso: Button = $Fenetre/Corps/ContenuPersonnage/ActionsStats/BtnEffacerPerso
@onready var grille_stats: GridContainer = $Fenetre/Corps/ContenuPersonnage/StatsGrid
@onready var contenus := {
	"personnage": $Fenetre/Corps/ContenuPersonnage,
	"sorts": $Fenetre/Corps/ContenuSorts,
	"quetes": $Fenetre/Corps/ContenuQuetes,
	"inventaire": $Fenetre/Corps/ContenuInventaire,
}
@onready var noms_sections := {
	"personnage": "Personnage",
	"sorts": "Sorts",
	"quetes": "Quêtes",
	"inventaire": "Inventaire",
}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	fenetre.visible = false
	$Fenetre/Entete/Fermer.pressed.connect(fermer)
	btn_valider.pressed.connect(_on_valider_points)
	btn_reinitialiser.pressed.connect(_on_reinitialiser_points)
	btn_effacer_perso.pressed.connect(_on_effacer_perso)
	btn_menu.pressed.connect(_on_bouton_menu)
	$BarreCascade/Personnage.pressed.connect(ouvrir.bind("personnage"))
	$BarreCascade/Sorts.pressed.connect(ouvrir.bind("sorts"))
	$BarreCascade/Quetes.pressed.connect(ouvrir.bind("quetes"))
	$BarreCascade/Inventaire.pressed.connect(ouvrir.bind("inventaire"))
	Inventaire.inventaire_modifie.connect(maj_grille)
	QuestManager.quete_acceptee.connect(maj_quetes)
	QuestManager.quete_progressee.connect(maj_quetes)
	QuestManager.quete_abandonnee.connect(maj_quetes)
	QuestManager.quete_terminee.connect(maj_quetes)
	Personnage.caracteristiques_modifiees.connect(maj_personnage)

func _process(_delta: float) -> void:
	# referme la fenêtre si un dialogue met le jeu en pause
	if get_tree().paused and fenetre.visible:
		fermer()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and (event.keycode == KEY_ESCAPE or event.keycode == KEY_M):
		if fenetre.visible:
			fermer()
		elif not get_tree().paused:
			ouvrir()
		else:
			return  # un dialogue est ouvert : laisser Échap à DialogueUI
		get_viewport().set_input_as_handled()

func _on_bouton_menu() -> void:
	barre_cascade.visible = not barre_cascade.visible
	if barre_cascade.visible:
		barre_cascade.modulate.a = 0.0
		var fondu := create_tween()
		fondu.tween_property(barre_cascade, "modulate:a", 1.0, 0.15)

func ouvrir(section: String = "") -> void:
	if get_tree().paused:
		return
	if section != "":
		section_actuelle = section
	elif section_actuelle == "":
		section_actuelle = "personnage"
	fenetre.visible = true
	maj_section()

func fermer() -> void:
	# les points non validés sont abandonnés à la fermeture
	points_en_attente = {}
	fenetre.visible = false

func maj_section() -> void:
	for section in contenus:
		contenus[section].visible = section == section_actuelle
	titre.text = noms_sections[section_actuelle]
	match section_actuelle:
		"personnage":
			maj_personnage()
		"sorts":
			maj_sorts()
		"quetes":
			maj_quetes()
		"inventaire":
			maj_grille()

func maj_personnage() -> void:
	var libelles: Dictionary = {
		"vitalite": "Vitalité",
		"sagesse": "Sagesse",
		"force": "Force",
		"intelligence": "Intelligence",
		"chance": "Chance",
		"agilite": "Agilité",
	}
	var en_attente := _total_points_en_attente()
	var restants := maxi(Personnage.points_statistique - en_attente, 0)
	label_nom.text = Personnage.nom
	label_race_classe.text = "Race : %s — Classe : %s" % [Personnage.nom_race(), Personnage.nom_classe()]
	label_niveau.text = "Niveau %d" % Personnage.niveau
	label_xp.text = "Expérience : %d / %d" % [Personnage.xp, Personnage.xp_prochain_niveau()]
	var vie_max_affichee: int = Personnage.vie_max + 5 * int(points_en_attente.get("vitalite", 0))
	label_vie.text = "Vie : %d / %d" % [Personnage.vie, vie_max_affichee]
	label_argent.text = "Berry : %d" % Personnage.berry
	label_points.text = "Points à répartir : %d" % restants
	if en_attente > 0:
		label_points.text += "  (non validés : %d)" % en_attente
	btn_valider.disabled = en_attente == 0
	btn_reinitialiser.disabled = en_attente == 0
	for enfant in grille_stats.get_children():
		enfant.queue_free()
	for entree in [["Vie max", vie_max_affichee], ["Attaque", Personnage.attaque], ["Défense", Personnage.defense]]:
		var etiquette := Label.new()
		etiquette.text = entree[0]
		var valeur_fixe := Label.new()
		valeur_fixe.text = str(entree[1])
		grille_stats.add_child(etiquette)
		grille_stats.add_child(valeur_fixe)
		grille_stats.add_child(Control.new())  # colonne vide pour l'alignement
	for cle in Personnage.caracteristiques:
		var nom := Label.new()
		nom.text = libelles.get(cle, cle)
		var valeur := Label.new()
		valeur.text = str(Personnage.caracteristiques[cle] + int(points_en_attente.get(cle, 0)))
		var btn_augmenter := Button.new()
		btn_augmenter.text = "+"
		btn_augmenter.disabled = restants <= 0
		btn_augmenter.pressed.connect(_on_augmenter_stat.bind(cle))
		grille_stats.add_child(nom)
		grille_stats.add_child(valeur)
		grille_stats.add_child(btn_augmenter)

func _total_points_en_attente() -> int:
	var total := 0
	for cle in points_en_attente:
		total += int(points_en_attente[cle])
	return total

func _on_augmenter_stat(cle: String) -> void:
	if _total_points_en_attente() >= Personnage.points_statistique:
		return
	points_en_attente[cle] = int(points_en_attente.get(cle, 0)) + 1
	maj_personnage()

func _on_valider_points() -> void:
	if _total_points_en_attente() == 0:
		return
	var repartition := points_en_attente
	points_en_attente = {}
	Personnage.appliquer_points(repartition)

func _on_reinitialiser_points() -> void:
	points_en_attente = {}
	maj_personnage()

# debug : efface le perso (fichier + mémoire), remet quêtes et inventaire
# à zéro, puis recharge la map — l'écran de création réapparaît
func _on_effacer_perso() -> void:
	Personnage.supprimer_perso()
	QuestManager.reinitialiser()
	Inventaire.reinitialiser()
	get_tree().reload_current_scene()

func maj_sorts() -> void:
	for enfant in liste_sorts.get_children():
		enfant.queue_free()
	for id in Personnage.sorts:
		var sort: Dictionary = Personnage.sorts[id]
		var encadre := PanelContainer.new()
		var boite := VBoxContainer.new()
		var nom := Label.new()
		nom.text = sort.nom
		nom.add_theme_font_size_override("font_size", 22)
		var infos := Label.new()
		var texte_infos := "Type : %s — Portée : %d — Recharge : %d" % [
			sort.get("type", "—"), int(sort.get("portee", 0)), int(sort.get("recharge", 0)),
		]
		if int(sort.get("degats", 0)) > 0:
			texte_infos += " — Dégâts : %d" % int(sort["degats"])
		infos.text = texte_infos
		var description := Label.new()
		description.text = sort.description
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		boite.add_child(nom)
		boite.add_child(infos)
		boite.add_child(description)
		encadre.add_child(boite)
		liste_sorts.add_child(encadre)

func maj_quetes(_quest_id: String = "") -> void:
	for enfant in liste_quetes.get_children():
		enfant.queue_free()
	# les quêtes terminées ne s'affichent plus
	var visibles: Array = []
	for id in QuestManager.quetes_actives:
		if not QuestManager.est_terminee(id):
			visibles.append(id)
	label_aucune_quete.visible = visibles.is_empty()
	for id in visibles:
		var quest: Dictionary = QuestManager.get_quest(id)
		var encadre := PanelContainer.new()
		var boite := VBoxContainer.new()
		var titre_quete := Label.new()
		titre_quete.text = quest.titre
		titre_quete.add_theme_font_size_override("font_size", 20)
		var description := Label.new()
		description.text = quest.description
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var progression := Label.new()
		progression.text = "Progression : %d / %d" % [QuestManager.quetes_actives[id], quest.objectif]
		var btn_terminer := Button.new()
		btn_terminer.text = "Terminer (debug)"
		btn_terminer.pressed.connect(_on_terminer_quete.bind(id))
		var btn_abandonner := Button.new()
		btn_abandonner.text = "Abandonner"
		btn_abandonner.pressed.connect(_on_abandonner_quete.bind(id))
		boite.add_child(titre_quete)
		boite.add_child(description)
		boite.add_child(progression)
		boite.add_child(btn_terminer)
		boite.add_child(btn_abandonner)
		encadre.add_child(boite)
		liste_quetes.add_child(encadre)

func _on_terminer_quete(id: String) -> void:
	QuestManager.terminer_quete(id)

func _on_abandonner_quete(id: String) -> void:
	QuestManager.abandonner_quete(id)

func maj_grille() -> void:
	for enfant in grille.get_children():
		enfant.queue_free()
	label_vide.visible = Inventaire.objets.is_empty()
	for id in Inventaire.objets:
		var slot := PanelContainer.new()
		var boite := VBoxContainer.new()
		var nom := Label.new()
		nom.text = Inventaire.nom_objet(id)
		nom.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var quantite := Label.new()
		quantite.text = "x%d" % Inventaire.objets[id]
		quantite.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		boite.add_child(nom)
		boite.add_child(quantite)
		slot.add_child(boite)
		slot.custom_minimum_size = Vector2(170, 90)
		grille.add_child(slot)
