# creation_perso.gd — interface de création de personnage (premier lancement)
extends CanvasLayer

@onready var liste_races: ItemList = $Panneau/VBoxContainer/Corps/VBoxRace/ListeRaces
@onready var liste_classes: ItemList = $Panneau/VBoxContainer/Corps/VBoxClasse/ListeClasses
@onready var label_details: Label = $Panneau/VBoxContainer/Corps/VBoxDetails/ScrollDescriptions/LabelDescriptions
@onready var label_resume: Label = $Panneau/VBoxContainer/ZoneBas/LabelResume
@onready var champ_nom: LineEdit = $Panneau/VBoxContainer/ZoneBas/LigneNom/ChampNom
@onready var option_sexe: OptionButton = $Panneau/VBoxContainer/ZoneBas/LigneSexe/OptionSexe
@onready var btn_commencer: Button = $Panneau/VBoxContainer/ZoneBas/BtnCommencer
@onready var label_erreur: Label = $Panneau/VBoxContainer/ZoneBas/LabelErreur

var ids_races: Array = []
var ids_classes: Array = []
var index_race := 0
var index_classe := 0

# seul choix de personnalisation à la création : le sexe
# (l'apparence dépendra ensuite de l'équipement porté)
const LIBELLES_SEXES: Array[String] = ["Masculin", "Féminin"]
const VALEURS_SEXES: Array[String] = ["M", "F"]

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
	option_sexe.item_selected.connect(func(_i): _maj_affichage())
	champ_nom.text_changed.connect(func(_texte: String): _maj_affichage())
	_peupler()
	for libelle in LIBELLES_SEXES:
		option_sexe.add_item(libelle)
	option_sexe.select(0)
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

# métier lié à la classe choisie (table character_class_professions) — la
# classe détermine le métier, aucun choix séparé n'est proposé
func _metier_de_la_classe() -> String:
	if ids_classes.is_empty():
		return ""
	var professions := Personnage.professions_pour_classe(ids_classes[index_classe])
	if professions.is_empty():
		return ""
	return str(professions[0])

func _sexe_choisi() -> String:
	return VALEURS_SEXES[option_sexe.selected]

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
	var bloc_race := "Race : %s\n%s" % [race.get("nom", "—"), race.get("description", "")]
	var bonus_race := _texte_bonus(race)
	if bonus_race != "":
		bloc_race += "\n\n" + bonus_race
	var bloc_classe := "Classe : %s\n%s" % [classe.get("nom", "—"), classe.get("description", "")]
	var bonus_classe := _texte_bonus(classe)
	if bonus_classe != "":
		bloc_classe += "\n\n" + bonus_classe
	var sorts_txt := _texte_sorts(classe)
	if sorts_txt != "":
		bloc_classe += "\n\nSorts de départ : %s" % sorts_txt
	label_details.text = bloc_race + "\n\n" + bloc_classe

	var nouveau_nom := champ_nom.text.strip_edges()
	var resume: String = "Nom : %s — Race : %s — Classe : %s — Sexe : %s" % [
		(nouveau_nom if nouveau_nom != "" else "—"),
		race.get("nom", "—"), classe.get("nom", "—"),
		LIBELLES_SEXES[option_sexe.selected],
	]
	var nom_metier := "—"
	var id_metier := _metier_de_la_classe()
	if id_metier != "" and Personnage.professions().has(id_metier):
		nom_metier = str(Personnage.professions()[id_metier]["nom"])
	resume += " — Métier : %s" % nom_metier
	var stats: Array[String] = []
	for cle in ["vie", "attaque", "defense", "vitesse", "force", "intelligence", "agilite", "vitalite", "sagesse", "chance"]:
		var total := int(race.get(cle, 0)) + int(classe.get(cle, 0))
		if total != 0:
			stats.append("%s %+d" % [cle, total])
	if not stats.is_empty():
		resume += " — Suppléments : " + " ; ".join(PackedStringArray(stats))
	resume += " — Vie de départ : %d" % maxi(100 + int(race.get("vie", 0)) + int(classe.get("vie", 0)), 1)
	label_resume.text = resume

func _on_commencer() -> void:
	var nouveau_nom := champ_nom.text.strip_edges()
	if ids_races.is_empty() or ids_classes.is_empty():
		label_erreur.text = "Aucune race ou classe disponible (base de données absente ?)"
		return
	if nouveau_nom == "":
		label_erreur.text = "Choisissez un nom pour votre personnage."
		return
	var id_metier := _metier_de_la_classe()
	if id_metier == "":
		label_erreur.text = "Aucun métier lié à cette classe."
		return
	Personnage.creer(nouveau_nom, ids_races[index_race], ids_classes[index_classe], id_metier, _sexe_choisi())
	_donner_ingredients_debug(id_metier)
	get_tree().paused = false
	queue_free()

# debug : donne au nouveau personnage les ingrédients pour fabriquer les
# DEBUG_NB_RECETTES premières recettes actives de son métier,
# DEBUG_FABRICATIONS fois chacune
const DEBUG_NB_RECETTES := 3
const DEBUG_FABRICATIONS := 10

func _donner_ingredients_debug(id_profession: String) -> void:
	if not BaseDonnees.disponible:
		return
	var condition := "is_active = 1"
	if id_profession != "":
		condition += " AND profession_id = %d" % int(id_profession)
	var besoins: Dictionary = {}
	for ligne in BaseDonnees.lire(
		"SELECT result_item_id FROM crafts WHERE " + condition
		+ " ORDER BY id LIMIT %d;" % DEBUG_NB_RECETTES):
		for ing in BaseDonnees.lire(
			"SELECT ingredient_id, quantity FROM item_craft_ingredients"
			+ " WHERE item_id = %d;" % int(ligne["result_item_id"])):
			var id := str(ing["ingredient_id"])
			besoins[id] = int(besoins.get(id, 0)) + int(ing["quantity"]) * DEBUG_FABRICATIONS
	for id in besoins:
		Inventaire.ajouter_objet(id, int(besoins[id]))
