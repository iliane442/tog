extends Node

signal combat_commence
signal combat_termine(victoire: bool)
signal placement_commence
signal sort_demandee(id_sort: String)
signal fin_tour_demandee
signal fuite_demandee
signal placement_valide
signal ressources_joueur_modifiees(pa: int, pa_max: int, pm: int, pm_max: int)
# annonce qui joue : le HUD n'affiche le bouton de fin de tour que
# pendant le tour du joueur local
signal tour_actif_change(combattant: Node2D)

const ARENE_COMBAT := preload("res://scripts/combat/arene_combat.gd")
const ANIMATION_SORT := preload("res://scripts/combat/animation_sort.gd")
const VISUELS_SORTS := preload("res://scripts/combat/visuels_sorts.gd")
const POSITION_ARENE := Vector2(-16384, -16384)
# difficulté des combats : PV et dégâts des ennemis sont multipliés à
# l'ouverture de l'arène (ennemis classiques uniquement — les duels PvP
# gardent les vraies stats des joueurs) ; les dégâts suivent en plus
# le niveau du joueur (attaque et défense croissent avec lui, les dégâts
# des scènes restent fixes) ; les attaques par tour se règlent sur
# chaque ennemi (attaques_par_tour, 2 par défaut)
const DIFFICULTE_PV := 1.5
const DIFFICULTE_DEGATS := 1.25
const DEGATS_PAR_NIVEAU := 0.15
# renfort de la salle d'opération (Room du bistouri) : +25 % infligés,
# -25 % encaissés, seulement pour ses occupants alliés
const MODIFICATEUR_SALLE := 0.25

var en_combat := false
var en_placement := false
# cases de la salle d'opération active (Room du bistouri) : ses
# occupants alliés frappent plus fort et encaissent mieux, sans état
var cases_salle: Array[Vector2i] = []
var conclusion_en_cours := false
var numero_combat := 0
var _arene: ARENE_COMBAT
var _dernier_sort_anime: ANIMATION_SORT
var _planches_sorts := {}
var _camera_exploration: Camera2D
var _positions_exploration := {}
var _joueur: Node
# ennemis engagés dans le combat en cours (le plus proche du joueur
# reste disponible via _ennemi / ennemi_actuel pour l'interface)
var _ennemis: Array = []
# ennemis rencontrés sur la carte hors combat
var _ennemis_connus: Array = []
# ennemis étiquetés par groupe (voir ennemy.gd) : détecter un membre
# propose sa rencontre entière ; « Combattre » engage l'union des
# propositions
var _propositions: Array = []
# ennemis dont la zone de détection chevauche actuellement le joueur
var _detecteurs: Array = []
var _ennemi
var _cible_fiche: Node
# cible verrouillée via les touches de sélection (null = plus proche)
var _cible_selectionnee: Node
# monde partagé : étiquette du groupe combattu ("" si aucun)
var groupe_combat := ""
var pvp_actif := false        # un duel contre un joueur distant est en cours
var pvp_premier := false      # le duel a commencé par notre tour
var groupe_actif := false     # combat de groupe : les coéquipiers rejouent ici
var _pvp_adversaire: SCRIPT_ADVERSAIRE_PVP   # miroir du joueur distant dans notre arène
# miroirs des coéquipiers dans notre arène : peer_id -> combattant distant
var _miroirs_groupe := {}
# --- combat de groupe synchronisé : tour par tour, ordre par initiative ---
# ordre des combattants diffusé par l'arbitre : chaque entrée porte
# k ("p" joueur / "e" ennemi), id (peer ou nom du node ennemi) et init
var _ordre_tours: Array = []
var _position_tour := -1     # index dans _ordre_tours du tour en cours
var _prets_groupe := {}       # peer -> jet d'initiative annoncé
var _ma_initiative := 0       # notre jet, calculé à la fin du placement
var _cle_active := ""         # clé "p:peer" / "e:nom" du combattant qui joue
var _fins_ennemis_recues := {}  # nom d'ennemi -> fin de tour reçue (arbitre)
var _pilote_en_cours := false
var _ui: CanvasLayer
var _fiche_ennemi: PanelContainer
var _barre_vie_ennemi: ProgressBar
var _label_nom_ennemi: Label
var _label_vie_ennemi: Label
var _label_stats_ennemi: Label
var _label_etats_ennemi: Label
var _souris_sur_ennemi := false
var _bouton_combattre: Button
var _etats_actifs: Dictionary = {}
# récompenses cumulées du combat en cours : une seule fenêtre de
# récapitulatif à la fin, pas une par ennemi vaincu
var _recompenses := {"vaincus": 0, "xp": 0, "berry": 0, "objets": {}}
# roster des combattants : menu dépliant des stats + tour actif
var _panneau_roster: PanelContainer
var _liste_roster: VBoxContainer
var _bouton_roster: Button
var _roster_deplie := false
var _combattant_actif: Node2D
var _marqueur_tour: Node2D
var _hasard := RandomNumberGenerator.new()
const SCENE_COMBAT_UI := preload("res://scenes/combat_ui.tscn")
const SCRIPT_ADVERSAIRE_PVP := preload("res://scripts/combat/adversaire_pvp.gd")
const THEME_COMBAT := preload("res://themes/theme_interface_pirate.tres")

func _ready() -> void:
	_hasard.randomize()
	if _joueur == null:
		_joueur = get_tree().current_scene.find_child("player", true, false)
	_construire_interface()
	for ennemi in _ennemis_connus:
		_connecter_survol_ennemi(ennemi)
	_maj_ennemi_principal()
	mettre_a_jour_stats(Personnage.vie, Personnage.vie_max, 6, 6, 3, 3)

func initialiser(joueur: Node, ennemi: Node) -> void:
	_joueur = joueur
	enregistrer_ennemi(ennemi)

# tout ennemi présent sur la carte est connu : il participe aux combats
# de groupe (détection, ciblage au clic) même hors de son voisinage
func enregistrer_ennemi(ennemi: Node) -> void:
	if ennemi == null or not is_instance_valid(ennemi):
		return
	if not _ennemis_connus.has(ennemi):
		_ennemis_connus.append(ennemi)
	_connecter_survol_ennemi(ennemi)
	_maj_ennemi_principal()

# l'ennemi principal : le plus proche du joueur — sert de cible par
# défaut à l'interface (distances, overlays, sorts alliés)
func _maj_ennemi_principal() -> void:
	# les vaincus et disparus quittent le groupe
	_ennemis = _ennemis.filter(func(e: Node) -> bool: return is_instance_valid(e) and int(e.get("pv")) > 0)
	# le principal est l'engagé le plus proche du joueur (hors combat :
	# le plus proche des ennemis connus)
	_ennemi = ennemi_proche()

func ennemi_actuel() -> Node:
	return _ennemi

# ennemis engagés dans le combat, vivants et encore valides
func ennemis_actifs() -> Array:
	var actifs := []
	for ennemi in _ennemis:
		if ennemi != null and is_instance_valid(ennemi) and int(ennemi.get("pv")) > 0:
			actifs.append(ennemi)
	return actifs

# l'ennemi engagé qui occupe cette case (null si aucun)
func ennemi_sur_case(case_sol: Vector2i) -> Node:
	var sol := sol_combat()
	if sol == null:
		return null
	for ennemi in ennemis_actifs():
		if sol.local_to_map(sol.to_local((ennemi as Node2D).global_position)) == case_sol:
			return ennemi
	return null

# l'occupant d'une case de l'arène : le joueur local, un ennemi
# engagé ou un miroir de coéquipier (une future invocation s'y
# ajoutera : tout combattant positionné suffit)
func occupant_case(case_sol: Vector2i) -> Node2D:
	var sol := sol_combat()
	if sol == null:
		return null
	if _joueur is Node2D and is_instance_valid(_joueur) \
			and sol.local_to_map(sol.to_local((_joueur as Node2D).global_position)) == case_sol:
		return _joueur
	var ennemi := ennemi_sur_case(case_sol)
	if ennemi != null:
		return ennemi as Node2D
	for miroir in _miroirs_groupe.values():
		if miroir is Node2D and is_instance_valid(miroir) \
				and sol.local_to_map(sol.to_local((miroir as Node2D).global_position)) == case_sol:
			return miroir
	return null

# Shambles (pouvoir du Bistouri) : échange le contenu de deux cases
# de l'arène — leurs occupants et leur terrain. Un mur échangé avec
# autre chose prend réellement la place de l'autre case, qui redevient
# une dalle praticable ; une case sans occupant sert de destination
# (téléportation de l'autre occupant). Les occupants atterrissent
# toujours sur une dalle : le terrain accompagne le mouvement
func permuter_cases(case_a: Vector2i, case_b: Vector2i) -> bool:
	var sol := sol_combat()
	if sol == null or _arene == null or case_a == case_b:
		return false
	if not dans_zone_combat(case_a) or not dans_zone_combat(case_b):
		return false
	var occupant_a := occupant_case(case_a)
	var occupant_b := occupant_case(case_b)
	var mur_a := _arene.est_mur(case_a)
	var mur_b := _arene.est_mur(case_b)
	# deux dalles sans occupant : rien à échanger ; deux murs non
	# plus : ils sont identiques, la permutation ne se voit pas
	if (not mur_a and not mur_b and occupant_a == null and occupant_b == null) \
			or (mur_a and mur_b):
		return false
	if mur_a != mur_b:
		_arene.deplacer_mur(case_a if mur_a else case_b, case_b if mur_a else case_a)
	if occupant_a != null:
		occupant_a.global_position = sol.to_global(sol.map_to_local(case_b))
	if occupant_b != null:
		occupant_b.global_position = sol.to_global(sol.map_to_local(case_a))
	return true

# cases que le Shambles peut viser : autour du lanceur jusqu'à la
# portée du sort, dalles et murs confondus — un mur se vise jusqu'à
# son bord (sa propre cellule n'entrave pas la ligne de vue)
func cases_permutables(lanceur: Node2D, portee: int) -> Array[Vector2i]:
	var cases: Array[Vector2i] = []
	var sol := sol_combat()
	if sol == null or _arene == null or not is_instance_valid(lanceur):
		return cases
	var depart := sol.local_to_map(sol.to_local(lanceur.global_position))
	for dy in range(-portee, portee + 1):
		for dx in range(-portee, portee + 1):
			var case_cible := depart + Vector2i(dx, dy)
			if absi(dx) + absi(dy) > portee or not dans_zone_combat(case_cible):
				continue
			var mur := _arene.est_mur(case_cible)
			if not mur and sol.get_cell_source_id(case_cible) == -1:
				continue
			if ligne_de_vue_libre(depart, case_cible, mur):
				cases.append(case_cible)
	return cases

# les cases traversées par une lame en ligne (Gamma Scalpel) : jusqu'à
# profondeur cases dans la direction cardinale donnée, en s'arrêtant
# au bord de l'arène et au premier mur — la lame ne le traverse jamais
func cases_ligne(depart: Vector2i, direction: Vector2i, profondeur: int) -> Array[Vector2i]:
	var cases: Array[Vector2i] = []
	var sol := sol_combat()
	if sol == null or _arene == null or direction == Vector2i.ZERO:
		return cases
	for i in range(1, profondeur + 1):
		var case_suivante := depart + direction * i
		if not dans_zone_combat(case_suivante) or _arene.est_mur(case_suivante):
			break
		cases.append(case_suivante)
	return cases

# l'ennemi le plus proche du joueur (engagés d'abord, connus sinon)
func ennemi_proche() -> Node:
	if _joueur == null or not is_instance_valid(_joueur):
		return null
	var meilleure: Node = null
	var meilleure_distance := INF
	var sol := sol_combat()
	for ennemi in ennemis_actifs() if en_combat else _ennemis_connus:
		if ennemi == null or not is_instance_valid(ennemi) or int(ennemi.get("pv")) <= 0:
			continue
		var e := ennemi as Node2D
		var distance: float = _joueur.global_position.distance_squared_to(e.global_position)
		if en_combat and sol != null:
			distance = sol.to_local(_joueur.global_position).distance_squared_to(sol.to_local(e.global_position))
		if distance < meilleure_distance:
			meilleure = ennemi
			meilleure_distance = distance
	return meilleure

# la cible par défaut des sorts : la cible verrouillée au clavier si
# elle est encore valide, l'ennemi le plus proche sinon
func cible_courante() -> Node:
	if _cible_selectionnee != null and is_instance_valid(_cible_selectionnee) and int(_cible_selectionnee.get("pv")) > 0:
		return _cible_selectionnee
	return ennemi_proche()

# la cible explicitement verrouillée (null si le joueur n'en a pas
# choisi une via les touches)
func cible_verrouillee() -> Node:
	if _cible_selectionnee != null and is_instance_valid(_cible_selectionnee) and int(_cible_selectionnee.get("pv")) > 0:
		return _cible_selectionnee
	return null

# fait tourner la sélection de cible parmi les ennemis engagés
func cible_suivante() -> void:
	_cycle_cible(1)

func cible_precedente() -> void:
	_cycle_cible(-1)

func _cycle_cible(sens: int) -> void:
	if not en_combat or en_placement:
		return
	var actifs := ennemis_actifs()
	if actifs.size() < 2:
		return
	var cible := cible_courante()
	var index := 0
	if cible != null:
		index = maxi(actifs.find(cible), 0)
	index = int(fposmod(float(index + sens), float(actifs.size())))
	_cible_selectionnee = actifs[index]
	# la fiche de l'ennemi survolé suit la sélection
	_survol_ennemi(_cible_selectionnee)
	_actualiser_fiche_ennemi()

func sol_combat() -> TileMapLayer:
	return _arene.sol if _arene != null else null

func jouer_animation_sort(id_sort: String, lanceur: Node2D, cible: Node2D, touche := true) -> void:
	if _arene == null or not is_instance_valid(cible) or id_sort.is_empty():
		return
	var identifiant := id_sort.to_int() if id_sort.is_valid_int() else -1
	if id_sort == "boule_de_feu":
		identifiant = 0
	var sort: Dictionary = Personnage.sorts.get(id_sort, {})
	var profil := VISUELS_SORTS.pour_sort(identifiant, str(sort.get("type", "attack")),
		int(sort.get("portee", 1)))
	var details := _planche_sort(identifiant) if touche else {}
	var animation := ANIMATION_SORT.new()
	_arene.add_child(animation)
	animation.jouer(identifiant, profil, lanceur if is_instance_valid(lanceur) else cible,
		cible, details, touche)
	if touche:
		_dernier_sort_anime = animation

func _planche_sort(id_sort: int) -> Dictionary:
	if not _planches_sorts.has(id_sort):
		var details := {}
		if BaseDonnees.disponible and id_sort >= 0:
			var lignes := BaseDonnees.lire(
				"SELECT sprite_sheet_path, frame_count, frame_delay_ms, loop, frame_width, frame_height"
				+ " FROM animations WHERE entity_type = 'skill' AND entity_id = %d;" % id_sort)
			if not lignes.is_empty():
				details = lignes[0]
		_planches_sorts[id_sort] = details
	return _planches_sorts[id_sort]

func case_sous_point(point: Vector2, viser_ennemi: bool) -> Vector2i:
	var sol := sol_combat()
	if sol == null:
		return ARENE_COMBAT.CASE_HORS_ARENE
	# La sélection suit le sol et les personnages visibles à travers les blocs.
	var case_sol := sol.local_to_map(sol.to_local(point))
	if not viser_ennemi:
		return case_sol
	var premier_plan := -INF
	var cible := case_sol
	for entite in ennemis_actifs():
		if entite.global_position.y <= premier_plan:
			continue
		var sprite := entite.get_node_or_null("Sprite2D") as Sprite2D
		if sprite == null:
			continue
		var point_sprite := sprite.to_local(point)
		if sprite.get_rect().has_point(point_sprite) and sprite.is_pixel_opaque(point_sprite):
			premier_plan = entite.global_position.y
			cible = sol.local_to_map(sol.to_local(entite.global_position))
	return cible

func dans_zone_combat(case: Vector2i) -> bool:
	return _arene != null and Rect2i(Vector2i.ZERO, _arene.dimensions).has_point(case)

func ligne_de_vue_libre(depart: Vector2i, arrivee: Vector2i, ignorer_arrivee := false) -> bool:
	var sol := sol_combat()
	if sol == null:
		return false
	var x := depart.x
	var y := depart.y
	var dx := absi(arrivee.x - x)
	var dy := absi(arrivee.y - y)
	var sx := 1 if x < arrivee.x else -1
	var sy := 1 if y < arrivee.y else -1
	var erreur := dx - dy
	while x != arrivee.x or y != arrivee.y:
		var double_erreur := 2 * erreur
		if double_erreur > -dy:
			erreur -= dy
			x += sx
		if double_erreur < dx:
			erreur += dx
			y += sy
		# ignorer_arrivee : viser un mur jusqu'à son bord — sa propre
		# cellule ne bloque pas la ligne de vue qui le désigne
		if not (ignorer_arrivee and x == arrivee.x and y == arrivee.y) \
				and sol.get_cell_source_id(Vector2i(x, y)) == -1:
			return false
	return true

func _construire_interface() -> void:
	var ui_existante := get_node_or_null("CombatUI")
	if ui_existante == null:
		_ui = SCENE_COMBAT_UI.instantiate() as CanvasLayer
		if _ui == null:
			push_warning("Impossible de charger l'interface de combat.")
			return
		_ui.name = "CombatUI"
		add_child(_ui)
	else:
		_ui = ui_existante as CanvasLayer
	if _ui == null:
		push_warning("La scène de combat ne contient pas de CanvasLayer CombatUI.")
		return
	_fiche_ennemi = _ui.get_node("FicheEnnemi") as PanelContainer
	_label_nom_ennemi = _ui.get_node("FicheEnnemi/Marges/Colonne/Nom") as Label
	_barre_vie_ennemi = _ui.get_node("FicheEnnemi/Marges/Colonne/LigneVie/Vie") as ProgressBar
	_label_vie_ennemi = _ui.get_node("FicheEnnemi/Marges/Colonne/LigneVie/VieTexte") as Label
	_label_stats_ennemi = _ui.get_node("FicheEnnemi/Marges/Colonne/Stats") as Label
	_label_etats_ennemi = _ui.get_node("FicheEnnemi/Marges/Colonne/Etats") as Label
	_fiche_ennemi.hide()
	_actualiser_fiche_ennemi()
	# bouton de proposition de combat (affiché par proposer_combat quand
	# le joueur s'approche d'un ennemi)
	_bouton_combattre = Button.new()
	_bouton_combattre.text = "Combattre"
	_bouton_combattre.theme = THEME_COMBAT
	_bouton_combattre.custom_minimum_size = Vector2(160, 44)
	_bouton_combattre.pressed.connect(_on_bouton_combattre_presse)
	_ui.add_child(_bouton_combattre)
	_bouton_combattre.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_bouton_combattre.offset_top -= 176.0
	_bouton_combattre.offset_bottom -= 176.0
	_bouton_combattre.hide()
	_construire_roster()
	# les pv du joueur changent souvent (coups reçus, soins) : la
	# liste des combattants suit en direct
	Personnage.caracteristiques_modifiees.connect(_sur_stats_joueur)

func _sur_stats_joueur() -> void:
	if en_combat:
		_rafraichir_roster()

# ============================================================
#  ROSTER DES COMBATTANTS (menu dépliant) ET TOUR ACTIF
# ============================================================

# panneau déroulant des stats des alliés et des ennemis du combat ;
# replié (défaut), le combattant dont c'est le tour est mis en avant
# sur l'arène par une flèche dorée
func _construire_roster() -> void:
	_panneau_roster = PanelContainer.new()
	_panneau_roster.theme = THEME_COMBAT
	_panneau_roster.theme_type_variation = "ParchmentPanel"
	_ui.add_child(_panneau_roster)
	var colonne := VBoxContainer.new()
	colonne.add_theme_constant_override("separation", 4)
	_panneau_roster.add_child(colonne)
	_bouton_roster = Button.new()
	_bouton_roster.text = "▸ Combattants"
	_bouton_roster.pressed.connect(basculer_roster)
	colonne.add_child(_bouton_roster)
	_liste_roster = VBoxContainer.new()
	_liste_roster.visible = _roster_deplie
	colonne.add_child(_liste_roster)
	_panneau_roster.hide()
	get_viewport().size_changed.connect(_placer_roster)

# positionne le roster en haut à droite, sous la barre de navigation et
# le panneau de berries du HUD, aligné sur leur marge droite ; sa taille
# suit le contenu, il est repositionné à chaque rafraîchissement
func _placer_roster() -> void:
	if _panneau_roster == null or not is_instance_valid(_panneau_roster):
		return
	_panneau_roster.size = _panneau_roster.get_minimum_size()
	var haut := 160.0
	var marge_droite := 20.0
	var scene_courante := get_tree().current_scene
	if scene_courante != null:
		var hud: Node = scene_courante.find_child("HUD", true, false)
		if hud != null:
			var berry := hud.get_node_or_null("BerryPanel") as Control
			if berry != null:
				haut = berry.offset_bottom + 12.0
				marge_droite = -berry.offset_right
	var ecran := get_viewport().get_visible_rect().size
	_panneau_roster.position = Vector2(ecran.x - _panneau_roster.size.x - marge_droite, haut)

# déploie ou replie la liste des combattants ; replié, le tour actif
# est rappelé sur l'arène par le marqueur doré
func basculer_roster() -> void:
	_roster_deplie = not _roster_deplie
	_liste_roster.visible = _roster_deplie
	_bouton_roster.text = ("▾ Combattants" if _roster_deplie else "▸ Combattants")
	_marquer_tour(_combattant_actif)

# ouvre la liste des combattants en début de combat : les vies de
# toutes les entités présentes restent visibles d'un coup d'œil
# (repliable à tout moment depuis le bouton)
func defplier_roster() -> void:
	if not _roster_deplie:
		basculer_roster()

# reconstruit la liste des combattants (alliés puis ennemis), avec le
# tour actif surligné
func _rafraichir_roster() -> void:
	if _liste_roster == null:
		return
	_panneau_roster.visible = en_combat
	if not en_combat:
		return
	for enfant in _liste_roster.get_children():
		_liste_roster.remove_child(enfant)
		enfant.queue_free()
	_ajouter_titre_roster("Alliés")
	var allies := [_joueur]
	for miroir in _miroirs_groupe.values():
		if miroir is Node and is_instance_valid(miroir):
			allies.append(miroir)
	for allie in allies:
		if allie != null and is_instance_valid(allie):
			_ajouter_ligne_roster(allie)
	_ajouter_titre_roster("Ennemis")
	for ennemi in ennemis_actifs():
		_ajouter_ligne_roster(ennemi)
	# la taille du panneau dépend des lignes affichées : replacer après
	# le remplissage pour qu'il reste entier à l'écran
	_placer_roster()

func _ajouter_titre_roster(texte: String) -> void:
	var titre := Label.new()
	titre.text = texte
	titre.add_theme_font_size_override("font_size", 15)
	titre.add_theme_color_override("font_color", Color("#ffd166"))
	_liste_roster.add_child(titre)

# une ligne du roster : bloc contenant le nom (et attaque/défense),
# la barre de vie colorée (vert, orange puis rouge) et les valeurs,
# puis la légende des états actifs (couleur selon le type d'effet)
func _ajouter_ligne_roster(entite: Node2D) -> void:
	var stats := _stats_combattant(entite)
	if stats.is_empty():
		return
	var pv_max := maxi(int(stats["pv_max"]), 1)
	var pv := clampi(int(stats["pv"]), 0, pv_max)
	var bloc := VBoxContainer.new()
	bloc.add_theme_constant_override("separation", 0)
	var ligne := HBoxContainer.new()
	ligne.add_theme_constant_override("separation", 8)
	var nom := Label.new()
	nom.add_theme_font_size_override("font_size", 15)
	var texte_nom := str(stats["nom"])
	if stats.has("attaque"):
		texte_nom += " — ATT %d" % int(stats["attaque"])
	if stats.has("defense"):
		texte_nom += " — DEF %d" % int(stats["defense"])
	if entite == _combattant_actif:
		texte_nom = "▸ " + texte_nom
		nom.add_theme_color_override("font_color", Color("#ffd166"))
	elif entite is SCRIPT_ADVERSAIRE_PVP and entite.allie:
		nom.add_theme_color_override("font_color", Color("#164a50"))
	else:
		nom.add_theme_color_override("font_color", Color.WHITE)
	nom.text = texte_nom
	nom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ligne.add_child(nom)
	ligne.add_child(_creer_barre_vie_roster(pv, pv_max))
	var valeurs := Label.new()
	valeurs.text = "%d/%d" % [pv, pv_max]
	valeurs.add_theme_font_size_override("font_size", 14)
	valeurs.add_theme_color_override("font_color", Color.WHITE)
	valeurs.add_theme_color_override("font_shadow_color", Color.BLACK)
	valeurs.add_theme_constant_override("shadow_offset_x", 1)
	valeurs.add_theme_constant_override("shadow_offset_y", 1)
	valeurs.custom_minimum_size = Vector2(64, 0)
	valeurs.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ligne.add_child(valeurs)
	bloc.add_child(ligne)
	var etats := _etats_roster(entite)
	if not etats.is_empty():
		var legende := HBoxContainer.new()
		legende.add_theme_constant_override("separation", 10)
		for etat in etats:
			var badge := Label.new()
			var texte_etat := "%s · %d" % [str(etat["nom"]), int(etat["duree"])]
			texte_etat += " tour" if int(etat["duree"]) == 1 else " tours"
			if int(etat["piles"]) > 1:
				texte_etat += " (x%d)" % int(etat["piles"])
			badge.text = texte_etat
			badge.tooltip_text = "%s\n%s" % [str(etat["nom"]), str(etat["description"])]
			badge.add_theme_font_size_override("font_size", 12)
			badge.add_theme_color_override("font_shadow_color", Color.BLACK)
			badge.add_theme_constant_override("shadow_offset_x", 1)
			badge.add_theme_constant_override("shadow_offset_y", 1)
			match str(etat["type"]):
				"buff":
					badge.add_theme_color_override("font_color", Color("#81c784"))
				"control":
					badge.add_theme_color_override("font_color", Color("#ffd166"))
				_:
					badge.add_theme_color_override("font_color", Color("#ff8a80"))
			legende.add_child(badge)
		bloc.add_child(legende)
	_liste_roster.add_child(bloc)

# états actifs d'un combattant pour le roster : nom, type, description,
# durée restante et piles (même source que la fiche ennemi)
func _etats_roster(entite: Node2D) -> Array[Dictionary]:
	var resultat: Array[Dictionary] = []
	if entite == null or not is_instance_valid(entite):
		return resultat
	var effets: Dictionary = _etats_actifs.get(entite.get_instance_id(), {})
	for cle in effets:
		var definition: Dictionary = Personnage.etats.get(int(cle), {})
		var actif: Dictionary = effets[cle]
		resultat.append({
			"nom": str(definition.get("nom", "Etat %s" % cle)),
			"type": str(definition.get("type", "debuff")),
			"description": str(definition.get("description", "")),
			"duree": int(actif.get("duree", 1)),
			"piles": int(actif.get("piles", 1)),
		})
	return resultat

# petite barre de vie du roster : verte au-delà de la moitié, orange
# jusqu'au quart, rouge en dessous
func _creer_barre_vie_roster(pv: int, pv_max: int) -> ProgressBar:
	var barre := ProgressBar.new()
	barre.custom_minimum_size = Vector2(90, 10)
	barre.min_value = 0
	barre.max_value = pv_max
	barre.value = pv
	barre.show_percentage = false
	var proportion := float(pv) / float(pv_max)
	var couleur := Color("#e53935")
	if proportion > 0.5:
		couleur = Color("#4caf50")
	elif proportion > 0.25:
		couleur = Color("#ffa726")
	var fond := StyleBoxFlat.new()
	fond.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	fond.corner_radius_top_left = 3
	fond.corner_radius_top_right = 3
	fond.corner_radius_bottom_left = 3
	fond.corner_radius_bottom_right = 3
	var remplissage := StyleBoxFlat.new()
	remplissage.bg_color = couleur
	remplissage.corner_radius_top_left = 3
	remplissage.corner_radius_top_right = 3
	remplissage.corner_radius_bottom_left = 3
	remplissage.corner_radius_bottom_right = 3
	barre.add_theme_stylebox_override("background", fond)
	barre.add_theme_stylebox_override("fill", remplissage)
	return barre

# stats affichables d'un combattant (joueur local depuis Personnage,
# ennemis et miroirs depuis leurs propriétés)
func _stats_combattant(entite: Node2D) -> Dictionary:
	if entite == null or not is_instance_valid(entite):
		return {}
	if entite == _joueur:
		return {"nom": Personnage.nom, "pv": Personnage.vie, "pv_max": Personnage.vie_max,
			"attaque": Personnage.attaque, "defense": Personnage.defense}
	if entite is SCRIPT_ADVERSAIRE_PVP:
		return {"nom": str(entite.get("nom")), "pv": int(entite.get("pv")),
			"pv_max": maxi(int(entite.get("pv_max")), 1),
			"attaque": int(entite.get("degats_attaque")),
			"defense": int(entite.get("defense_pvp"))}
	var pv_max: Variant = entite.get("pv_max")
	if pv_max == null:
		return {}
	return {"nom": str(entite.get("nom")), "pv": int(entite.get("pv")),
		"pv_max": maxi(int(pv_max), 1), "attaque": int(entite.get("degats_attaque"))}

# le joueur local ou player.gd annonce qui joue : le marqueur part sur
# lui (menu replié) et sa ligne est surlignée (menu déplié)
func definir_combattant_actif(entite: Node2D) -> void:
	_combattant_actif = entite if entite != null and is_instance_valid(entite) and en_combat else null
	_marquer_tour(_combattant_actif)
	_rafraichir_roster()
	tour_actif_change.emit(_combattant_actif)

# qui joue actuellement (null : personne, placement ou combat fini)
func combattant_actif() -> Node2D:
	return _combattant_actif

# l'adversaire distant d'un duel (miroir dans notre arène)
func adversaire_duel() -> Node2D:
	var adversaire := _adversaire_valide()
	if adversaire == null:
		return null
	return adversaire

# flèche dorée battante au-dessus du combattant dont c'est le tour ;
# visible seulement quand le roster est replié
func _marquer_tour(entite: Node2D) -> void:
	_retirer_marqueur_tour()
	if entite == null or not is_instance_valid(entite) or _roster_deplie:
		return
	var marqueur := _creer_marqueur_tour()
	entite.add_child(marqueur)
	var sprite: Sprite2D = entite.get_node_or_null("Sprite2D")
	var hauteur := 96.0
	if sprite != null and sprite.texture != null:
		# les planches de sprites à rangées de direction ne comptent
		# qu'une seule rangée de haut à l'écran
		var rangs := maxi(int(sprite.vframes), 1)
		hauteur = sprite.position.y - sprite.texture.get_height() * sprite.scale.y / (2.0 * rangs) - 16.0
	marqueur.position = Vector2(0, hauteur)
	_marqueur_tour = marqueur

func _retirer_marqueur_tour() -> void:
	if _marqueur_tour != null and is_instance_valid(_marqueur_tour):
		_marqueur_tour.queue_free()
	_marqueur_tour = null

func _creer_marqueur_tour() -> Node2D:
	var marqueur := Node2D.new()
	marqueur.name = "MarqueurTour"
	marqueur.z_index = 30
	var fleche := Polygon2D.new()
	fleche.polygon = PackedVector2Array([Vector2(-10, -12), Vector2(10, -12), Vector2(0, 2)])
	fleche.color = Color("#ffd166")
	marqueur.add_child(fleche)
	var battement := marqueur.create_tween()
	battement.set_loops()
	battement.tween_property(fleche, "position:y", -5.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	battement.tween_property(fleche, "position:y", 0.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return marqueur

# branche la fiche de survol sur un ennemi donné (mouse_entered avec
# bind pour que la fiche suive n'importe lequel des ennemis)
func _connecter_survol_ennemi(ennemi: Node) -> void:
	if ennemi == null or not is_instance_valid(ennemi):
		return
	var cible := ennemi
	var survol_entree := Callable(self, "_survol_ennemi").bind(cible)
	var survol_sortie := Callable(self, "_quitter_survol_ennemi").bind(cible)
	if ennemi.has_signal("mouse_entered") and not ennemi.is_connected("mouse_entered", survol_entree):
		ennemi.connect("mouse_entered", survol_entree)
	if ennemi.has_signal("mouse_exited") and not ennemi.is_connected("mouse_exited", survol_sortie):
		ennemi.connect("mouse_exited", survol_sortie)
	var maj_sante := Callable(self, "_sante_ennemi_modifiee").bind(cible)
	if ennemi.has_signal("sante_modifiee") and not ennemi.is_connected("sante_modifiee", maj_sante):
		ennemi.connect("sante_modifiee", maj_sante)
	# le roster des combattants suit les pv de chaque ennemi engagé
	var maj_roster := Callable(self, "_sur_sante_combattant").bind(cible)
	if ennemi.has_signal("sante_modifiee") and not ennemi.is_connected("sante_modifiee", maj_roster):
		ennemi.connect("sante_modifiee", maj_roster)

func _sur_sante_combattant(_vie: int, _vie_max: int, _cible: Node = null) -> void:
	if en_combat:
		_rafraichir_roster()

# pv d'un miroir de coéquipier (combat de groupe) : le roster suit
func _sur_sante_miroir(_vie: int, _vie_max: int) -> void:
	if en_combat:
		_rafraichir_roster()

func _survol_ennemi(ennemi: Node = null) -> void:
	_souris_sur_ennemi = true
	if ennemi != null:
		_cible_fiche = ennemi
	if not en_combat or _fiche_ennemi == null:
		return
	if ennemi == null and _cible_fiche == null:
		return
	_actualiser_fiche_ennemi()
	_fiche_ennemi.show()
	_positionner_fiche_ennemi()

func _quitter_survol_ennemi(_ennemi_survole: Node = null) -> void:
	_souris_sur_ennemi = false
	if _fiche_ennemi != null:
		_fiche_ennemi.hide()

# la fiche se met à jour pour l'ennemi survolé (ou vu au dernier survol)
func _sante_ennemi_modifiee(_vie: int, _vie_max: int, ennemi: Node = null) -> void:
	if ennemi != null and _cible_fiche != ennemi:
		return
	_actualiser_fiche_ennemi()

func _actualiser_fiche_ennemi() -> void:
	var cible: Node = _cible_fiche if _cible_fiche != null else ennemi_actuel()
	if _fiche_ennemi == null or cible == null or not is_instance_valid(cible):
		return
	var nom_ennemi: String = str(cible.get("nom"))
	if nom_ennemi.is_empty():
		nom_ennemi = "Ennemi"
	var vie_max: int = maxi(int(cible.get("pv_max")), 1)
	var vie: int = clampi(int(cible.get("pv")), 0, vie_max)
	_label_nom_ennemi.text = nom_ennemi
	_barre_vie_ennemi.max_value = vie_max
	_barre_vie_ennemi.value = vie
	_label_vie_ennemi.text = "%d / %d" % [vie, vie_max]
	_label_stats_ennemi.text = "ATTAQUE : %d\nPORTEE : %d cases\nDEPLACEMENT : %d PM" % [
		int(cible.get("degats_attaque")),
		int(cible.get("portee_attaque")),
		int(cible.get("pm_max")),
	]
	_label_etats_ennemi.text = _texte_etats_cible(cible)

func _texte_etats_cible(cible: Node) -> String:
	if cible == null or not is_instance_valid(cible):
		return "Aucun"
	var effets: Dictionary = _etats_actifs.get(cible.get_instance_id(), {})
	if effets.is_empty():
		return "Aucun"
	var lignes: Array[String] = []
	for id_texte in effets:
		var definition: Dictionary = Personnage.etats.get(int(id_texte), {})
		var nom_etat: String = str(definition.get("nom", "Etat %d" % int(id_texte)))
		var effet_actif: Dictionary = effets[id_texte]
		var piles: int = int(effet_actif.get("piles", 1))
		var duree: int = int(effet_actif.get("duree", 1))
		var duree_texte: String = "1 tour" if duree == 1 else "%d tours" % duree
		var piles_texte: String = " x%d" % piles if piles > 1 else ""
		lignes.append("%s - %s%s" % [nom_etat, duree_texte, piles_texte])
	return "\n".join(lignes)

func _positionner_fiche_ennemi() -> void:
	if _fiche_ennemi == null or not _fiche_ennemi.visible:
		return
	var taille_vue: Vector2 = get_viewport().get_visible_rect().size
	var taille_fiche: Vector2 = _fiche_ennemi.size
	if taille_fiche == Vector2.ZERO:
		taille_fiche = _fiche_ennemi.custom_minimum_size
	var souris: Vector2 = get_viewport().get_mouse_position()
	var position_fiche: Vector2 = souris + Vector2(18, 18)
	if position_fiche.x + taille_fiche.x > taille_vue.x:
		position_fiche.x = souris.x - taille_fiche.x - 18
	if position_fiche.y + taille_fiche.y > taille_vue.y:
		position_fiche.y = souris.y - taille_fiche.y - 18
	_fiche_ennemi.position = position_fiche.clamp(Vector2.ZERO, (taille_vue - taille_fiche).max(Vector2.ZERO))

func _process(_delta: float) -> void:
	if _fiche_ennemi != null and _fiche_ennemi.visible:
		_positionner_fiche_ennemi()

# un ennemi détecte le joueur : sa rencontre entière rejoint les
# propositions — y compris les membres placés hors des zones de
# détection (le combat est contre un groupe, pas un voisinage)
func proposer_combat(ennemi: Node) -> void:
	if en_combat or ennemi == null or not is_instance_valid(ennemi):
		return
	if int(ennemi.get("pv")) <= 0:
		return
	if not _detecteurs.has(ennemi):
		_detecteurs.append(ennemi)
	_maj_propositions()

func annuler_proposition_combat(ennemi: Node) -> void:
	if not _detecteurs.has(ennemi):
		return
	_detecteurs.erase(ennemi)
	_maj_propositions()

# propositions = union des rencontres des ennemis qui détectent le
# joueur ; le bouton annonce l'effectif réel du combat
func _maj_propositions() -> void:
	_propositions = []
	for detecteur in _detecteurs:
		for membre in _groupe_de(detecteur):
			if int(membre.get("pv")) > 0 and not _propositions.has(membre):
				_propositions.append(membre)
	if en_combat:
		return
	if _propositions.is_empty():
		_bouton_combattre.hide()
	else:
		_bouton_combattre.text = "Combattre" if _propositions.size() == 1 else "Combattre (x%d)" % _propositions.size()
		_bouton_combattre.show()

# la rencontre d'un ennemi : lui seul si son groupe n'est pas étiqueté
# (comportement historique), tous les ennemis connus de même étiquette
# sinon
func _groupe_de(ennemi: Node) -> Array:
	var etiquette := _etiquette_de(ennemi)
	if etiquette.is_empty():
		return [ennemi]
	var membres := []
	for connu in _ennemis_connus:
		if connu == null or not is_instance_valid(connu) or int(connu.get("pv")) <= 0:
			continue
		if _etiquette_de(connu) == etiquette:
			membres.append(connu)
	return membres

# accès public au camp d'un ennemi (surbrillance rouge au survol,
# voir ennemy.gd)
func membres_du_camp(ennemi: Node) -> Array:
	return _groupe_de(ennemi)

func _etiquette_de(entite: Node) -> String:
	if entite == null or not is_instance_valid(entite):
		return ""
	var etiquette = entite.get("groupe")
	if etiquette == null:
		return ""
	return str(etiquette)

func _on_bouton_combattre_presse() -> void:
	var groupe := _propositions.duplicate()
	_propositions.clear()
	_bouton_combattre.hide()
	lancer_combat(groupe)

# engagement automatique (clic sur un ennemi en exploration, voir
# ennemy.gd) : lance directement le combat contre la rencontre cliquée,
# sans passer par le bouton Combattre
func engager_rencontre(ennemi: Node) -> void:
	if en_combat or ennemi == null or not is_instance_valid(ennemi):
		return
	if int(ennemi.get("pv")) <= 0:
		return
	_bouton_combattre.hide()
	_propositions.clear()
	lancer_combat(_groupe_de(ennemi))

# engage un combat : contre le groupe d'ennemis donné (tableau), ou
# l'ennemi le plus proche du joueur si rien n'est fourni
func lancer_combat(groupe = null) -> void:
	if en_combat:
		return
	_bouton_combattre.hide()
	_propositions.clear()
	var ennemis: Array = []
	if groupe is Array:
		for ennemi in groupe:
			if is_instance_valid(ennemi) and int(ennemi.get("pv")) > 0 and not ennemis.has(ennemi):
				ennemis.append(ennemi)
	elif groupe is Node2D and is_instance_valid(groupe) and int(groupe.get("pv")) > 0:
		ennemis.append(groupe)
	if ennemis.is_empty():
		var proche := ennemi_proche()
		if proche == null:
			push_warning("Combat impossible : joueur ou ennemi introuvable.")
			return
		ennemis.append(proche)
	if _joueur == null:
		push_warning("Combat impossible : joueur introuvable.")
		return
	# monde partagé : l'étiquette du camp combattu est connue avant
	# l'arène car elle détermine le plan — tous les joueurs qui
	# engagent ce même camp sur cette map partagent la même grille
	# (mêmes cases, mêmes lignes de vue, mêmes trajets rejoués)
	groupe_combat = ""
	for ennemi_combat in ennemis:
		var etiquette_combat := _etiquette_de(ennemi_combat)
		if etiquette_combat != "":
			groupe_combat = etiquette_combat
			break
	_ouvrir_arene(_index_plan_partage(groupe_combat))
	var places := _arene.cases_ennemis()
	if ennemis.size() > places.size():
		_quitter_arene()
		afficher_message("Il n’y a pas assez de place dans l’arène pour cette rencontre.")
		return
	_ennemis = ennemis
	# difficulté : les ennemis entrent dans l'arène durcis (les ennemis
	# qui survivent à un combat perdu retrouvent leurs stats en_sortie) ;
	# les dégâts montent avec le niveau du joueur pour suivre sa défense
	var facteur_degats := DIFFICULTE_DEGATS * (1.0 + float(maxi(Personnage.niveau - 1, 0)) * DEGATS_PAR_NIVEAU)
	for ennemi_durci in _ennemis:
		if ennemi_durci.has_method("durcir"):
			ennemi_durci.durcir(DIFFICULTE_PV, facteur_degats)
	_etats_actifs.clear()
	_raz_recompenses()
	numero_combat += 1
	en_combat = true
	en_placement = true
	_placer_dans_arene(_joueur, _arene.case_joueur())
	for i in _ennemis.size():
		var ennemi: Node2D = _ennemis[i]
		_connecter_survol_ennemi(ennemi)
		_placer_dans_arene(ennemi, places[i])
	_arene.activer_camera()
	_maj_ennemi_principal()
	_mettre_a_jour_etiquette_etats()
	_actualiser_fiche_ennemi()
	if _souris_sur_ennemi:
		_survol_ennemi()
	placement_commence.emit()
	# roster des combattants : visible pendant le combat, tour actif nul
	# jusqu'à la première annonce (le placement n'est le tour de personne)
	_combattant_actif = null
	_retirer_marqueur_tour()
	tour_actif_change.emit(_combattant_actif)
	defplier_roster()
	_rafraichir_roster()
	# monde partagé : annoncer le combat contre ce camp (lookup au
	# runtime : Reseau n'est pas chargé dans l'éditeur)
	groupe_actif = groupe_combat != "" and not pvp_actif
	_raz_tours_groupe()
	if groupe_combat != "":
		var reseau := get_tree().root.get_node_or_null("/root/Reseau")
		if reseau != null:
			reseau.call("debut_combat_local", groupe_combat)
	# combat de groupe : les coéquipiers font apparaître notre miroir
	if groupe_actif:
		var reseau_groupe := get_tree().root.get_node_or_null("/root/Reseau")
		if reseau_groupe != null:
			reseau_groupe.call("emettre_action_groupe", _profil_groupe())

# plan d'arène d'un combat partagé : identique pour tous ceux qui
# combattent le même camp sur la même map (les cases relayées par le
# réseau coïncident) ; aléatoire pour une rencontre sans étiquette
func _index_plan_partage(etiquette_camp: String) -> int:
	if etiquette_camp == "":
		return _hasard.randi_range(0, ARENE_COMBAT.PLANS.size() - 1)
	var nom_scene := str(get_tree().current_scene.name)
	return absi((nom_scene + "|" + etiquette_camp).hash()) % ARENE_COMBAT.PLANS.size()

# duel contre un joueur distant : l'arène utilise le même plan des deux
# côtés (grilles identiques), l'adversaire est un miroir dont les
# actions nous parviennent par le réseau, et l'issue est annoncée par le
# serveur quand l'un des deux tombe
func lancer_duel(adversaire: SCRIPT_ADVERSAIRE_PVP, premier: bool) -> void:
	if en_combat or adversaire == null or not is_instance_valid(adversaire):
		return
	_bouton_combattre.hide()
	_propositions.clear()
	if _joueur == null or not is_instance_valid(_joueur):
		push_warning("Duel impossible : joueur introuvable.")
		return
	_ouvrir_arene(0)
	pvp_actif = true
	pvp_premier = premier
	_pvp_adversaire = adversaire
	_ennemis = [adversaire]
	_etats_actifs.clear()
	_raz_recompenses()
	numero_combat += 1
	en_combat = true
	en_placement = true
	# sans symétrie imposée, chaque duelliste plaçait SON joueur sur la
	# case joueur de sa grille — la même case des deux côtés — pendant
	# que le miroir campait sur une case que son propriétaire
	# n'occupait jamais : le premier déplacement révélait l'écart par un
	# téléportage ; le premier part donc à gauche, le second en face à
	# droite, et chaque miroir naît sur la vraie case de son propriétaire
	_placer_dans_arene(_joueur, case_depart_duel(premier))
	_connecter_survol_ennemi(adversaire)
	_placer_dans_arene(adversaire, case_depart_duel(not premier))
	_arene.activer_camera()
	_maj_ennemi_principal()
	_mettre_a_jour_etiquette_etats()
	_actualiser_fiche_ennemi()
	placement_commence.emit()
	# roster des combattants : visible pendant le duel, tour actif nul
	# jusqu'à la première annonce
	_combattant_actif = null
	_retirer_marqueur_tour()
	tour_actif_change.emit(_combattant_actif)
	defplier_roster()
	_rafraichir_roster()

# case de départ d'un duelliste : le premier à gauche (case joueur),
# son adversaire en vis-à-vis sur la même ligne, à droite ; les deux
# grilles étant identiques, chaque client calcule la même paire et le
# miroir de l'adversaire occupe, dès l'ouverture de l'arène, la case
# que son propriétaire occupe vraiment chez lui
func case_depart_duel(premier: bool) -> Vector2i:
	var gauche := _arene.case_joueur()
	if premier:
		return gauche
	var sol := _arene.sol
	var colonne := _arene.dimensions.x - 3
	while colonne > gauche.x \
			and (sol.get_cell_source_id(Vector2i(colonne, gauche.y)) == -1 \
			or _arene.est_mur(Vector2i(colonne, gauche.y))):
		colonne -= 1
	return Vector2i(maxi(colonne, gauche.x + 1), gauche.y)

# une action de l'adversaire distant, relayée par le serveur, rejouée
# sur notre grille : profil, déplacements, sorts résolus chez lui
# (dégâts, soins, états) et fin de son tour
func pvp_action_recue(evenement: Dictionary) -> void:
	if not pvp_actif:
		return
	var type := str(evenement.get("t", ""))
	var adversaire := _adversaire_valide()
	match type:
		"profil":
			if adversaire != null:
				adversaire.appliquer_profil(evenement.get("profil", {}))
		"placement":
			# l'adversaire vient de valider sa place : le miroir la
			# rejoint instantanément (la case est relayée, la grille est
			# la même) — sans cet événement, il restait sur sa case de
			# naissance et le premier trajet de combat le corrigeait
			# d'un glissement
			var case_recue = evenement.get("case", [])
			var sol_place := sol_combat()
			if adversaire != null and sol_place != null and case_recue is Array \
					and (case_recue as Array).size() == 2:
				var case_arrivee := Vector2i(int(case_recue[0]), int(case_recue[1]))
				if dans_zone_combat(case_arrivee) \
						and sol_place.get_cell_source_id(case_arrivee) != -1:
					adversaire.arreter_deplacement_combat()
					adversaire.global_position = sol_place.to_global(
						sol_place.map_to_local(case_arrivee))
		"deplacement":
			var sol := sol_combat()
			if adversaire != null and sol != null:
				adversaire.rejouer_trajet(evenement.get("trajet", []), sol)
		"manque", "sort":
			_rejouer_sort_distant(evenement)
		"sort_case":
			# sort adverse posé sur une case vide : aucune victime
			# n'annoncera l'animation, l'ancre la joue à sa place
			var case_sort = evenement.get("case", [])
			if adversaire != null and case_sort is Array \
					and (case_sort as Array).size() == 2:
				_rejouer_sort_sur_case(str(evenement.get("id", "")), adversaire,
					Vector2i(int(case_sort[0]), int(case_sort[1])))
				afficher_message("%s lance %s." % [_nom_adversaire(),
					str(evenement.get("nom", "un sort"))])
		"echange":
			_rejouer_echange_distant(evenement)
			afficher_message("%s utilise Shambles !" % _nom_adversaire())
		"fin_tour":
			if adversaire != null:
				adversaire.terminer_tour_distant()
				# ses états se décomptent aussi chez nous : le roster
				# du haut droit suit leurs durées réelles
				terminer_tour(adversaire)
	_mettre_a_jour_etiquette_etats()

func _adversaire_valide() -> SCRIPT_ADVERSAIRE_PVP:
	if _pvp_adversaire != null and is_instance_valid(_pvp_adversaire):
		return _pvp_adversaire
	return null

func _nom_adversaire() -> String:
	var adversaire := _adversaire_valide()
	if adversaire == null:
		return "L'adversaire"
	return str(adversaire.get("nom"))

# le sort a été entièrement résolu côté lanceur : on applique ici les
# conséquences sur la victime locale (nous ou notre miroir de lui)
func _rejouer_sort_distant(evenement: Dictionary) -> void:
	var touche := str(evenement.get("t", "sort")) != "manque"
	if not touche:
		afficher_message("%s rate son sort." % _nom_adversaire())
	var cible_moi := str(evenement.get("cible", "adv")) == "adv"
	var cible: Node = _joueur if cible_moi else _adversaire_valide()
	if cible == null or not is_instance_valid(cible):
		return
	jouer_animation_sort(str(evenement.get("id", "")), _adversaire_valide(), cible as Node2D, touche)
	if not touche:
		return
	var soin := int(evenement.get("soin", 0))
	if soin > 0:
		if cible == _joueur:
			Personnage.soigner(soin)
			_joueur.call("_maj_affichage")
		elif cible.has_method("soigner"):
			cible.soigner(soin)
	var degats := int(evenement.get("degats", 0))
	if degats > 0 and cible == _joueur:
		_joueur.recevoir_degats(degats)   # gère aussi notre mort locale
	var etats: Array = evenement.get("etats", [])
	if not etats.is_empty():
		pvp_appliquer_etats(cible, etats)
	var nom_sort := str(evenement.get("nom", "un sort"))
	afficher_message("%s lance %s." % [_nom_adversaire(), nom_sort])

# un sort distant posé sur une case vide, rejoué : une ancre invisible
# remplace la victime absente — l'animation part du miroir du lanceur
# vers la case visée, comme dans l'arène de son propriétaire
func _rejouer_sort_sur_case(id_sort: String, lanceur: Node2D, case_visee: Vector2i) -> void:
	var sol := sol_combat()
	if lanceur == null or not is_instance_valid(lanceur) or sol == null:
		return
	if not dans_zone_combat(case_visee):
		return
	var ancre := Node2D.new()
	get_tree().current_scene.add_child(ancre)
	ancre.global_position = sol.to_global(sol.map_to_local(case_visee))
	jouer_animation_sort(id_sort, lanceur, ancre, true)
	get_tree().create_timer(3.0).timeout.connect(func():
		if is_instance_valid(ancre):
			ancre.queue_free())

# un Shambles relancé ici : les deux cases de l'échange partent telles
# quelles — les grilles étant identiques, la permutation rejouée
# déplace exactement les mêmes occupants (et le même mur)
func _rejouer_echange_distant(evenement: Dictionary) -> void:
	var cases_recues: Array = evenement.get("cases", [])
	if cases_recues.size() != 2:
		return
	permuter_cases(
		Vector2i(int(cases_recues[0][0]), int(cases_recues[0][1])),
		Vector2i(int(cases_recues[1][0]), int(cases_recues[1][1])))

# états appliqués chez le lanceur, rejoués ici à l'identique (pas de
# nouveaux jets de dés : les valeurs font foi)
func pvp_appliquer_etats(cible: Node, etats: Array) -> void:
	if cible == null or not is_instance_valid(cible) or etats.is_empty():
		return
	var par_cible: Dictionary = _etats_actifs.get(cible.get_instance_id(), {})
	for etat in etats:
		var id_etat := int(etat.get("id", 0))
		if id_etat <= 0:
			continue
		par_cible[str(id_etat)] = {
			"duree": maxi(int(etat.get("duree", 1)), 1),
			"valeur": float(etat.get("valeur", 0.0)),
			"piles": maxi(int(etat.get("piles", 1)), 1),
			# frais pour notre joueur (il vient d'être appliqué) et
			# pour un miroir : décompte à la fin du tour de son
			# propriétaire, pas à la nôtre
			"frais": cible == _joueur or cible.get("distante") == true,
		}
		if id_etat == 8 or id_etat == 9:
			_deplacer_par_etat(cible, int(float(etat.get("valeur", 1.0))), id_etat == 8)
	_etats_actifs[cible.get_instance_id()] = par_cible

# ============================================================
#  COMBATS DE GROUPE (PvE a plusieurs, instances relieurs)
# ============================================================

# profil du joueur local, diffuse aux coequipiers pour notre miroir ;
# embarque notre case d'arène pour que notre place soit rejouée chez
# eux (même grille : le plan est partagé par étiquette de camp)
func _profil_groupe() -> Dictionary:
	var visuel := "humain_pirate"
	var pa_max := 6
	var pm_max := 3
	var case_mine := Vector2i(2, 2)
	if _joueur != null:
		if _joueur.has_method("_prefixe_visuel_race"):
			visuel = str(_joueur.call("_prefixe_visuel_race"))
		pa_max = int(_joueur.get("pa_max"))
		pm_max = int(_joueur.get("pm_max"))
		if _joueur.has_method("ma_case"):
			case_mine = _joueur.call("ma_case")
	return {"t": "profil_groupe", "visuel": visuel,
		"pv": int(Personnage.vie), "pv_max": int(Personnage.vie_max),
		"attaque": int(Personnage.attaque), "defense": int(Personnage.defense),
		"pa_max": pa_max, "pm_max": pm_max,
		"case": [case_mine.x, case_mine.y]}

# le serveur nous transmet les combattants deja en place (on arrive)
func groupe_membres_recus(presents: Array) -> void:
	if not groupe_actif:
		return
	for present in presents:
		if present is Dictionary:
			_apparaitre_miroir_groupe(int(present.get("peer", 0)),
				str(present.get("pseudo", "??")), str(present.get("visuel", "humain_pirate")))

# une action d'un coequipier, resolue chez lui, jouee ici
func groupe_action_recue(peer_exp: int, pseudo_exp: String, evenement: Dictionary) -> void:
	if not groupe_actif or evenement == null or evenement is not Dictionary:
		return
	match str(evenement.get("t", "")):
		"pret":
			_prets_groupe[peer_exp] = int(evenement.get("init", 0))
			if _suis_arbitre_groupe():
				_diffuser_ordre_groupe()
		"ordre":
			if int(peer_exp) == _arbitre_groupe():
				_appliquer_ordre_groupe(evenement)
		"profil_groupe":
			var profil: Dictionary = evenement.duplicate()
			profil["pseudo"] = pseudo_exp
			var miroir = _apparaitre_miroir_groupe(peer_exp, pseudo_exp,
				str(profil.get("visuel", "humain_pirate")))
			if miroir != null:
				miroir.appliquer_profil(profil)
				# notre grille est identique (plan partagé) : le miroir
				# rejoint la vraie case de son propriétaire
				var case_recue = profil.get("case", [])
				if case_recue is Array and (case_recue as Array).size() == 2:
					_placer_miroir_sur_case(miroir,
						Vector2i(int(case_recue[0]), int(case_recue[1])))
		"deplacement":
			var miroir_depl = _miroirs_groupe.get(peer_exp)
			var sol := sol_combat()
			if is_instance_valid(miroir_depl) and sol != null:
				miroir_depl.rejouer_trajet(evenement.get("trajet", []), sol)
		"ennemi_deplacement":
			var ennemi_dep = _ennemi_du_nom(str(evenement.get("nom", "")))
			if ennemi_dep != null:
				ennemi_dep.rejouer_deplacement(evenement.get("trajet", []), sol_combat())
		"ennemi_attaque":
			_rejouer_attaque_ennemie(evenement, true)
		"ennemi_manque":
			_rejouer_attaque_ennemie(evenement, false)
			afficher_message("L’ennemi rate son coup.")
		"ennemi_fin":
			_fins_ennemis_recues[str(evenement.get("nom", ""))] = true
		"gura_allie":
			# le Séisme frappe les alliés : la vraie victime encaisse
			# chez elle (nous : notre joueur, sinon notre miroir du pair)
			var victime_gura = _cible_par_cle(str(evenement.get("cible", "")))
			if victime_gura != null and is_instance_valid(victime_gura):
				victime_gura.recevoir_degats(int(evenement.get("degats", 0)))
		"gura_pousse":
			# le Fracas Sismique repousse un ennemi : chaque copie
			# locale recule du même pas (2 cases), loin du lanceur
			var pousse = _ennemi_du_nom(str(evenement.get("nom", "")))
			if pousse != null and is_instance_valid(pousse) and int(pousse.get("pv")) > 0:
				_deplacer_par_etat(pousse, 2, true)
		"manque", "sort":
			_rejouer_sort_groupe(peer_exp, pseudo_exp, evenement)
		"echange":
			_rejouer_echange_distant(evenement)
			afficher_message("%s utilise Shambles !" % pseudo_exp)
		"sort_case":
			# sort de coéquipier posé sur une case vide : l'ancre en
			# joue l'animation, aucune victime ne la portera
			var lanceur_case = _miroirs_groupe.get(peer_exp)
			var case_sort_groupe = evenement.get("case", [])
			if is_instance_valid(lanceur_case) and case_sort_groupe is Array \
					and (case_sort_groupe as Array).size() == 2:
				_rejouer_sort_sur_case(str(evenement.get("id", "")), lanceur_case,
					Vector2i(int(case_sort_groupe[0]), int(case_sort_groupe[1])))
				afficher_message("%s lance %s." % [pseudo_exp,
					str(evenement.get("nom", "un sort"))])
		"fin_tour":
			afficher_message("%s termine son tour." % pseudo_exp)
			# les états de son miroir se décomptent à sa fin de tour,
			# comme côté propriétaire (le roster suit les durées)
			var miroir_fin = _miroirs_groupe.get(peer_exp)
			if is_instance_valid(miroir_fin):
				terminer_tour(miroir_fin)
				# le pilote de tours attendait sa fin : il repart
				miroir_fin.terminer_tour_distant()
		"tombe":
			afficher_message("%s est a terre !" % pseudo_exp)
			_retirer_miroir_groupe(peer_exp)
	_mettre_a_jour_etiquette_etats()

# Un sort de coéquipier cible son miroir ou l'ennemi partagé.
func _rejouer_sort_groupe(peer_exp: int, pseudo_exp: String, evenement: Dictionary) -> void:
	var touche := str(evenement.get("t", "sort")) != "manque"
	if not touche:
		afficher_message("%s rate son sort." % pseudo_exp)
	var id_sort := str(evenement.get("id", ""))
	var lanceur := _miroirs_groupe.get(peer_exp) as Node2D
	if str(evenement.get("cible", "")) == "soi":
		if is_instance_valid(lanceur):
			jouer_animation_sort(id_sort, lanceur, lanceur, touche)
			if not touche:
				return
			var soin := int(evenement.get("soin", 0))
			if soin > 0:
				lanceur.soigner(soin)
			var etats_soi: Array = evenement.get("etats", [])
			if not etats_soi.is_empty():
				pvp_appliquer_etats(lanceur, etats_soi)
		if touche:
			afficher_message("%s lance %s." % [pseudo_exp, str(evenement.get("nom", "un sort"))])
		return
	# attaque : le nom du node désigne le même ennemi chez tous les
	# coéquipiers (grille et scène identiques) ; l'index ne reste
	# aligné que tant qu'aucun ennemi n'est tombé d'un côté, il ne
	# sert que de repli aux événements plus anciens
	var ennemis := ennemis_actifs()
	var cible: Node = null
	var cible_nom := str(evenement.get("cible_nom", ""))
	if cible_nom != "":
		for ennemi in ennemis:
			if str((ennemi as Node).name) == cible_nom:
				cible = ennemi
				break
	if cible == null:
		var index := int(evenement.get("index", -1))
		if index >= 0 and index < ennemis.size():
			cible = ennemis[index]
	if cible == null:
		return
	jouer_animation_sort(id_sort, lanceur, cible as Node2D, touche)
	if not touche:
		return
	var degats := int(evenement.get("degats", 0))
	if degats > 0 and cible.has_method("recevoir_degats"):
		cible.recevoir_degats(degats)
	var etats: Array = evenement.get("etats", [])
	if not etats.is_empty():
		pvp_appliquer_etats(cible, etats)
	afficher_message("%s lance %s." % [pseudo_exp, str(evenement.get("nom", "un sort"))])

# un coequipier quitte le combat (victoire ou defaite chez lui)
func groupe_membre_parti(peer_qui_part: int) -> void:
	_retirer_miroir_groupe(peer_qui_part)

# fait apparaitre le miroir d'un coequipier dans notre arene : sur une
# case libre proche de nous (sa vraie case suivra dès que son profil
# ou ses deplacements arriveront)
func _apparaitre_miroir_groupe(peer_id: int, nom_recu: String, visuel_recu: String):
	if not groupe_actif or peer_id == 0 or _joueur == null:
		return null
	var existant = _miroirs_groupe.get(peer_id)
	if is_instance_valid(existant):
		return existant
	var miroir := SCRIPT_ADVERSAIRE_PVP.new()
	miroir.nom = nom_recu
	miroir.distante = true
	miroir.allie = true
	miroir.sante_modifiee.connect(_sur_sante_miroir)
	get_tree().current_scene.add_child(miroir)
	miroir.definir_visuel(visuel_recu)
	miroir.global_position = _joueur.global_position
	if _joueur.has_method("ma_case"):
		_placer_miroir_sur_case(miroir, _joueur.call("ma_case"))
	_miroirs_groupe[peer_id] = miroir
	_rafraichir_roster()
	afficher_message("%s combat a tes cotes !" % nom_recu)
	return miroir

# place le miroir de coequipier sur la case demandee (relayee par son
# proprietaire) ; si elle est occupee — chacun se place sur la case
# joueur de sa propre arene — la case libre la plus proche gagne
func _placer_miroir_sur_case(miroir: Node2D, case_voulue: Vector2i) -> void:
	if miroir == null or not is_instance_valid(miroir):
		return
	var sol := sol_combat()
	if sol == null:
		return
	# une case hors arène n'a pas de sens ici ; une case murée trouve
	# son voisin libre par le parcours ci-dessous
	if not dans_zone_combat(case_voulue):
		return
	var visitees := {}
	var file: Array[Vector2i] = [case_voulue]
	var index := 0
	while index < file.size():
		var courante: Vector2i = file[index]
		index += 1
		if visitees.has(courante):
			continue
		visitees[courante] = true
		if sol.get_cell_source_id(courante) != -1 and not _case_combat_occupee(courante, miroir):
			miroir.global_position = sol.to_global(sol.map_to_local(courante))
			return
		for direction in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
			var voisine: Vector2i = courante + direction
			if dans_zone_combat(voisine) and not visitees.has(voisine):
				file.append(voisine)
	# rien de libre : rester à sa position approximative

# true si une case de l'arène est déjà prise (par le joueur local, un
# miroir de coéquipier ou un ennemi — le miroir en cours de placement
# ne compte pas)
func _case_combat_occupee(case_sol: Vector2i, miroir_ignore: Node2D) -> bool:
	var sol := sol_combat()
	if sol == null:
		return true
	if _joueur != null and is_instance_valid(_joueur) and _joueur is Node2D:
		if sol.local_to_map(sol.to_local((_joueur as Node2D).global_position)) == case_sol:
			return true
	if ennemi_sur_case(case_sol) != null:
		return true
	for pair in _miroirs_groupe:
		var miroir = _miroirs_groupe[pair]
		if miroir is Node2D and miroir != miroir_ignore and is_instance_valid(miroir):
			if sol.local_to_map(sol.to_local((miroir as Node2D).global_position)) == case_sol:
				return true
	return false

func _retirer_miroir_groupe(peer_id: int) -> void:
	var miroir = _miroirs_groupe.get(peer_id)
	_miroirs_groupe.erase(peer_id)
	if is_instance_valid(miroir):
		miroir.queue_free()

func _retirer_tous_miroirs_groupe() -> void:
	for peer_id in _miroirs_groupe.keys():
		_retirer_miroir_groupe(int(peer_id))

# les miroirs de coéquipiers engagés dans notre combat de groupe
func miroirs_groupe() -> Array:
	var liste: Array = []
	for miroir in _miroirs_groupe.values():
		if is_instance_valid(miroir):
			liste.append(miroir)
	return liste

# le pair propriétaire d'un miroir de coéquipier (0 si introuvable)
func peer_du_miroir(miroir: Node2D) -> int:
	for pair in _miroirs_groupe:
		if _miroirs_groupe[pair] == miroir:
			return int(pair)
	return 0

# ============================================================
#  TOURS SYNCHRONISES DU COMBAT DE GROUPE
# ============================================================

# le combat tourne au tour par tour : l'ordre est décidé par
# l'initiative (agilité, niveau et un dé 20 pour chacun), l'arbitre du
# combat — le pair d'identifiant le plus bas — le calcule et le
# diffuse ; seul l'arbitre résout l'IA des ennemis, les autres
# rejouent ses événements, et personne ne joue hors de son tour

func combat_groupe_synchro() -> bool:
	return en_combat and groupe_actif and not _ordre_tours.is_empty()

func _emettre_groupe(evenement: Dictionary) -> void:
	var reseau := get_tree().root.get_node_or_null("/root/Reseau")
	if reseau != null:
		reseau.call("emettre_action_groupe", evenement)

# pairs engagés dans ce combat : nous, nos miroirs et ceux qui ont
# annoncé leur initiative (les événements peuvent se croiser : un pret
# arrive avant le profil)
func _pairs_du_combat() -> Array:
	var pairs := [multiplayer.get_unique_id()]
	for peer in _miroirs_groupe:
		pairs.append(int(peer))
	for peer in _prets_groupe:
		pairs.append(int(peer))
	return pairs

func _arbitre_groupe() -> int:
	var pairs := _pairs_du_combat()
	var plus_bas := int(pairs[0])
	for pair in pairs:
		if int(pair) < plus_bas:
			plus_bas = int(pair)
	return plus_bas

func _mon_peer() -> int:
	return int(multiplayer.get_unique_id())

func _suis_arbitre_groupe() -> bool:
	return _arbitre_groupe() == _mon_peer()

# l'arbitre construit l'ordre complet — joueurs et ennemis, triés par
# initiative décroissante — et le diffuse ; l'entrée active repart
# avec pour que chacun reprenne le combat à l'identique
func _diffuser_ordre_groupe() -> void:
	if not _suis_arbitre_groupe() or not en_combat:
		return
	var entrees: Array = [
		{"k": "p", "id": _mon_peer(), "init": _ma_initiative}]
	for peer in _prets_groupe:
		entrees.append({"k": "p", "id": int(peer),
			"init": int(_prets_groupe[peer])})
	for ennemi in ennemis_actifs():
		var initiative := int(maxi(int(ennemi.get("degats_attaque")), 1)) + _hasard.randi_range(1, 15)
		entrees.append({"k": "e", "id": str((ennemi as Node).name),
			"init": initiative})
	entrees.sort_custom(func(a, b): return int(a["init"]) > int(b["init"]))
	var evenement := {"t": "ordre", "ordre": entrees, "actuel": _cle_active}
	_emettre_groupe(evenement)
	_appliquer_ordre_groupe(evenement)

func _cle_de(entree: Dictionary) -> String:
	if str(entree.get("k", "")) == "p":
		return "p:%d" % int(entree.get("id", 0))
	return "e:%s" % str(entree.get("id", ""))

# l'ordre arrive (premier jet ou mise à jour après un pret) : chacun
# adopte la liste et pointe sur le combattant en cours — sans relancer
# un tour déjà commencé
func _appliquer_ordre_groupe(evenement: Dictionary) -> void:
	var nouvelles: Array = evenement.get("ordre", [])
	if nouvelles.is_empty():
		return
	_ordre_tours = nouvelles
	var recherche := _cle_active
	if recherche == "":
		recherche = str(evenement.get("actuel", ""))
	_position_tour = -1
	if recherche != "":
		for index in _ordre_tours.size():
			if _cle_de(_ordre_tours[index]) == recherche:
				# déjà en train de jouer : rester sur place ; en
				# retard (rejoin) : reprendre ce tour-ci
				_position_tour = index if _cle_active != "" else index - 1
				break
	if not en_placement:
		_demarrer_pilote_groupe()

# notre joueur a fini son tour : le pilote passe au suivant de l'ordre
func fin_de_mon_tour_groupe() -> void:
	_cle_active = ""
	_demarrer_pilote_groupe()

# pilote du tour synchronisé : avance l'ordre combatant par
# combatant, saute les morts et les partis, et s'arrête dès qu'un
# humain doit jouer (nous ou l'attente de la fin de tour d'un miroir)
func _demarrer_pilote_groupe() -> void:
	if _pilote_en_cours or not combat_groupe_synchro() or en_placement:
		return
	if _joueur != null and is_instance_valid(_joueur) and bool(_joueur.get("_tour_joueur")):
		return  # je joue déjà : le pilote repartira à ma fin de tour
	_pilote_en_cours = true
	var numero := numero_combat
	while en_combat and not conclusion_en_cours and numero == numero_combat:
		var entree := _entree_active_valide()
		if entree.is_empty():
			break
		var cle := _cle_de(entree)
		_cle_active = cle
		if cle.begins_with("p:"):
			if int(entree["id"]) == _mon_peer():
				# à nous : notre tour démarre et le pilote rend la
				# main (relancé à notre fin de tour)
				definir_combattant_actif(_joueur)
				_cle_active = cle
				_joueur.call("_commencer_mon_tour", numero)
				_pilote_en_cours = false
				return
			var miroir = _miroirs_groupe.get(int(entree["id"]))
			if miroir == null or not is_instance_valid(miroir):
				_cle_active = ""
				continue
			definir_combattant_actif(miroir)
			afficher_message("Au tour de %s…" % str(miroir.nom))
			await miroir.jouer_tour(null, sol_combat())
			_cle_active = ""
			continue
		var nom_ennemi := str(entree["id"])
		var ennemi_local = _ennemi_du_nom(nom_ennemi)
		if ennemi_local == null:
			_cle_active = ""
			continue
		definir_combattant_actif(ennemi_local)
		afficher_message("C’est au tour de %s…" % str(ennemi_local.get("nom")))
		if _suis_arbitre_groupe():
			await _resoudre_tour_ennemi_groupe(ennemi_local, numero)
		else:
			await _attendre_fin_ennemi(nom_ennemi, numero)
		_cle_active = ""
	_pilote_en_cours = false

# prochaine entrée jouable : les vaincus (joueur mort, miroir disparu,
# ennemi tombé) ne prennent jamais la main
func _entree_active_valide() -> Dictionary:
	for tour in _ordre_tours.size():
		_position_tour += 1
		if _position_tour >= _ordre_tours.size():
			_position_tour = 0
		var entree: Dictionary = _ordre_tours[_position_tour]
		if str(entree.get("k", "")) == "p":
			var pair := int(entree.get("id", 0))
			if pair == _mon_peer():
				if Personnage.vie > 0:
					return entree
				continue
			var miroir = _miroirs_groupe.get(pair)
			if is_instance_valid(miroir) and int(miroir.get("pv")) > 0:
				return entree
			continue
		if _ennemi_du_nom(str(entree.get("id", ""))) != null:
			return entree
	return {}

func _ennemi_du_nom(nom: String) -> Node2D:
	for ennemi in ennemis_actifs():
		if str((ennemi as Node).name) == nom:
			return ennemi
	return null

# Le tour d'un ennemi, résolu par l'arbitre : la cible la plus proche
# parmi les combattants, chaque pas et chaque coup partent aux
# coéquipiers qui les rejouent à l'identique
func _resoudre_tour_ennemi_groupe(ennemi: Node2D, _numero: int) -> void:
	var sol := sol_combat()
	var cible := _cible_proche_combattant(ennemi)
	var cle_cible := ""
	if cible == _joueur:
		cle_cible = "p:%d" % _mon_peer()
	else:
		for pair in _miroirs_groupe:
			if _miroirs_groupe[pair] == cible:
				cle_cible = "p:%d" % int(pair)
				break
	if cible != null and sol != null:
		var emission := func(evenement: Dictionary):
			var type := str(evenement.get("t", ""))
			if type == "ennemi_attaque" or type == "ennemi_manque":
				evenement["cible"] = cle_cible
			_emettre_groupe(evenement)
		await ennemi.jouer_tour(cible, sol, emission)
	_fins_ennemis_recues[str(ennemi.name)] = true
	_emettre_groupe({"t": "ennemi_fin", "nom": str(ennemi.name)})

func _cible_proche_combattant(ennemi: Node2D) -> Node2D:
	var plus_proche: Node2D = null
	var distance_mini := INF
	if ennemi == null or not is_instance_valid(ennemi):
		return null
	for combattant in _combattants_groupe():
		var distance: float = (combattant as Node2D).global_position.distance_squared_to(
			ennemi.global_position)
		if distance < distance_mini:
			distance_mini = distance
			plus_proche = combattant
	return plus_proche

func _combattants_groupe() -> Array:
	var liste: Array = []
	if _joueur is Node2D and Personnage.vie > 0:
		liste.append(_joueur)
	for miroir in _miroirs_groupe.values():
		if is_instance_valid(miroir) and int(miroir.get("pv")) > 0:
			liste.append(miroir)
	return liste

# côté coéquipier : le tour d'un ennemi de l'arbitre se joue quand sa
# fin arrive (événement fiable ordonné)
func _attendre_fin_ennemi(nom_ennemi: String, numero: int) -> void:
	while en_combat and numero == numero_combat and not _fins_ennemis_recues.has(nom_ennemi):
		await get_tree().process_frame
	_fins_ennemis_recues.erase(nom_ennemi)

# un coup d'ennemi résolu par l'arbitre, rejoué ici : la victime est
# la nôtre ("peer:moi") ou le miroir d'un coéquipier
func _rejouer_attaque_ennemie(evenement: Dictionary, touche: bool) -> void:
	var ennemi_partant = _ennemi_du_nom(str(evenement.get("nom", "")))
	var cible = _cible_par_cle(str(evenement.get("cible", "")))
	if ennemi_partant == null or cible == null or not is_instance_valid(cible):
		return
	ennemi_partant.rejouer_attaque(cible,
		int(evenement.get("degats", 0)), touche)

func _cible_par_cle(cle: String) -> Node2D:
	if not cle.begins_with("p:"):
		return null
	var pair := int(cle.substr(2))
	if pair == _mon_peer():
		return _joueur as Node2D
	var miroir = _miroirs_groupe.get(pair)
	if miroir is Node2D:
		return miroir
	return null

func _raz_tours_groupe() -> void:
	_ordre_tours = []
	_position_tour = -1
	_prets_groupe = {}
	_ma_initiative = 0
	_cle_active = ""
	_fins_ennemis_recues = {}
	_pilote_en_cours = false

# un ennemi du groupe est vaincu : le combat continue tant qu'il en
# reste un debout
func ennemi_vaincu(ennemi: Node) -> void:
	_ennemis.erase(ennemi)
	_ennemis_connus.erase(ennemi)
	_detecteurs.erase(ennemi)
	if ennemi == _cible_selectionnee:
		_cible_selectionnee = null
	if ennemi == _ennemi:
		_maj_ennemi_principal()
	if _propositions.has(ennemi):
		_propositions.erase(ennemi)
	if ennemi == _combattant_actif:
		definir_combattant_actif(null)
	elif en_combat:
		_rafraichir_roster()
	if not en_combat:
		_maj_propositions()
	if en_combat and ennemis_actifs().is_empty():
		terminer_sur_impact(true, ennemi)

func terminer_sur_impact(victoire: bool, cible: Node) -> void:
	if not en_combat or conclusion_en_cours:
		return
	var animation := _dernier_sort_anime
	if is_instance_valid(animation) and not animation.is_queued_for_deletion() \
			and animation.cible_id == cible.get_instance_id():
		conclusion_en_cours = true
		definir_combattant_actif(null)
		var numero := numero_combat
		await animation.tree_exited
		if not conclusion_en_cours or numero != numero_combat or not is_inside_tree():
			return
	terminer_combat(victoire)

func _ouvrir_arene(index_plan: int) -> void:
	_camera_exploration = get_viewport().get_camera_2d()
	_arene = ARENE_COMBAT.new()
	_arene.index_plan = index_plan
	var terrain := get_tree().current_scene.get_node_or_null("TerrainZone")
	if terrain != null:
		_arene.dallage = terrain.dallage
		_arene.maconnerie = terrain.maconnerie
		_arene.fond_personnalise = terrain.fond_arene
	_arene.position = POSITION_ARENE
	get_tree().current_scene.add_child(_arene)

func _placer_dans_arene(entite: Node2D, case: Vector2i) -> void:
	_positions_exploration[entite] = entite.global_position
	var sol := sol_combat()
	entite.global_position = sol.to_global(sol.map_to_local(case))

func _quitter_arene() -> void:
	for entite in _positions_exploration:
		if is_instance_valid(entite):
			entite.arreter_deplacement_combat()
			entite.global_position = _positions_exploration[entite]
			# un ennemi qui survit au combat (défaite ou fuite) retrouve
			# ses stats d'origine en exploration
			if entite.has_method("assouplir"):
				entite.assouplir()
	_positions_exploration.clear()
	if is_instance_valid(_camera_exploration):
		_camera_exploration.make_current()
		_camera_exploration.reset_smoothing()
		_camera_exploration.force_update_scroll()
	_camera_exploration = null
	_arene.hide()
	_arene.queue_free()
	_arene = null

func valider_placement() -> void:
	if not en_combat or not en_placement:
		return
	en_placement = false
	combat_commence.emit()
	# duel : notre case de placement part à l'adversaire — son miroir
	# de nous rejoint notre vraie place (grille identique), exactement
	# comme son miroir de nous suit la nôtre dans un combat de groupe
	if pvp_actif:
		var case_mine := Vector2i(2, 2)
		if _joueur != null and is_instance_valid(_joueur) and _joueur.has_method("ma_case"):
			case_mine = _joueur.call("ma_case")
		var reseau_duel := get_tree().root.get_node_or_null("/root/Reseau")
		if reseau_duel != null:
			reseau_duel.call("emettre_action_duel",
				{"t": "placement", "case": [case_mine.x, case_mine.y]})
	# combat de groupe : notre case de départ part aux coéquipiers —
	# leur miroir de nous rejoint notre vraie place (grille partagée)
	if groupe_actif:
		var reseau := get_tree().root.get_node_or_null("/root/Reseau")
		if reseau != null:
			reseau.call("emettre_action_groupe", _profil_groupe())
			# le combat démarre réellement : le serveur ne laisse plus
			# personne le rejoindre
			reseau.call("combat_local_lance")
		# tour synchronisé : notre initiative part à l'arbitre du combat
		# (le pair d'identifiant le plus bas), qui construit et diffuse
		# l'ordre des tours ; nous seuls, il n'y a rien à attendre
		_ma_initiative = int(Personnage.caracteristiques.get("agilite", 0)) * 2 \
			+ Personnage.niveau + _hasard.randi_range(1, 20)
		_emettre_groupe({"t": "pret", "init": _ma_initiative})
		if _suis_arbitre_groupe():
			_diffuser_ordre_groupe()

func terminer_combat(victoire: bool, fuite := false) -> void:
	if not en_combat:
		return
	conclusion_en_cours = false
	_dernier_sort_anime = null
	en_combat = false
	en_placement = false
	# plus de combat : la salle d'opération, si elle restait dressée, ferme
	effacer_salle()
	groupe_actif = false
	_raz_tours_groupe()
	# le combat est fini : plus personne ne joue, le roster et le
	# marqueur de tour disparaissent
	_combattant_actif = null
	_retirer_marqueur_tour()
	tour_actif_change.emit(_combattant_actif)
	_rafraichir_roster()
	_retirer_tous_miroirs_groupe()
	if pvp_actif:
		# notre départ du duel (défaite ou fuite) est annoncé au serveur,
		# qui préviendra l'adversaire ; une victoire locale n'est que
		# l'echo du réseau
		if not victoire:
			var reseau_depart := get_tree().root.get_node_or_null("/root/Reseau")
			if reseau_depart != null:
				reseau_depart.call("declarer_fuite_duel" if fuite else "declarer_defaite_duel")
		pvp_actif = false
		if is_instance_valid(_pvp_adversaire):
			_pvp_adversaire.queue_free()
		_pvp_adversaire = null
	if groupe_combat != "":
		var reseau := get_tree().root.get_node_or_null("/root/Reseau")
		if reseau != null:
			reseau.call("fin_combat_local", groupe_combat)
		groupe_combat = ""
	_quitter_arene()
	_etats_actifs.clear()
	_ennemis.clear()
	_propositions.clear()
	_detecteurs.clear()
	_cible_selectionnee = null
	_bouton_combattre.hide()
	_mettre_a_jour_etiquette_etats()
	if _fiche_ennemi != null:
		_fiche_ennemi.hide()
	ressources_joueur_modifiees.emit(0, 0, 0, 0)
	# récapitulatif unique du combat gagné : XP, Berry et objets de
	# tous les ennemis vaincus, une fenêtre pour tout le combat
	if victoire and int(_recompenses["vaincus"]) > 0:
		_afficher_recompenses_combat()
		_raz_recompenses()
	combat_termine.emit(victoire)

# remet à zéro les récompenses cumulées (début de combat)
func _raz_recompenses() -> void:
	_recompenses = {"vaincus": 0, "xp": 0, "berry": 0, "objets": {}}

# un ennemi vient de tomber (côté vainqueur) : ses récompenses rejoignent
# le récapitulatif de fin, présenté en une seule fenêtre
func cumuler_recompense(xp: int, berry: int, objets: Array) -> void:
	_recompenses["vaincus"] = int(_recompenses["vaincus"]) + 1
	_recompenses["xp"] = int(_recompenses["xp"]) + maxi(xp, 0)
	_recompenses["berry"] = int(_recompenses["berry"]) + maxi(berry, 0)
	var cumules: Dictionary = _recompenses["objets"]
	for objet in objets:
		if not objet is Dictionary:
			continue
		var id := str(objet.get("id", ""))
		if id == "":
			continue
		cumules[id] = int(cumules.get(id, 0)) + maxi(int(objet.get("qte", 0)), 0)

# fenêtre de fin de combat gagné : le total des récompenses accumulées
# (les objets sont déjà dans l'inventaire, l'XP et les Berry déjà versés)
func _afficher_recompenses_combat() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var lignes := ["+%d XP" % int(_recompenses["xp"]), "+%d Berry" % int(_recompenses["berry"])]
	var objets: Dictionary = _recompenses["objets"]
	if objets.is_empty():
		lignes.append("Aucun objet trouvé.")
	else:
		var noms: Array[String] = []
		for id in objets:
			noms.append("%s x%d" % [Inventaire.nom_objet(str(id)), int(objets[id])])
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

func mettre_a_jour_stats(_vie: int, _vie_max: int, pa: int, pa_max: int, pm: int, pm_max: int) -> void:
	ressources_joueur_modifiees.emit(pa, pa_max, pm, pm_max)
	_actualiser_fiche_ennemi()
	_mettre_a_jour_etiquette_etats()

func afficher_message(message: String) -> void:
	var interface_hud: Node = get_tree().current_scene.find_child("HUD", true, false)
	if interface_hud != null and interface_hud.has_method("afficher_message_sort"):
		interface_hud.call("afficher_message_sort", message)

# transmet le compte à rebours du tour au HUD (label Timer de la ligne
# de combat) ; secondes négatives = tour terminé, label effacé
func maj_temps_tour(secondes: int) -> void:
	var interface_hud: Node = get_tree().current_scene.find_child("HUD", true, false)
	if interface_hud != null and interface_hud.has_method("maj_temps_tour"):
		interface_hud.call("maj_temps_tour", secondes)

func effacer_message() -> void:
	var interface_hud: Node = get_tree().current_scene.find_child("HUD", true, false)
	if interface_hud != null and interface_hud.has_method("afficher_message_sort"):
		interface_hud.call("afficher_message_sort", "Sorts au clavier | clic : cible ou deplacement")

func demander_sort(id_sort: String) -> void:
	if en_combat and not en_placement:
		sort_demandee.emit(id_sort)

func demander_validation_placement() -> void:
	if en_combat and en_placement:
		placement_valide.emit()

func demander_fin_tour() -> void:
	if en_combat and not en_placement:
		fin_tour_demandee.emit()

func demander_fuite() -> void:
	if en_combat:
		fuite_demandee.emit()

func est_allie(sort: Dictionary) -> bool:
	return str(sort.get("type", "")) in ["buff", "defense", "heal", "healing"]

# alliés engagés dans le combat : le joueur et les miroirs de son
# groupe encore présents
func allies_actifs() -> Array:
	var allies := [_joueur]
	for miroir in _miroirs_groupe.values():
		if miroir is Node and is_instance_valid(miroir):
			allies.append(miroir)
	return allies

# la salle d'opération se dresse pour plusieurs tours : son renfort
# suit la position à chaque coup, aucun état n'est posé sur les alliés
func definir_salle(cases: Array[Vector2i]) -> void:
	cases_salle = cases.duplicate()

func effacer_salle() -> void:
	cases_salle.clear()

func _dans_salle(noeud: Node) -> bool:
	if noeud == null or not is_instance_valid(noeud) or cases_salle.is_empty():
		return false
	return cases_salle.has(case_sous_point(noeud.global_position, false))

# le camp servi par la salle : le joueur et les miroirs de son groupe
func _est_allie_local(noeud: Node) -> bool:
	if noeud == null or not is_instance_valid(noeud):
		return false
	if noeud == _joueur:
		return true
	for miroir in _miroirs_groupe.values():
		if miroir is Node and is_instance_valid(miroir) and miroir == noeud:
			return true
	return false

func appliquer_effets_sort(cible: Node, sort: Dictionary) -> Array:
	var appliques: Array = []
	if cible == null or not is_instance_valid(cible):
		return appliques
	var effets: Array = sort.get("effets", [])
	for effet in effets:
		if _hasard.randf() > float(effet.get("chance", 1.0)):
			continue
		var id_etat := int(effet.get("id", 0))
		if id_etat <= 0:
			continue
		var etat: Dictionary = Personnage.etats.get(id_etat, {})
		var par_cible: Dictionary = _etats_actifs.get(cible.get_instance_id(), {})
		var cle := str(id_etat)
		var existant: Dictionary = par_cible.get(cle, {})
		var piles := int(existant.get("piles", 0))
		if piles == 0:
			piles = 1
		elif bool(etat.get("empilable", false)):
			piles = mini(piles + 1, int(etat.get("max_stacks", 1)))
		# un état posé sur un combattant distant (miroir) est frais : il
		# ne se décompte qu'à la prochaine fin de tour de son
		# propriétaire, exactement comme dans le client où il vit
		par_cible[cle] = {"duree": maxi(int(effet.get("duree", 1)), 1), "valeur": float(effet.get("valeur", 0.0)), "piles": piles, "frais": cible == _joueur or cible.get("distante") == true}
		_etats_actifs[cible.get_instance_id()] = par_cible
		appliques.append({"id": id_etat,
			"duree": maxi(int(effet.get("duree", 1)), 1),
			"valeur": float(effet.get("valeur", 0.0)),
			"piles": piles})
		if id_etat == 8 or id_etat == 9:
			_deplacer_par_etat(cible, int(effet.get("valeur", 1.0)), id_etat == 8)
	_mettre_a_jour_etiquette_etats()
	return appliques

func a_etat(cible: Node, id_etat: int) -> bool:
	if cible == null or not is_instance_valid(cible):
		return false
	return _etats_actifs.get(cible.get_instance_id(), {}).has(str(id_etat))

func preparer_tour(cible: Node) -> bool:
	if cible == null or not is_instance_valid(cible):
		return false
	var par_cible: Dictionary = _etats_actifs.get(cible.get_instance_id(), {})
	var bloque := par_cible.has("1") or par_cible.has("4")
	for id_texte in par_cible:
		var id_etat := int(id_texte)
		var effet: Dictionary = par_cible[id_texte]
		var montant := int(round(float(effet.get("valeur", 0.0)) * float(effet.get("piles", 1))))
		if id_etat == 2 or id_etat == 3:
			_recevoir_degats(cible, maxi(montant, 1))
		elif id_etat == 12:
			_soigner_cible(cible, _soin_regeneration(cible, float(effet.get("valeur", 0.0))))
		if not is_instance_valid(cible):
			return true
	return bloque

func terminer_tour(cible: Node) -> void:
	if cible == null or not is_instance_valid(cible):
		return
	var id_cible := cible.get_instance_id()
	var par_cible: Dictionary = _etats_actifs.get(id_cible, {})
	for cle in par_cible.keys():
		var effet: Dictionary = par_cible[cle]
		if bool(effet.get("frais", false)):
			effet["frais"] = false
		else:
			effet["duree"] = int(effet.get("duree", 1)) - 1
			if int(effet["duree"]) <= 0:
				par_cible.erase(cle)
	if par_cible.is_empty():
		_etats_actifs.erase(id_cible)
	else:
		_etats_actifs[id_cible] = par_cible
	_mettre_a_jour_etiquette_etats()

func _mettre_a_jour_etiquette_etats() -> void:
	_actualiser_fiche_ennemi()
	var interface_hud: Node = get_tree().current_scene.find_child("HUD", true, false)
	if interface_hud != null and interface_hud.has_method("maj_etats_joueur"):
		interface_hud.call("maj_etats_joueur", _texte_etats_cible(_joueur))
	# le roster affiche aussi les états en cours : il suit chaque
	# application d'effet et chaque fin de tour (durées décrémentées)
	if en_combat:
		_rafraichir_roster()

func etats_joueur_texte() -> String:
	return _texte_etats_cible(_joueur)

func calculer_degats(lanceur: Node, cible: Node, degats_base: int, type_sort: String = "", portee_sort: int = 1) -> int:
	var degats := float(maxi(degats_base, 0))
	if lanceur == _joueur:
		degats += float(Personnage.attaque)
		degats += Personnage.bonus_degats_sort(type_sort, portee_sort)
	if a_etat(lanceur, 13):
		degats *= 1.0 + float(_valeur_etat(lanceur, 13)) * _piles_etat(lanceur, 13)
	if a_etat(lanceur, 16) and _hasard.randf() < float(_valeur_etat(lanceur, 16)):
		degats *= 1.5
	if a_etat(cible, 10):
		return 0
	if a_etat(cible, 11):
		degats *= 1.0 - float(_valeur_etat(cible, 11))
	if a_etat(cible, 14):
		degats *= 1.0 - float(_valeur_etat(cible, 14))
	if a_etat(cible, 3):
		degats *= 1.2
	if a_etat(cible, 17):
		degats *= 1.0 + float(_valeur_etat(cible, 17)) * _piles_etat(cible, 17)
	# la salle d'opération de la Room : aucun état, seuls les alliés
	# qui se tiennent dans la zone au moment du coup en profitent
	if not cases_salle.is_empty():
		if _est_allie_local(lanceur) and _dans_salle(lanceur):
			degats *= 1.0 + MODIFICATEUR_SALLE
		if _est_allie_local(cible) and _dans_salle(cible):
			degats *= 1.0 - MODIFICATEUR_SALLE
	# la défense réduit un pourcentage du coup reçu, comme l'armure de
	# League of Legends : dégâts x 100 / (100 + défense). Chaque point
	# de défense rapproche l'absorption de 100 % sans jamais
	# l'atteindre : un coup ne peut pas tomber à zéro et le centième
	# point de défense vaut toujours quelque chose
	if cible == _joueur:
		degats *= 100.0 / (100.0 + maxf(float(Personnage.defense), 0.0))
	elif _pvp_adversaire != null and is_instance_valid(_pvp_adversaire) and cible == _pvp_adversaire:
		degats *= 100.0 / (100.0 + maxf(float(_pvp_adversaire.defense_pvp), 0.0))
	return maxi(int(round(degats)), 0)

# réussite d'une attaque : précision de base, bonus du lanceur s'il est
# le joueur (caractéristique « Précision »), esquive retranchée si le
# joueur est la cible (caractéristique « Vitesse »)
func precision_reussie(lanceur: Node, cible: Node = null) -> bool:
	var precision := 0.9
	if lanceur == _joueur:
		precision += Personnage.bonus_precision()
	elif cible == _joueur:
		precision -= Personnage.bonus_esquive()
	if a_etat(lanceur, 6):
		precision *= maxf(0.0, 1.0 - float(_valeur_etat(lanceur, 6)) * float(_piles_etat(lanceur, 6)))
	if a_etat(lanceur, 15):
		precision += float(_valeur_etat(lanceur, 15))
	return _hasard.randf() <= clampf(precision, 0.1, 1.0)

func sort_autorise(cible: Node) -> bool:
	return not a_etat(cible, 7)

func points_mouvement(cible: Node, points: int) -> int:
	# la valeur de l'état Ralentissement donne la taille du malus (1
	# par défaut, 2 pour le Sceau des ruines) ; il reste au moins 1 PM
	if not a_etat(cible, 5):
		return points
	return maxi(points - maxi(int(round(_valeur_etat(cible, 5))), 1), 1)

func _valeur_etat(cible: Node, id_etat: int) -> float:
	return float(_etats_actifs.get(cible.get_instance_id(), {}).get(str(id_etat), {}).get("valeur", 0.0))

func _piles_etat(cible: Node, id_etat: int) -> int:
	return int(_etats_actifs.get(cible.get_instance_id(), {}).get(str(id_etat), {}).get("piles", 1))

func _recevoir_degats(cible: Node, montant: int) -> void:
	if cible.has_method("recevoir_degats"):
		cible.recevoir_degats(montant)

func _soigner_cible(cible: Node, montant: int) -> void:
	if cible == _joueur:
		Personnage.soigner(montant)
		_joueur.call("_maj_affichage")
	elif cible.has_method("soigner"):
		cible.soigner(montant)

func _soin_regeneration(cible: Node, proportion: float) -> int:
	if cible == _joueur:
		return maxi(int(round(float(Personnage.vie_max) * proportion)), 1)
	return maxi(int(round(float(cible.get("pv_max")) * proportion)), 1)

func _deplacer_par_etat(cible: Node, nombre: int, repousser: bool) -> void:
	var entite := cible as Node2D
	if entite == null:
		return
	var sol := sol_combat()
	if sol == null or nombre <= 0:
		return
	var lanceur: Node2D = null
	if cible == _joueur:
		lanceur = ennemi_proche() as Node2D
	else:
		lanceur = _joueur as Node2D
	if lanceur == null or not is_instance_valid(lanceur):
		return
	var depart := sol.local_to_map(sol.to_local(entite.global_position))
	var origine := sol.local_to_map(sol.to_local(lanceur.global_position))
	var delta := depart - origine
	var axe := Vector2i.RIGHT if absi(delta.x) >= absi(delta.y) else Vector2i.DOWN
	if (absi(delta.x) >= absi(delta.y) and delta.x < 0) or (absi(delta.x) < absi(delta.y) and delta.y < 0):
		axe = -axe
	if not repousser:
		axe = -axe
	var destination := depart
	for _i in range(nombre):
		var suivante := destination + axe
		if sol.get_cell_source_id(suivante) == -1 or not dans_zone_combat(suivante):
			break
		var occupee_par_groupe := false
		for ennemi in ennemis_actifs():
			if suivante == sol.local_to_map(sol.to_local((ennemi as Node2D).global_position)):
				occupee_par_groupe = true
				break
		if occupee_par_groupe or (cible != _joueur and suivante == sol.local_to_map(sol.to_local((_joueur as Node2D).global_position))):
			break
		destination = suivante
	entite.global_position = sol.to_global(sol.map_to_local(destination))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F:
			lancer_combat()
		elif event.keycode == KEY_G:
			terminer_combat(false)
