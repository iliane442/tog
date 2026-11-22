@tool
extends CharacterBody2D

signal sante_modifiee(vie: int, vie_max: int)
signal vaincu

@export var pv_max := 100
@export var nom := "Loup pirate"
@export var degats_attaque := 10
@export var portee_attaque := 2
@export var pm_max := 3
# nombre d'attaques de mêlée par tour (difficulté) : les scènes
# peuvent l'ajuster ennemi par ennemi
@export var attaques_par_tour := 2
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

const EFFET_SORT := preload("res://scripts/combat/effet_sort.gd")
# nombre de dégâts flottant (chiffre qui jaillit, rebondit, s'envole)
const DEGATS_FLOTTANTS := preload("res://scripts/combat/degats_flottants.gd")

# surbrillance rouge au survol : même mécanique que les PNJ (shader
# surlignage.gdshader) mais en rouge pour signaler un camp hostile
const shader_surlignage := preload("res://assets/shaders/surlignage.gdshader")
const COULEUR_SURBRILLANCE := Color(0.95, 0.16, 0.16, 1.0)

var pv := 100
# ligne d'`animations` de l'attaque : chargée au premier coup puis
# gardée (liaison mob via `entity_animations`, coup simple sinon)
var _details_attaque: Dictionary = {}
var _attaque_chargee := false
var _combat_manager
var _deplacement_combat: Tween
var _etiquette_mob: Label
# joueur présent dans la zone de détection
var _zone_contient_joueur := false
# engagement différé au clic : le joueur marche vers cet ennemi et le
# combat se lance dès l'entrée dans la zone, sans bouton
var _engagement_au_clique := false
# un seul engagement différé à la fois, tous ennemis confondus
static var _cible_engagement: Node = null

@onready var zone_detection: Area2D = $ZoneDetection
@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	pv = pv_max
	if Engine.is_editor_hint():
		# dans l'éditeur : juste le visuel (le loup par défaut sinon),
		# pas de combat ni d'étiquette (pour ne pas polluer la scène)
		_charger_visuel_mob()
		_centrer_contenu_sprite()
		return
	add_to_group("entites_minicarte")
	_combat_manager = get_tree().current_scene.get_node_or_null("CombatManager")
	zone_detection.body_entered.connect(_on_zone_body_entered)
	zone_detection.body_exited.connect(_on_zone_body_exited)
	if _combat_manager != null:
		_combat_manager.enregistrer_ennemi(self)
	var mat := ShaderMaterial.new()
	mat.shader = shader_surlignage
	mat.set_shader_parameter("couleur", COULEUR_SURBRILLANCE)
	mat.set_shader_parameter("surligne", false)
	sprite.material = mat
	_charger_visuel_mob()
	_centrer_contenu_sprite()
	sante_modifiee.emit(pv, pv_max)

func repere_minicarte() -> Dictionary:
	if pv <= 0:
		return {}
	return {"categorie": "ennemis", "nom": nom, "role": "Rencontre"}

# survol : surligne l'ennemi, ou tout son camp s'il porte une étiquette
func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var survol := _clic_sur_ennemi(get_global_mouse_position())
	if _combat_manager != null and _combat_manager.has_method("membres_du_camp"):
		for membre in _combat_manager.membres_du_camp(self):
			if membre != null and membre.has_method("_appliquer_surbrillance"):
				membre.call("_appliquer_surbrillance", survol)
	else:
		_appliquer_surbrillance(survol)

func _appliquer_surbrillance(surligne: bool) -> void:
	if sprite.material == null or sprite.material is not ShaderMaterial:
		return
	if bool(sprite.material.get_shader_parameter("surligne")) != surligne:
		sprite.material.set_shader_parameter("surligne", surligne)

# zone de survol : le sprite et son étiquette « Nom (Niv. X) »
func _clic_sur_ennemi(point: Vector2) -> bool:
	if sprite.texture == null:
		return false
	var point_local := to_local(point)
	if (
		_etiquette_mob != null
		and _etiquette_mob.visible
		and _etiquette_mob.get_rect().has_point(point_local)
	):
		return true
	var taille := sprite.texture.get_size() * sprite.scale
	var coin := Vector2(
		-taille.x / 2.0 - 16.0,
		sprite.position.y - taille.y / 2.0 - 26.0)
	return Rect2(coin, Vector2(taille.x + 32.0, taille.y + 40.0)).has_point(
		point_local)

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

# décale le sprite pour que le DESSIN (et non les bords transparents
# de sa planche) soit centré sur l'entité : le loup par exemple vit
# dans un canvas de 100 px majoritairement vide à gauche, il
# apparaissait décalé vers la droite de sa case de combat
func _centrer_contenu_sprite() -> void:
	if sprite.texture == null:
		return
	var image := sprite.texture.get_image()
	if image == null or image.is_empty():
		return
	var largeur := image.get_width()
	var min_x := largeur
	var max_x := -1
	for y in image.get_height():
		for x in largeur:
			if image.get_pixel(x, y).a8 > 25:
				if x < min_x:
					min_x = x
				if x > max_x:
						max_x = x
	if max_x < 0:
		return  # planche entièrement transparente
	var centre_dessin := (min_x + max_x + 1) / 2.0
	# le canvas est centré sur la position du sprite : on décale
	# d'autant que le dessin s'écarte du centre du canvas
	sprite.position.x = float(largeur) / 2.0 - centre_dessin

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
	etiquette.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var hauteur: float = 100.0
	if sprite.texture != null:
		hauteur = float(sprite.texture.get_height())
	add_child(etiquette)
	etiquette.reset_size()
	etiquette.position = Vector2(-etiquette.size.x / 2.0, sprite.position.y - hauteur / 2.0 - 22.0)
	_etiquette_mob = etiquette

func _on_zone_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and _combat_manager != null:
		_zone_contient_joueur = true
		_combat_manager.proposer_combat(self)
		if _engagement_au_clique:
			_engager_si_encore_valide()

func _on_zone_body_exited(body: Node2D) -> void:
	if body.is_in_group("player") and _combat_manager != null:
		_zone_contient_joueur = false
		_combat_manager.annuler_proposition_combat(self)

# clic sur l'ennemi en exploration : le joueur rejoint la zone et le
# combat démarre tout seul à l'arrivée
func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or pv <= 0:
		return
	if _combat_manager != null and _combat_manager.en_combat:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not _clic_sur_ennemi(get_global_mouse_position()):
			return
		var joueur := get_tree().get_first_node_in_group("player")
		if joueur != null and joueur.has_method("rejoindre_interaction"):
			_definir_engagement_differe()
			joueur.rejoindre_interaction(global_position, _engager_si_encore_valide)
			get_viewport().set_input_as_handled()

func _definir_engagement_differe() -> void:
	if _cible_engagement != null and _cible_engagement != self \
			and is_instance_valid(_cible_engagement) \
			and _cible_engagement.has_method("_annuler_engagement"):
		_cible_engagement.call("_annuler_engagement")
	_engagement_au_clique = true
	_cible_engagement = self
	# déjà dans la zone : combat immédiat, pas besoin de marcher
	if _zone_contient_joueur:
		_engager_si_encore_valide()

func _annuler_engagement() -> void:
	_engagement_au_clique = false
	if _cible_engagement == self:
		_cible_engagement = null

func _engager_si_encore_valide() -> void:
	if not _engagement_au_clique:
		return
	_annuler_engagement()
	if not is_inside_tree() or pv <= 0:
		return
	if _combat_manager != null and _combat_manager.en_combat:
		return
	if _combat_manager != null and _combat_manager.has_method("engager_rencontre"):
		_combat_manager.engager_rencontre(self)

# stats d'origine : la difficulté multiplie toujours les valeurs de
# base, jamais des valeurs déjà durcies — et l'ennemi qui survit à un
# combat perdus les retrouve en exploration
var _pv_max_original := 0
var _degats_originaux := 0

# entre en mode combat durci : PV et dégâts multipliés (appellé par le
# gestionnaire de combat à l'ouverture de l'arène)
func durcir(facteur_pv: float, facteur_degats: float) -> void:
	if pv_max <= 0:
		return
	if _pv_max_original == 0:
		_pv_max_original = pv_max
		_degats_originaux = degats_attaque
	# la proportion de vie est conservée, comme dans assouplir : un
	# ennemi au maximum entre dans l'arène à son maximum durci, un
	# blessé garde sa blessure en proportion
	var proportion := float(pv) / float(pv_max)
	pv_max = maxi(int(round(_pv_max_original * facteur_pv)), 1)
	degats_attaque = maxi(int(round(_degats_originaux * facteur_degats)), 1)
	pv = clampi(int(round(proportion * pv_max)), 0, pv_max)
	sante_modifiee.emit(pv, pv_max)

# sort du mode combat durci : retour aux stats d'origine, la barre de
# vie conserve sa proportion
func assouplir() -> void:
	if _pv_max_original == 0:
		return
	var proportion := float(pv) / float(maxi(pv_max, 1))
	pv_max = _pv_max_original
	degats_attaque = _degats_originaux
	pv = clampi(int(round(proportion * pv_max)), 0, pv_max)
	sante_modifiee.emit(pv, pv_max)

func recevoir_degats(degats: int) -> void:
	if pv <= 0:
		return
	pv = maxi(pv - maxi(degats, 0), 0)
	sante_modifiee.emit(pv, pv_max)
	_nombre_flottant(self, "-%d" % maxi(degats, 0), "degats")
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
	_nombre_flottant(self, "+%d" % maxi(montant, 0), "soin")

# affiche un texte flottant au-dessus d'un combattant : dégâts
# subis, soin reçu… le chiffre vit sa vie puis se libère seul
func _nombre_flottant(cible: Node2D, texte: String, type: String) -> void:
	if not is_inside_tree() or cible == null or not is_instance_valid(cible):
		return
	var nombre := DEGATS_FLOTTANTS.new()
	nombre.texte = texte
	nombre.type = type
	nombre.position = cible.global_position + Vector2(0, -26)
	get_tree().current_scene.add_child(nombre)

# --- animation d'attaque ---

# définition de l'attaque visuelle : la ligne d'`animations` liée au
# mob dans `entity_animations` (contexte « attack »), à défaut le
# coup simple (slash) ; chargée une seule fois puis gardée
func _animation_attaque() -> Dictionary:
	if _attaque_chargee:
		return _details_attaque
	_attaque_chargee = true
	if BaseDonnees.disponible:
		if mob_id > 0:
			var specifique := BaseDonnees.lire(
				"SELECT a.sprite_sheet_path, a.frame_width, a.frame_height, a.frame_count, a.frame_delay_ms, a.loop"
				+ " FROM entity_animations ea JOIN animations a ON a.id = ea.animation_id"
				+ " WHERE ea.entity_type = 'mob' AND ea.entity_id = %d AND ea.context = 'attack';" % mob_id)
			if not specifique.is_empty():
				_details_attaque = specifique[0]
				return _details_attaque
		var repli := BaseDonnees.lire(
			"SELECT sprite_sheet_path, frame_width, frame_height, frame_count, frame_delay_ms, loop"
			+ " FROM animations WHERE name = 'fx_coup_simple';")
		if not repli.is_empty():
			_details_attaque = repli[0]
	return _details_attaque

# l'effet d'attaque se joue sur la cible touchée, comme les effets de
# sorts du joueur (instancié et auto-libéré par effet_sort.gd)
func _jouer_animation_attaque(cible: Node2D) -> void:
	if cible == null or not is_instance_valid(cible):
		return
	var details := _animation_attaque()
	if details.is_empty():
		return
	var effet := EFFET_SORT.new()
	effet.configure(
		str(details.get("sprite_sheet_path", "")),
		int(details.get("frame_count", 1)),
		int(details.get("frame_delay_ms", 100)),
		int(details.get("loop", 0)) == 1,
		int(details.get("frame_width", 32)),
		int(details.get("frame_height", 32)))
	get_tree().current_scene.add_child(effet)
	effet.jouer(cible.global_position)

func jouer_tour(joueur: CharacterBody2D, sol: TileMapLayer) -> void:
	if not is_instance_valid(joueur) or sol == null:
		return
	if _combat_manager != null and _combat_manager.preparer_tour(self):
		_combat_manager.afficher_message("L’ennemi perd son tour.")
		_combat_manager.terminer_tour(self)
		return
	if not is_inside_tree():
		return
	var numero: int = _combat_manager.numero_combat if _combat_manager != null else 0
	var depart := _case_de(sol, global_position)
	var cible := _case_de(sol, joueur.global_position)
	if not _peut_attaquer(depart, cible):
		var chemin := _calculer_chemin(sol, depart, cible)
		var pm: int = int(_combat_manager.points_mouvement(self, pm_max)) if _combat_manager != null else pm_max
		var pas := mini(pm, chemin.size())
		for index in range(pas):
			var position_cible := sol.to_global(sol.map_to_local(chemin[index]))
			_deplacement_combat = create_tween()
			_deplacement_combat.tween_property(self, "global_position", position_cible, 0.2)
			await get_tree().create_timer(0.2, false).timeout
			if not is_inside_tree() or (_combat_manager != null and (not _combat_manager.en_combat or _combat_manager.numero_combat != numero)):
				return
			arreter_deplacement_combat()
			global_position = position_cible
		depart = _case_de(sol, global_position)
	if _peut_attaquer(depart, cible):
		# le Sceau du silence (état 7) prive l'ennemi de sa capacité
		# spéciale, comme il prive le joueur de ses sorts
		if _combat_manager == null or _combat_manager.sort_autorise(self):
			_appliquer_ralentissement_test(joueur)
		else:
			_combat_manager.afficher_message("L’ennemi est réduit au silence : sa capacité spéciale échoue.")
		# difficulté : l'ennemi frappe tant qu'il lui reste des attaques
		# et que sa cible est à portée (chaque coup jette sa précision)
		var attaques := maxi(attaques_par_tour, 1)
		while attaques > 0 and is_instance_valid(joueur) and _peut_attaquer(depart, cible):
			if _combat_manager == null:
				joueur.recevoir_degats(degats_attaque)
			else:
				if not _combat_manager.en_combat:
					return
				if _combat_manager.precision_reussie(self, joueur):
					_jouer_animation_attaque(joueur)
					var degats: int = int(_combat_manager.calculer_degats(self, joueur, degats_attaque))
					joueur.recevoir_degats(degats)
					_nombre_flottant(joueur, "-%d" % degats, "degats")
			attaques -= 1
			# laisser lire la salve : une courte pause entre chaque coup
			# (le combat peut finir entre-temps : mêmes gardes que le
			# déplacement)
			if attaques > 0 and is_inside_tree():
				await get_tree().create_timer(0.25, false).timeout
				if not is_inside_tree() or (_combat_manager != null and (not _combat_manager.en_combat or _combat_manager.numero_combat != numero)):
					return
	if _combat_manager != null and _combat_manager.en_combat and is_inside_tree():
		_combat_manager.terminer_tour(self)

func arreter_deplacement_combat() -> void:
	if _deplacement_combat != null:
		_deplacement_combat.kill()
		_deplacement_combat = null

func _peut_attaquer(depart: Vector2i, cible: Vector2i) -> bool:
	var distance := absi(depart.x - cible.x) + absi(depart.y - cible.y)
	return distance <= portee_attaque and (_combat_manager == null or _combat_manager.ligne_de_vue_libre(depart, cible))

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

func _butin_specifique() -> Array:
	return []

# applique les récompenses du mob vaincu (XP, Berry, drops de la table
# `mobs`) puis affiche un récapitulatif
func recompenser_victoire() -> void:
	var xp := maxi(int(pv_max / 4.0), 5)
	var berry_min := maxi(int(pv_max / 5.0), 5)
	var berry_max := maxi(int(pv_max / 2.0), berry_min)
	var drops := _butin_specifique()
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
				drops.append_array(liste)
	# la tablette des Flots Calmes honore sa promesse : les gains de ce
	# combat sont doublés (le drapeau tient jusqu'à la victoire, donc
	# toutes les rencontres de la même escarmouche profitent du bonus)
	if Personnage.prochain_combat_double:
		xp *= 2
		berry_min *= 2
		berry_max *= 2
		if _combat_manager != null:
			_combat_manager.afficher_message("La tablette des Flots Calmes double tes gains !")
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
	# le récapitulatif n'est plus affiché ici : les récompenses se
	# cumulent dans le gestionnaire de combat et une seule fenêtre
	# résume tout à la fin du combat
	if _combat_manager != null and _combat_manager.has_method("cumuler_recompense"):
		_combat_manager.cumuler_recompense(Personnage.xp_effectif(xp), berry, objets_gagnes)

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
		if _peut_attaquer(courante, cible):
			destination = courante
			break
		for voisin in voisins:
			var suivante := courante + voisin
			if parents.has(suivante) or sol.get_cell_source_id(suivante) == -1 or suivante == cible:
				continue
			if _combat_manager != null and _combat_manager.ennemi_sur_case(suivante) != null:
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
