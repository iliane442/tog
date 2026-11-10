# creation_perso.gd — interface de création de personnage (premier lancement)
extends CanvasLayer

@onready var liste_races: ItemList = $Panneau/VBoxContainer/Corps/VBoxRace/ListeRaces
@onready var liste_classes: ItemList = $Panneau/VBoxContainer/Corps/VBoxClasse/ListeClasses
@onready var label_details_race: Label = $Panneau/VBoxContainer/Corps/VBoxRace/LabelDetailsRace
@onready var label_details_classe: Label = $Panneau/VBoxContainer/Corps/VBoxClasse/LabelDetailsClasse
@onready var label_resume: Label = $Panneau/VBoxContainer/Corps/VBoxDetails/LabelResume
@onready var champ_nom: LineEdit = $Panneau/VBoxContainer/ZoneBas/LigneNom/ChampNom
@onready var btn_commencer: Button = $Panneau/VBoxContainer/ZoneBas/BtnCommencer
@onready var label_erreur: Label = $Panneau/VBoxContainer/ZoneBas/LabelErreur

var ids_races: Array = []
var ids_classes: Array = []
var index_race := 0
var index_classe := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if Personnage.perso_cree:
		# personnage déjà créé : l'interface ne s'affiche pas
		queue_free()
		return
	get_tree().paused = true
	btn_commencer.pressed.connect(_on_commencer)
	liste_races.item_selected.connect(_on_race_choisie)
	liste_classes.item_selected.connect(_on_classe_choisie)
	champ_nom.text_changed.connect(func(_texte: String): _maj_affichage())
	_peupler()
	_maj_affichage()

func _peupler() -> void:
	var cles_races := Personnage.races.keys()
	cles_races.sort_custom(func(a, b): return a.to_int() < b.to_int())
	for id in cles_races:
		ids_races.append(id)
		liste_races.add_item(Personnage.races[id]["nom"])
	var cles_classes := Personnage.classes.keys()
	cles_classes.sort_custom(func(a, b): return a.to_int() < b.to_int())
	for id in cles_classes:
		ids_classes.append(id)
		liste_classes.add_item(Personnage.classes[id]["nom"])
	liste_races.select(0)
	liste_classes.select(0)

func _race_selectionnee() -> Dictionary:
	if ids_races.is_empty():
		return {}
	return Personnage.races[ids_races[index_race]]

func _classe_selectionnee() -> Dictionary:
	if ids_classes.is_empty():
		return {}
	return Personnage.classes[ids_classes[index_classe]]

func _texte_bonus(donnees: Dictionary) -> String:
	var libelles: Dictionary = {
		"vie": "Vie", "attaque": "Attaque", "defense": "Défense", "vitesse": "Vitesse",
		"force": "Force", "intelligence": "Intelligence", "agilite": "Agilité",
		"vitalite": "Vitalité", "sagesse": "Sagesse", "chance": "Chance",
	}
	var fragments: Array[String] = []
	for cle in libelles:
		var valeur := int(donnees.get(cle, 0))
		if valeur != 0:
			fragments.append("%s %+d" % [libelles[cle], valeur])
	return " ; ".join(PackedStringArray(fragments))

func _texte_sorts(classe: Dictionary) -> String:
	var noms: Array[String] = []
	for id_sort in classe.get("sorts_initiaux", []):
		var sort: Dictionary = Personnage.sorts.get(str(id_sort), {})
		noms.append(str(sort.get("nom", id_sort)))
	return " ; ".join(PackedStringArray(noms))

func _on_race_choisie(index: int) -> void:
	index_race = index
	_maj_affichage()

func _on_classe_choisie(index: int) -> void:
	index_classe = index
	_maj_affichage()

func _maj_affichage() -> void:
	var race := _race_selectionnee()
	var classe := _classe_selectionnee()
	var bonus_race := _texte_bonus(race)
	if bonus_race != "":
		bonus_race = "\n\n" + bonus_race
	label_details_race.text = "%s\n%s%s" % [
		race.get("nom", "—"), race.get("description", ""), bonus_race,
	]
	var sorts_txt := _texte_sorts(classe)
	if sorts_txt != "":
		sorts_txt = "\n\nSorts de départ : %s" % sorts_txt
	var bonus_classe := _texte_bonus(classe)
	if bonus_classe != "":
		bonus_classe = "\n\n" + bonus_classe
	label_details_classe.text = "%s\n%s%s%s" % [
		classe.get("nom", "—"), classe.get("description", ""), bonus_classe, sorts_txt,
	]
	var nouveau_nom := champ_nom.text.strip_edges()
	var resume: String = "Nom : %s" % (nouveau_nom if nouveau_nom != "" else "—")
	resume += "\nRace : %s" % race.get("nom", "—")
	resume += "\nClasse : %s" % classe.get("nom", "—")
	var stats: Array[String] = []
	for cle in ["vie", "attaque", "defense", "vitesse", "force", "intelligence", "agilite", "vitalite", "sagesse", "chance"]:
		var total := int(race.get(cle, 0)) + int(classe.get(cle, 0))
		if total != 0:
			stats.append("%s %+d" % [cle, total])
	if not stats.is_empty():
		resume += "\n\nSuppléments : " + " ; ".join(PackedStringArray(stats))
	resume += "\n\nVie de départ : %d" % maxi(100 + int(race.get("vie", 0)) + int(classe.get("vie", 0)), 1)
	label_resume.text = resume

func _on_commencer() -> void:
	var nouveau_nom := champ_nom.text.strip_edges()
	if ids_races.is_empty() or ids_classes.is_empty():
		label_erreur.text = "Aucune race ou classe disponible (base de données absente ?)"
		return
	if nouveau_nom == "":
		label_erreur.text = "Choisissez un nom pour votre personnage."
		return
	Personnage.creer(nouveau_nom, ids_races[index_race], ids_classes[index_classe])
	get_tree().paused = false
	queue_free()
