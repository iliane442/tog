extends Control

const RACCOURCIS := preload("res://scripts/ui/parametres_touches.gd")
const COULEUR_ERREUR := Color("#ffb9a0")

@onready var _menu: VBoxContainer = %Menu
@onready var _formulaire: PanelContainer = %Formulaire
@onready var _solo: Button = %Solo
@onready var _multijoueur: Button = %Multijoueur
@onready var _serveur: Button = %Serveur
@onready var _connexion: Button = %Connexion
@onready var _inscription: Button = %Inscription
@onready var _pseudo: LineEdit = %Pseudo
@onready var _mot_de_passe: LineEdit = %MotDePasse
@onready var _voir_mot_de_passe: Button = %VoirMotDePasse
@onready var _adresse: LineEdit = %Adresse
@onready var _valider: Button = %Valider
@onready var _message: Label = %Message

var _raccourcis: CanvasLayer
var _en_attente := false
var _chargement_partie := false

func _ready() -> void:
	if Personnage.perso_cree:
		_solo.text = "Reprendre en solo"
		%Sauvegarde.text = "%s · Niveau %d" % [Personnage.nom, Personnage.niveau]
		%Sauvegarde.show()
	_solo.pressed.connect(_jouer_en_solo)
	_multijoueur.pressed.connect(_ouvrir_multijoueur)
	_serveur.pressed.connect(_lancer_serveur)
	_actualiser_etat_serveur()
	%Raccourcis.pressed.connect(_ouvrir_raccourcis)
	%Quitter.pressed.connect(get_tree().quit)
	%Retour.pressed.connect(_fermer_multijoueur)
	_connexion.pressed.connect(_actualiser_mode)
	_inscription.pressed.connect(_actualiser_mode)
	_valider.pressed.connect(_soumettre)
	_voir_mot_de_passe.toggled.connect(_afficher_mot_de_passe)
	_pseudo.text_submitted.connect(func(_texte): _mot_de_passe.grab_focus())
	_mot_de_passe.text_submitted.connect(func(_texte): _soumettre())
	_adresse.text_submitted.connect(func(_texte): _soumettre())
	Reseau.authentification_resultat.connect(_sur_authentification)
	_adresse.text = Reseau.adresse_preferee
	_pseudo.text = Reseau.pseudo_prefere
	if not Reseau.message_accueil.is_empty():
		_ouvrir_multijoueur()
		_afficher_message(Reseau.message_accueil, true)
		Reseau.message_accueil = ""
	else:
		_solo.grab_focus()

func _jouer_en_solo() -> void:
	Reseau.jouer_hors_ligne()
	_preparer_partie()

func _preparer_partie() -> void:
	if _chargement_partie:
		return
	_chargement_partie = true
	_charger_partie.call_deferred()

func _charger_partie() -> void:
	# le perso reprend là où il a été laissé : la map mémorisée
	# remplace Fushia quand elle existe ; une map introuvable
	# retombe sur Fushia
	var chemin_partie := Reseau.scene_de_reprise()
	if chemin_partie != "" and get_tree().change_scene_to_file(chemin_partie) == OK:
		return
	Reseau.position_memorisee = {}
	if get_tree().change_scene_to_file(Personnage.PORT_NAVIRE_DEFAUT) == OK:
		return
	_chargement_partie = false
	Reseau.jouer_hors_ligne()
	_ouvrir_multijoueur()
	_definir_attente(false)
	_afficher_message("Le jeu n’a pas pu charger la partie.", true)

func _ouvrir_multijoueur() -> void:
	_menu.hide()
	_formulaire.show()
	_actualiser_mode()
	(_pseudo if _pseudo.text.is_empty() else _mot_de_passe).grab_focus()

func _fermer_multijoueur() -> void:
	if _chargement_partie:
		return
	Reseau.annuler_authentification()
	_effacer_mot_de_passe()
	_definir_attente(false)
	_formulaire.hide()
	_menu.show()
	_multijoueur.grab_focus()

func _actualiser_mode() -> void:
	_mot_de_passe.placeholder_text = "4 caractères minimum" if _inscription.button_pressed else "Ton mot de passe"
	_actualiser_bouton()
	_afficher_message("")

func _actualiser_bouton() -> void:
	if _en_attente:
		_valider.text = "Connexion en cours…"
	else:
		_valider.text = "Créer mon compte" if _inscription.button_pressed else "Se connecter"

func _soumettre() -> void:
	if _en_attente or _chargement_partie:
		return
	_definir_attente(true)
	var erreur := Reseau.authentifier(_adresse.text, _pseudo.text, _mot_de_passe.text, _inscription.button_pressed)
	if not erreur.is_empty():
		_definir_attente(false)
		_afficher_message(erreur, true)
	else:
		_afficher_message("Contact du serveur…")

func _sur_authentification(ok: bool, message: String) -> void:
	_effacer_mot_de_passe()
	if ok:
		_afficher_message("Chargement de la partie…")
		_preparer_partie()
	else:
		_definir_attente(false)
		_afficher_message(message, true)
		_mot_de_passe.grab_focus()

func _afficher_message(message: String, erreur := false) -> void:
	_message.text = message
	if erreur:
		_message.add_theme_color_override("font_color", COULEUR_ERREUR)
	else:
		_message.remove_theme_color_override("font_color")

func _afficher_mot_de_passe(afficher: bool) -> void:
	_mot_de_passe.secret = not afficher
	_voir_mot_de_passe.text = "Masquer" if afficher else "Afficher"

func _effacer_mot_de_passe() -> void:
	_mot_de_passe.clear()
	_voir_mot_de_passe.set_pressed_no_signal(false)
	_afficher_mot_de_passe(false)

func _definir_attente(attente: bool) -> void:
	_en_attente = attente
	for bouton in [_connexion, _inscription, _valider, _voir_mot_de_passe]:
		bouton.disabled = attente
	for champ in [_pseudo, _mot_de_passe, _adresse]:
		champ.editable = not attente
	%Retour.text = "Annuler" if attente else "‹  Retour"
	_actualiser_bouton()

func _ouvrir_raccourcis() -> void:
	_menu.hide()
	_raccourcis = RACCOURCIS.new()
	_raccourcis.theme_panneau = theme
	_raccourcis.fermee.connect(_fermer_raccourcis)
	add_child(_raccourcis)

func _fermer_raccourcis() -> void:
	_raccourcis = null
	_menu.show()
	%Raccourcis.grab_focus()

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE):
		return
	if _raccourcis != null:
		_raccourcis.fermer()
	elif _formulaire.visible:
		_fermer_multijoueur()
	else:
		return
	get_viewport().set_input_as_handled()

func _lancer_serveur() -> void:
	if _serveur.disabled:
		return
	_serveur.disabled = true
	if _serveur_en_ligne():
		_serveur.text = "Serveur en ligne (%d)" % Reseau.PORT_DEFAUT
		return
	_serveur.text = "Lancement du serveur…"
	var projet := ProjectSettings.globalize_path("res://")
	var pid := OS.create_process(OS.get_executable_path(), ["--headless", "--path", projet, "scenes/serveur_monde.tscn"])
	# le serveur s'éteindra avec le jeu : Reseau le coupe à la fermeture
	if pid > 0:
		Reseau.pid_serveur_local = pid
	# le serveur vient d'être relancé : il lui faut quelques secondes
	# pour ouvrir le port avant de confirmer son état
	await get_tree().create_timer(3.0).timeout
	_actualiser_etat_serveur()

func _actualiser_etat_serveur() -> void:
	if not is_instance_valid(_serveur):
		return
	var en_ligne := _serveur_en_ligne()
	_serveur.disabled = en_ligne
	_serveur.text = "Serveur en ligne (%d)" % Reseau.PORT_DEFAUT if en_ligne else "Lancer le serveur"

func _serveur_en_ligne() -> bool:
	# le serveur dédié écoute en UDP (ENet) : si le port se laisse
	# lier, rien ne tourne dessus ; sur macOS un test TCP se
	# déclare « connecté » même sans serveur, d'où la sonde UDP
	var sonde := PacketPeerUDP.new()
	if sonde.bind(Reseau.PORT_DEFAUT, "127.0.0.1") == OK:
		sonde.close()
		return false
	return true
