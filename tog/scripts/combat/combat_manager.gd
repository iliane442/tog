extends Node

signal combat_commence
signal combat_termine(victoire: bool)
signal placement_commence
signal sort_demandee(id_sort: String)
signal fin_tour_demandee
signal placement_valide
signal ressources_joueur_modifiees(pa: int, pa_max: int, pm: int, pm_max: int)

var en_combat := false
var en_placement := false
var _joueur: Node
var _ennemi
var _ui: CanvasLayer
var _fiche_ennemi: PanelContainer
var _barre_vie_ennemi: ProgressBar
var _label_nom_ennemi: Label
var _label_vie_ennemi: Label
var _label_stats_ennemi: Label
var _label_etats_ennemi: Label
var _souris_sur_ennemi := false
var _etats_actifs: Dictionary = {}
var _hasard := RandomNumberGenerator.new()
const SCENE_COMBAT_UI := preload("res://scenes/combat_ui.tscn")

func _ready() -> void:
	_hasard.randomize()
	if _joueur == null:
		_joueur = get_tree().current_scene.find_child("player", true, false)
	if _ennemi == null:
		_ennemi = get_tree().current_scene.find_child("ennemy", true, false)
	_construire_interface()
	_connecter_survol_ennemi()
	mettre_a_jour_stats(Personnage.vie, Personnage.vie_max, 6, 6, 3, 3)

func initialiser(joueur: Node, ennemi: Node) -> void:
	_joueur = joueur
	_ennemi = ennemi
	_connecter_survol_ennemi()
	_actualiser_fiche_ennemi()

func enregistrer_ennemi(ennemi: Node) -> void:
	_ennemi = ennemi
	_connecter_survol_ennemi()
	_actualiser_fiche_ennemi()

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

func _connecter_survol_ennemi() -> void:
	if _ennemi == null or not is_instance_valid(_ennemi):
		return
	var survol_entree := Callable(self, "_survol_ennemi")
	var survol_sortie := Callable(self, "_quitter_survol_ennemi")
	if _ennemi.has_signal("mouse_entered") and not _ennemi.is_connected("mouse_entered", survol_entree):
		_ennemi.connect("mouse_entered", survol_entree)
	if _ennemi.has_signal("mouse_exited") and not _ennemi.is_connected("mouse_exited", survol_sortie):
		_ennemi.connect("mouse_exited", survol_sortie)
	var maj_sante := Callable(self, "_sante_ennemi_modifiee")
	if _ennemi.has_signal("sante_modifiee") and not _ennemi.is_connected("sante_modifiee", maj_sante):
		_ennemi.connect("sante_modifiee", maj_sante)

func _survol_ennemi() -> void:
	_souris_sur_ennemi = true
	if not en_combat or _fiche_ennemi == null:
		return
	_actualiser_fiche_ennemi()
	_fiche_ennemi.show()
	_positionner_fiche_ennemi()

func _quitter_survol_ennemi() -> void:
	_souris_sur_ennemi = false
	if _fiche_ennemi != null:
		_fiche_ennemi.hide()

func _sante_ennemi_modifiee(_vie: int, _vie_max: int) -> void:
	_actualiser_fiche_ennemi()

func _actualiser_fiche_ennemi() -> void:
	if _fiche_ennemi == null or _ennemi == null or not is_instance_valid(_ennemi):
		return
	var nom_ennemi: String = str(_ennemi.get("nom"))
	if nom_ennemi.is_empty():
		nom_ennemi = "Ennemi"
	var vie_max: int = maxi(int(_ennemi.get("pv_max")), 1)
	var vie: int = clampi(int(_ennemi.get("pv")), 0, vie_max)
	_label_nom_ennemi.text = nom_ennemi
	_barre_vie_ennemi.max_value = vie_max
	_barre_vie_ennemi.value = vie
	_label_vie_ennemi.text = "%d / %d" % [vie, vie_max]
	_label_stats_ennemi.text = "ATTAQUE : %d\nPORTEE : %d cases\nDEPLACEMENT : %d PM" % [
		int(_ennemi.get("degats_attaque")),
		int(_ennemi.get("portee_attaque")),
		int(_ennemi.get("pm_max")),
	]
	_label_etats_ennemi.text = _texte_etats_cible(_ennemi)

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
	_fiche_ennemi.position = position_fiche

func _process(_delta: float) -> void:
	if _fiche_ennemi != null and _fiche_ennemi.visible:
		_positionner_fiche_ennemi()

func lancer_combat(ennemi: Node = null) -> void:
	if en_combat:
		return
	if ennemi != null:
		_ennemi = ennemi
	_connecter_survol_ennemi()
	if _joueur == null or _ennemi == null:
		push_warning("Combat impossible : joueur ou ennemi introuvable.")
		return
	_aligner_sur_grille(_joueur)
	_aligner_sur_grille(_ennemi)
	_etats_actifs.clear()
	en_combat = true
	en_placement = true
	_mettre_a_jour_etiquette_etats()
	_actualiser_fiche_ennemi()
	if _souris_sur_ennemi:
		_survol_ennemi()
	placement_commence.emit()

func _aligner_sur_grille(entite: Node2D) -> void:
	var sol := get_tree().current_scene.get_node_or_null("ground") as TileMapLayer
	if sol == null or sol.tile_set == null:
		return
	var case := sol.local_to_map(sol.to_local(entite.global_position))
	if sol.get_cell_source_id(case) == -1:
		return
	entite.global_position = sol.to_global(sol.map_to_local(case))

func valider_placement() -> void:
	if not en_combat or not en_placement:
		return
	en_placement = false
	combat_commence.emit()

func terminer_combat(victoire: bool) -> void:
	if not en_combat:
		return
	en_combat = false
	en_placement = false
	_etats_actifs.clear()
	_mettre_a_jour_etiquette_etats()
	if _fiche_ennemi != null:
		_fiche_ennemi.hide()
	ressources_joueur_modifiees.emit(0, 0, 0, 0)
	combat_termine.emit(victoire)

func mettre_a_jour_stats(_vie: int, _vie_max: int, pa: int, pa_max: int, pm: int, pm_max: int) -> void:
	ressources_joueur_modifiees.emit(pa, pa_max, pm, pm_max)
	_actualiser_fiche_ennemi()
	_mettre_a_jour_etiquette_etats()

func afficher_message(message: String) -> void:
	var interface_hud: Node = get_tree().current_scene.find_child("HUD", true, false)
	if interface_hud != null and interface_hud.has_method("afficher_message_sort"):
		interface_hud.call("afficher_message_sort", message)

func effacer_message() -> void:
	var interface_hud: Node = get_tree().current_scene.find_child("HUD", true, false)
	if interface_hud != null and interface_hud.has_method("afficher_message_sort"):
		interface_hud.call("afficher_message_sort", "Touches 1-0 : sort | clic : cible ou deplacement")

func demander_sort(id_sort: String) -> void:
	if en_combat and not en_placement:
		sort_demandee.emit(id_sort)

func demander_validation_placement() -> void:
	if en_combat and en_placement:
		placement_valide.emit()

func demander_fin_tour() -> void:
	if en_combat and not en_placement:
		fin_tour_demandee.emit()

func est_allie(sort: Dictionary) -> bool:
	return str(sort.get("type", "")) in ["buff", "defense", "heal", "healing"]

func appliquer_effets_sort(cible: Node, sort: Dictionary) -> void:
	if cible == null or not is_instance_valid(cible):
		return
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
		par_cible[cle] = {"duree": maxi(int(effet.get("duree", 1)), 1), "valeur": float(effet.get("valeur", 0.0)), "piles": piles, "frais": cible == _joueur}
		_etats_actifs[cible.get_instance_id()] = par_cible
		if id_etat == 8 or id_etat == 9:
			_deplacer_par_etat(cible, int(effet.get("valeur", 1.0)), id_etat == 8)
	_mettre_a_jour_etiquette_etats()

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

func etats_joueur_texte() -> String:
	return _texte_etats_cible(_joueur)

func calculer_degats(lanceur: Node, cible: Node, degats_base: int) -> int:
	var degats := float(maxi(degats_base, 0))
	if lanceur == _joueur:
		degats += float(Personnage.attaque)
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
	if cible == _joueur:
		degats -= float(Personnage.defense)
	return maxi(int(round(degats)), 0)

func precision_reussie(lanceur: Node) -> bool:
	var precision := 0.9
	if a_etat(lanceur, 6):
		precision *= maxf(0.0, 1.0 - float(_valeur_etat(lanceur, 6)) * float(_piles_etat(lanceur, 6)))
	if a_etat(lanceur, 15):
		precision += float(_valeur_etat(lanceur, 15))
	return _hasard.randf() <= clampf(precision, 0.1, 1.0)

func sort_autorise(cible: Node) -> bool:
	return not a_etat(cible, 7)

func points_mouvement(cible: Node, points: int) -> int:
	return maxi(points - (1 if a_etat(cible, 5) else 0), 1)

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
	var sol := get_tree().current_scene.get_node_or_null("ground") as TileMapLayer
	if sol == null or nombre <= 0:
		return
	var lanceur: Node2D = null
	if cible == _ennemi:
		lanceur = _joueur as Node2D
	else:
		lanceur = _ennemi as Node2D
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
	var obstacles := get_tree().current_scene.get_node_or_null("cliffs") as TileMapLayer
	var destination := depart
	for _i in range(nombre):
		var suivante := destination + axe
		if sol.get_cell_source_id(suivante) == -1 or (obstacles != null and obstacles.get_cell_source_id(suivante) != -1):
			break
		if (cible == _joueur and _ennemi != null and suivante == sol.local_to_map(sol.to_local(_ennemi.global_position))) or (cible == _ennemi and suivante == sol.local_to_map(sol.to_local(_joueur.global_position))):
			break
		destination = suivante
	entite.global_position = sol.to_global(sol.map_to_local(destination))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F:
			lancer_combat()
		elif event.keycode == KEY_G:
			terminer_combat(false)
