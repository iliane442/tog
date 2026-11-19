# menu.gd — sur le CanvasLayer MenuUI
# Barre de raccourcis en bas de l'écran (style Dofus) :
# Menu, Personnage, Sorts, Quêtes, Inventaire.
# Échap ou M ouvre et referme aussi l'interface.
extends CanvasLayer

signal menu_ouvert
signal menu_ferme

var section_actuelle: String = ""
# répartition en cours, pas encore validée (cle -> points en attente)
var points_en_attente: Dictionary = {}
var _tween_fenetre: Tween
const SCENE_CASE_INVENTAIRE := preload("res://scenes/case_inventaire.tscn")
const SCENE_CASE_EQUIPEMENT := preload("res://scenes/case_equipement.tscn")
const LIBELLES_TYPES_INVENTAIRE := {
	"": "Sans type",
	"accessoire": "Accessoires",
	"arme": "Armes",
	"armure": "Armures",
	"coffre": "Coffres",
	"consumable": "Consommables",
	"fruit_demon": "Fruits du démon",
	"outil": "Outils",
	"ressource": "Ressources",
}

@onready var fenetre: Panel = $Fenetre
@onready var btn_menu: Button = $BoutonMenu
@onready var titre: Label = $Fenetre/Entete/Titre
@onready var option_type_inventaire: OptionButton = $Fenetre/Corps/ContenuInventaire/ZoneInventaire/CoteDroit/LigneFiltreInventaire/OptionTypeInventaire
@onready var defilement_inventaire: ScrollContainer = $Fenetre/Corps/ContenuInventaire/ZoneInventaire/CoteDroit/DefilementInventaire
@onready var grille: GridContainer = defilement_inventaire.get_node("Grille")
@onready var label_vide: Label = $Fenetre/Corps/ContenuInventaire/Vide
@onready var liste_quetes: VBoxContainer = $Fenetre/Corps/ContenuQuetes/DefilementQuetes/ListeQuetes
@onready var label_aucune_quete: Label = $Fenetre/Corps/ContenuQuetes/Aucune
@onready var liste_sorts: VBoxContainer = $Fenetre/Corps/ContenuSorts/DefilementSorts/ListeSorts
@onready var label_nom: Label = $Fenetre/Corps/ContenuPersonnage/DefilementPersonnage/ColonnePersonnage/CarteIdentite/IdentiteRow/Identite/Nom
@onready var label_race_classe: Label = $Fenetre/Corps/ContenuPersonnage/DefilementPersonnage/ColonnePersonnage/CarteIdentite/IdentiteRow/Identite/RaceClasse
@onready var label_niveau: Label = $Fenetre/Corps/ContenuPersonnage/DefilementPersonnage/ColonnePersonnage/CarteIdentite/IdentiteRow/Identite/Niveau
@onready var label_xp: Label = $Fenetre/Corps/ContenuPersonnage/DefilementPersonnage/ColonnePersonnage/XP
@onready var label_vie: Label = $Fenetre/Corps/ContenuPersonnage/DefilementPersonnage/ColonnePersonnage/Vie
@onready var label_argent: Label = $Fenetre/Corps/ContenuPersonnage/DefilementPersonnage/ColonnePersonnage/Argent
@onready var label_points: Label = $Fenetre/Corps/ContenuPersonnage/DefilementPersonnage/ColonnePersonnage/Points
@onready var btn_valider: Button = $Fenetre/Corps/ContenuPersonnage/DefilementPersonnage/ColonnePersonnage/ActionsStats/BtnValider
@onready var btn_reinitialiser: Button = $Fenetre/Corps/ContenuPersonnage/DefilementPersonnage/ColonnePersonnage/ActionsStats/BtnReinitialiser
@onready var btn_effacer_perso: Button = $Fenetre/Corps/ContenuPersonnage/DefilementPersonnage/ColonnePersonnage/ActionsStats/BtnEffacerPerso
@onready var grille_stats: VBoxContainer = $Fenetre/Corps/ContenuPersonnage/DefilementPersonnage/ColonnePersonnage/StatsGrid
@onready var valeur_vie_max: Label = $Fenetre/Corps/ContenuPersonnage/DefilementPersonnage/ColonnePersonnage/StatsDerivees/VieMax/VieMax/Valeur
@onready var valeur_attaque: Label = $Fenetre/Corps/ContenuPersonnage/DefilementPersonnage/ColonnePersonnage/StatsDerivees/Attaque/Attaque/Valeur
@onready var valeur_defense: Label = $Fenetre/Corps/ContenuPersonnage/DefilementPersonnage/ColonnePersonnage/StatsDerivees/Defense/Defense/Valeur
@onready var lignes_stats: Dictionary = {
	"vitalite": {"valeur": $Fenetre/Corps/ContenuPersonnage/DefilementPersonnage/ColonnePersonnage/StatsGrid/StatVitalite/Ligne/Valeur, "ajouter": $Fenetre/Corps/ContenuPersonnage/DefilementPersonnage/ColonnePersonnage/StatsGrid/StatVitalite/Ligne/Ajouter},
	"sagesse": {"valeur": $Fenetre/Corps/ContenuPersonnage/DefilementPersonnage/ColonnePersonnage/StatsGrid/StatSagesse/Ligne/Valeur, "ajouter": $Fenetre/Corps/ContenuPersonnage/DefilementPersonnage/ColonnePersonnage/StatsGrid/StatSagesse/Ligne/Ajouter},
	"force": {"valeur": $Fenetre/Corps/ContenuPersonnage/DefilementPersonnage/ColonnePersonnage/StatsGrid/StatForce/Ligne/Valeur, "ajouter": $Fenetre/Corps/ContenuPersonnage/DefilementPersonnage/ColonnePersonnage/StatsGrid/StatForce/Ligne/Ajouter},
	"intelligence": {"valeur": $Fenetre/Corps/ContenuPersonnage/DefilementPersonnage/ColonnePersonnage/StatsGrid/StatIntelligence/Ligne/Valeur, "ajouter": $Fenetre/Corps/ContenuPersonnage/DefilementPersonnage/ColonnePersonnage/StatsGrid/StatIntelligence/Ligne/Ajouter},
	"chance": {"valeur": $Fenetre/Corps/ContenuPersonnage/DefilementPersonnage/ColonnePersonnage/StatsGrid/StatChance/Ligne/Valeur, "ajouter": $Fenetre/Corps/ContenuPersonnage/DefilementPersonnage/ColonnePersonnage/StatsGrid/StatChance/Ligne/Ajouter},
	"agilite": {"valeur": $Fenetre/Corps/ContenuPersonnage/DefilementPersonnage/ColonnePersonnage/StatsGrid/StatAgilite/Ligne/Valeur, "ajouter": $Fenetre/Corps/ContenuPersonnage/DefilementPersonnage/ColonnePersonnage/StatsGrid/StatAgilite/Ligne/Ajouter},
}
@onready var icone_detail: TextureRect = $Fenetre/Corps/ContenuInventaire/ZoneInventaire/CoteDroit/DetailItem/MargesDetail/ColonneDetail/IconeItem
@onready var nom_detail: Label = $Fenetre/Corps/ContenuInventaire/ZoneInventaire/CoteDroit/DetailItem/MargesDetail/ColonneDetail/NomItem
@onready var type_detail: Label = $Fenetre/Corps/ContenuInventaire/ZoneInventaire/CoteDroit/DetailItem/MargesDetail/ColonneDetail/TypeRareteItem
@onready var description_detail: Label = $Fenetre/Corps/ContenuInventaire/ZoneInventaire/CoteDroit/DetailItem/MargesDetail/ColonneDetail/DescriptionItem
@onready var stats_detail: Label = $Fenetre/Corps/ContenuInventaire/ZoneInventaire/CoteDroit/DetailItem/MargesDetail/ColonneDetail/StatsItem
@onready var prix_detail: Label = $Fenetre/Corps/ContenuInventaire/ZoneInventaire/CoteDroit/DetailItem/MargesDetail/ColonneDetail/PrixItem
@onready var compteur_wiki: Label = $Fenetre/Corps/ContenuWiki/CompteurWiki
@onready var champ_recherche: LineEdit = $Fenetre/Corps/ContenuWiki/ChampRechercheWiki
@onready var option_type_wiki: OptionButton = $Fenetre/Corps/ContenuWiki/LigneFiltreWiki/OptionTypeWiki
@onready var btn_donner_item_wiki: Button = $Fenetre/Corps/ContenuWiki/ZoneWiki/DetailWiki/MargesWiki/ColonneWiki/BtnDonnerItemWiki
@onready var liste_wiki: VBoxContainer = $Fenetre/Corps/ContenuWiki/ZoneWiki/DefilementWiki/ListeWiki
@onready var icone_wiki: TextureRect = $Fenetre/Corps/ContenuWiki/ZoneWiki/DetailWiki/MargesWiki/ColonneWiki/IconeWiki
@onready var nom_wiki: Label = $Fenetre/Corps/ContenuWiki/ZoneWiki/DetailWiki/MargesWiki/ColonneWiki/NomWiki
@onready var type_wiki: Label = $Fenetre/Corps/ContenuWiki/ZoneWiki/DetailWiki/MargesWiki/ColonneWiki/TypeWiki
@onready var description_wiki: Label = $Fenetre/Corps/ContenuWiki/ZoneWiki/DetailWiki/MargesWiki/ColonneWiki/DescriptionWiki
@onready var stats_wiki: Label = $Fenetre/Corps/ContenuWiki/ZoneWiki/DetailWiki/MargesWiki/ColonneWiki/StatsWiki
@onready var prix_wiki: Label = $Fenetre/Corps/ContenuWiki/ZoneWiki/DetailWiki/MargesWiki/ColonneWiki/PrixWiki
@onready var nom_metier: Label = $Fenetre/Corps/ContenuMetiers/ZoneMetiers/PanneauMetier/MargesMetier/ColonneMetier/NomMetier
@onready var desc_metier: Label = $Fenetre/Corps/ContenuMetiers/ZoneMetiers/PanneauMetier/MargesMetier/ColonneMetier/DescMetier
@onready var xp_metier: Label = $Fenetre/Corps/ContenuMetiers/ZoneMetiers/PanneauMetier/MargesMetier/ColonneMetier/XpMetier
@onready var titre_recettes: Label = $Fenetre/Corps/ContenuMetiers/ZoneMetiers/PanneauMetier/MargesMetier/ColonneMetier/TitreRecettes
@onready var liste_recettes: VBoxContainer = $Fenetre/Corps/ContenuMetiers/ZoneMetiers/PanneauMetier/MargesMetier/ColonneMetier/DefilementRecettes/ListeRecettes
@onready var btn_equiper: Button = $Fenetre/Corps/ContenuInventaire/ZoneInventaire/CoteDroit/DetailItem/MargesDetail/ColonneDetail/BtnEquip
@onready var btn_manger_fruit: Button = $Fenetre/Corps/ContenuInventaire/ZoneInventaire/CoteDroit/DetailItem/MargesDetail/ColonneDetail/BtnMangerFruit
@onready var btn_ouvrir_coffre: Button = $Fenetre/Corps/ContenuInventaire/ZoneInventaire/CoteDroit/DetailItem/MargesDetail/ColonneDetail/BtnOuvrirCoffre
@onready var btn_ouvrir_tous: Button = $Fenetre/Corps/ContenuInventaire/ZoneInventaire/CoteDroit/DetailItem/MargesDetail/ColonneDetail/BtnOuvrirTous
@onready var btn_debug_berry: Button = $Fenetre/Corps/ContenuInventaire/ZoneInventaire/CoteDroit/DetailItem/MargesDetail/ColonneDetail/BtnDebugBerry
@onready var silhouette: Control = $Fenetre/Corps/ContenuInventaire/ZoneInventaire/PanneauSilhouette/Silhouette
@onready var argent_hotel: Label = $Fenetre/Corps/ContenuHotel/ArgentHotel
@onready var info_achats_hotel: Label = $Fenetre/Corps/ContenuHotel/ZoneHotel/PanneauAchats/MargesAchats/ColonneAchats/InfoAchats
@onready var liste_achats_hotel: VBoxContainer = $Fenetre/Corps/ContenuHotel/ZoneHotel/PanneauAchats/MargesAchats/ColonneAchats/DefilementAchats/ListeAchats
@onready var liste_ventes_hotel: VBoxContainer = $Fenetre/Corps/ContenuHotel/ZoneHotel/PanneauVentes/MargesVentes/ColonneVentes/DefilementVentes/ListeVentes
@onready var champ_objet_hotel: OptionButton = $Fenetre/Corps/ContenuHotel/ZoneHotel/PanneauVentes/MargesVentes/ColonneVentes/RangeeObjet/ChampObjet
@onready var nb_quantite_hotel: SpinBox = $Fenetre/Corps/ContenuHotel/ZoneHotel/PanneauVentes/MargesVentes/ColonneVentes/RangeeMise/NbQuantite
@onready var nb_prix_hotel: SpinBox = $Fenetre/Corps/ContenuHotel/ZoneHotel/PanneauVentes/MargesVentes/ColonneVentes/RangeePrix/NbPrix
@onready var btn_mettre_hotel: Button = $Fenetre/Corps/ContenuHotel/ZoneHotel/PanneauVentes/MargesVentes/ColonneVentes/RangeeMise/BtnMettre
@onready var info_mise_hotel: Label = $Fenetre/Corps/ContenuHotel/ZoneHotel/PanneauVentes/MargesVentes/ColonneVentes/InfoMise
@onready var info_equipage: Label = $Fenetre/Corps/ContenuEquipage/ZoneEquipage/PanneauEquipage/MargesEquipage/DefilementEquipage/ColonneEquipage/InfoEquipage
@onready var forme_creation_equipage: HBoxContainer = $Fenetre/Corps/ContenuEquipage/ZoneEquipage/PanneauEquipage/MargesEquipage/DefilementEquipage/ColonneEquipage/FormeCreationEquipage
@onready var champ_nom_equipage: LineEdit = $Fenetre/Corps/ContenuEquipage/ZoneEquipage/PanneauEquipage/MargesEquipage/DefilementEquipage/ColonneEquipage/FormeCreationEquipage/ChampNomEquipage
@onready var btn_fonder_equipage: Button = $Fenetre/Corps/ContenuEquipage/ZoneEquipage/PanneauEquipage/MargesEquipage/DefilementEquipage/ColonneEquipage/FormeCreationEquipage/BtnFonder
@onready var titre_membres: Label = $Fenetre/Corps/ContenuEquipage/ZoneEquipage/PanneauEquipage/MargesEquipage/DefilementEquipage/ColonneEquipage/TitreMembres
@onready var liste_membres: VBoxContainer = $Fenetre/Corps/ContenuEquipage/ZoneEquipage/PanneauEquipage/MargesEquipage/DefilementEquipage/ColonneEquipage/ListeMembres
@onready var btn_dissoudre: Button = $Fenetre/Corps/ContenuEquipage/ZoneEquipage/PanneauEquipage/MargesEquipage/DefilementEquipage/ColonneEquipage/BtnDissoudre
@onready var forme_ajout_membre: HBoxContainer = $Fenetre/Corps/ContenuEquipage/ZoneEquipage/PanneauEquipage/MargesEquipage/DefilementEquipage/ColonneEquipage/FormeAjoutMembre
@onready var champ_nom_membre: LineEdit = $Fenetre/Corps/ContenuEquipage/ZoneEquipage/PanneauEquipage/MargesEquipage/DefilementEquipage/ColonneEquipage/FormeAjoutMembre/ChampNomMembre
@onready var btn_ajouter_membre: Button = $Fenetre/Corps/ContenuEquipage/ZoneEquipage/PanneauEquipage/MargesEquipage/DefilementEquipage/ColonneEquipage/FormeAjoutMembre/BtnAjouterMembre
@onready var btn_quitter_equipage: Button = $Fenetre/Corps/ContenuEquipage/ZoneEquipage/PanneauEquipage/MargesEquipage/DefilementEquipage/ColonneEquipage/BtnQuitter
@onready var forme_description: HBoxContainer = $Fenetre/Corps/ContenuEquipage/ZoneEquipage/PanneauEquipage/MargesEquipage/DefilementEquipage/ColonneEquipage/FormeDescription
@onready var champ_description: LineEdit = $Fenetre/Corps/ContenuEquipage/ZoneEquipage/PanneauEquipage/MargesEquipage/DefilementEquipage/ColonneEquipage/FormeDescription/ChampDescription
@onready var btn_modifier_description: Button = $Fenetre/Corps/ContenuEquipage/ZoneEquipage/PanneauEquipage/MargesEquipage/DefilementEquipage/ColonneEquipage/FormeDescription/BtnModifierDescription
@onready var info_caisse: Label = $Fenetre/Corps/ContenuEquipage/ZoneEquipage/PanneauEquipage/MargesEquipage/DefilementEquipage/ColonneEquipage/InfoCaisse
@onready var forme_caisse: HBoxContainer = $Fenetre/Corps/ContenuEquipage/ZoneEquipage/PanneauEquipage/MargesEquipage/DefilementEquipage/ColonneEquipage/FormeCaisse
@onready var nb_caisse: SpinBox = $Fenetre/Corps/ContenuEquipage/ZoneEquipage/PanneauEquipage/MargesEquipage/DefilementEquipage/ColonneEquipage/FormeCaisse/NbCaisse
@onready var btn_deposer: Button = $Fenetre/Corps/ContenuEquipage/ZoneEquipage/PanneauEquipage/MargesEquipage/DefilementEquipage/ColonneEquipage/FormeCaisse/BtnDeposer
@onready var btn_retirer_caisse: Button = $Fenetre/Corps/ContenuEquipage/ZoneEquipage/PanneauEquipage/MargesEquipage/DefilementEquipage/ColonneEquipage/FormeCaisse/BtnRetirerCaisse
@onready var titre_journal: Label = $Fenetre/Corps/ContenuEquipage/ZoneEquipage/PanneauFlotte/MargesFlotte/ColonneFlotte/TitreJournal
@onready var liste_journal: VBoxContainer = $Fenetre/Corps/ContenuEquipage/ZoneEquipage/PanneauFlotte/MargesFlotte/ColonneFlotte/DefilementJournal/ListeJournal
@onready var info_flotte: Label = $Fenetre/Corps/ContenuEquipage/ZoneEquipage/PanneauFlotte/MargesFlotte/ColonneFlotte/InfoFlotte
@onready var btn_rompre_flotte: Button = $Fenetre/Corps/ContenuEquipage/ZoneEquipage/PanneauFlotte/MargesFlotte/ColonneFlotte/BtnRompreFlotte
@onready var liste_alliances: VBoxContainer = $Fenetre/Corps/ContenuEquipage/ZoneEquipage/PanneauFlotte/MargesFlotte/ColonneFlotte/DefilementAlliances/ListeAlliances

# positions des emplacements sur le visuel du personnage (paperdoll)
var emplacements_ui := {}
var detail_id_courant := ""

# bouton d'utilisation des consommables (créé dans _ready : la scène ne
# contient que les boutons Équiper, Fruit et Coffres)
var btn_utiliser: Button

const TEXTES_EMPLACEMENTS := {
	"arme": "Arme",
	"arme2": "Arme secondaire",
	"corps": "Manteau",
	"tête": "Chapeau",
	"visage": "Visage",
	"cou": "Cou",
	"main": "Gants",
	"cape": "Cape",
	"ceinture": "Ceinture",
	"pantalon": "Pantalon",
	"pieds": "Chaussures",
	"anneau1": "Anneau 1",
	"anneau2": "Anneau 2",
}
const LABELS_COURTS_EMPLACEMENTS := {
	"ceinture": "Ceint.",
	"pieds": "Chauss.",
}
const NOMS_NODES_EMPLACEMENTS := {
	"arme": "EquipementArme",
	"arme2": "EquipementArme2",
	"corps": "EquipementCorps",
	"tête": "EquipementTete",
	"visage": "EquipementVisage",
	"cou": "EquipementCou",
	"main": "EquipementMain",
	"cape": "EquipementCape",
	"ceinture": "EquipementCeinture",
	"pantalon": "EquipementPantalon",
	"pieds": "EquipementPieds",
	"anneau1": "EquipementAnneau1",
	"anneau2": "EquipementAnneau2",
}
const POSITIONS_REPLI_EMPLACEMENTS := {
	"tête": Vector2(14, 70),
	"arme2": Vector2(200, 298),
	"visage": Vector2(298, 70),
	"cou": Vector2(298, 146),
	"corps": Vector2(14, 146),
	"cape": Vector2(14, 222),
	"ceinture": Vector2(16, 402),
	"pantalon": Vector2(108, 402),
	"pieds": Vector2(200, 402),
	"main": Vector2(14, 298),
	"arme": Vector2(298, 222),
	"anneau1": Vector2(298, 298),
	"anneau2": Vector2(292, 402),
}
const ICONES_EMPLACEMENTS := {
	"arme": "res://addons/pixel_ui_fantasy/icons/sword.png",
	"arme2": "res://addons/pixel_ui_fantasy/icons/sword.png",
	"corps": "res://addons/pixel_ui_fantasy/icons/shield.png",
	"tête": "res://addons/pixel_ui_fantasy/icons/helmet.png",
	"visage": "res://addons/pixel_ui_fantasy/icons/scroll.png",
	"cou": "res://addons/pixel_ui_fantasy/icons/gem.png",
	"main": "res://addons/pixel_ui_fantasy/icons/key.png",
	"cape": "res://addons/pixel_ui_fantasy/icons/quest.png",
	"ceinture": "res://addons/pixel_ui_fantasy/icons/chest.png",
	"pantalon": "res://addons/pixel_ui_fantasy/icons/cross.png",
	"pieds": "res://addons/pixel_ui_fantasy/icons/arrow_right.png",
	"anneau1": "res://addons/pixel_ui_fantasy/icons/coin.png",
	"anneau2": "res://addons/pixel_ui_fantasy/icons/coin.png",
}
@onready var contenus := {
	"personnage": $Fenetre/Corps/ContenuPersonnage,
	"sorts": $Fenetre/Corps/ContenuSorts,
	"quetes": $Fenetre/Corps/ContenuQuetes,
	"inventaire": $Fenetre/Corps/ContenuInventaire,
	"wiki": $Fenetre/Corps/ContenuWiki,
	"metiers": $Fenetre/Corps/ContenuMetiers,
	"hotel": $Fenetre/Corps/ContenuHotel,
	"equipage": $Fenetre/Corps/ContenuEquipage,
}
@onready var noms_sections := {
	"personnage": "Personnage",
	"sorts": "Sorts",
	"quetes": "Quêtes",
	"inventaire": "Inventaire",
	"wiki": "Wiki",
	"metiers": "Métiers",
	"hotel": "Hôtel des ventes",
	"equipage": "Équipage",
}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	fenetre.visible = false
	_ajuster_fenetre()
	_creer_emplacements()
	btn_equiper.pressed.connect(_on_bouton_equiper)
	btn_manger_fruit.pressed.connect(_on_bouton_manger_fruit)
	btn_manger_fruit.visible = false
	btn_ouvrir_coffre.pressed.connect(_on_bouton_ouvrir_coffre)
	btn_ouvrir_tous.pressed.connect(_on_bouton_ouvrir_tous)
	btn_debug_berry.pressed.connect(_on_debug_berry)
	btn_utiliser = Button.new()
	btn_utiliser.text = "Utiliser"
	btn_utiliser.visible = false
	btn_equiper.get_parent().add_child(btn_utiliser)
	btn_utiliser.pressed.connect(_on_bouton_utiliser)
	$Fenetre/Entete/Fermer.pressed.connect(fermer)
	btn_valider.pressed.connect(_on_valider_points)
	btn_reinitialiser.pressed.connect(_on_reinitialiser_points)
	btn_effacer_perso.pressed.connect(_on_effacer_perso)
	for cle: String in lignes_stats:
		var ligne_stat: Dictionary = lignes_stats[cle]
		var bouton_ajouter: Button = ligne_stat["ajouter"] as Button
		bouton_ajouter.pressed.connect(_on_augmenter_stat.bind(cle))
	btn_menu.pressed.connect(_on_bouton_menu)
	$Fenetre/Corps/NavigationPirate/BarreCascade/Personnage.pressed.connect(ouvrir.bind("personnage"))
	$Fenetre/Corps/NavigationPirate/BarreCascade/Sorts.pressed.connect(ouvrir.bind("sorts"))
	$Fenetre/Corps/NavigationPirate/BarreCascade/Quetes.pressed.connect(ouvrir.bind("quetes"))
	$Fenetre/Corps/NavigationPirate/BarreCascade/Inventaire.pressed.connect(ouvrir.bind("inventaire"))
	$Fenetre/Corps/NavigationPirate/BarreCascade/Wiki.pressed.connect(ouvrir.bind("wiki"))
	champ_recherche.text_changed.connect(func(_t): maj_wiki())
	_peupler_types_wiki()
	option_type_wiki.item_selected.connect(func(_i): maj_wiki())
	btn_donner_item_wiki.pressed.connect(_on_donner_item_wiki)
	$Fenetre/Corps/NavigationPirate/BarreCascade/Metiers.pressed.connect(ouvrir.bind("metiers"))
	$Fenetre/Corps/NavigationPirate/BarreCascade/Hotel.pressed.connect(ouvrir.bind("hotel"))
	$Fenetre/Corps/NavigationPirate/BarreCascade/Equipage.pressed.connect(ouvrir.bind("equipage"))
	option_type_inventaire.item_selected.connect(_on_type_inventaire_selectionne)
	Inventaire.inventaire_modifie.connect(maj_grille)
	Inventaire.inventaire_modifie.connect(_maj_filtre_types_wiki)
	QuestManager.quete_acceptee.connect(maj_quetes)
	QuestManager.quete_progressee.connect(maj_quetes)
	QuestManager.quete_abandonnee.connect(maj_quetes)
	QuestManager.quete_terminee.connect(maj_quetes)
	Personnage.caracteristiques_modifiees.connect(maj_personnage)
	HotelVentes.hdv_modifie.connect(_on_hotel_modifie)
	champ_objet_hotel.item_selected.connect(_maj_forme_hotel)
	btn_mettre_hotel.pressed.connect(_on_mettre_en_vente)
	btn_fonder_equipage.pressed.connect(_on_fonder_equipage)
	btn_dissoudre.pressed.connect(_on_dissoudre_equipage)
	btn_ajouter_membre.pressed.connect(_on_ajouter_membre)
	btn_quitter_equipage.pressed.connect(_on_quitter_equipage)
	btn_rompre_flotte.pressed.connect(_on_rompre_flotte)
	btn_modifier_description.pressed.connect(_on_modifier_description)
	btn_deposer.pressed.connect(_on_deposer_caisse)
	btn_retirer_caisse.pressed.connect(_on_retirer_caisse)
	Equipages.equipage_modifie.connect(_on_equipage_modifie)
func _ajuster_fenetre() -> void:
	var taille_ecran: Vector2 = get_viewport().get_visible_rect().size
	var demi_largeur := minf(600.0, taille_ecran.x * 0.47)
	var demi_hauteur := minf(400.0, taille_ecran.y * 0.44)
	fenetre.offset_left = -demi_largeur
	fenetre.offset_right = demi_largeur
	fenetre.offset_top = -demi_hauteur
	fenetre.offset_bottom = demi_hauteur
	fenetre.pivot_offset = Vector2(demi_largeur, demi_hauteur)

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
	if fenetre.visible:
		fermer()
	else:
		ouvrir()

func ouvrir(section: String = "") -> void:
	if get_tree().paused:
		return
	if section != "":
		section_actuelle = section
	elif section_actuelle == "":
		section_actuelle = "personnage"
	var etait_fermee := not fenetre.visible
	if _tween_fenetre != null and _tween_fenetre.is_running():
		_tween_fenetre.kill()
	fenetre.visible = true
	if etait_fermee:
		menu_ouvert.emit()
		fenetre.modulate.a = 0.0
		fenetre.scale = Vector2(0.98, 0.98)
		_tween_fenetre = create_tween().set_parallel(true)
		_tween_fenetre.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tween_fenetre.tween_property(fenetre, "modulate:a", 1.0, 0.18)
		_tween_fenetre.tween_property(fenetre, "scale", Vector2.ONE, 0.18)
	maj_section()

func fermer() -> void:
	# les points non validés sont abandonnés à la fermeture
	points_en_attente = {}
	if not fenetre.visible:
		return
	if _tween_fenetre != null and _tween_fenetre.is_running():
		_tween_fenetre.kill()
	menu_ferme.emit()
	_tween_fenetre = create_tween().set_parallel(true)
	_tween_fenetre.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween_fenetre.tween_property(fenetre, "modulate:a", 0.0, 0.14)
	_tween_fenetre.tween_property(fenetre, "scale", Vector2(0.98, 0.98), 0.14)
	_tween_fenetre.finished.connect(fenetre.hide)

func maj_section() -> void:
	for section in contenus:
		contenus[section].visible = section == section_actuelle
	# bouton debug visible uniquement dans l'inventaire
	btn_debug_berry.visible = section_actuelle == "inventaire"
	titre.text = noms_sections[section_actuelle]
	match section_actuelle:
		"personnage":
			maj_personnage()
		"sorts":
			maj_sorts()
		"quetes":
			maj_quetes()
		"inventaire":
			maj_equipement()
			maj_grille()
		"wiki":
			maj_wiki()
		"metiers":
			maj_metiers()
		"hotel":
			maj_hotel()
		"equipage":
			maj_equipage()

func maj_personnage() -> void:
	var en_attente := _total_points_en_attente()
	var restants := maxi(Personnage.points_statistique - en_attente, 0)
	label_nom.text = Personnage.nom
	label_race_classe.text = "Race : %s | Classe : %s" % [Personnage.nom_race(), Personnage.nom_classe()]
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
	valeur_vie_max.text = str(vie_max_affichee)
	valeur_attaque.text = str(Personnage.attaque)
	valeur_defense.text = str(Personnage.defense)
	for cle: String in Personnage.caracteristiques:
		var ligne_stat: Dictionary = lignes_stats[cle]
		var valeur_stat: Label = ligne_stat["valeur"] as Label
		var bouton_ajouter: Button = ligne_stat["ajouter"] as Button
		valeur_stat.text = str(int(Personnage.caracteristiques[cle]) + int(points_en_attente.get(cle, 0)))
		bouton_ajouter.disabled = restants <= 0

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
	HotelVentes.reinitialiser()
	Equipages.reinitialiser()
	Coffres.reinitialiser()
	get_tree().reload_current_scene()

const TAILLE_CASE_SORT := Vector2(56, 56)
const ICONE_SORT_DEFAUT := "res://addons/pixel_ui_fantasy/icons/scroll.png"
const ICONES_SORTS := {
	"attack": "res://addons/pixel_ui_fantasy/icons/sword.png",
	"heal": "res://addons/pixel_ui_fantasy/icons/potion_red.png",
	"defense": "res://addons/pixel_ui_fantasy/icons/shield.png",
	"buff": "res://addons/pixel_ui_fantasy/icons/gem.png",
	"debuff": "res://addons/pixel_ui_fantasy/icons/cross.png",
}

func _icone_sort(sort: Dictionary) -> Texture2D:
	var chemin: String = ICONES_SORTS.get(str(sort.get("type", "")).to_lower(), ICONE_SORT_DEFAUT)
	return load(chemin)

# onglet Sorts : barre de combat en haut (cliquer un sort placé pour le
# retirer), puis la liste des sorts de la classe et des pouvoirs du fruit
# mangé débloqués, avec un bouton pour placer chacun dans la barre
func maj_sorts() -> void:
	for enfant in liste_sorts.get_children():
		enfant.queue_free()
	_construire_barre_sorts()
	var ids_classe: Array[String] = Personnage.sorts_de_classe()
	var ids_combat: Array[String] = []
	# seuls les sorts disponibles hors classe (pouvoirs du fruit mangé
	# débloqués par son niveau d'utilisation) apparaissent ici
	for id_sort in Personnage.sorts_disponibles():
		if not ids_classe.has(id_sort):
			ids_combat.append(id_sort)
	if ids_classe.is_empty() and ids_combat.is_empty():
		var vide := Label.new()
		vide.text = "Aucun sort n'est disponible pour le moment."
		liste_sorts.add_child(vide)
		return
	if not ids_classe.is_empty():
		_ajouter_titre_section_sorts("Sorts de classe")
		for id_classe in ids_classe:
			if Personnage.sorts.has(id_classe):
				_construire_carte_sort(id_classe)
	if not ids_combat.is_empty():
		_ajouter_titre_section_sorts("Pouvoirs du fruit du démon")
		for id_combat in ids_combat:
			_construire_carte_sort(id_combat)
func _ajouter_titre_section_sorts(texte: String) -> void:
	var titre_section := Label.new()
	titre_section.text = texte
	titre_section.add_theme_font_size_override("font_size", 24)
	liste_sorts.add_child(titre_section)

# barre de sorts : un bouton par emplacement ; les emplacements vides
# sont grisés, cliquer un sort placé le retire de la barre
func _construire_barre_sorts() -> void:
	var encadre := PanelContainer.new()
	var colonne := VBoxContainer.new()
	colonne.add_theme_constant_override("separation", 8)
	var titre_barre := Label.new()
	titre_barre.text = "Barre de sorts - %d / %d" % [
		Personnage.barre_sorts.size(), Personnage.TAILLE_BARRE_SORTS]
	titre_barre.add_theme_font_size_override("font_size", 22)
	colonne.add_child(titre_barre)
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 8)
	for i in Personnage.TAILLE_BARRE_SORTS:
		var id: String = Personnage.barre_sorts[i] if i < Personnage.barre_sorts.size() else ""
		var bouton := Button.new()
		bouton.custom_minimum_size = TAILLE_CASE_SORT
		if id != "" and Personnage.sorts.has(id):
			var sort: Dictionary = Personnage.sorts[id]
			bouton.icon = _icone_sort(sort)
			bouton.expand_icon = true
			bouton.tooltip_text = "%s\nCliquez pour retirer de la barre." % sort.get("nom", "Sort")
			bouton.pressed.connect(_on_retirer_sort_barre.bind(id))
		else:
			bouton.disabled = true
		slots.add_child(bouton)
	colonne.add_child(slots)
	encadre.add_child(colonne)
	liste_sorts.add_child(encadre)

# carte d'un sort de la classe : nom, icône, infos, description et
# bouton de placement dans la barre de combat
func _construire_carte_sort(id: String) -> void:
	var sort: Dictionary = Personnage.sorts[id]
	var encadre := PanelContainer.new()
	var boite := VBoxContainer.new()
	var entete := HBoxContainer.new()
	entete.add_theme_constant_override("separation", 10)
	var icone := TextureRect.new()
	icone.texture = _icone_sort(sort)
	icone.custom_minimum_size = Vector2(32, 32)
	icone.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icone.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var nom := Label.new()
	nom.text = str(sort.get("nom", "Sort"))
	nom.add_theme_font_size_override("font_size", 26)
	nom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var btn_barre := Button.new()
	if Personnage.sort_dans_barre(id):
		btn_barre.text = "Retirer de la barre"
		btn_barre.pressed.connect(_on_retirer_sort_barre.bind(id))
	else:
		btn_barre.text = "Ajouter à la barre"
		btn_barre.disabled = Personnage.barre_sorts_pleine()
		btn_barre.pressed.connect(_on_ajouter_sort_barre.bind(id))
	entete.add_child(icone)
	entete.add_child(nom)
	entete.add_child(btn_barre)
	var infos := Label.new()
	var texte_infos := "Type : %s | Portée : %d | Recharge : %d" % [
		sort.get("type", "-"), int(sort.get("portee", 0)), int(sort.get("recharge", 0)),
	]
	if int(sort.get("degats", 0)) > 0:
		texte_infos += " | Dégâts : %d" % int(sort["degats"])
	infos.text = texte_infos
	var description := Label.new()
	var texte_description: String = str(sort.get("description", ""))
	var effets: Array = sort.get("effets", [])
	if not effets.is_empty():
		var noms_effets: Array[String] = []
		for effet: Variant in effets:
			if effet is Dictionary:
				var id_etat: int = int(effet.get("id", 0))
				var donnees_etat: Dictionary = Personnage.etats.get(id_etat, {})
				var nom_effet: String = str(donnees_etat.get("nom", "État %d" % id_etat))
				var duree: int = int(effet.get("duree", 0))
				var chance_brute: float = float(effet.get("chance", 1.0))
				var chance: int = roundi(chance_brute * 100.0 if chance_brute <= 1.0 else chance_brute)
				var texte_effet: String = "%s - %d%%" % [nom_effet, chance]
				if duree > 0:
					texte_effet += " - %d tour%s" % [duree, "s" if duree > 1 else ""]
				noms_effets.append(texte_effet)
		if not noms_effets.is_empty():
			texte_description += "\nEffets : " + ", ".join(noms_effets)
	description.text = texte_description
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	boite.add_child(entete)
	boite.add_child(infos)
	boite.add_child(description)
	encadre.add_child(boite)
	liste_sorts.add_child(encadre)

func _on_ajouter_sort_barre(id: String) -> void:
	Personnage.ajouter_sort_barre(id)
	maj_sorts()

func _on_retirer_sort_barre(id: String) -> void:
	Personnage.retirer_sort_barre(id)
	maj_sorts()

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
		titre_quete.add_theme_font_size_override("font_size", 24)
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
		grille.remove_child(enfant)
		enfant.queue_free()

	var ids_par_type := {}
	for id: String in Inventaire.objets:
		var type_item := str(Inventaire.details_objet(id).get("type", ""))
		if not ids_par_type.has(type_item):
			ids_par_type[type_item] = []
		ids_par_type[type_item].append(id)
	var types := ids_par_type.keys()
	types.sort_custom(func(a: String, b: String) -> bool:
		return _libelle_type_inventaire(a).naturalnocasecmp_to(_libelle_type_inventaire(b)) < 0)
	var type_choisi: Variant = _maj_types_inventaire(types)
	var types_affiches := types if type_choisi == null else [type_choisi]

	label_vide.visible = Inventaire.objets.is_empty()
	maj_detail_aucun()
	for type_item in types_affiches:
		var ids: Array = ids_par_type[type_item]
		ids.sort_custom(func(a: String, b: String) -> bool:
			return Inventaire.nom_objet(a).naturalnocasecmp_to(Inventaire.nom_objet(b)) < 0)
		for id: String in ids:
			_ajouter_case_inventaire(id)

func _libelle_type_inventaire(type_item: String) -> String:
	return LIBELLES_TYPES_INVENTAIRE.get(type_item, type_item.capitalize())

func _maj_types_inventaire(types: Array) -> Variant:
	var type_courant: Variant = null
	if option_type_inventaire.selected >= 0:
		type_courant = option_type_inventaire.get_item_metadata(option_type_inventaire.selected)
	option_type_inventaire.clear()
	option_type_inventaire.add_item("Tous les types")
	var selection := 0
	for type_item: String in types:
		option_type_inventaire.add_item(_libelle_type_inventaire(type_item))
		var index := option_type_inventaire.item_count - 1
		option_type_inventaire.set_item_metadata(index, type_item)
		if type_item == type_courant:
			selection = index
	option_type_inventaire.select(selection)
	option_type_inventaire.disabled = types.is_empty()
	return option_type_inventaire.get_item_metadata(selection)

func _on_type_inventaire_selectionne(_index: int) -> void:
	defilement_inventaire.scroll_vertical = 0
	maj_grille()

func _ajouter_case_inventaire(id: String) -> void:
	var details := Inventaire.details_objet(id)
	var quantite_objet := int(Inventaire.objets[id])
	var slot := SCENE_CASE_INVENTAIRE.instantiate() as PanelContainer
	if slot == null:
		push_warning("Impossible de charger la case d'inventaire.")
		return
	slot.theme_type_variation = _variation_rarete(int(details.get("id_rarete", 1)))
	slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	slot.gui_input.connect(_on_slot_clique.bind(id))
	slot.tooltip_text = "%s x%d\n%s" % [Inventaire.nom_objet(id), quantite_objet, str(details.get("description", ""))]
	var icone: TextureRect = slot.get_node("Boite/Icone")
	icone.texture = _icone_objet(details)
	var quantite: Label = slot.get_node("Boite/Quantite")
	quantite.text = "x%d" % quantite_objet
	grille.add_child(slot)

func _on_slot_clique(evenement: InputEvent, id: String) -> void:
	if evenement is InputEventMouseButton and evenement.pressed and evenement.button_index == MOUSE_BUTTON_LEFT:
		maj_detail_item(id)

func maj_detail_item(id: String) -> void:
	detail_id_courant = id
	var details := Inventaire.details_objet(id)
	icone_detail.texture = _icone_objet(details)
	nom_detail.text = Inventaire.nom_objet(id)
	nom_detail.add_theme_color_override("font_color", details["couleur_rarete"])
	var type_texte: String = details.get("type", "").capitalize()
	if details.get("sous_type", "") != "":
		type_texte += " | %s" % details["sous_type"].capitalize()
	if details.get("rarete", "") != "":
		type_texte += "\n%s" % details["rarete"]
	type_detail.text = type_texte
	type_detail.add_theme_color_override("font_color", details["couleur_rarete"])
	description_detail.text = details.get("description", "")
	var texte_stats := _texte_stats(details)
	stats_detail.text = texte_stats
	stats_detail.visible = texte_stats != ""
	prix_detail.text = "Prix : %d Berry" % int(details.get("prix", 0))
	_maj_bouton_equiper(details, id)
	_maj_bouton_utiliser(details)

func maj_detail_aucun() -> void:
	detail_id_courant = ""
	icone_detail.texture = null
	nom_detail.text = "Aucun objet sélectionné"
	nom_detail.remove_theme_color_override("font_color")
	type_detail.text = ""
	description_detail.text = "Cliquez sur un objet de l'inventaire pour voir ses détails."
	stats_detail.text = ""
	prix_detail.text = ""
	btn_equiper.visible = false
	btn_manger_fruit.visible = false
	btn_ouvrir_coffre.visible = false
	btn_ouvrir_tous.visible = false
	if btn_utiliser != null:
		btn_utiliser.visible = false

# construit le paperdoll : portrait du personnage au centre, un slot
# cliquable par emplacement positionné sur le corps
func _creer_emplacements() -> void:
	for emplacement in TEXTES_EMPLACEMENTS:
		var nom_noeud: String = str(NOMS_NODES_EMPLACEMENTS[str(emplacement)])
		var slot: PanelContainer = silhouette.get_node_or_null(nom_noeud) as PanelContainer
		if slot == null:
			slot = SCENE_CASE_EQUIPEMENT.instantiate() as PanelContainer
			if slot == null:
				push_warning("Impossible de charger la case d'équipement : %s." % str(emplacement))
				continue
			slot.name = nom_noeud
			slot.position = POSITIONS_REPLI_EMPLACEMENTS[str(emplacement)]
			silhouette.add_child(slot)
		slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		slot.gui_input.connect(_on_emplacement_clique.bind(emplacement))
		var icone: TextureRect = slot.get_node("Contenu/Icone")
		var libelle: Label = slot.get_node("Contenu/Libelle")
		libelle.text = LABELS_COURTS_EMPLACEMENTS.get(emplacement, TEXTES_EMPLACEMENTS[emplacement])
		emplacements_ui[emplacement] = {"slot": slot, "icone": icone}

# met à jour les boutons d'action selon l'objet affiché dans le détail :
# Équiper/Déséquiper, Ouvrir les coffres, Manger les fruits du démon
func _maj_bouton_equiper(details: Dictionary, id: String) -> void:
	var est_coffre := str(details.get("type", "")) == "coffre"
	btn_ouvrir_coffre.visible = est_coffre
	btn_ouvrir_tous.visible = est_coffre and int(Inventaire.objets.get(id, 0)) >= 2
	var est_fruit := str(details.get("type", "")) == "fruit_demon"
	btn_manger_fruit.visible = est_fruit
	if est_fruit:
		if Personnage.fruit_id != "":
			btn_manger_fruit.text = "Fruit déjà mangé"
			btn_manger_fruit.disabled = true
		else:
			btn_manger_fruit.text = "Manger le fruit"
			btn_manger_fruit.disabled = false
	var equipable := Personnage.emplacement_equipement(str(details.get("type", "")), str(details.get("sous_type", ""))) != ""
	btn_equiper.visible = equipable
	if not equipable:
		return
	var emplacement_equipe: String = Personnage.est_equipe(id)
	btn_equiper.text = "Déséquiper" if emplacement_equipe != "" else "Équiper"
	var niveau_suffisant := int(details.get("niveau_min", 1)) <= Personnage.niveau
	btn_equiper.disabled = emplacement_equipe == "" and not niveau_suffisant

func _on_bouton_equiper() -> void:
	if detail_id_courant == "":
		return
	var emplacement_equipe: String = Personnage.est_equipe(detail_id_courant)
	if emplacement_equipe != "":
		Personnage.desequiper(emplacement_equipe)
	else:
		Personnage.equiper(detail_id_courant)
	maj_equipement()
	maj_grille()
	maj_detail_item(detail_id_courant)

# met à jour le bouton Utiliser selon l'objet affiché dans le détail :
# visible pour les consommables, désactivé s'il n'a aucun effet
func _maj_bouton_utiliser(details: Dictionary) -> void:
	if btn_utiliser == null:
		return
	var consommable := str(details.get("type", "")) == "consumable"
	btn_utiliser.visible = consommable
	if not consommable:
		return
	btn_utiliser.text = "Utiliser"
	btn_utiliser.disabled = (details.get("effets", {}) as Dictionary).is_empty()

# utilise le consommable sélectionné dans le détail : applique ses effets
# (points de vie restaurés, bonus temporaires) et le retire de
# l'inventaire
func _on_bouton_utiliser() -> void:
	if detail_id_courant == "":
		return
	var nom := Inventaire.nom_objet(detail_id_courant)
	var details := Inventaire.details_objet(detail_id_courant)
	var effets: Dictionary = details.get("effets", {})
	var soin := int(effets.get("heal", 0))
	var message := Personnage.utiliser_objet(detail_id_courant)
	maj_grille()
	if Inventaire.objets.has(detail_id_courant):
		maj_detail_item(detail_id_courant)
	else:
		maj_detail_aucun()
	if message != "":
		avertir(message)
		return
	var info := AcceptDialog.new()
	info.title = "%s consommé !" % nom
	var texte := "Ses bonus sont actifs temporairement."
	if soin > 0:
		texte = "Tu récupères %d points de vie." % soin
	# carte au trésor : la croix est plantée, la chasse commence
	if str(details.get("sous_type", "")) == "carte_tresor":
		texte = "Une croix marque un trésor sur la carte du monde. File la déterrer !"
	info.dialog_text = texte
	add_child(info)
	info.popup_centered()
	info.visibility_changed.connect(func() -> void:
		if not info.visible:
			info.queue_free())

# mange le fruit du démon sélectionné dans le détail — action définitive
# (un seul fruit par personnage), d'où l'écran de confirmation ; les
# pouvoirs débloqués apparaissent dans la barre et l'onglet Sorts
func _on_bouton_manger_fruit() -> void:
	if detail_id_courant == "" or Personnage.fruit_id != "":
		return
	var details := Inventaire.details_objet(detail_id_courant)
	if str(details.get("type", "")) != "fruit_demon":
		return
	var id_fruit := detail_id_courant
	var dialogue := ConfirmationDialog.new()
	dialogue.title = "Manger le fruit"
	dialogue.dialog_text = "Manger %s est définitif : ses pouvoirs deviendront les tiens, mais aucun autre fruit du démon ne pourra jamais être mangé.\n\nSes pouvoirs rejoignent ta barre de sorts." % Inventaire.nom_objet(id_fruit)
	dialogue.ok_button_text = "Manger"
	dialogue.cancel_button_text = "Attendre"
	dialogue.confirmed.connect(_confirmer_manger_fruit.bind(id_fruit))
	add_child(dialogue)
	dialogue.popup_centered()
	dialogue.visibility_changed.connect(func() -> void:
		if not dialogue.visible:
			dialogue.queue_free())

func _confirmer_manger_fruit(id_fruit: String) -> void:
	var message := Personnage.manger_fruit(id_fruit)
	if message != "":
		avertir(message)
		return
	maj_grille()
	maj_detail_aucun()
	maj_sorts()
	var info := AcceptDialog.new()
	info.title = "Fruit mangé !"
	info.dialog_text = "Le fruit a été absorbé : ses pouvoirs sont débloqués (onglet Sorts) et son aura t'a transformé pour toujours."
	add_child(info)
	info.popup_centered()
	info.visibility_changed.connect(func() -> void:
		if not info.visible:
			info.queue_free())

# petite fenêtre d'information bloquante
func avertir(texte: String) -> void:
	var info := AcceptDialog.new()
	info.title = "Attention"
	info.dialog_text = texte
	add_child(info)
	info.popup_centered()
	info.visibility_changed.connect(func() -> void:
		if not info.visible:
			info.queue_free())

# ouvre un coffre-objet de l'inventaire : le consomme, tire le loot via Coffres
# et l'affiche dans la fenêtre de loot ; le reliquat est emporté à la fermeture
func _on_bouton_ouvrir_coffre() -> void:
	if detail_id_courant == "":
		return
	var details := Inventaire.details_objet(detail_id_courant)
	if str(details.get("type", "")) != "coffre":
		return
	var rarete := Coffres.rarete_depuis_sous_type(str(details.get("sous_type", "")))
	if rarete == 0:
		return
	# état temporaire dans Coffres : même logique que les coffres de la carte
	var id_coffre := "inventaire_%s_%d" % [detail_id_courant, randi()]
	var contenu := Coffres.ouvrir(id_coffre, rarete)
	Inventaire.retirer_objet(detail_id_courant, 1)
	maj_grille()
	if Inventaire.objets.has(detail_id_courant):
		maj_detail_item(detail_id_courant)
	else:
		maj_detail_aucun()
	var ui := get_tree().get_first_node_in_group("coffres_ui")
	if ui != null:
		ui.ouvrir_contenu("Coffre %s" % str(details.get("sous_type", "commun")).to_lower(), id_coffre, contenu, rarete)

# ouvre d'un coup tous les exemplaires du coffre sélectionné : ils sont
# consommés, le loot de chaque coffre est tiré et regroupé dans la fenêtre
func _on_bouton_ouvrir_tous() -> void:
	if detail_id_courant == "":
		return
	var details := Inventaire.details_objet(detail_id_courant)
	if str(details.get("type", "")) != "coffre":
		return
	var rarete := Coffres.rarete_depuis_sous_type(str(details.get("sous_type", "")))
	if rarete == 0:
		return
	var nombre := int(Inventaire.objets.get(detail_id_courant, 0))
	if nombre < 2:
		return
	# état temporaire unique : une section pour tout le lot
	var id_coffre := "inventaire_%s_%d" % [detail_id_courant, randi()]
	var contenu := Coffres.ouvrir_lot(id_coffre, rarete, nombre)
	Inventaire.retirer_objet(detail_id_courant, nombre)
	maj_grille()
	if Inventaire.objets.has(detail_id_courant):
		maj_detail_item(detail_id_courant)
	else:
		maj_detail_aucun()
	var ui := get_tree().get_first_node_in_group("coffres_ui")
	if ui != null:
		ui.ouvrir_contenu(
			"Coffres %s (x%d)" % [str(details.get("sous_type", "commun")).to_lower(), nombre],
			id_coffre, contenu, rarete)

# debug : crédite un million de Berry pour tester la boutique
func _on_debug_berry() -> void:
	Personnage.ajouter_berry(1_000_000)
	maj_personnage()

func _on_emplacement_clique(evenement: InputEvent, emplacement: String) -> void:
	if evenement is InputEventMouseButton and evenement.pressed and evenement.button_index == MOUSE_BUTTON_LEFT:
		var id: String = Personnage.equipement.get(emplacement, "")
		if id != "":
			maj_detail_item(id)

# rafraîchit les emplacements du paperdoll (icône, cadre de rareté, tooltip)
func maj_equipement() -> void:
	for emplacement in emplacements_ui:
		var id: String = Personnage.equipement.get(emplacement, "")
		var infos: Dictionary = emplacements_ui[emplacement]
		var slot: PanelContainer = infos["slot"]
		var icone: TextureRect = infos["icone"]
		if id == "":
			slot.theme_type_variation = ""
			icone.texture = load(ICONES_EMPLACEMENTS[emplacement])
			slot.tooltip_text = TEXTES_EMPLACEMENTS[emplacement]
		else:
			var details := Inventaire.details_objet(id)
			slot.theme_type_variation = _variation_rarete(int(details.get("id_rarete", 1)))
			icone.texture = _icone_objet(details)
			slot.tooltip_text = "%s\n(%s)" % [Inventaire.nom_objet(id), TEXTES_EMPLACEMENTS[emplacement]]

# libellés français des effets stockés dans effects_json
const LIBELLES_EFFETS := {
	"attack": "Attaque", "defense": "Défense", "speed": "Vitesse", "heal": "Soin",
	"vie": "Vie", "health": "Vie", "vitalite": "Vitalité", "sagesse": "Sagesse",
	"force": "Force", "intelligence": "Intelligence", "chance": "Chance",
	"agilite": "Agilité",
}

func _texte_stats(details: Dictionary) -> String:
	var lignes: Array[String] = []
	var effets: Dictionary = details.get("effets", {})
	for cle in effets:
		var libelle: String = LIBELLES_EFFETS.get(cle, str(cle).capitalize())
		lignes.append("%s : %+d" % [libelle, int(effets[cle])])
	if int(details.get("niveau_min", 1)) > 1:
		lignes.append("Niveau requis : %d" % details["niveau_min"])
	return "\n".join(PackedStringArray(lignes))

# cadre de slot coloré selon la rareté (variations du thème parchemin)
func _variation_rarete(id_rarete: int) -> String:
	match id_rarete:
		2:
			return "RareSlot"
		3:
			return "EpicSlot"
		4, 6:
			return "LegendarySlot"
		5:
			return "UncommonSlot"
		_:
			return "CommonSlot"

# icône de l'objet : icone_path de la base si le fichier existe,
# sinon une icône par défaut selon le type de l'objet
const ICONE_DEFAUT := "res://addons/pixel_ui_fantasy/icons/chest.png"
const ICONES_PAR_TYPE := {
	"arme": "res://addons/pixel_ui_fantasy/icons/sword.png",
	"armure": "res://addons/pixel_ui_fantasy/icons/shield.png",
	"accessoire": "res://addons/pixel_ui_fantasy/icons/gem.png",
	"consumable": "res://addons/pixel_ui_fantasy/icons/potion_red.png",
	"ressource": "res://addons/pixel_ui_fantasy/icons/scroll.png",
}

func _icone_objet(details: Dictionary) -> Texture2D:
	var chemin: String = details.get("chemin_icone", "")
	if chemin != "" and ResourceLoader.exists(chemin):
		return load(chemin)
	chemin = ICONES_PAR_TYPE.get(details.get("type", "").to_lower(), ICONE_DEFAUT)
	return load(chemin)

# --- Wiki des objets : liste complete, details seulement si deja rencontres ---

const COULEUR_INCONNU := Color(0.55, 0.5, 0.45)
const ICONE_CADENAS := "res://addons/pixel_ui_fantasy/icons/lock.png"

# Encyclopédie des fruits du démon (item 950 de la base) : craftée par
# l'Archéologue, elle révèle les fruits du démon dans le wiki
const ID_ENCYCLOPEDIE_FRUITS := "950"

# l'encyclopédie des fruits du démon est-elle dans l'inventaire ?
func _encyclopedie_fruits_possedee() -> bool:
	return Inventaire.objets.has(ID_ENCYCLOPEDIE_FRUITS)

# types proposés par le filtre du wiki ; "" = tous les types
var types_wiki: Array = [""]
# objet affiché dans la fiche du wiki (cible du bouton debug "Donner x5")
var id_wiki_courant := ""

# remplit le filtre de types avec les types réellement présents en base ;
# les fruits du démon sont volontairement absents du wiki (objets secrets),
# sauf si l'encyclopédie des fruits du démon est possédée
func _peupler_types_wiki() -> void:
	option_type_wiki.clear()
	types_wiki = [""]
	option_type_wiki.add_item("Tous")
	var exclure_fruits := "" if _encyclopedie_fruits_possedee() else " AND type != 'fruit_demon'"
	for ligne in BaseDonnees.lire(
		"SELECT DISTINCT type FROM items WHERE is_active = 1" + exclure_fruits + " ORDER BY type;"):
		var type_item := str(ligne["type"])
		types_wiki.append(type_item)
		option_type_wiki.add_item(type_item.capitalize())
	option_type_wiki.select(0)

# le filtre de types dépend de l'encyclopédie : il est reconstruit à chaque
# changement d'inventaire, en conservant la sélection si elle reste valide
func _maj_filtre_types_wiki() -> void:
	var type_courant := ""
	if option_type_wiki.selected >= 0 and option_type_wiki.selected < types_wiki.size():
		type_courant = str(types_wiki[option_type_wiki.selected])
	_peupler_types_wiki()
	var index := types_wiki.find(type_courant)
	option_type_wiki.select(index if index >= 0 else 0)
	maj_wiki()

func maj_wiki() -> void:
	for enfant in liste_wiki.get_children():
		enfant.queue_free()
	var type_choisi := str(types_wiki[option_type_wiki.selected]) if option_type_wiki.selected >= 0 else ""
	var condition := "is_active = 1"
	if not _encyclopedie_fruits_possedee():
		condition += " AND type != 'fruit_demon'"
	if type_choisi != "":
		condition += " AND type = '%s'" % type_choisi
	var lignes := BaseDonnees.lire("SELECT id, name, type FROM items WHERE " + condition + " ORDER BY id;")
	var filtre := champ_recherche.text.strip_edges().to_lower()
	var connus := 0
	var affiches := 0
	for ligne in lignes:
		var id := str(ligne["id"])
		var nom_item := str(ligne["name"])
		if filtre != "" and not nom_item.to_lower().contains(filtre):
			continue
		affiches += 1
		var bouton := Button.new()
		bouton.text = nom_item
		bouton.alignment = HORIZONTAL_ALIGNMENT_LEFT
		# police contenue pour la liste : les noms de plus de 50 caractères
		# doivent tenir dans la colonne sans défilement horizontal
		bouton.add_theme_font_size_override("font_size", 20)
		# l'encyclopédie révèle les fruits du démon sans les avoir trouvés
		var est_fruit := str(ligne["type"]) == "fruit_demon"
		if Inventaire.est_connu(id) or (est_fruit and _encyclopedie_fruits_possedee()):
			connus += 1
		else:
			bouton.add_theme_color_override("font_color", COULEUR_INCONNU)
			bouton.add_theme_color_override("font_hover_color", COULEUR_INCONNU.lightened(0.2))
		bouton.pressed.connect(maj_detail_wiki.bind(id))
		liste_wiki.add_child(bouton)
	var prefixe := ""
	if type_choisi != "":
		prefixe = "Type : %s | " % type_choisi.capitalize()
	if filtre == "":
		compteur_wiki.text = prefixe + "Objets découverts : %d / %d" % [connus, lignes.size()]
	elif affiches > 0:
		compteur_wiki.text = prefixe + "Recherche : %d objet(s) | %d découvert(s)" % [affiches, connus]
	else:
		compteur_wiki.text = prefixe + "Aucun objet ne correspond à « %s »" % filtre
	maj_detail_aucun_wiki()

func maj_detail_wiki(id: String) -> void:
	id_wiki_courant = id
	btn_donner_item_wiki.visible = true
	nom_wiki.text = Inventaire.nom_objet(id)
	var details := Inventaire.details_objet(id)
	# l'encyclopédie des fruits du démon révèle leur fiche sans rencontre
	var fruit_revele := str(details.get("type", "")) == "fruit_demon" and _encyclopedie_fruits_possedee()
	if not Inventaire.est_connu(id) and not fruit_revele:
		icone_wiki.texture = load(ICONE_CADENAS)
		type_wiki.text = ""
		description_wiki.text = "Objet non encore rencontré. Ses caractéristiques apparaîtront quand vous le trouverez."
		stats_wiki.text = ""
		prix_wiki.text = ""
		return
	icone_wiki.texture = _icone_objet(details)
	nom_wiki.add_theme_color_override("font_color", details["couleur_rarete"])
	var type_texte: String = details.get("type", "").capitalize()
	if details.get("sous_type", "") != "":
		type_texte += " | %s" % details["sous_type"].capitalize()
	if details.get("rarete", "") != "":
		type_texte += "\n%s" % details["rarete"]
	type_wiki.text = type_texte
	type_wiki.add_theme_color_override("font_color", details["couleur_rarete"])
	description_wiki.text = details.get("description", "")
	var texte_stats := _texte_stats(details)
	# l'encyclopédie dresse aussi la liste des pouvoirs du fruit
	if fruit_revele:
		var pouvoirs := _pouvoirs_fruit(id)
		if not pouvoirs.is_empty():
			var texte_pouvoirs := "Pouvoirs : %s" % " ; ".join(pouvoirs)
			texte_stats = (texte_pouvoirs + "\n" + texte_stats) if texte_stats != "" else texte_pouvoirs
	stats_wiki.text = texte_stats
	stats_wiki.visible = texte_stats != ""
	prix_wiki.text = "Prix : %d Berry" % int(details.get("prix", 0))

# pouvoirs d'un fruit du démon (tables `fruit_skills` + `skills`),
# au format "Nom (coût PA)" ; vide si le fruit n'a aucun pouvoir rattaché
func _pouvoirs_fruit(id_fruit: String) -> Array[String]:
	var pouvoirs: Array[String] = []
	if not BaseDonnees.disponible or not id_fruit.is_valid_int():
		return pouvoirs
	for ligne in BaseDonnees.lire(
		"SELECT s.name, s.base_cooldown FROM fruit_skills fs"
		+ " JOIN skills s ON s.id = fs.skill_id WHERE fs.fruit_item_id = %d ORDER BY fs.skill_id;" % id_fruit.to_int()):
		pouvoirs.append("%s (%d PA)" % [str(ligne["name"]), maxi(int(ligne["base_cooldown"]), 1)])
	return pouvoirs

func maj_detail_aucun_wiki() -> void:
	icone_wiki.texture = null
	nom_wiki.text = "Sélectionnez un objet"
	nom_wiki.remove_theme_color_override("font_color")
	type_wiki.text = ""
	description_wiki.text = ""
	stats_wiki.text = ""
	prix_wiki.text = ""
	id_wiki_courant = ""
	btn_donner_item_wiki.visible = false

# debug : ajoute 5 exemplaires de l'objet affiché dans la fiche du wiki
func _on_donner_item_wiki() -> void:
	if id_wiki_courant != "":
		Inventaire.ajouter_objet(id_wiki_courant, 5)
		var nom := Inventaire.nom_objet(id_wiki_courant)
		description_wiki.text = "Debug : %s x5 ajouté à l'inventaire" % nom

# --- Métiers et artisanat ---

var metier_affiche := ""

# seul le métier du personnage est affiché dans l'onglet
func maj_metiers() -> void:
	if not Personnage.metiers.is_empty():
		metier_affiche = str(Personnage.metiers.keys()[0])
	else:
		metier_affiche = ""
	if metier_affiche != "":
		afficher_metier(metier_affiche)
		return
	nom_metier.text = "Aucun métier"
	desc_metier.text = "Un métier unique est accordé à la création du personnage."
	xp_metier.text = ""
	titre_recettes.visible = false
	for enfant in liste_recettes.get_children():
		enfant.queue_free()

func afficher_metier(id_profession: String) -> void:
	metier_affiche = id_profession
	var infos: Dictionary = Personnage.professions().get(id_profession, {})
	nom_metier.text = str(infos.get("nom", "-"))
	desc_metier.text = str(infos.get("description", ""))
	if not Personnage.a_metier(id_profession):
		xp_metier.text = "Métier non choisi - un seul métier est accordé à la création du personnage."
		titre_recettes.visible = false
		for enfant in liste_recettes.get_children():
			enfant.queue_free()
		return
	titre_recettes.visible = true
	var donnees: Dictionary = Personnage.metiers[id_profession]
	xp_metier.text = "Niveau %d - %d / %d XP" % [
		Personnage.niveau_metier(id_profession),
		int(donnees["xp"]),
		Personnage.xp_prochain_niveau_metier(id_profession),
	]
	_construire_recettes(id_profession)

func _construire_recettes(id_profession: String) -> void:
	for enfant in liste_recettes.get_children():
		enfant.queue_free()
	var recettes := Personnage.recettes(id_profession)
	if recettes.is_empty():
		var vide := Label.new()
		vide.text = "Aucune recette pour ce métier."
		liste_recettes.add_child(vide)
		return
	for r in recettes:
		var encadre := PanelContainer.new()
		var boite := VBoxContainer.new()
		boite.add_theme_constant_override("separation", 4)
		var entete := HBoxContainer.new()
		var nom := Label.new()
		nom.text = str(r["nom"])
		nom.add_theme_font_size_override("font_size", 22)
		nom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nom.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var btn := Button.new()
		btn.text = "Fabriquer"
		btn.disabled = Personnage.verifier_recette(str(r["id"])) != ""
		btn.pressed.connect(_on_fabriquer.bind(str(r["id"])))
		entete.add_child(nom)
		entete.add_child(btn)
		var fragments: Array[String] = []
		var complet := true
		for ing in r["ingredients"]:
			var possede := int(Inventaire.objets.get(ing["id"], 0))
			if possede < int(ing["quantite"]):
				complet = false
			fragments.append("%s %d/%d" % [Inventaire.nom_objet(ing["id"]), possede, int(ing["quantite"])])
		var ligne_ing := Label.new()
		ligne_ing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ligne_ing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if fragments.is_empty():
			ligne_ing.text = "Ingrédients : aucun"
		else:
			ligne_ing.text = "Ingrédients : " + ", ".join(PackedStringArray(fragments))
		if not complet:
			ligne_ing.add_theme_color_override("font_color", Color(0.85, 0.3, 0.3))
		var infos := Label.new()
		infos.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		infos.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		infos.text = "Niveau %d requis - Coût %d Berry - +%d XP - %d s" % [
			int(r["niveau_requis"]), int(r["cout_berry"]), int(r["xp"]), int(r["temps"]),
		]
		boite.add_child(entete)
		boite.add_child(ligne_ing)
		boite.add_child(infos)
		encadre.add_child(boite)
		liste_recettes.add_child(encadre)

func _on_fabriquer(id_recette: String) -> void:
	Personnage.artisaner(id_recette)
	maj_metiers()

# --- Hôtel des ventes ---

# ids d'objets de la liste déroulante de mise en vente
var ids_ventes_hotel: Array[String] = []

func _on_hotel_modifie() -> void:
	if fenetre.visible and section_actuelle == "hotel":
		maj_hotel()

func maj_hotel() -> void:
	argent_hotel.text = "Berry : %d" % Personnage.berry
	info_achats_hotel.text = "Prochain réapprovisionnement des vendeurs dans %d s" % HotelVentes.secondes_avant_remplissage()
	_construire_achats_hotel()
	_construire_ventes_hotel()
	_remplir_forme_hotel()

func _construire_achats_hotel() -> void:
	for enfant in liste_achats_hotel.get_children():
		enfant.queue_free()
	if HotelVentes.offres.is_empty():
		var vide := Label.new()
		vide.text = "Aucune offre pour l'instant."
		liste_achats_hotel.add_child(vide)
		return
	for i in HotelVentes.offres.size():
		var offre: Dictionary = HotelVentes.offres[i]
		var details := Inventaire.details_objet(str(offre["item"]))
		var encadre := PanelContainer.new()
		encadre.theme_type_variation = _variation_rarete(int(details.get("id_rarete", 1)))
		# nom sur sa propre ligne (retour automatique si long) puis
		# prix et bouton dessous : rien ne déborde du panneau
		var colonne := VBoxContainer.new()
		colonne.add_theme_constant_override("separation", 6)
		var ligne_nom := HBoxContainer.new()
		ligne_nom.add_theme_constant_override("separation", 12)
		var icone := TextureRect.new()
		icone.texture = _icone_objet(details)
		icone.custom_minimum_size = Vector2(32, 32)
		icone.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icone.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var nom := Label.new()
		nom.text = Inventaire.nom_objet(str(offre["item"]))
		nom.add_theme_color_override("font_color", details["couleur_rarete"])
		nom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nom.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nom.add_theme_font_size_override("font_size", 22)
		ligne_nom.add_child(icone)
		ligne_nom.add_child(nom)
		var ligne_action := HBoxContainer.new()
		ligne_action.add_theme_constant_override("separation", 12)
		var prix := Label.new()
		prix.text = "x%d - %d Berry" % [int(offre["quantite"]), int(offre["prix"])]
		prix.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		prix.add_theme_font_size_override("font_size", 20)
		var btn := Button.new()
		btn.text = "Acheter"
		btn.disabled = Personnage.berry < int(offre["prix"]) * int(offre["quantite"])
		btn.pressed.connect(_on_acheter_hotel.bind(i))
		ligne_action.add_child(prix)
		ligne_action.add_child(btn)
		colonne.add_child(ligne_nom)
		colonne.add_child(ligne_action)
		encadre.add_child(colonne)
		liste_achats_hotel.add_child(encadre)

func _construire_ventes_hotel() -> void:
	for enfant in liste_ventes_hotel.get_children():
		enfant.queue_free()
	if HotelVentes.ventes.is_empty():
		var vide := Label.new()
		vide.text = "Aucune mise en vente. Vos objets en vente attendent ici leurs acheteurs."
		liste_ventes_hotel.add_child(vide)
		return
	for i in HotelVentes.ventes.size():
		var mise: Dictionary = HotelVentes.ventes[i]
		var details := Inventaire.details_objet(str(mise["item"]))
		var encadre := PanelContainer.new()
		encadre.theme_type_variation = _variation_rarete(int(details.get("id_rarete", 1)))
		# idem que les offres : nom seul sur sa ligne, détails et bouton dessous
		var colonne := VBoxContainer.new()
		colonne.add_theme_constant_override("separation", 6)
		var nom := Label.new()
		nom.text = Inventaire.nom_objet(str(mise["item"]))
		nom.add_theme_color_override("font_color", details["couleur_rarete"])
		nom.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nom.add_theme_font_size_override("font_size", 22)
		var total := int(mise["prix_unite"]) * int(mise["quantite"])
		var ligne_action := HBoxContainer.new()
		ligne_action.add_theme_constant_override("separation", 12)
		var prix := Label.new()
		prix.text = "x%d à %d Berry/u - %d Berry" % [int(mise["quantite"]), int(mise["prix_unite"]), total]
		prix.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		prix.add_theme_font_size_override("font_size", 20)
		var btn := Button.new()
		btn.text = "Retirer"
		btn.pressed.connect(_on_retirer_hotel.bind(i))
		ligne_action.add_child(prix)
		ligne_action.add_child(btn)
		colonne.add_child(nom)
		colonne.add_child(ligne_action)
		encadre.add_child(colonne)
		liste_ventes_hotel.add_child(encadre)

# reconstruit la liste déroulante des objets vendables de l'inventaire
func _remplir_forme_hotel() -> void:
	champ_objet_hotel.clear()
	ids_ventes_hotel.clear()
	for id in Inventaire.objets:
		ids_ventes_hotel.append(str(id))
		champ_objet_hotel.add_item("%s (x%d)" % [Inventaire.nom_objet(str(id)), int(Inventaire.objets[id])])
	btn_mettre_hotel.disabled = ids_ventes_hotel.is_empty()
	if ids_ventes_hotel.is_empty():
		champ_objet_hotel.add_item("Inventaire vide")
		champ_objet_hotel.select(0)
		nb_quantite_hotel.max_value = 1
		nb_quantite_hotel.value = 1
		nb_prix_hotel.value = 1
		return
	champ_objet_hotel.select(0)
	_maj_forme_hotel(0)

# adapte les bornes du formulaire à l'objet sélectionné
func _maj_forme_hotel(_index: int) -> void:
	if ids_ventes_hotel.is_empty():
		return
	var id := ids_ventes_hotel[maxi(champ_objet_hotel.selected, 0)]
	nb_quantite_hotel.max_value = maxi(int(Inventaire.objets.get(id, 1)), 1)
	nb_quantite_hotel.value = mini(int(nb_quantite_hotel.value), int(nb_quantite_hotel.max_value))
	nb_prix_hotel.value = int(Inventaire.details_objet(id).get("prix", 1))

func _on_acheter_hotel(index: int) -> void:
	HotelVentes.acheter(index)
	maj_hotel()

func _on_retirer_hotel(index: int) -> void:
	HotelVentes.retirer(index)
	maj_hotel()

func _on_mettre_en_vente() -> void:
	if ids_ventes_hotel.is_empty():
		return
	var id := ids_ventes_hotel[maxi(champ_objet_hotel.selected, 0)]
	var erreur := HotelVentes.mettre_en_vente(
		id, int(nb_quantite_hotel.value), int(nb_prix_hotel.value))
	if erreur != "":
		info_mise_hotel.text = erreur
		info_mise_hotel.add_theme_color_override("font_color", Color(0.85, 0.3, 0.3))
	else:
		info_mise_hotel.text = "Mise en vente créée."
		info_mise_hotel.add_theme_color_override("font_color", Color(0.4, 0.7, 0.35))
		_remplir_forme_hotel()
		_construire_ventes_hotel()

# --- Équipages (guildes de joueurs), alliances et flotte ---

func _on_equipage_modifie() -> void:
	if fenetre.visible and section_actuelle == "equipage":
		maj_equipage()

func maj_equipage() -> void:
	var equipe := not Equipages.mon_equipage.is_empty()
	var capitaine := Equipages.suis_capitaine()
	var gerant := Equipages.puis_je_gerer()
	forme_creation_equipage.visible = not equipe
	btn_dissoudre.visible = capitaine
	btn_quitter_equipage.visible = equipe and not capitaine
	titre_membres.visible = equipe
	forme_ajout_membre.visible = gerant and Equipages.places_libres() > 0
	forme_description.visible = gerant
	forme_caisse.visible = equipe
	btn_retirer_caisse.visible = gerant
	titre_journal.visible = equipe
	if equipe:
		titre_membres.text = "Membres (%d / %d)" % [
			Equipages.nb_membres(), Equipages.MEMBRES_MAX]
		info_equipage.text = "« %s » - Niveau %d - Capitaine : %s" % [
			Equipages.mon_equipage["nom"], int(Equipages.mon_equipage["niveau"]),
			Equipages.mon_equipage["capitaine"]]
		var description := str(Equipages.mon_equipage.get("description", ""))
		if description != "":
			info_equipage.text += "\n" + description
		if not capitaine:
			info_equipage.text += "\nVotre rang : %s." % Equipages.mon_equipage["mon_rang"]
			if not gerant:
				info_equipage.text += " Seul le capitaine ou le vice-capitaine gère l'équipage."
		if gerant and champ_description.text.is_empty():
			champ_description.text = description
		info_caisse.text = "Caisse : %d Berry" % int(Equipages.mon_equipage["caisse"])
	else:
		info_equipage.text = "Fondez votre équipage : jusqu'à %d joueurs, capitaine compris." % Equipages.MEMBRES_MAX
		champ_description.text = ""
	_construire_membres()
	_construire_alliances()
	_construire_journal()

func _construire_membres() -> void:
	for enfant in liste_membres.get_children():
		enfant.queue_free()
	if Equipages.mon_equipage.is_empty():
		return
	var capitaine := Equipages.suis_capitaine()
	var gerant := Equipages.puis_je_gerer()
	var membres := Equipages.liste_membres()
	var encadre_capitaine := PanelContainer.new()
	var boite_capitaine := HBoxContainer.new()
	boite_capitaine.add_theme_constant_override("separation", 12)
	var nom_capitaine := Label.new()
	nom_capitaine.text = "%s - Capitaine" % Equipages.mon_equipage["capitaine"]
	nom_capitaine.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nom_capitaine.add_theme_font_size_override("font_size", 22)
	boite_capitaine.add_child(nom_capitaine)
	encadre_capitaine.add_child(boite_capitaine)
	liste_membres.add_child(encadre_capitaine)
	if membres.is_empty():
		var vide := Label.new()
		vide.text = "Aucun autre membre pour l'instant."
		liste_membres.add_child(vide)
		return
	for ligne in membres:
		var nom_membre := str(ligne["nom_joueur"])
		var rang := str(ligne["rang"])
		var encadre := PanelContainer.new()
		var boite := HBoxContainer.new()
		boite.add_theme_constant_override("separation", 12)
		var nom := Label.new()
		nom.text = nom_membre if rang == Equipages.RANG_MATELOT else "%s - %s" % [nom_membre, rang.capitalize()]
		nom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nom.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nom.add_theme_font_size_override("font_size", 22)
		boite.add_child(nom)
		if capitaine and rang == Equipages.RANG_MATELOT:
			var btn_vice := Button.new()
			btn_vice.text = "Nommer vice"
			btn_vice.tooltip_text = "Délègue la gestion de l'équipage à ce membre."
			btn_vice.pressed.connect(_on_nommer_vice.bind(nom_membre))
			boite.add_child(btn_vice)
		if gerant:
			var btn := Button.new()
			btn.text = "Virer"
			btn.pressed.connect(_on_virer_membre.bind(nom_membre))
			boite.add_child(btn)
		encadre.add_child(boite)
		liste_membres.add_child(encadre)

func _construire_alliances() -> void:
	for enfant in liste_alliances.get_children():
		enfant.queue_free()
	var flotte := Equipages.ma_flotte()
	btn_rompre_flotte.visible = not flotte.is_empty() and Equipages.puis_je_gerer()
	if Equipages.mon_equipage.is_empty():
		info_flotte.text = "Sans équipage, pas d'alliance possible."
		btn_rompre_flotte.visible = false
		var vide := Label.new()
		vide.text = "Fondez un équipage pour rencontrer d'autres équipages."
		liste_alliances.add_child(vide)
		return
	if flotte.is_empty():
		info_flotte.text = "Aucune flotte : concluez une alliance avec un autre équipage pour fonder la vôtre."
	else:
		info_flotte.text = "« %s » - %d équipage(s)" % [
			flotte["nom"], Equipages.membres_de_ma_flotte().size()]
	var gerant := Equipages.puis_je_gerer()
	var autres := Equipages.autres_equipages()
	if autres.is_empty():
		var vide := Label.new()
		vide.text = "Aucun autre équipage sur les mers pour l'instant."
		liste_alliances.add_child(vide)
		return
	for ligne in autres:
		var id_equipage := int(ligne["id"])
		var allie := Equipages.est_allie(id_equipage)
		var encadre := PanelContainer.new()
		var boite := HBoxContainer.new()
		boite.add_theme_constant_override("separation", 12)
		var nom := Label.new()
		nom.text = "« %s » - Capitaine %s" % [str(ligne["nom"]), str(ligne["capitaine"])]
		nom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nom.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nom.add_theme_font_size_override("font_size", 22)
		var infos := Label.new()
		infos.text = "Niveau %d - %d membres" % [
			int(ligne["niveau"]), Equipages.nb_membres_de(id_equipage)]
		boite.add_child(nom)
		boite.add_child(infos)
		if allie:
			var etiquette := Label.new()
			etiquette.text = "Allié"
			etiquette.add_theme_color_override("font_color", Color(0.4, 0.7, 0.35))
			boite.add_child(etiquette)
		else:
			var btn := Button.new()
			btn.text = "Proposer alliance"
			btn.tooltip_text = "En MMO, la proposition sera à accepter par le capitaine adverse."
			btn.disabled = not gerant
			btn.pressed.connect(_on_proposer_alliance.bind(id_equipage))
			boite.add_child(btn)
		encadre.add_child(boite)
		liste_alliances.add_child(encadre)

func _construire_journal() -> void:
	for enfant in liste_journal.get_children():
		enfant.queue_free()
	if Equipages.mon_equipage.is_empty():
		return
	var entrees := Equipages.liste_journal()
	if entrees.is_empty():
		var vide := Label.new()
		vide.text = "Le journal de bord est vide."
		liste_journal.add_child(vide)
		return
	for entree in entrees:
		var ligne := Label.new()
		ligne.text = "[%s] %s" % [str(entree["heure"]), str(entree["message"])]
		ligne.add_theme_font_size_override("font_size", 16)
		ligne.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		liste_journal.add_child(ligne)

func _on_fonder_equipage() -> void:
	var erreur := Equipages.creer(champ_nom_equipage.text)
	if erreur != "":
		info_equipage.text = erreur
		return
	champ_nom_equipage.text = ""
	maj_equipage()

func _on_dissoudre_equipage() -> void:
	Equipages.dissoudre()
	maj_equipage()

func _on_quitter_equipage() -> void:
	Equipages.quitter()
	maj_equipage()

func _on_ajouter_membre() -> void:
	var erreur := Equipages.ajouter_membre(champ_nom_membre.text)
	if erreur != "":
		info_equipage.text = erreur
		return
	champ_nom_membre.text = ""
	maj_equipage()

func _on_virer_membre(nom_membre: String) -> void:
	var erreur := Equipages.virer(nom_membre)
	if erreur != "":
		info_equipage.text = erreur
	maj_equipage()

func _on_nommer_vice(nom_membre: String) -> void:
	var erreur := Equipages.nommer_vice(nom_membre)
	if erreur != "":
		info_equipage.text = erreur
	maj_equipage()

func _on_modifier_description() -> void:
	var erreur := Equipages.changer_description(champ_description.text)
	if erreur != "":
		info_equipage.text = erreur
	maj_equipage()

func _on_deposer_caisse() -> void:
	var erreur := Equipages.deposer_berry(int(nb_caisse.value))
	if erreur != "":
		info_caisse.text = erreur
	maj_equipage()

func _on_retirer_caisse() -> void:
	var erreur := Equipages.retirer_berry(int(nb_caisse.value))
	if erreur != "":
		info_caisse.text = erreur
	maj_equipage()

func _on_proposer_alliance(id_equipage: int) -> void:
	var erreur := Equipages.proposer_alliance(id_equipage)
	if erreur != "":
		info_flotte.text = erreur
	maj_equipage()

func _on_rompre_flotte() -> void:
	var erreur := Equipages.rompre_alliance()
	if erreur != "":
		info_flotte.text = erreur
	maj_equipage()
