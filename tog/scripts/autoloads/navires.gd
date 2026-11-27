extends Node

const CATALOGUE := preload("res://scripts/world/catalogue_navires.gd")
const FINITIONS := preload("res://scripts/world/finitions_pont.gd")
const THEME_PORT := preload("res://themes/theme_interface_pirate.tres")
const PORTEE_QUAI := 220.0
const DELAI_INVITATION := 45000
const MAX_QUANTITE := 999999

signal port_modifie
signal bord_modifie
signal message_recu(texte: String)

var hote := 0
var mode_bord := ""
var escale: Dictionary = {}
var _galion_bord: Dictionary = {}
var _garde_port: Dictionary = {}
var _demandes: Dictionary = {}
var _ports: Dictionary = {}
var _operation := ""
var _attente_changement := ""
var _invitation: ConfirmationDialog
var _theme_fenetre: Theme

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Equipages.equipage_modifie.connect(nouvel_equipage)

func reinitialiser() -> void:
	hote = 0
	mode_bord = ""
	escale.clear()
	_galion_bord.clear()
	_garde_port.clear()
	_operation = ""
	_attente_changement = ""
	if is_instance_valid(_invitation):
		_invitation.queue_free()

func sauvegarde_suspendue() -> bool:
	return not _operation.is_empty() or not _attente_changement.is_empty()

func theme_fenetre() -> Theme:
	if _theme_fenetre == null:
		_theme_fenetre = THEME_PORT.duplicate()
		var cadre := StyleBoxFlat.new()
		cadre.bg_color = Color("#f9e4b3")
		cadre.border_color = Color("#865630")
		cadre.set_border_width_all(3)
		cadre.set_corner_radius_all(8)
		for cote in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			cadre.set_content_margin(cote, 14)
		_theme_fenetre.set_stylebox("panel", "AcceptDialog", cadre)
		_theme_fenetre.set_stylebox("embedded_border", "Window", cadre)
		_theme_fenetre.set_color("title_color", "Window", Color("#f9e4b3"))
		_theme_fenetre.set_color("title_outline_modulate", "Window", Color("#472817"))
		_theme_fenetre.set_constant("title_outline_size", "Window", 4)
	return _theme_fenetre

func port_info(fichier: String) -> Dictionary:
	if _ports.has(fichier):
		return _ports[fichier]
	if not fichier.begins_with("res://scenes/") or not ResourceLoader.exists(fichier, "PackedScene"):
		return {}
	var carte := (load(fichier) as PackedScene).instantiate()
	var routes := {}
	var arrivees := {}
	for noeud in carte.get_children():
		if noeud.has_method("_traverser") and noeud.has_method("_embarquer") and noeud.destination != "":
			routes[noeud.destination] = {
				"arrivee": str(noeud.arrivee), "libelle": str(noeud.libelle_traversee), "quai": noeud.position,
			}
	var reperes := carte.get_node_or_null("Arrivees")
	if reperes != null:
		for repere in reperes.get_children():
			if repere is Marker2D:
				arrivees[str(repere.name)] = repere.position
	var info := {"routes": routes, "nom": str(carte.name), "arrivees": arrivees}
	var quai: Variant = carte.get("quai_chaloupe")
	if quai is Vector2 and quai.is_finite():
		info["quai_chaloupe"] = quai
	carte.free()
	_ports[fichier] = info if not routes.is_empty() else {}
	return _ports[fichier]

func peut_traverser(scene: Node) -> bool:
	return scene != null and scene.has_method("rejoindre_zone") and not get_tree().paused \
		and not scene.get("_changement_zone") and not scene.get_node("CombatManager").en_combat

func _position_ancrage(port: String) -> Vector2:
	var info := port_info(port)
	var quai: Vector2 = info.get("quai_chaloupe", Vector2.INF)
	if quai.is_finite():
		return quai
	var routes: Dictionary = info.get("routes", {})
	return routes.values()[0]["quai"] if not routes.is_empty() else Vector2.INF

func modele_a_bord() -> String:
	return str(_galion_bord.get("modele", Personnage.modele_bateau())) if hote != 0 else Personnage.modele_bateau()

func donnees_a_bord() -> Dictionary:
	if not Personnage.en_ligne:
		return Equipages.donnees_galion(Equipages.galion_du_joueur(Personnage.nom))
	return _galion_bord.get("donnees", {})

func finition_pont() -> String:
	if (Personnage.en_ligne and hote != 0) or modele_a_bord() in CATALOGUE.GALIONS:
		return FINITIONS.normaliser(str(donnees_a_bord().get("finition_pont", "")))
	return Personnage.finition_pont_perso

func changer_finition_pont(finition: String) -> bool:
	var scene := get_tree().current_scene
	if scene == null or scene.scene_file_path != Personnage.SCENE_NAVIRE or not est_pilote() \
			or not FINITIONS.CHOIX.has(finition):
		return false
	if finition == finition_pont():
		return true
	if Personnage.en_ligne:
		return _demander("finition_pont", [finition])
	var galion := Equipages.galion_du_joueur(Personnage.nom)
	if galion.is_empty():
		Personnage.finition_pont_perso = finition
		Personnage.sauvegarder()
	elif not _enregistrer_finition_galion(galion, finition):
		_message("La finition du pont n’a pas pu être enregistrée.")
		return false
	bord_modifie.emit()
	return true

func _enregistrer_finition_galion(galion: Dictionary, finition: String) -> bool:
	var donnees := Equipages.donnees_galion(galion)
	donnees["finition_pont"] = finition
	return Equipages.enregistrer_galion(galion, donnees)

func equipement_galion() -> Dictionary:
	if not Personnage.en_ligne:
		return donnees_a_bord().get("equipement", {})
	return Equipages.mon_equipage.get("modules_galion", {})

func est_pilote() -> bool:
	return hote == 0 or hote == multiplayer.get_unique_id()

func peut_utiliser_galion() -> bool:
	return est_pilote() or mode_bord == "equipage"

func indice_chambre() -> int:
	if Personnage.en_ligne:
		return int(donnees_a_bord().get("indice_chambre", 0))
	var equipage := int(Equipages.mon_equipage.get("id", 0))
	return maxi(0, Equipages.noms_de_l_equipage(equipage).find(Personnage.nom))

func acheter_personnel() -> void:
	var scene := get_tree().current_scene
	if not peut_traverser(scene):
		return
	var port := scene.scene_file_path
	var prix := CATALOGUE.prix_achat(Personnage.modele_bateau_perso, port)
	if prix <= 0:
		_message("Le chantier naval ne propose aucun nouveau modèle pour le moment.")
		return
	if Personnage.en_ligne:
		_demander("acheter")
	elif Personnage.berry >= prix:
		Personnage.modele_bateau_perso = CATALOGUE.modele_vendu(port)
		Personnage.berry -= prix
		Personnage.recalculer_stats(false)
		port_modifie.emit()
		_message("%s rejoint ton équipement." % CATALOGUE.fiche(Personnage.modele_bateau_perso)["nom"])
	else:
		_message("Il te faut %d Berry pour acheter ce bateau." % prix)

func naviguer(destination: String) -> void:
	var scene := get_tree().current_scene
	if not peut_traverser(scene) or not est_pilote():
		return
	var port := str(escale.get("scene", Personnage.escale_navire.get("scene", ""))) if scene.scene_file_path == Personnage.SCENE_NAVIRE else scene.scene_file_path
	var route: Dictionary = port_info(port).get("routes", {}).get(destination, {})
	if route.is_empty():
		return
	if Personnage.en_ligne:
		_demander("naviguer", [destination])
		return
	var prix := int(CATALOGUE.fiche(Personnage.modele_bateau())["entretien"])
	if Personnage.berry < prix:
		_message("Entretien de %d Berry. Ton bateau reste à quai." % prix)
		return
	Personnage.ajouter_berry(-prix)
	scene.rejoindre_zone(destination, StringName(route["arrivee"]))

func embarquer(pilote := 0) -> void:
	var scene := get_tree().current_scene
	if not peut_traverser(scene):
		return
	if Personnage.en_ligne:
		_demander("embarquer", [pilote])
		return
	var position := Reseau._joueur_local().global_position
	Personnage.memoriser_escale_navire(scene.scene_file_path, position)
	scene.rejoindre_zone(Personnage.SCENE_NAVIRE, &"DepuisQuai")

func debarquer() -> void:
	var scene := get_tree().current_scene
	if not peut_traverser(scene):
		return
	if Personnage.en_ligne:
		_demander("debarquer")
		return
	var retour := Personnage.escale_navire
	var port := str(retour.get("scene", Personnage.PORT_NAVIRE_DEFAUT))
	scene.rejoindre_zone(port, &"DepuisShells", Vector2(float(retour.get("x", INF)), float(retour.get("y", INF))))

func acheter_atelier(indice: int, metier: String) -> bool:
	return _action_galion("atelier", [indice, metier])

func decorer(categorie: String, indice: int) -> bool:
	return _action_galion("decor", [categorie, indice])

func transferer_cale(id: String, quantite: int, depot: bool) -> bool:
	return _action_galion("cale", [id, quantite, depot])

func modifier_module(emplacement: String, id: String) -> bool:
	return _action_galion("module", [emplacement, id])

func _action_galion(action: String, params: Array) -> bool:
	if not peut_utiliser_galion():
		return false
	if Personnage.en_ligne:
		return _demander(action, params)
	var galion := Equipages.galion_du_joueur(Personnage.nom)
	if galion.is_empty():
		return false
	var ancien_sac := Inventaire.objets
	var sac := Inventaire.objets.duplicate()
	var erreur := _appliquer_galion(action, params, galion, Personnage.nom, true, sac, Personnage.niveau)
	if not erreur.is_empty():
		_message(erreur)
		return false
	if sac != ancien_sac:
		Inventaire.inventaire_modifie.emit()
	if action == "atelier":
		Equipages._recharger_mon_equipage()
		Equipages.equipage_modifie.emit()
	bord_modifie.emit()
	Personnage.recalculer_stats(false)
	return true

func _appliquer_galion(action: String, params: Array, galion: Dictionary, joueur: String, pilote: bool,
		sac: Dictionary, niveau: int, compte := 0, profil: Dictionary = {}) -> String:
	var donnees := Equipages.donnees_galion(galion)
	var modele := str(galion["modele"])
	match action:
		"atelier":
			if modele != "ateliers" or not pilote or params.size() != 2:
				return "Seul le pilote peut aménager les ateliers du galion."
			var cle := str(int(params[0]))
			var ateliers: Dictionary = donnees.get("ateliers", {})
			var metier := str(params[1])
			if int(cle) not in range(CATALOGUE.MAX_ATELIERS) or ateliers.has(cle) or not Personnage.professions().has(metier):
				return "Ce choix d’atelier est indisponible."
			var equipage := int(galion["equipage_id"])
			var lignes := Equipages._lire("SELECT caisse FROM equipages WHERE id = %d;" % equipage)
			if lignes.is_empty() or int(lignes[0]["caisse"]) < CATALOGUE.PRIX_ATELIER:
				return "La caisse d’équipage doit contenir %d Berry." % CATALOGUE.PRIX_ATELIER
			ateliers[cle] = metier
			donnees["ateliers"] = ateliers
			if Equipages._transaction([
				"UPDATE equipages SET caisse = caisse - %d WHERE id = %d;" % [CATALOGUE.PRIX_ATELIER, equipage],
				"UPDATE galions_equipage SET donnees = '%s' WHERE id = %d;" %
					[Equipages._echapper(JSON.stringify(donnees)), int(galion["id"])],
				Equipages._requete_journal(equipage, "%s aménage un atelier de %s." %
					[joueur, Personnage.professions()[metier]["nom"]]),
			]):
				return ""
			return "Impossible d’acheter l’atelier."
		"decor":
			if modele != "vie" or params.size() != 2:
				return "Les chambres se trouvent sur le galion de vie."
			var type := str(params[0])
			var indice := int(params[1])
			if not CATALOGUE.DECORS.has(type) or indice not in range(CATALOGUE.DECORS[type].size()):
				return "Ce décor est indisponible."
			var chambres: Dictionary = donnees.get("chambres", {})
			var chambre: Dictionary = chambres.get(joueur, {})
			chambre[type] = indice
			chambres[joueur] = chambre
			donnees["chambres"] = chambres
		"cale":
			if modele != "stockage" or params.size() != 3:
				return "Cette cale commune n’est pas accessible."
			var id := str(params[0])
			var quantite := int(params[1])
			var depot := bool(params[2])
			var cale: Dictionary = donnees.get("cale", {})
			if depot and not cale.has(id) and cale.size() >= int(CATALOGUE.fiche(modele)["cale"]):
				return "La cale est pleine."
			var source := sac if depot else cale
			var cible := cale if depot else sac
			if not _deplacer_objets(source, cible, id, quantite):
				return "Quantité indisponible."
			donnees["cale"] = cale
		"module":
			if modele != "navigation" or not pilote or params.size() != 2:
				return "Seul le pilote peut équiper ce galion."
			var place := str(params[0])
			var id := str(params[1])
			if place not in Personnage.EMPLACEMENTS_NAVIRE.values() + ["mat2", "coque2"]:
				return "Emplacement inconnu."
			if id != "" and (Personnage.emplacement_navire(id) != place.trim_suffix("2")
					or int(Inventaire.details_objet(id).get("niveau_min", 1)) > niveau or int(sac.get(id, 0)) <= 0):
				return "Module indisponible ou niveau insuffisant."
			var modules: Dictionary = donnees.get("equipement", {})
			var ancien := str(modules.get(place, ""))
			if ancien == id:
				return ""
			if id != "":
				_deplacer_objets(sac, {}, id, 1)
			if ancien != "":
				sac[ancien] = int(sac.get(ancien, 0)) + 1
			modules[place] = id
			donnees["equipement"] = modules
		_:
			return "Action indisponible à bord."
	if compte != 0:
		profil["sac"] = sac
		return "" if Equipages.enregistrer_galion(galion, donnees, compte, profil) else "La modification du galion a échoué."
	var ancien_sac := Inventaire.objets
	if sac != ancien_sac:
		Inventaire.objets = sac
		if Inventaire._sauver_objets() != OK:
			Inventaire.objets = ancien_sac
			return "Impossible d’enregistrer l’inventaire."
	if not Equipages.enregistrer_galion(galion, donnees):
		if sac != ancien_sac:
			Inventaire.objets = ancien_sac
			Inventaire._sauver_objets()
		return "La modification du galion a échoué."
	return ""

func _deplacer_objets(source: Dictionary, cible: Dictionary, id: String, quantite: int) -> bool:
	var dispo := int(source.get(id, 0))
	if quantite <= 0 or quantite > MAX_QUANTITE or quantite > dispo:
		return false
	if quantite == dispo:
		source.erase(id)
	else:
		source[id] = dispo - quantite
	cible[id] = int(cible.get(id, 0)) + quantite
	return true

func _demander(action: String, params: Array = []) -> bool:
	if not sauvegarde_suspendue():
		Reseau.sauvegarder_perso_immediat()
		_operation = action
		if rpc_id(1, "demande_navire", action, params) == OK:
			return true
		_operation = ""
		_message("La demande n’a pas pu être envoyée au serveur.")
	return false

func _message(texte: String) -> void:
	message_recu.emit(texte)
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("afficher_info_fushia"):
		scene.afficher_info_fushia(texte)

func nouvel_equipage() -> void:
	if Reseau.mode == Reseau.Mode.SERVEUR:
		return
	port_modifie.emit()
	Personnage.recalculer_stats(false)

# --- Serveur ---

func _session(pair: int) -> Dictionary:
	return Reseau._sessions.get(pair, {})

func _galion(pair: int) -> Dictionary:
	return Equipages.galion_du_joueur(str(_session(pair).get("nom_personnage", "")))

func _modele_serveur(pair: int) -> String:
	return str(_galion(pair).get("modele", _session(pair).get("modele_bateau", CATALOGUE.DEPART)))

func scene_serveur(pair: int, nom_scene: String, fichier: String) -> String:
	var session := _session(pair)
	if fichier == Personnage.SCENE_NAVIRE or nom_scene == "Lanterne" or nom_scene.begins_with("Lanterne:"):
		var pilote := int(session.get("hote_navire", pair))
		return "Lanterne:%d" % pilote
	var info := port_info(fichier)
	if not info.is_empty() and info["nom"] != nom_scene:
		return ""
	return nom_scene

func changement_scene(pair: int, fichier: String) -> void:
	var session := _session(pair)
	var ancien := str(session.get("port_navire", ""))
	var port := fichier if not port_info(fichier).is_empty() else ancien
	if port.is_empty():
		var profil := Reseau._perso_json_serveur(Reseau._compte(str(session["pseudo"])))
		var retour := str(profil.get("amenagement_navire", {}).get("escale", {}).get("scene", ""))
		if not port_info(retour).is_empty():
			port = retour
	if fichier == Personnage.SCENE_NAVIRE:
		if not session.has("hote_navire"):
			session["hote_navire"] = pair
			session["mode_navire"] = "pilote"
		session["port_navire"] = port if not port.is_empty() else Personnage.PORT_NAVIRE_DEFAUT
		_envoyer_bord(pair)
	else:
		session.erase("hote_navire")
		session.erase("mode_navire")
		session["port_navire"] = port
		if not ancien.is_empty() and ancien != session["port_navire"]:
			for invite: int in Reseau._sessions:
				if int(_session(invite).get("hote_navire", 0)) == pair:
					_retour_quai(invite, ancien)
	_diffuser_port(ancien)
	if str(session.get("port_navire", "")) != ancien:
		_diffuser_port(str(session["port_navire"]))

func equipage_modifie() -> void:
	var ports := {}
	for pair: int in Reseau._sessions:
		var session := _session(pair)
		var pilote := int(session.get("hote_navire", 0))
		if pilote != 0 and Reseau._pair_connecte(pair):
			if session.get("mode_navire") == "equipage" and not _meme_equipage(pair, pilote):
				_retour_quai(pair, str(_session(pilote).get("port_navire", "")))
			else:
				_envoyer_bord(pair)
		var port := str(session.get("port_navire", ""))
		if not port.is_empty():
			ports[port] = true
	for port: String in ports:
		_diffuser_port(port)

func deconnexion_serveur(pair: int, port: String) -> void:
	_demandes.erase(pair)
	for invite: int in _demandes.keys():
		if int(_demandes[invite].get("pilote", 0)) == pair:
			_demandes.erase(invite)
	for invite: int in Reseau._sessions:
		if int(_session(invite).get("hote_navire", 0)) == pair:
			_retour_quai(invite, port)
	_diffuser_port(port)

func _meme_equipage(pair: int, pilote: int) -> bool:
	var galion := _galion(pilote)
	if galion.is_empty():
		return false
	return str(_session(pair).get("nom_personnage", "")) in Equipages.noms_de_l_equipage(int(galion["equipage_id"]))

func _diffuser_port(port: String) -> void:
	if port.is_empty():
		return
	var presents: Array = []
	var clients: Array[int] = []
	for pair: int in Reseau._sessions:
		var session := _session(pair)
		if session.get("port_navire", "") != port or not Reseau._pair_connecte(pair):
			continue
		clients.append(pair)
		presents.append({"id": pair, "nom": str(session["nom_personnage"]), "modele": _modele_serveur(pair)})
	presents.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))
	for pair in clients:
		rpc_id(pair, "recevoir_port", port, presents)

func _envoyer_bord(pair: int) -> void:
	var session := _session(pair)
	var pilote := int(session.get("hote_navire", pair))
	var mode := str(session.get("mode_navire", "pilote"))
	var galion := _galion(pilote)
	var galion_donnees := Equipages.donnees_galion(galion)
	var donnees := galion_donnees if mode in ["equipage", "pilote"] else {}
	# La finition est visible par toute personne à bord.
	donnees["finition_pont"] = FINITIONS.normaliser(str(
		_session(pilote).get("finition_pont", "") if galion.is_empty() else galion_donnees.get("finition_pont", "")))
	if galion.get("modele", "") == "vie" and mode in ["equipage", "pilote"]:
		var membres := Equipages.noms_de_l_equipage(int(galion["equipage_id"]))
		donnees["indice_chambre"] = maxi(0, membres.find(str(session["nom_personnage"])))
	if donnees.has("chambres"):
		var chambres: Dictionary = donnees["chambres"]
		var nom := str(session.get("nom_personnage", ""))
		donnees["chambres"] = {nom: chambres.get(nom, {})}
	rpc_id(pair, "recevoir_bord", pilote, mode, _modele_serveur(pilote), donnees)

@rpc("any_peer", "call_remote", "reliable")
func demande_navire(action: String, params: Array) -> void:
	if Reseau.mode != Reseau.Mode.SERVEUR or not multiplayer.is_server():
		return
	var pair := multiplayer.get_remote_sender_id()
	var session := _session(pair)
	if session.is_empty() or str(session.get("nom_personnage", "")).is_empty():
		return
	var port := str(session.get("port_navire", ""))
	match action:
		"acheter", "naviguer":
			_serveur_depart(pair, action, params, port)
		"embarquer":
			var pilote := int(params[0]) if params.size() == 1 else -1
			if pilote == 0:
				pilote = pair
			if not _accessible_quai(pair, pilote, port):
				_echec(pair, "Ce bateau n’est pas à portée au quai.")
			elif pilote != pair and not _meme_equipage(pair, pilote):
				_echec(pair, "Demande une invitation au pilote pour monter à bord.")
			else:
				_placer_a_bord(pair, pilote, port, "pilote" if pilote == pair else "equipage")
		"debarquer":
			if not _a_bord(pair):
				_echec(pair, "Position à bord introuvable.")
			else:
				_retour_quai(pair, port)
		"inviter", "invitation":
			_gerer_invitation(pair, action, params, port)
		"atelier", "decor", "cale", "module":
			_serveur_galion(pair, action, params)
		"finition_pont":
			_serveur_finition_pont(pair, params)
		_:
			_echec(pair, "Cette action n’est plus disponible.")

func _a_bord(pair: int) -> bool:
	return str(_session(pair).get("scene", "")).begins_with("Lanterne:") and _session(pair).has("hote_navire")

func _accessible_quai(pair: int, pilote: int, port: String) -> bool:
	if port.is_empty() or _a_bord(pair) or not Reseau._pair_connecte(pilote):
		return false
	var hote_session := _session(pilote)
	if hote_session.get("port_navire", "") != port or int(hote_session.get("hote_navire", pilote)) != pilote:
		return false
	return _proche_du_quai(pair, port)

func _proche_du_quai(pair: int, port: String) -> bool:
	var info := port_info(port)
	if _session(pair).get("scene", "") != info.get("nom", ""):
		return false
	var pos: Vector2 = _session(pair).get("position", Vector2.INF)
	var quai: Vector2 = info.get("quai_chaloupe", Vector2.INF)
	if quai.is_finite() and pos.distance_to(quai) <= PORTEE_QUAI:
		return true
	for route: Dictionary in info.get("routes", {}).values():
		if pos.distance_to(route["quai"]) <= PORTEE_QUAI:
			return true
	return false

func _serveur_depart(pair: int, action: String, params: Array, port: String) -> void:
	var session := _session(pair)
	var navigation := action == "naviguer"
	var destination := str(params[0]) if navigation and params.size() == 1 else ""
	var route: Dictionary = port_info(port).get("routes", {}).get(destination, {})
	if port.is_empty() or session.get("en_combat", false) or (navigation and route.is_empty()):
		_echec(pair, "Cette traversée est indisponible.")
		return
	if _a_bord(pair):
		if not navigation or int(session["hote_navire"]) != pair:
			_echec(pair, "Seul le pilote peut faire partir son navire.")
			return
	elif not _proche_du_quai(pair, port):
		_echec(pair, "Approche-toi du quai pour cette action.")
		return
	var compte := Reseau._compte(str(session["pseudo"]))
	var profil := Reseau._perso_json_serveur(compte)
	if profil.is_empty():
		_echec(pair, "Personnage introuvable.")
		return
	var amenagement: Dictionary = profil.get("amenagement_navire", {})
	var personnel := CATALOGUE.personnel(str(amenagement.get("modele", CATALOGUE.DEPART)))
	var prix := int(CATALOGUE.fiche(_modele_serveur(pair))["entretien"]) if navigation else CATALOGUE.prix_achat(personnel, port)
	if prix <= 0:
		_echec(pair, "Ce bateau n’est pas disponible à l’achat.")
		return
	if int(profil.get("berry", 0)) < prix:
		_echec(pair, "Entretien de %d Berry. Ton bateau reste à quai." % prix if navigation else "Il te faut %d Berry." % prix)
		return
	profil["berry"] = int(profil["berry"]) - prix
	if not navigation:
		personnel = CATALOGUE.modele_vendu(port)
		amenagement["modele"] = personnel
		profil["amenagement_navire"] = amenagement
	else:
		var position := _position_arrivee(destination, str(route["arrivee"]))
		profil["position"] = position
	if not Reseau._ecrire_perso_serveur(int(compte["id"]), JSON.stringify(profil)):
		_echec(pair, "L’opération n’a pas été enregistrée.")
		return
	if not navigation:
		session["modele_bateau"] = personnel
		_diffuser_port(port)
		rpc_id(pair, "resultat_navire", {"delta": -prix, "modele": personnel, "texte": "Bateau acheté."})
		return
	_modification_traversee(pair, port, destination, str(route["arrivee"]), prix)

func _position_arrivee(destination: String, arrivee: String) -> Dictionary:
	var position: Vector2 = port_info(destination).get("arrivees", {}).get(arrivee, Vector2.INF)
	var memorisee := {"scene": destination.get_file().get_basename()}
	if position.is_finite():
		memorisee["x"] = position.x
		memorisee["y"] = position.y
	return memorisee

func _modification_traversee(pilote: int, port: String, destination: String, arrivee: String, prix: int) -> void:
	for pair: int in Reseau._sessions:
		if pair == pilote or int(_session(pair).get("hote_navire", 0)) != pilote:
			continue
		if _session(pair).get("mode_navire", "") == "passager":
			var compte := Reseau._compte(str(_session(pair)["pseudo"]))
			var profil := Reseau._perso_json_serveur(compte)
			if not profil.is_empty():
				profil["position"] = _position_arrivee(destination, arrivee)
				Reseau._ecrire_perso_serveur(int(compte["id"]), JSON.stringify(profil))
			_session(pair)["port_navire"] = ""
			_session(pair).erase("hote_navire")
			_session(pair).erase("mode_navire")
			rpc_id(pair, "resultat_navire", {"destination": destination, "arrivee": arrivee})
		else:
			_retour_quai(pair, port)
	_session(pilote)["port_navire"] = ""
	_diffuser_port(port)
	rpc_id(pilote, "resultat_navire", {"delta": -prix, "destination": destination, "arrivee": arrivee,
		"texte": "%d Berry payés pour l’entretien." % prix})

func _serveur_galion(pair: int, action: String, params: Array) -> void:
	var session := _session(pair)
	var pilote := int(session.get("hote_navire", 0))
	if not _a_bord(pair) or (pair != pilote and (session.get("mode_navire") != "equipage" or not _meme_equipage(pair, pilote))):
		_echec(pair, "Tu dois être à bord de ce galion comme membre de l’équipage.")
		return
	var galion := _galion(pilote)
	var compte := Reseau._compte(str(session["pseudo"]))
	var profil := Reseau._perso_json_serveur(compte)
	if galion.is_empty() or profil.is_empty():
		_echec(pair, "Ce galion est indisponible.")
		return
	var sac_stocke: Variant = profil.get("sac", {})
	var sac: Dictionary = sac_stocke if sac_stocke is Dictionary else {}
	var avant := sac.duplicate()
	var erreur := _appliquer_galion(action, params, galion, str(session["nom_personnage"]), pair == pilote,
		sac, int(profil.get("niveau", 1)), int(compte["id"]), profil)
	if not erreur.is_empty():
		_echec(pair, erreur)
		return
	var changements := {}
	for id in avant.keys() + sac.keys():
		var delta := int(sac.get(id, 0)) - int(avant.get(id, 0))
		if delta != 0:
			changements[id] = delta
	Reseau._diffuser_equipage(int(galion["equipage_id"]))
	_diffuser_bord(pilote)
	rpc_id(pair, "resultat_navire", {"sac": changements})

func _diffuser_bord(pilote: int) -> void:
	for membre: int in Reseau._sessions:
		if int(_session(membre).get("hote_navire", 0)) == pilote:
			_envoyer_bord(membre)

func _serveur_finition_pont(pair: int, params: Array) -> void:
	var session := _session(pair)
	var finition := str(params[0]) if params.size() == 1 else ""
	if not _a_bord(pair) or int(session["hote_navire"]) != pair or not FINITIONS.CHOIX.has(finition):
		_echec(pair, "Seul le pilote à bord peut choisir la finition du pont.")
		return
	var galion := _galion(pair)
	var resultat := {"texte": "Finition du pont · %s" % FINITIONS.fiche(finition)["nom"]}
	if galion.is_empty():
		var compte := Reseau._compte(str(session["pseudo"]))
		var profil := Reseau._perso_json_serveur(compte)
		if profil.is_empty():
			_echec(pair, "Le bateau personnel est indisponible.")
			return
		var amenagement: Dictionary = profil.get("amenagement_navire", {})
		amenagement["finition_pont"] = finition
		profil["amenagement_navire"] = amenagement
		if not Reseau._ecrire_perso_serveur(int(compte["id"]), JSON.stringify(profil)):
			_echec(pair, "La finition du pont n’a pas pu être enregistrée.")
			return
		session["finition_pont"] = finition
		resultat["finition_pont_perso"] = finition
	elif not _enregistrer_finition_galion(galion, finition):
		_echec(pair, "La finition du pont n’a pas pu être enregistrée.")
		return
	_diffuser_bord(pair)
	rpc_id(pair, "resultat_navire", resultat)

func _placer_a_bord(pair: int, pilote: int, port: String, mode: String) -> void:
	var session := _session(pair)
	session["hote_navire"] = pilote
	session["mode_navire"] = mode
	var ancrage := _position_ancrage(port)
	_envoyer_bord(pair)
	rpc_id(pair, "resultat_navire", {"destination": Personnage.SCENE_NAVIRE, "arrivee": "DepuisQuai",
		"escale": {"scene": port, "x": ancrage.x, "y": ancrage.y}})

func _retour_quai(pair: int, port: String) -> void:
	var retour := port if not port_info(port).is_empty() else Personnage.PORT_NAVIRE_DEFAUT
	var position := _position_ancrage(retour)
	rpc_id(pair, "resultat_navire", {"destination": retour, "position": position})
	_session(pair).erase("hote_navire")
	_session(pair).erase("mode_navire")

func _echec(pair: int, texte: String) -> void:
	rpc_id(pair, "resultat_navire", {"texte": texte})

func _gerer_invitation(pair: int, action: String, params: Array, port: String) -> void:
	if action == "inviter":
		var cible := int(params[0]) if params.size() == 2 else 0
		var mode := str(params[1]) if params.size() == 2 else ""
		if cible == pair or mode not in ["visiteur", "passager"] or not _accessible_quai(cible, pair, port):
			_echec(pair, "Le joueur doit se trouver près du même quai.")
			return
		if not _a_bord(pair) and not _proche_du_quai(pair, port):
			_echec(pair, "Approche-toi du quai pour inviter un joueur.")
			return
		_demandes[cible] = {"pilote": pair, "mode": mode, "port": port, "expiration": Time.get_ticks_msec() + DELAI_INVITATION}
		rpc_id(cible, "invitation_navire", pair, str(_session(pair)["nom_personnage"]), mode)
		_echec(pair, "Invitation envoyée.")
		return
	var offre: Dictionary = _demandes.get(pair, {})
	if params.size() != 2 or offre.is_empty() or int(params[1]) != int(offre["pilote"]):
		_echec(pair, "Cette invitation a expiré.")
		return
	_demandes.erase(pair)
	if not bool(params[0]):
		_echec(pair, "")
		return
	var pilote := int(offre.get("pilote", 0))
	if offre.is_empty() or int(offre["expiration"]) < Time.get_ticks_msec() or offre["port"] != port \
			or not _accessible_quai(pair, pilote, port) or _session(pair).get("en_combat", false):
		_echec(pair, "Cette invitation a expiré ou le bateau a quitté ce quai.")
	else:
		_placer_a_bord(pair, pilote, port, str(offre["mode"]))

# --- Client ---

func demander_invitation(pilote: int, mode: String) -> void:
	_demander("inviter", [pilote, mode])

@rpc("authority", "call_remote", "reliable")
func invitation_navire(pilote: int, nom: String, mode: String) -> void:
	if is_instance_valid(_invitation):
		_invitation.queue_free()
	_invitation = ConfirmationDialog.new()
	_invitation.set_meta("pilote", pilote)
	_invitation.theme = theme_fenetre()
	_invitation.title = "Invitation à bord"
	_invitation.dialog_text = "%s te propose %s." % [nom, "de visiter son navire" if mode == "visiteur" else "d’embarquer comme passager"]
	_invitation.ok_button_text = "Embarquer"
	_invitation.cancel_button_text = "Refuser"
	add_child(_invitation)
	for bouton in [_invitation.get_ok_button(), _invitation.get_cancel_button()]:
		bouton.add_theme_color_override("font_color", Color("#f9e4b3"))
	_invitation.confirmed.connect(_repondre_invitation.bind(true))
	_invitation.canceled.connect(_repondre_invitation.bind(false))
	_invitation.popup_centered()

func _repondre_invitation(accepter: bool) -> void:
	if not is_instance_valid(_invitation):
		return
	var pilote := int(_invitation.get_meta("pilote"))
	_invitation.queue_free()
	_demander("invitation", [accepter and peut_traverser(get_tree().current_scene), pilote])

@rpc("authority", "call_remote", "reliable")
func recevoir_port(port: String, presents: Array) -> void:
	_garde_port[port] = presents
	port_modifie.emit()

func bateaux_au_port(port: String) -> Array:
	return _garde_port.get(port, [])

@rpc("authority", "call_remote", "reliable")
func recevoir_bord(pilote: int, mode: String, modele: String, donnees: Dictionary) -> void:
	hote = pilote
	mode_bord = mode
	_galion_bord = {"modele": modele, "donnees": donnees}
	bord_modifie.emit()

@rpc("authority", "call_remote", "reliable")
func resultat_navire(resultat: Dictionary) -> void:
	_operation = ""
	var destination := str(resultat.get("destination", ""))
	var scene := get_tree().current_scene
	if not destination.is_empty():
		_attente_changement = destination
	if resultat.has("escale"):
		escale = resultat["escale"]
		if est_pilote():
			Personnage.escale_navire = escale.duplicate()
	if resultat.has("modele"):
		Personnage.modele_bateau_perso = CATALOGUE.personnel(str(resultat["modele"]))
	if resultat.has("finition_pont_perso"):
		Personnage.finition_pont_perso = FINITIONS.normaliser(str(resultat["finition_pont_perso"]))
	if resultat.has("delta"):
		Personnage.ajouter_berry(int(resultat["delta"]))
	if resultat.has("sac"):
		var delta: Dictionary = resultat["sac"]
		for id in delta:
			var nombre := int(delta[id])
			if nombre > 0:
				Inventaire.ajouter_objet(id, nombre)
			elif nombre < 0:
				Inventaire.retirer_objet(id, -nombre)
		bord_modifie.emit()
	if resultat.has("modele"):
		Personnage.recalculer_stats(false)
		port_modifie.emit()
	if not destination.is_empty() and scene != null and scene.has_method("rejoindre_zone"):
		if scene.scene_file_path == Personnage.SCENE_NAVIRE:
			scene.fermer_interfaces_navire()
		else:
			var quai := scene.get_node_or_null("EscaleNavires")
			if quai != null:
				quai.fermer()
			scene.get_node("DialogueUI").fermer()
			scene.get_node("MenuUI").fermer()
		if peut_traverser(scene):
			scene.rejoindre_zone(destination, StringName(resultat.get("arrivee", "")), resultat.get("position", Vector2.INF))
		else:
			_attente_changement = ""
	if not str(resultat.get("texte", "")).is_empty():
		_message(str(resultat["texte"]))

func entree_locale(fichier: String) -> void:
	if fichier != Personnage.SCENE_NAVIRE:
		hote = 0
		mode_bord = ""
		_galion_bord.clear()
		var position := _position_ancrage(fichier)
		if position.is_finite():
			Personnage.escale_navire = {"scene": fichier, "x": position.x, "y": position.y}
	if _attente_changement == fichier:
		_attente_changement = ""
		Reseau.sauvegarder_perso_immediat()
