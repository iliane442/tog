extends Node

signal combat_commence
signal combat_termine(victoire: bool)
signal placement_commence
signal sort_demandee(id_sort: String)
signal fin_tour_demandee
signal placement_valide

var en_combat := false
var en_placement := false
var _joueur: Node
var _ennemi
var _ui: CanvasLayer
var _panneau: PanelContainer
var _barre_vie_joueur: ProgressBar
var _barre_vie_ennemi: ProgressBar
var _label_stats: Label
var _label_message: Label
var _label_etats: Label
var _bouton_sort: Button
var _bouton_fin_tour: Button
var _bouton_pret: Button
var _liste_sorts: VBoxContainer
var _conteneur_sorts: ScrollContainer
var _etats_actifs: Dictionary = {}
var _hasard := RandomNumberGenerator.new()

func _ready() -> void:
	_hasard.randomize()
	if _joueur == null:
		_joueur = get_tree().current_scene.find_child("player", true, false)
	if _ennemi == null:
		_ennemi = get_tree().current_scene.find_child("ennemy", true, false)
	_construire_interface()
	mettre_a_jour_stats(Personnage.vie, Personnage.vie_max, 6, 6, 3, 3)

func initialiser(joueur: Node, ennemi: Node) -> void:
	_joueur = joueur
	_ennemi = ennemi

func enregistrer_ennemi(ennemi: Node) -> void:
	_ennemi = ennemi
	if _barre_vie_ennemi != null:
		mettre_a_jour_stats(Personnage.vie, Personnage.vie_max, 0, 0, 0, 0)

func _construire_interface() -> void:
	_ui = CanvasLayer.new()
	_ui.name = "CombatUI"
	_ui.layer = 5
	add_child(_ui)
	_panneau = PanelContainer.new()
	_panneau.name = "PanneauCombat"
	_panneau.position = Vector2(24, 110)
	_panneau.custom_minimum_size = Vector2(330, 0)
	_ui.add_child(_panneau)
	var colonne := VBoxContainer.new()
	colonne.add_theme_constant_override("separation", 8)
	_panneau.add_child(colonne)
	var titre := Label.new()
	titre.text = "Combat"
	titre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	colonne.add_child(titre)
	_barre_vie_joueur = _creer_barre(colonne, "Vie du joueur", "RedBar")
	_barre_vie_ennemi = _creer_barre(colonne, "Vie de l’ennemi", "RedBar")
	_label_stats = Label.new()
	colonne.add_child(_label_stats)
	_label_etats = Label.new()
	_label_etats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	colonne.add_child(_label_etats)
	_label_message = Label.new()
	_label_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	colonne.add_child(_label_message)
	_bouton_sort = Button.new()
	_bouton_sort.text = "Lancer la boule de feu (3 PA)"
	_bouton_sort.pressed.connect(func() -> void: sort_demandee.emit("boule_de_feu"))
	colonne.add_child(_bouton_sort)
	_conteneur_sorts = ScrollContainer.new()
	_conteneur_sorts.custom_minimum_size = Vector2(290, 230)
	colonne.add_child(_conteneur_sorts)
	_liste_sorts = VBoxContainer.new()
	_liste_sorts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_conteneur_sorts.add_child(_liste_sorts)
	_construire_sorts_etats()
	_bouton_fin_tour = Button.new()
	_bouton_fin_tour.text = "Fin du tour"
	_bouton_fin_tour.pressed.connect(func() -> void: fin_tour_demandee.emit())
	colonne.add_child(_bouton_fin_tour)
	_bouton_pret = Button.new()
	_bouton_pret.text = "Valider le placement"
	_bouton_pret.pressed.connect(func() -> void: placement_valide.emit())
	colonne.add_child(_bouton_pret)
	_panneau.hide()
	_bouton_sort.hide()
	_conteneur_sorts.hide()
	_bouton_fin_tour.hide()
	_bouton_pret.hide()

func _construire_sorts_etats() -> void:
	for enfant in _liste_sorts.get_children():
		enfant.queue_free()
	for id_sort in Personnage.sorts:
		var sort: Dictionary = Personnage.sorts[id_sort]
		var effets: Array = sort.get("effets", [])
		if effets.is_empty():
			continue
		var bouton := Button.new()
		bouton.text = "%s (%d PA)" % [str(sort.get("nom", "Sort")), int(sort.get("cout_pa", 2))]
		bouton.tooltip_text = str(sort.get("description", ""))
		bouton.pressed.connect(func() -> void: sort_demandee.emit(str(id_sort)))
		_liste_sorts.add_child(bouton)

func _creer_barre(parent: VBoxContainer, nom: String, variation: String) -> ProgressBar:
	var ligne := VBoxContainer.new()
	parent.add_child(ligne)
	var label := Label.new()
	label.text = nom
	ligne.add_child(label)
	var barre := ProgressBar.new()
	barre.theme_type_variation = variation
	barre.custom_minimum_size = Vector2(290, 22)
	barre.show_percentage = false
	ligne.add_child(barre)
	return barre

func lancer_combat(ennemi: Node = null) -> void:
	if en_combat:
		return
	if ennemi != null:
		_ennemi = ennemi
	if _joueur == null or _ennemi == null:
		push_warning("Combat impossible : joueur ou ennemi introuvable.")
		return
	_aligner_sur_grille(_joueur)
	_aligner_sur_grille(_ennemi)
	_etats_actifs.clear()
	en_combat = true
	en_placement = true
	_panneau.show()
	_bouton_sort.hide()
	_conteneur_sorts.hide()
	_bouton_fin_tour.hide()
	_bouton_pret.show()
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
	_bouton_pret.hide()
	_bouton_sort.show()
	_conteneur_sorts.show()
	_bouton_fin_tour.show()
	combat_commence.emit()

func terminer_combat(victoire: bool) -> void:
	if not en_combat:
		return
	en_combat = false
	en_placement = false
	_etats_actifs.clear()
	_mettre_a_jour_etiquette_etats()
	_panneau.hide()
	combat_termine.emit(victoire)

func mettre_a_jour_stats(vie: int, vie_max: int, pa: int, pa_max: int, pm: int, pm_max: int) -> void:
	if _barre_vie_joueur == null:
		return
	_barre_vie_joueur.max_value = maxi(vie_max, 1)
	_barre_vie_joueur.value = vie
	if _ennemi != null and is_instance_valid(_ennemi):
		_barre_vie_ennemi.max_value = maxi(_ennemi.pv_max, 1)
		_barre_vie_ennemi.value = _ennemi.pv
	_label_stats.text = "PA : %d / %d    PM : %d / %d" % [pa, pa_max, pm, pm_max]
	_mettre_a_jour_etiquette_etats()

func afficher_message(message: String) -> void:
	if _label_message != null:
		_label_message.text = message

func effacer_message() -> void:
	if _label_message != null:
		_label_message.text = ""

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
		var etat: Dictionary = Personnage.etats.get(id_etat, {})
		if etat.is_empty():
			continue
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
	if _label_etats == null:
		return
	var lignes: Array[String] = []
	for cible in [_joueur, _ennemi]:
		if cible == null or not is_instance_valid(cible):
			continue
		var par_cible: Dictionary = _etats_actifs.get(cible.get_instance_id(), {})
		if par_cible.is_empty():
			continue
		var noms: Array[String] = []
		for id_texte in par_cible:
			var donnees: Dictionary = Personnage.etats.get(int(id_texte), {})
			var nom := str(donnees.get("nom", "État"))
			var piles := int(par_cible[id_texte].get("piles", 1))
			if piles > 1:
				nom += " x%d" % piles
			noms.append(nom)
		lignes.append(("Toi" if cible == _joueur else "Ennemi") + " : " + ", ".join(noms))
	_label_etats.text = "États actifs\n" + "\n".join(lignes) if not lignes.is_empty() else "Aucun état actif"

func calculer_degats(lanceur: Node, cible: Node, degats_base: int) -> int:
	var degats := float(maxi(degats_base, 0))
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
