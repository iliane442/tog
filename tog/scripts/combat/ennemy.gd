@tool
extends CharacterBody2D

signal sante_modifiee(vie: int, vie_max: int)
signal vaincu

@export var pv_max := 100
@export var nom := "Loup pirate"
@export var degats_attaque := 10
@export var portee_attaque := 2
@export var pm_max := 3
# mob correspondant dans la table `mobs` (0 = aucun : récompenses
# estimées à partir des stats de l'ennemi)
@export var mob_id := 0
@export var quetes_a_progresser: Array[String] = ["1"]
@export var texture_personnalisee: Texture2D
@export var niveau_personnalise := 1
# étiquette de rencontre : vide = combat individuel, sinon détecter
# n'importe quel membre engage tous les ennemis de même étiquette
@export var groupe := ""

const ID_ETAT_TEST := 5 # Ralentissement
const DUREE_ETAT_TEST := 2

var pv := 100
var _combat_manager

@onready var zone_detection: Area2D = $ZoneDetection
@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	pv = pv_max
	if Engine.is_editor_hint():
		# dans l'éditeur : juste le visuel (le loup par défaut sinon),
		# pas de combat ni d'étiquette (pour ne pas polluer la scène)
		_charger_visuel_mob()
		return
	_combat_manager = get_tree().current_scene.get_node_or_null("CombatManager")
	zone_detection.body_entered.connect(_on_zone_body_entered)
	zone_detection.body_exited.connect(_on_zone_body_exited)
	if _combat_manager != null:
		_combat_manager.enregistrer_ennemi(self)
	_charger_visuel_mob()
	sante_modifiee.emit(pv, pv_max)

# données visuelles du mob : sprite statique (colonne sprite_path, le loup
# par défaut si absent) et étiquette nom + niveau au-dessus du sprite
var _sprites_introuvables: Dictionary = {}  # chemin -> true (avertit une fois)

func _charger_visuel_mob() -> void:
	if texture_personnalisee != null:
		sprite.texture = texture_personnalisee
		sprite.position.y = -texture_personnalisee.get_height() / 2.0
		if not Engine.is_editor_hint():
			_ajouter_etiquette(nom, niveau_personnalise)
		return
	if mob_id <= 0 or not BaseDonnees.disponible:
		return
	var lignes := BaseDonnees.lire(
		"SELECT name, level, sprite_path FROM mobs WHERE id = %d AND is_active = 1;" % mob_id)
	if lignes.is_empty():
		return
	var ligne: Dictionary = lignes[0]
	_appliquer_sprite(str(ligne.get("sprite_path", "")))
	if not Engine.is_editor_hint():
		_ajouter_etiquette(str(ligne.get("name", "")), int(ligne.get("level", 1)))

func _appliquer_sprite(chemin: String) -> void:
	if chemin == "":
		return
	var chemin_res := chemin if chemin.begins_with("res://") else "res://" + chemin
	if not ResourceLoader.exists(chemin_res):
		# le sprite n'a pas encore été posé : on garde le loup et on
		# prévient une seule fois (par chemin) dans la console
		if not _sprites_introuvables.has(chemin_res):
			_sprites_introuvables[chemin_res] = true
			push_warning("Sprite du mob %d introuvable : %s — loup affiché à la place" % [mob_id, chemin_res])
		return
	sprite.texture = load(chemin_res)
	# les personnages (cellule 96 px, comme le joueur) se calent comme lui ;
	# le loup par défaut garde son décalage d'origine
	if sprite.texture.get_height() != 100:
		sprite.position = Vector2(0, -24)

# étiquette flottante au-dessus de l'ennemi : « Nom (Niv. X) »
func _ajouter_etiquette(nom_mob: String, niveau_mob: int) -> void:
	var etiquette := Label.new()
	etiquette.name = "EtiquetteMob"
	etiquette.text = "%s (Niv. %d)" % [nom_mob, niveau_mob]
	etiquette.z_index = 20
	etiquette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	etiquette.add_theme_font_size_override("font_size", 13)
	etiquette.add_theme_color_override("font_color", Color.WHITE)
	etiquette.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	etiquette.add_theme_constant_override("outline_size", 6)
	etiquette.custom_minimum_size = Vector2(150, 0)
	etiquette.size = Vector2(150, 0)
	etiquette.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var hauteur: float = 100.0
	if sprite.texture != null:
		hauteur = float(sprite.texture.get_height())
	etiquette.position = Vector2(-75, sprite.position.y - hauteur / 2.0 - 22.0)
	add_child(etiquette)

func _on_zone_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and _combat_manager != null:
		_combat_manager.proposer_combat(self)

func _on_zone_body_exited(body: Node2D) -> void:
	if body.is_in_group("player") and _combat_manager != null:
		_combat_manager.annuler_proposition_combat(self)

func recevoir_degats(degats: int) -> void:
	if pv <= 0:
		return
	pv = maxi(pv - maxi(degats, 0), 0)
	sante_modifiee.emit(pv, pv_max)
	if pv > 0:
		return
	for quest_id in quetes_a_progresser:
		if QuestManager.quetes_actives.has(quest_id):
			QuestManager.progresser(quest_id)
	recompenser_victoire()
	if _combat_manager != null:
		_combat_manager.ennemi_vaincu(self)
	vaincu.emit()
	# monde partagé : la rencontre disparaît aussi pour les autres
	# joueurs de la même map jusqu'à ce que le serveur la fasse
	# réapparaître (résolu au runtime : Reseau n'existe pas dans
	# l'éditeur et ennemy.gd est @tool)
	var reseau := get_tree().root.get_node_or_null("/root/Reseau")
	if reseau != null:
		reseau.call("signaler_rencontre_vaincue", self)
	queue_free()

func soigner(montant: int) -> void:
	pv = mini(pv + maxi(montant, 0), pv_max)
	sante_modifiee.emit(pv, pv_max)

func jouer_tour(joueur: CharacterBody2D, sol: TileMapLayer) -> void:
	if not is_instance_valid(joueur) or sol == null:
		return
	if _combat_manager != null and _combat_manager.preparer_tour(self):
		_combat_manager.afficher_message("L’ennemi perd son tour.")
		_combat_manager.terminer_tour(self)
		return
	if not is_inside_tree():
		return
	var depart := _case_de(sol, global_position)
	var cible := _case_de(sol, joueur.global_position)
	var distance := absi(depart.x - cible.x) + absi(depart.y - cible.y)
	if distance > portee_attaque:
		var chemin := _calculer_chemin(sol, depart, cible)
		var pm: int = int(_combat_manager.points_mouvement(self, pm_max)) if _combat_manager != null else pm_max
		var pas := mini(pm, chemin.size())
		for index in range(pas):
			var position_cible := sol.to_global(sol.map_to_local(chemin[index]))
			var tween := create_tween()
			tween.tween_property(self, "global_position", position_cible, 0.2)
			await tween.finished
			if not is_inside_tree():
				return
		depart = _case_de(sol, global_position)
		distance = absi(depart.x - cible.x) + absi(depart.y - cible.y)
	if distance <= portee_attaque:
		_appliquer_ralentissement_test(joueur)
		if _combat_manager == null or _combat_manager.precision_reussie(self):
			var degats: int = int(_combat_manager.calculer_degats(self, joueur, degats_attaque)) if _combat_manager != null else degats_attaque
			joueur.recevoir_degats(degats)
	if _combat_manager != null and is_inside_tree():
		_combat_manager.terminer_tour(self)

func _appliquer_ralentissement_test(joueur: Node) -> void:
	if _combat_manager == null:
		return
	var effet: Dictionary = {
		"id": ID_ETAT_TEST,
		"chance": 1.0,
		"duree": DUREE_ETAT_TEST,
		"valeur": 1.0,
	}
	var attaque: Dictionary = {"effets": [effet]}
	_combat_manager.appliquer_effets_sort(joueur, attaque)

func _case_de(sol: TileMapLayer, position_globale: Vector2) -> Vector2i:
	return sol.local_to_map(sol.to_local(position_globale))

# --- récompenses de victoire ---

# applique les récompenses du mob vaincu (XP, Berry, drops de la table
# `mobs`) puis affiche un récapitulatif
func recompenser_victoire() -> void:
	var xp := maxi(int(pv_max / 4.0), 5)
	var berry_min := maxi(int(pv_max / 5.0), 5)
	var berry_max := maxi(int(pv_max / 2.0), berry_min)
	var drops: Array = []
	if BaseDonnees.disponible and mob_id > 0:
		var lignes := BaseDonnees.lire(
			"SELECT xp_reward, berry_reward_min, berry_reward_max, drops_json"
			+ " FROM mobs WHERE id = %d AND is_active = 1;" % mob_id)
		if not lignes.is_empty():
			var ligne: Dictionary = lignes[0]
			xp = int(ligne.get("xp_reward", xp))
			berry_min = int(ligne.get("berry_reward_min", berry_min))
			berry_max = int(ligne.get("berry_reward_max", berry_max))
			var liste: Variant = JSON.parse_string(str(ligne.get("drops_json", "[]")))
			if liste is Array:
				drops = liste
	# tirage des objets : chaque entrée {item_id, probability, min/max_quantity}
	# (les ids arrivent en float depuis le JSON : on les repasse en int)
	var objets_gagnes: Array = []
	for drop in drops:
		if randf() > float(drop.get("probability", 0.0)):
			continue
		var qte := randi_range(int(drop.get("min_quantity", 1)), int(drop.get("max_quantity", 1)))
		if qte > 0 and drop.get("item_id") != null:
			var id_objet := str(int(drop["item_id"]))
			Inventaire.ajouter_objet(id_objet, qte)
			objets_gagnes.append({"id": id_objet, "qte": qte})
	var berry := randi_range(berry_min, maxi(berry_max, berry_min))
	Personnage.gagner_xp(xp)
	Personnage.ajouter_berry(berry)
	_afficher_recompenses(xp, berry, objets_gagnes)

# récapitulatif de fin de combat : les objets vont directement à l'inventaire
func _afficher_recompenses(xp: int, berry: int, objets: Array) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var lignes := ["+%d XP" % xp, "+%d Berry" % berry]
	if objets.is_empty():
		lignes.append("Aucun objet trouvé.")
	else:
		var noms: Array[String] = []
		for objet in objets:
			noms.append("%s x%d" % [Inventaire.nom_objet(str(objet["id"])), int(objet["qte"])])
		lignes.append("Objets : " + ", ".join(noms))
	var fenetre := AcceptDialog.new()
	fenetre.title = "Victoire !"
	fenetre.dialog_text = "\n".join(lignes)
	fenetre.ok_button_text = "Continuer"
	scene.add_child(fenetre)
	fenetre.popup_centered()
	fenetre.visibility_changed.connect(func() -> void:
		if not fenetre.visible:
			fenetre.queue_free())

func _calculer_chemin(sol: TileMapLayer, depart: Vector2i, cible: Vector2i) -> Array[Vector2i]:
	var file: Array[Vector2i] = [depart]
	var parents: Dictionary = {depart: depart}
	var voisins: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
	var destination := depart
	var meilleure_distance := absi(depart.x - cible.x) + absi(depart.y - cible.y)
	while not file.is_empty():
		var courante: Vector2i = file.pop_front()
		var distance := absi(courante.x - cible.x) + absi(courante.y - cible.y)
		if distance < meilleure_distance:
			meilleure_distance = distance
			destination = courante
		if distance <= portee_attaque:
			destination = courante
			break
		for voisin in voisins:
			var suivante := courante + voisin
			if parents.has(suivante) or sol.get_cell_source_id(suivante) == -1 or suivante == cible:
				continue
			if _combat_manager != null and not _combat_manager.dans_zone_combat(suivante):
				continue
			parents[suivante] = courante
			file.append(suivante)
	var chemin: Array[Vector2i] = []
	var case_actuelle := destination
	while case_actuelle != depart:
		if not parents.has(case_actuelle):
			return []
		chemin.push_front(case_actuelle)
		case_actuelle = parents[case_actuelle]
	return chemin
