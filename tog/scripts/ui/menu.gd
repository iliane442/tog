extends CanvasLayer

signal menu_ouvert
signal menu_ferme

var section_actuelle: String = ""
# répartition en cours, pas encore validée (cle -> points en attente)
var points_en_attente: Dictionary = {}
var _tween_fenetre: Tween
var _catalogue_wiki: Array = []
var _wiki_a_actualiser := true
var _prochaine_maj_hotel_ms := 0
const FICHE_MENU := preload("res://themes/fiche_menu.tres")
const TAILLE_MENU := Vector2(1380, 840)
const TAILLE_CASE_EQUIP := Vector2(58, 58)
const ESPACEMENT_CASE_EQUIP := 8.0
const EMPLACEMENTS_GAUCHE: Array[String] = ["tête", "corps", "cape", "main", "ceinture", "pantalon"]
const EMPLACEMENTS_DROIT: Array[String] = ["visage", "cou", "arme", "arme2", "anneau1", "anneau2", "pieds"]
const VISUELS_RACES := {
	"human": "humain_pirate",
	"mink": "mink_pirate",
	"fishman": "fishman_pirate",
}
const FONDS := {
	"personnage": preload("res://assets/ui/planches/carnet.jpg"),
	"inventaire": preload("res://assets/ui/planches/sac.jpg"),
	"sorts": preload("res://assets/ui/planches/sorts.jpg"),
}
const FOND_AUTRES := preload("res://assets/ui/fond_menu_pirate.png")
# Coordonnées du bouton illustré dans chaque planche de 1380 × 840.
const FERMETURES := {
	"personnage": Rect2(1212, 12, 98, 108),
	"inventaire": Rect2(1242, 76, 81, 63),
	"sorts": Rect2(1282, 39, 55, 53),
}
const ILLUSTRATIONS_SORTS := {
	"Haki du Roi": preload("res://assets/ui/planches/fiche_haki.png"),
	"ShakuShaku": preload("res://assets/ui/planches/fiche_lames.png"),
	"Kuro Kabuto": preload("res://assets/ui/planches/fiche_kabuto.png"),
}
var _grille_sale := true
var _sorts_sales := true
var _boutons_sorts: Dictionary = {}
var _barre_apercu: PanelContainer
var _mise_a_jour_sac_prevue := false
var _mode_inventaire_compact := false
var _race_portrait_chargee := ""
var _tweens_cases: Dictionary = {}
var _cache_icones_objets: Dictionary = {}
@onready var option_type_inventaire: OptionButton = $Fenetre/Corps/ContenuInventaire/ZoneInventaire/PanneauSac/ColonneSac/FiltresSac/Categorie
@onready var case_portables: CheckBox = $Fenetre/Corps/ContenuInventaire/ZoneInventaire/PanneauSac/ColonneSac/CasePortables
@onready var champ_recherche_sac: LineEdit = $Fenetre/Corps/ContenuInventaire/ZoneInventaire/PanneauSac/ColonneSac/FiltresSac/ChampRechercheSac
@onready var btn_manger_fruit: Button = $Fenetre/Corps/ContenuInventaire/ZoneInventaire/DetailItem/MargesDetail/ColonneDetail/ActionsItem/BtnMangerFruit
@onready var btn_barre_objets: Button = $Fenetre/Corps/ContenuInventaire/ZoneInventaire/DetailItem/MargesDetail/ColonneDetail/ActionsItem/BtnBarreObjets
@onready var retour_accueil: Button = $Fenetre/RetourAccueil
var filtre_portables := false
var _fruit_wiki_visible := false
var _niveau_sorts := -1
@onready var info_ventes_joueurs: Label = $Fenetre/Corps/ContenuHotel/ZoneHotel/PanneauAchats/MargesAchats/ColonneAchats/InfoVentesJoueurs
@onready var liste_ventes_joueurs: VBoxContainer = $Fenetre/Corps/ContenuHotel/ZoneHotel/PanneauAchats/MargesAchats/ColonneAchats/DefilementVentesJoueurs/ListeVentesJoueurs
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

const AIDE_STATS := {
	"vitalite": "Vitalité : +5 points de vie par point.",
	"sagesse": "Sagesse : +2% d'expérience gagnée par point.",
	"force": "Force : +1 dégât par point sur les sorts d'attaque au corps à corps (portée 1).",
	"intelligence": "Intelligence : +1 dégât par point sur les sorts d'attaque à distance (portée 2 et plus), +1 point de soin par point sur les sorts de soin.",
	"chance": "Précision : +1% de chances de toucher par point.",
	"agilite": "Vitesse : +1% d'esquive et +1% d'initiative par point, jusqu'à +50% de chances de gagner un PM supplémentaire par tour.",
	"defense": "Défense : chaque point absorbe une part croissante des dégâts reçus (dégâts x 100 / (100 + défense)) — 100 points réduisent tout coup de moitié.",
}

@onready var monnaie: Label = $Fenetre/Corps/ContenuInventaire/ZoneInventaire/PanneauSac/ColonneSac/FiltresSac/Monnaie
@onready var nombre_objets: Label = $Fenetre/Corps/ContenuInventaire/ZoneInventaire/PanneauSac/ColonneSac/EnteteSac/NombreObjets
@onready var btn_utiliser: Button = $Fenetre/Corps/ContenuInventaire/ZoneInventaire/DetailItem/MargesDetail/ColonneDetail/ActionsItem/BtnUtiliser
const SCENE_CASE_INVENTAIRE := preload("res://scenes/case_inventaire.tscn")
const SCENE_CASE_EQUIPEMENT := preload("res://scenes/case_equipement.tscn")

@onready var fenetre: Panel = $Fenetre
@onready var titre: Label = $Fenetre/Entete/Titre
@onready var grille: GridContainer = $Fenetre/Corps/ContenuInventaire/ZoneInventaire/PanneauSac/ColonneSac/DefilementInventaire/Grille
@onready var defilement_inventaire: ScrollContainer = $Fenetre/Corps/ContenuInventaire/ZoneInventaire/PanneauSac/ColonneSac/DefilementInventaire
@onready var label_vide: Label = $Fenetre/Corps/ContenuInventaire/ZoneInventaire/PanneauSac/ColonneSac/Vide
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
@onready var outils_dev: HFlowContainer = $Fenetre/Corps/ContenuPersonnage/DefilementPersonnage/ColonnePersonnage/OutilsDev
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
	"defense": {"valeur": $Fenetre/Corps/ContenuPersonnage/DefilementPersonnage/ColonnePersonnage/StatsGrid/StatDefense/Ligne/Valeur, "ajouter": $Fenetre/Corps/ContenuPersonnage/DefilementPersonnage/ColonnePersonnage/StatsGrid/StatDefense/Ligne/Ajouter},
}
@onready var icone_detail: TextureRect = $Fenetre/Corps/ContenuInventaire/ZoneInventaire/DetailItem/MargesDetail/ColonneDetail/EnteteDetail/IconeItem
@onready var nom_detail: Label = $Fenetre/Corps/ContenuInventaire/ZoneInventaire/DetailItem/MargesDetail/ColonneDetail/EnteteDetail/IdentiteItem/NomItem
@onready var type_detail: Label = $Fenetre/Corps/ContenuInventaire/ZoneInventaire/DetailItem/MargesDetail/ColonneDetail/EnteteDetail/IdentiteItem/TypeRareteItem
@onready var description_detail: Label = $Fenetre/Corps/ContenuInventaire/ZoneInventaire/DetailItem/MargesDetail/ColonneDetail/DefilementDetails/InfosItem/DescriptionItem
@onready var stats_detail: Label = $Fenetre/Corps/ContenuInventaire/ZoneInventaire/DetailItem/MargesDetail/ColonneDetail/DefilementDetails/InfosItem/StatsItem
@onready var prix_detail: Label = $Fenetre/Corps/ContenuInventaire/ZoneInventaire/DetailItem/MargesDetail/ColonneDetail/DefilementDetails/InfosItem/PrixItem
@onready var compteur_wiki: Label = $Fenetre/Corps/ContenuWiki/CompteurWiki
@onready var champ_recherche: LineEdit = $Fenetre/Corps/ContenuWiki/ChampRechercheWiki
@onready var option_type_wiki: OptionButton = $Fenetre/Corps/ContenuWiki/LigneFiltreWiki/OptionTypeWiki
@onready var btn_donner_item_wiki: Button = $Fenetre/Corps/ContenuWiki/ZoneWiki/DetailWiki/MargesWiki/ColonneWiki/BtnDonnerItemWiki
@onready var liste_wiki: ItemList = $Fenetre/Corps/ContenuWiki/ZoneWiki/ListeWiki
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
@onready var btn_equiper: Button = $Fenetre/Corps/ContenuInventaire/ZoneInventaire/DetailItem/MargesDetail/ColonneDetail/ActionsItem/BtnEquip
@onready var btn_auto_equipement: Button = $Fenetre/Corps/ContenuInventaire/ZoneInventaire/PanneauSilhouette/ColonnePersonnage/BtnAutoEquipement
@onready var btn_ouvrir_coffre: Button = $Fenetre/Corps/ContenuInventaire/ZoneInventaire/DetailItem/MargesDetail/ColonneDetail/ActionsItem/BtnOuvrirCoffre
@onready var btn_ouvrir_tous: Button = $Fenetre/Corps/ContenuInventaire/ZoneInventaire/DetailItem/MargesDetail/ColonneDetail/ActionsItem/BtnOuvrirTous
@onready var panneau_personnage_inventaire: PanelContainer = $Fenetre/Corps/ContenuInventaire/ZoneInventaire/PanneauSilhouette
@onready var panneau_sac: PanelContainer = $Fenetre/Corps/ContenuInventaire/ZoneInventaire/PanneauSac
@onready var panneau_detail: PanelContainer = $Fenetre/Corps/ContenuInventaire/ZoneInventaire/DetailItem
@onready var zone_inventaire: HBoxContainer = $Fenetre/Corps/ContenuInventaire/ZoneInventaire
@onready var zone_inventaire_compacte: ScrollContainer = $Fenetre/Corps/ContenuInventaire/ZoneInventaireCompacte
@onready var colonne_compacte: VBoxContainer = $Fenetre/Corps/ContenuInventaire/ZoneInventaireCompacte/ColonneCompacte
@onready var onglets: HBoxContainer = $Fenetre/Navigation
@onready var silhouette: Control = $Fenetre/Corps/ContenuInventaire/ZoneInventaire/PanneauSilhouette/ColonnePersonnage/Silhouette
@onready var portrait_equipement: TextureRect = $Fenetre/Corps/ContenuInventaire/ZoneInventaire/PanneauSilhouette/ColonnePersonnage/Silhouette/PortraitEquipement
@onready var nom_niveau_inventaire: Label = $Fenetre/Corps/ContenuInventaire/ZoneInventaire/PanneauSilhouette/ColonnePersonnage/ResumePersonnage/NomNiveau
@onready var resume_stats_inventaire: Label = $Fenetre/Corps/ContenuInventaire/ZoneInventaire/PanneauSilhouette/ColonnePersonnage/ResumePersonnage/ResumeStats
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
	"arme2": "Arme 2",
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
	"visage": Vector2(298, 70),
	"cou": Vector2(298, 146),
	"corps": Vector2(14, 146),
	"cape": Vector2(14, 222),
	"ceinture": Vector2(16, 402),
	"pantalon": Vector2(108, 402),
	"pieds": Vector2(200, 402),
	"main": Vector2(14, 298),
	"arme": Vector2(298, 222),
	"arme2": Vector2(200, 298),
	"anneau1": Vector2(298, 298),
	"anneau2": Vector2(292, 402),
}
const ICONES_EMPLACEMENTS := {
	"arme": preload("res://addons/pixel_ui_fantasy/icons/sword.png"),
	"arme2": preload("res://addons/pixel_ui_fantasy/icons/sword.png"),
	"corps": preload("res://addons/pixel_ui_fantasy/icons/shield.png"),
	"tête": preload("res://addons/pixel_ui_fantasy/icons/helmet.png"),
	"visage": preload("res://addons/pixel_ui_fantasy/icons/scroll.png"),
	"cou": preload("res://addons/pixel_ui_fantasy/icons/gem.png"),
	"main": preload("res://addons/pixel_ui_fantasy/icons/key.png"),
	"cape": preload("res://addons/pixel_ui_fantasy/icons/quest.png"),
	"ceinture": preload("res://addons/pixel_ui_fantasy/icons/chest.png"),
	"pantalon": preload("res://addons/pixel_ui_fantasy/icons/cross.png"),
	"pieds": preload("res://addons/pixel_ui_fantasy/icons/arrow_right.png"),
	"anneau1": preload("res://addons/pixel_ui_fantasy/icons/coin.png"),
	"anneau2": preload("res://addons/pixel_ui_fantasy/icons/coin.png"),
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
	set_process(false)
	_ajuster_fenetre()
	get_viewport().size_changed.connect(_ajuster_fenetre)
	$Fenetre/FermerPlanche.pressed.connect(fermer)
	option_type_inventaire.item_selected.connect(_on_type_inventaire_selectionne)
	case_portables.toggled.connect(_on_portables_toggle)
	champ_recherche_sac.text_changed.connect(_on_recherche_sac)
	btn_utiliser.pressed.connect(_on_bouton_utiliser)
	btn_manger_fruit.pressed.connect(_on_bouton_manger_fruit)
	btn_barre_objets.pressed.connect(_on_bouton_barre_objets)
	retour_accueil.pressed.connect(_confirmer_retour_accueil)
	_creer_emplacements()
	silhouette.resized.connect(_positionner_emplacements)
	call_deferred("_positionner_emplacements")
	_connecter_onglets()
	btn_equiper.pressed.connect(_on_bouton_equiper)
	btn_auto_equipement.pressed.connect(_on_auto_equipement)
	btn_ouvrir_coffre.pressed.connect(_on_bouton_ouvrir_coffre)
	btn_ouvrir_tous.pressed.connect(_on_bouton_ouvrir_tous)
	$Fenetre/Entete/Fermer.pressed.connect(fermer)
	btn_valider.pressed.connect(_on_valider_points)
	btn_reinitialiser.pressed.connect(_on_reinitialiser_points)
	outils_dev.visible = OS.is_debug_build()
	outils_dev.get_node("BtnEffacerPerso").pressed.connect(_on_effacer_perso)
	outils_dev.get_node("BtnBerry").pressed.connect(_on_debug_berry)
	outils_dev.get_node("BtnDebugNiveau").pressed.connect(_on_debug_niveau_200)
	for cle: String in lignes_stats:
		var ligne_stat: Dictionary = lignes_stats[cle]
		var bouton_ajouter: Button = ligne_stat["ajouter"] as Button
		bouton_ajouter.pressed.connect(_on_augmenter_stat.bind(cle))
		bouton_ajouter.gui_input.connect(_on_stat_bouton_input.bind(cle))
		bouton_ajouter.tooltip_text = str(AIDE_STATS.get(cle, "")) + "\nClic droit : choisir le nombre de points."
	champ_recherche.text_changed.connect(func(_t): maj_wiki())
	liste_wiki.item_selected.connect(_selectionner_objet_wiki)
	option_type_wiki.item_selected.connect(func(_i): maj_wiki())
	btn_donner_item_wiki.pressed.connect(_on_donner_item_wiki)
	Inventaire.inventaire_modifie.connect(_sur_inventaire_modifie)
	QuestManager.quete_acceptee.connect(maj_quetes)
	QuestManager.quete_progressee.connect(maj_quetes)
	QuestManager.quete_abandonnee.connect(maj_quetes)
	QuestManager.quete_terminee.connect(maj_quetes)
	Personnage.caracteristiques_modifiees.connect(_sur_personnage_modifie)
	Personnage.barre_sorts_modifiee.connect(_sur_barre_modifiee)
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
	var facteur := minf(1.0, minf(taille_ecran.x / TAILLE_MENU.x, taille_ecran.y / TAILLE_MENU.y) * 0.96)
	fenetre.offset_left = -TAILLE_MENU.x * 0.5
	fenetre.offset_right = TAILLE_MENU.x * 0.5
	fenetre.offset_top = -TAILLE_MENU.y * 0.5
	fenetre.offset_bottom = TAILLE_MENU.y * 0.5
	fenetre.pivot_offset = TAILLE_MENU * 0.5
	fenetre.scale = Vector2.ONE * facteur
	_adapter_inventaire(facteur < 0.82)

func _adapter_inventaire(compact: bool) -> void:
	if compact == _mode_inventaire_compact:
		return
	_mode_inventaire_compact = compact
	var parent_cible: Node = colonne_compacte if compact else zone_inventaire
	var panneaux: Array[Control] = [panneau_personnage_inventaire, panneau_sac, panneau_detail]
	for index in panneaux.size():
		var panneau: Control = panneaux[index]
		if panneau.get_parent() != parent_cible:
			panneau.reparent(parent_cible)
		parent_cible.move_child(panneau, index)
	if compact:
		panneau_personnage_inventaire.custom_minimum_size = Vector2(0, 500)
		panneau_sac.custom_minimum_size = Vector2(0, 360)
		panneau_detail.custom_minimum_size = Vector2(0, 260)
	else:
		panneau_personnage_inventaire.custom_minimum_size = Vector2(320, 0)
		panneau_sac.custom_minimum_size = Vector2(500, 0)
		panneau_detail.custom_minimum_size = Vector2(380, 0)
	zone_inventaire.visible = not compact
	zone_inventaire_compacte.visible = compact
	call_deferred("_positionner_emplacements")

func _connecter_onglets() -> void:
	for enfant in onglets.get_children():
		var bouton := enfant as Button
		bouton.pressed.connect(ouvrir.bind(bouton.name.to_lower()))

func _process(_delta: float) -> void:
	# referme la fenêtre si un dialogue met le jeu en pause
	if get_tree().paused and fenetre.visible:
		fermer()
	elif section_actuelle == "hotel" and Time.get_ticks_msec() >= _prochaine_maj_hotel_ms:
		_maj_delai_hotel()

func _input(event: InputEvent) -> void:
	if not fenetre.visible or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE or (event.keycode == KEY_M and not get_viewport().gui_get_focus_owner() is LineEdit):
		fermer()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if fenetre.visible:
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ESCAPE, KEY_M] and not get_tree().paused:
		ouvrir()
		get_viewport().set_input_as_handled()

func _confirmer_retour_accueil() -> void:
	var combat := get_tree().current_scene.get_node_or_null("CombatManager")
	if combat != null and combat.en_combat:
		return
	var dialogue := ConfirmationDialog.new()
	dialogue.title = "Retour à l’accueil"
	dialogue.dialog_text = "Ta prochaine partie commencera à Fushia."
	dialogue.ok_button_text = "Revenir à l’accueil"
	dialogue.cancel_button_text = "Continuer la partie"
	dialogue.confirmed.connect(func(): Reseau.revenir_accueil())
	dialogue.visibility_changed.connect(func():
		if not dialogue.visible:
			dialogue.queue_free())
	add_child(dialogue)
	dialogue.popup_centered()

func ouvrir(section: String = "") -> void:
	if get_tree().paused:
		return
	if section != "" and not contenus.has(section):
		return
	if fenetre.visible and section == section_actuelle:
		return
	if section != "":
		section_actuelle = section
	elif section_actuelle == "":
		section_actuelle = "personnage"
	var etait_fermee := not fenetre.visible
	var combat := get_tree().current_scene.get_node_or_null("CombatManager")
	retour_accueil.disabled = combat != null and combat.en_combat
	fenetre.visible = true
	if etait_fermee:
		set_process(true)
		$FondModal.show()
		menu_ouvert.emit()
		fenetre.modulate.a = 0.65
		_tween_fenetre = create_tween()
		_tween_fenetre.tween_property(fenetre, "modulate:a", 1.0, 0.10)
	maj_section()
	(onglets.get_node(section_actuelle.capitalize()) as Button).grab_focus()

func fermer() -> void:
	# les points non validés sont abandonnés à la fermeture
	points_en_attente = {}
	if not fenetre.visible:
		return
	if _tween_fenetre != null and _tween_fenetre.is_running():
		_tween_fenetre.kill()
	get_viewport().gui_release_focus()
	fenetre.hide()
	$FondModal.hide()
	set_process(false)
	menu_ferme.emit()

func maj_section() -> void:
	var illustre := FONDS.has(section_actuelle)
	$Fenetre/FondIllustration.texture = FONDS.get(section_actuelle, FOND_AUTRES)
	$Fenetre/Entete.visible = not illustre
	$Fenetre/EmblemePirate.visible = not illustre
	var fermer_planche: Button = $Fenetre/FermerPlanche
	fermer_planche.visible = illustre
	if illustre:
		var rect: Rect2 = FERMETURES[section_actuelle]
		fermer_planche.position = rect.position
		fermer_planche.size = rect.size
	var est_inventaire := section_actuelle == "inventaire"
	zone_inventaire.visible = est_inventaire and not _mode_inventaire_compact
	zone_inventaire_compacte.visible = est_inventaire and _mode_inventaire_compact
	(onglets.get_node(section_actuelle.capitalize()) as Button).button_pressed = true
	for section in contenus:
		contenus[section].visible = section == section_actuelle
	titre.text = noms_sections[section_actuelle]
	match section_actuelle:
		"personnage":
			maj_personnage()
		"sorts":
			if _sorts_sales or _niveau_sorts != Personnage.niveau:
				maj_sorts()
		"quetes":
			maj_quetes()
		"inventaire":
			maj_equipement()
			if _grille_sale:
				maj_grille()
		"wiki":
			if _wiki_a_actualiser:
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
	# la défense en attente se prévisualise comme la vie (points posés,
	# pas encore validés)
	valeur_defense.text = str(int(Personnage.defense) + int(points_en_attente.get("defense", 0)))
	for cle: String in Personnage.caracteristiques:
		var ligne_stat: Dictionary = lignes_stats[cle]
		var valeur_stat: Label = ligne_stat["valeur"] as Label
		var bouton_ajouter: Button = ligne_stat["ajouter"] as Button
		valeur_stat.text = str(int(Personnage.caracteristiques[cle]) + int(points_en_attente.get(cle, 0)))
		bouton_ajouter.disabled = restants <= 0

func _sur_personnage_modifie() -> void:
	if not fenetre.visible:
		return
	if section_actuelle == "personnage":
		maj_personnage()
	elif section_actuelle == "inventaire":
		_maj_resume_personnage()
		_maj_monnaie_et_compteur()
		if detail_id_courant != "":
			_maj_bouton_equiper(Inventaire.details_objet(detail_id_courant), detail_id_courant)

func _maj_resume_personnage() -> void:
	_maj_portrait_equipement()
	nom_niveau_inventaire.text = "%s · Niv. %d" % [Personnage.nom, Personnage.niveau]
	resume_stats_inventaire.text = "PV %d/%d · ATQ %d · DEF %d\n%s Berry" % [
		Personnage.vie, Personnage.vie_max, Personnage.attaque, Personnage.defense,
		_formater_nombre(Personnage.berry),
	]

func _maj_portrait_equipement() -> void:
	var identifiant_race := str(Personnage.races.get(Personnage.race_id, {}).get("id_technique", "human"))
	if identifiant_race == _race_portrait_chargee:
		return
	var dossier: String = str(VISUELS_RACES.get(identifiant_race, VISUELS_RACES["human"]))
	var chemin := "res://assets/sprites/%s/%s_idle.png" % [dossier, dossier]
	if not ResourceLoader.exists(chemin):
		dossier = str(VISUELS_RACES["human"])
		chemin = "res://assets/sprites/%s/%s_idle.png" % [dossier, dossier]
	var planche := load(chemin) as Texture2D
	if planche == null:
		return
	var taille_case := planche.get_size() / Vector2(4.0, 4.0)
	var portrait := AtlasTexture.new()
	portrait.atlas = planche
	portrait.region = Rect2(Vector2.ZERO, taille_case)
	portrait_equipement.texture = portrait
	_race_portrait_chargee = identifiant_race

func _maj_monnaie_et_compteur() -> void:
	monnaie.text = "%s Berry" % _formater_nombre(Personnage.berry)
	var total := 0
	for quantite: Variant in Inventaire.objets.values():
		total += int(quantite)
	nombre_objets.text = "%d objets" % total

func _formater_nombre(nombre: int) -> String:
	var texte := str(maxi(nombre, 0))
	var resultat := ""
	for index in texte.length():
		if index > 0 and (texte.length() - index) % 3 == 0:
			resultat += " "
		resultat += texte.substr(index, 1)
	return resultat

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

# clic droit sur le « + » d'une stat : ouvrir la saisie d'un nombre
# précis de points (le clic gauche garde son +1)
func _on_stat_bouton_input(evenement: InputEvent, cle: String) -> void:
	if evenement is InputEventMouseButton and evenement.pressed \
			and evenement.button_index == MOUSE_BUTTON_RIGHT:
		var restants := maxi(Personnage.points_statistique - _total_points_en_attente(), 0)
		if restants > 0:
			_ouvrir_saisie_points(cle, restants)

# fenêtre de choix du nombre : le maximum restant est prérempli —
# après une montée de 55 niveaux, 55 points se posent d'un coup
func _ouvrir_saisie_points(cle: String, restants: int) -> void:
	var fenetre := AcceptDialog.new()
	fenetre.title = "Répartir des points"
	var colonne := VBoxContainer.new()
	colonne.add_theme_constant_override("separation", 10)
	var question := Label.new()
	question.text = "Combien de points en %s ?" % str(LIBELLES_EFFETS.get(cle, cle))
	colonne.add_child(question)
	var saisie := SpinBox.new()
	saisie.min_value = 1
	saisie.max_value = restants
	saisie.value = restants
	saisie.custom_minimum_size = Vector2(64, 38)
	colonne.add_child(saisie)
	fenetre.add_child(colonne)
	fenetre.ok_button_text = "Ajouter"
	fenetre.confirmed.connect(func() -> void:
		var montant := clampi(int(roundi(saisie.value)), 1, restants)
		var en_attente := maxi(Personnage.points_statistique - _total_points_en_attente(), 0)
		points_en_attente[cle] = int(points_en_attente.get(cle, 0)) + mini(montant, en_attente)
		maj_personnage())
	add_child(fenetre)
	fenetre.popup_centered()
	saisie.get_line_edit().select_all()
	saisie.get_line_edit().grab_focus()
	fenetre.visibility_changed.connect(func() -> void:
		if not fenetre.visible:
			fenetre.queue_free())

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

# debug : mène le perso au niveau 200 (montées de niveau normales :
# points, vie, sorts débloqués inclus)
func _on_debug_niveau_200() -> void:
	Personnage.monter_niveau(200)
	maj_personnage()

const TAILLE_CASE_SORT := Vector2(56, 56)
const ICONES_SORTS := preload("res://scripts/ui/icones_sorts.gd")

func maj_sorts() -> void:
	_sorts_sales = false
	_niveau_sorts = Personnage.niveau
	_boutons_sorts.clear()
	for enfant in liste_sorts.get_children():
		liste_sorts.remove_child(enfant)
		enfant.queue_free()
	_construire_barre_sorts()
	var ids_classe: Array[String] = Personnage.sorts_de_classe()
	var ids_combat: Array[String] = []
	# sorts disponibles hors classe (pouvoirs du fruit mangé débloqués
	# par son niveau d'utilisation)
	for id_sort in Personnage.sorts_disponibles():
		if not ids_classe.has(id_sort):
			ids_combat.append(id_sort)
	var verrous_classe := Personnage.sorts_de_classe_verrouilles()
	var verrous_fruit := Personnage.sorts_fruit_verrouilles()
	if ids_classe.is_empty() and ids_combat.is_empty() and verrous_classe.is_empty() and verrous_fruit.is_empty():
		var vide := Label.new()
		vide.text = "Aucun sort n'est disponible pour le moment."
		liste_sorts.add_child(vide)
		return
	if not ids_classe.is_empty() or not verrous_classe.is_empty():
		_ajouter_titre_section_sorts("Sorts de classe")
		for id_classe in ids_classe:
			if Personnage.sorts.has(id_classe):
				_construire_carte_sort(id_classe)
		for verrou in verrous_classe:
			_construire_carte_sort(verrou["id"], "Débloqué au niveau %d du personnage." % int(verrou["niveau"]))
	if not ids_combat.is_empty() or not verrous_fruit.is_empty():
		_ajouter_titre_section_sorts("Pouvoirs du fruit du démon")
		for id_combat in ids_combat:
			_construire_carte_sort(id_combat)
		for verrou in verrous_fruit:
			_construire_carte_sort(verrou["id"], "Débloqué au niveau %d du fruit du démon." % int(verrou["niveau"]))

func _ajouter_titre_section_sorts(texte: String) -> void:
	var titre_section := Label.new()
	titre_section.text = texte
	titre_section.theme_type_variation = "Ribbon"
	titre_section.add_theme_font_size_override("font_size", 24)
	liste_sorts.add_child(titre_section)

# barre de sorts : un bouton par emplacement ; les emplacements vides
# sont grisés, cliquer un sort placé le retire de la barre
func _construire_barre_sorts() -> void:
	var encadre := PanelContainer.new()
	encadre.add_theme_stylebox_override("panel", FICHE_MENU)
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
			bouton.icon = ICONES_SORTS.pour_sort(id, str(sort.get("type", "")))
			bouton.expand_icon = true
			bouton.tooltip_text = "%s\nCliquez pour retirer de la barre." % sort.get("nom", "Sort")
			bouton.pressed.connect(_on_retirer_sort_barre.bind(id))
		else:
			bouton.disabled = true
		slots.add_child(bouton)
	colonne.add_child(slots)
	encadre.add_child(colonne)
	liste_sorts.add_child(encadre)
	liste_sorts.move_child(encadre, 0)
	_barre_apercu = encadre

func _sur_barre_modifiee() -> void:
	if not fenetre.visible or section_actuelle != "sorts":
		_sorts_sales = true
		return
	if is_instance_valid(_barre_apercu):
		liste_sorts.remove_child(_barre_apercu)
		_barre_apercu.queue_free()
	var disponibles := Personnage.sorts_disponibles()
	for id: String in disponibles:
		if not _boutons_sorts.has(id):
			maj_sorts()
			return
	_construire_barre_sorts()
	for id: String in _boutons_sorts:
		_maj_action_sort(id, _boutons_sorts[id])

func _maj_action_sort(id: String, bouton: Button) -> void:
	var equipe := Personnage.sort_dans_barre(id)
	bouton.text = "Retirer de la barre" if equipe else "Ajouter à la barre"
	bouton.disabled = not equipe and Personnage.barre_sorts_pleine()
	bouton.accessibility_name = "%s — %s" % [Personnage.sorts[id]["nom"], bouton.text]

# carte d'un sort de la classe : nom, icône, infos, description et
# bouton de placement dans la barre de combat
func _construire_carte_sort(id: String, texte_verrou: String = "") -> void:
	if not Personnage.sorts.has(id):
		return
	var sort: Dictionary = Personnage.sorts[id]
	var encadre := PanelContainer.new()
	encadre.add_theme_stylebox_override("panel", FICHE_MENU)
	var boite := VBoxContainer.new()
	var entete := HBoxContainer.new()
	entete.add_theme_constant_override("separation", 10)
	var icone := TextureRect.new()
	var illustration: Texture2D = ILLUSTRATIONS_SORTS.get(sort.get("nom", ""))
	icone.texture = illustration if illustration != null else ICONES_SORTS.pour_sort(id, str(sort.get("type", "")))
	icone.custom_minimum_size = Vector2(128, 72) if illustration else Vector2(40, 40)
	icone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icone.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icone.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var nom := Label.new()
	nom.text = str(sort.get("nom", "Sort"))
	nom.add_theme_font_size_override("font_size", 26)
	nom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var btn_barre := Button.new()
	if texte_verrou.is_empty():
		_boutons_sorts[id] = btn_barre
		_maj_action_sort(id, btn_barre)
		btn_barre.pressed.connect(_basculer_sort_barre.bind(id))
	else:
		btn_barre.text = "Verrouillé"
		btn_barre.tooltip_text = texte_verrou
		btn_barre.disabled = true
		icone.modulate = Color(0.6, 0.6, 0.6)
	entete.add_child(icone)
	entete.add_child(nom)
	entete.add_child(btn_barre)
	var infos := Label.new()
	var texte_infos := "Type : %s   •   Portée : %d   •   PA : %d   •   Recharge de base : %d" % [
		sort.get("type", "-"), int(sort.get("portee", 0)), int(sort.get("cout_pa", 2)), int(sort.get("recharge", 0)),
	]
	if int(sort.get("degats", 0)) > 0:
		texte_infos += " | Dégâts : %d" % int(sort["degats"])
	var stat_boost := Personnage.stat_booster_sort(sort)
	if not stat_boost.is_empty():
		texte_infos += " · %s +%d" % [stat_boost, roundi(Personnage.bonus_sort_actuel(sort))]
	infos.text = texte_infos
	infos.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	description.text = texte_description if texte_verrou.is_empty() else texte_description + "\n" + texte_verrou
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	boite.add_child(entete)
	boite.add_child(infos)
	boite.add_child(description)
	encadre.add_child(boite)
	liste_sorts.add_child(encadre)

func _basculer_sort_barre(id: String) -> void:
	if Personnage.sort_dans_barre(id):
		Personnage.retirer_sort_barre(id)
	else:
		Personnage.ajouter_sort_barre(id)

func _on_retirer_sort_barre(id: String) -> void:
	Personnage.retirer_sort_barre(id)

func maj_quetes(_quest_id: String = "") -> void:
	if not fenetre.visible or section_actuelle != "quetes":
		return
	for enfant in liste_quetes.get_children():
		enfant.queue_free()
	# les quêtes terminées ne s'affichent plus
	var visibles: Array = []
	for id in QuestManager.quetes_actives:
		if not QuestManager.est_terminee(id):
			visibles.append(id)
	label_aucune_quete.visible = visibles.is_empty()
	(liste_quetes.get_parent() as ScrollContainer).visible = not visibles.is_empty()
	for id in visibles:
		var quest: Dictionary = QuestManager.get_quest(id)
		var encadre := PanelContainer.new()
		encadre.add_theme_stylebox_override("panel", FICHE_MENU)
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
		btn_terminer.text = "Dév. · Terminer"
		btn_terminer.visible = OS.is_debug_build()
		btn_terminer.pressed.connect(_on_terminer_quete.bind(id))
		var btn_abandonner := Button.new()
		btn_abandonner.text = "Abandonner"
		btn_abandonner.pressed.connect(_on_abandonner_quete.bind(id))
		boite.add_child(titre_quete)
		boite.add_child(description)
		boite.add_child(progression)
		var actions := HBoxContainer.new()
		actions.alignment = BoxContainer.ALIGNMENT_END
		actions.add_child(btn_terminer)
		actions.add_child(btn_abandonner)
		boite.add_child(actions)
		encadre.add_child(boite)
		liste_quetes.add_child(encadre)

func _on_terminer_quete(id: String) -> void:
	QuestManager.terminer_quete(id)

func _on_abandonner_quete(id: String) -> void:
	QuestManager.abandonner_quete(id)

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

func _on_portables_toggle(coche: bool) -> void:
	filtre_portables = coche
	defilement_inventaire.scroll_vertical = 0
	maj_grille()

# frappe dans la recherche du sac : la grille suit immédiatement
func _on_recherche_sac(_texte: String) -> void:
	defilement_inventaire.scroll_vertical = 0
	maj_grille()

# true si l'objet est un équipement dont le niveau minimum est atteint
# (restriction de classe ignorée : une autre classe peut le mettre en arme2)
func _est_portable(id: String) -> bool:
	var details := Inventaire.details_objet(id)
	if Personnage.emplacement_equipement(str(details.get("type", "")), str(details.get("sous_type", ""))) == "":
		return false
	return int(details.get("niveau_min", 1)) <= Personnage.niveau

func _sur_inventaire_modifie() -> void:
	_grille_sale = true
	_wiki_a_actualiser = true
	if fenetre.visible and section_actuelle == "wiki":
		maj_wiki()
	if fenetre.visible and section_actuelle == "inventaire" and not _mise_a_jour_sac_prevue:
		_mise_a_jour_sac_prevue = true
		_rafraichir_sac.call_deferred()

func _rafraichir_sac() -> void:
	_mise_a_jour_sac_prevue = false
	if fenetre.visible and section_actuelle == "inventaire" and _grille_sale:
		maj_grille()
		maj_equipement()

func _objet_visible(id: String, type_choisi: Variant) -> bool:
	if filtre_portables and not _est_portable(id):
		return false
	# recherche par nom (cumulée aux filtres portables et catégorie) :
	# insensible à la casse, sur le nom affiché de l'objet
	var filtre_nom := champ_recherche_sac.text.strip_edges().to_lower()
	if filtre_nom != "" and not Inventaire.nom_objet(id).to_lower().contains(filtre_nom):
		return false
	return type_choisi == null or Inventaire.details_objet(id).get("type", "") == type_choisi

func maj_grille() -> void:
	_grille_sale = false
	var types: Array[String] = []
	var ids: Array = Inventaire.objets.keys()
	ids.sort_custom(func(id_a: String, id_b: String) -> bool:
		return Inventaire.nom_objet(id_a).naturalnocasecmp_to(Inventaire.nom_objet(id_b)) < 0)
	# le menu des catégories ne propose que les types des objets qui
	# passent aussi la recherche par nom
	var filtre_nom_types := champ_recherche_sac.text.strip_edges().to_lower()
	for id: String in ids:
		if filtre_nom_types != "" and not Inventaire.nom_objet(id).to_lower().contains(filtre_nom_types):
			continue
		var type_item := str(Inventaire.details_objet(id).get("type", ""))
		if not types.has(type_item) and (not filtre_portables or _est_portable(id)):
			types.append(type_item)
	types.sort_custom(func(a: String, b: String) -> bool:
		return _libelle_type_inventaire(a).naturalnocasecmp_to(_libelle_type_inventaire(b)) < 0)
	var type_choisi: Variant = _maj_types_inventaire(types)
	var cases_existantes: Dictionary = {}
	for enfant in grille.get_children():
		var id_existant := str(enfant.get_meta("item_id", ""))
		if id_existant != "":
			cases_existantes[id_existant] = enfant
	for id: String in ids:
		if not _objet_visible(id, type_choisi):
			continue
		var details := Inventaire.details_objet(id)
		var quantite_objet: int = int(Inventaire.objets[id])
		var slot := cases_existantes.get(id) as PanelContainer
		if slot == null:
			slot = SCENE_CASE_INVENTAIRE.instantiate() as PanelContainer
			if slot == null:
				push_warning("Impossible de charger la case d'inventaire.")
				continue
			slot.theme_type_variation = _variation_rarete(int(details.get("id_rarete", 1)))
			slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			slot.focus_mode = Control.FOCUS_ALL
			slot.gui_input.connect(_on_slot_clique.bind(id, slot))
			slot.mouse_entered.connect(_animer_case.bind(slot, true))
			slot.mouse_exited.connect(_animer_case.bind(slot, false))
			grille.add_child(slot)
		else:
			cases_existantes.erase(id)
		grille.move_child(slot, grille.get_child_count() - 1)
		_maj_case_inventaire(slot, id, details, quantite_objet)
	for id_supprime in cases_existantes:
		var case_supprimee: Control = cases_existantes[id_supprime]
		grille.remove_child(case_supprimee)
		case_supprimee.queue_free()
	var grille_vide := grille.get_child_count() == 0
	defilement_inventaire.visible = not grille_vide
	label_vide.visible = grille_vide
	if champ_recherche_sac.text.strip_edges() != "":
		label_vide.text = "Aucun objet ne correspond aux filtres."
	elif filtre_portables:
		label_vide.text = "Aucun équipement portable à ton niveau."
	else:
		label_vide.text = "Inventaire vide"
	_maj_monnaie_et_compteur()
	var detail_disponible := false
	if detail_id_courant != "" and Inventaire.objets.has(detail_id_courant):
		detail_disponible = _objet_visible(detail_id_courant, type_choisi)
	if detail_id_courant != "" and Personnage.est_equipe(detail_id_courant) != "":
		detail_disponible = true
	if detail_disponible:
		maj_detail_item(detail_id_courant)
	else:
		maj_detail_aucun()

func _maj_case_inventaire(slot: PanelContainer, id: String, details: Dictionary, quantite_objet: int) -> void:
	slot.set_meta("item_id", id)
	slot.theme_type_variation = _variation_rarete(int(details.get("id_rarete", 1)))
	slot.accessibility_name = "%s ×%d" % [Inventaire.nom_objet(id), quantite_objet]
	slot.tooltip_text = "%s x%d\n%s" % [Inventaire.nom_objet(id), quantite_objet, str(details.get("description", ""))]
	var icone: TextureRect = slot.get_node("Boite/Icone")
	var nouvelle_icone := _icone_objet(details)
	if icone.texture != nouvelle_icone:
		icone.texture = nouvelle_icone
	var quantite: Label = slot.get_node("Boite/Quantite")
	quantite.text = "x%d" % quantite_objet
	var selection := slot.get_node("Boite/Selection") as Panel
	selection.visible = id == detail_id_courant

func _on_slot_clique(evenement: InputEvent, id: String, slot: PanelContainer) -> void:
	if _activation_case(evenement):
		maj_detail_item(id)
		_maj_selection_grille(id, true)
		_animer_case(slot, true)

func _maj_selection_grille(id: String, animer := false) -> void:
	for enfant in grille.get_children():
		var slot := enfant as PanelContainer
		var selection := slot.get_node("Boite/Selection") as Panel
		var est_selectionne := str(slot.get_meta("item_id", "")) == id and id != ""
		selection.visible = est_selectionne
		if est_selectionne and animer:
			selection.modulate.a = 0.0
			var tween := selection.create_tween()
			tween.tween_property(selection, "modulate:a", 1.0, 0.12)

func _animer_case(slot: PanelContainer, survol: bool) -> void:
	var cle := slot.get_instance_id()
	var precedent := _tweens_cases.get(cle) as Tween
	if precedent != null and precedent.is_running():
		precedent.kill()
	var couleur := Color(1.0, 0.93, 0.78, 1.0) if survol else Color.WHITE
	var tween := slot.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(slot, "modulate", couleur, 0.09)
	_tweens_cases[cle] = tween
	tween.finished.connect(_oublier_tween_case.bind(cle, tween))

func _oublier_tween_case(cle: int, tween: Tween) -> void:
	if _tweens_cases.get(cle) == tween:
		_tweens_cases.erase(cle)

func _activation_case(evenement: InputEvent) -> bool:
	return evenement.is_action_pressed("ui_accept") or (evenement is InputEventMouseButton and evenement.pressed and evenement.button_index == MOUSE_BUTTON_LEFT)

func maj_detail_item(id: String) -> void:
	detail_id_courant = id
	_maj_selection_grille(id)
	var details := Inventaire.details_objet(id)
	icone_detail.texture = _icone_objet(details)
	nom_detail.text = Inventaire.nom_objet(id)
	nom_detail.add_theme_color_override("font_color", (details["couleur_rarete"] as Color).darkened(0.48))
	var type_texte: String = details.get("type", "").capitalize()
	if details.get("sous_type", "") != "":
		type_texte += " | %s" % details["sous_type"].capitalize()
	if details.get("rarete", "") != "":
		type_texte += "\n%s" % details["rarete"]
	type_detail.text = type_texte
	type_detail.add_theme_color_override("font_color", (details["couleur_rarete"] as Color).darkened(0.48))
	description_detail.text = details.get("description", "")
	var texte_stats := _texte_stats(details)
	stats_detail.text = texte_stats
	stats_detail.visible = texte_stats != ""
	prix_detail.text = "Prix : %s Berry" % _formater_nombre(int(details.get("prix", 0)))
	_maj_bouton_equiper(details, id)
	_maj_bouton_utiliser(details)
	_maj_bouton_barre_objets(details)

func maj_detail_aucun() -> void:
	detail_id_courant = ""
	_maj_selection_grille("")
	icone_detail.texture = null
	nom_detail.text = "Aucun objet sélectionné"
	nom_detail.remove_theme_color_override("font_color")
	type_detail.text = ""
	description_detail.text = "Cliquez sur un objet de l'inventaire pour voir ses détails."
	stats_detail.text = ""
	stats_detail.visible = false
	prix_detail.text = ""
	btn_equiper.visible = false
	btn_utiliser.hide()
	btn_manger_fruit.hide()
	btn_barre_objets.hide()
	btn_ouvrir_coffre.visible = false
	btn_ouvrir_tous.visible = false

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
		slot.focus_mode = Control.FOCUS_ALL
		slot.accessibility_name = TEXTES_EMPLACEMENTS[emplacement]
		slot.gui_input.connect(_on_emplacement_clique.bind(emplacement))
		var icone: TextureRect = slot.get_node("Contenu/Icone")
		var libelle: Label = slot.get_node("Contenu/Libelle")
		libelle.text = LABELS_COURTS_EMPLACEMENTS.get(emplacement, TEXTES_EMPLACEMENTS[emplacement])
		emplacements_ui[emplacement] = {"slot": slot, "icone": icone}

func _positionner_emplacements() -> void:
	if silhouette.size.x <= 0.0 or silhouette.size.y <= 0.0:
		return
	var nombre_rangees := maxi(EMPLACEMENTS_GAUCHE.size(), EMPLACEMENTS_DROIT.size())
	var hauteur_slots := TAILLE_CASE_EQUIP.y * nombre_rangees + ESPACEMENT_CASE_EQUIP * (nombre_rangees - 1)
	var debut_y := maxf((silhouette.size.y - hauteur_slots) * 0.5, 4.0)
	for index in EMPLACEMENTS_GAUCHE.size():
		_positionner_emplacement(EMPLACEMENTS_GAUCHE[index], 8.0, debut_y + index * (TAILLE_CASE_EQUIP.y + ESPACEMENT_CASE_EQUIP))
	for index in EMPLACEMENTS_DROIT.size():
		var x_droite := maxf(silhouette.size.x - TAILLE_CASE_EQUIP.x - 8.0, 8.0)
		_positionner_emplacement(EMPLACEMENTS_DROIT[index], x_droite, debut_y + index * (TAILLE_CASE_EQUIP.y + ESPACEMENT_CASE_EQUIP))
	var taille_portrait := Vector2(148, 148)
	portrait_equipement.position = Vector2((silhouette.size.x - taille_portrait.x) * 0.5, (silhouette.size.y - taille_portrait.y) * 0.5 - 8.0)
	portrait_equipement.size = taille_portrait

func _positionner_emplacement(emplacement: String, x: float, y: float) -> void:
	if not emplacements_ui.has(emplacement):
		return
	var slot: PanelContainer = emplacements_ui[emplacement]["slot"]
	slot.custom_minimum_size = TAILLE_CASE_EQUIP
	slot.position = Vector2(x, y)
	slot.size = TAILLE_CASE_EQUIP

# met à jour le bouton Équiper/Déséquiper selon l'objet affiché dans le détail
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

# équipe d'un coup le meilleur objet atteignable de chaque emplacement
# puis rafraîchit silhouette, grille et détail
func _on_auto_equipement() -> void:
	var changements := Personnage.equiper_les_meilleurs()
	if changements > 0:
		avertir("%d emplacement(s) optimisé(s)." % changements)
	else:
		avertir("Équipement déjà au mieux de ton inventaire.")
	maj_grille()
	maj_equipement()
	_maj_resume_personnage()
	maj_detail_aucun()

func _on_bouton_equiper() -> void:
	if detail_id_courant == "":
		return
	var emplacement_equipe: String = Personnage.est_equipe(detail_id_courant)
	if emplacement_equipe != "":
		Personnage.desequiper(emplacement_equipe)
	else:
		Personnage.equiper(detail_id_courant)
	maj_equipement()
	maj_detail_item(detail_id_courant)

func _maj_bouton_utiliser(details: Dictionary) -> void:
	if btn_utiliser == null:
		return
	var consommable := str(details.get("type", "")) == "consumable"
	btn_utiliser.visible = consommable
	if not consommable:
		return
	var effets: Dictionary = details.get("effets", {})
	btn_utiliser.text = "Réattribuer les points" if bool(effets.get(Personnage.EFFET_REATTRIBUTION, false)) else "Utiliser"
	btn_utiliser.disabled = effets.is_empty()

# met à jour le bouton de la barre d'objets selon l'objet affiché :
# visible pour les consommables, il place ou retire l'objet de la barre
func _maj_bouton_barre_objets(details: Dictionary) -> void:
	if btn_barre_objets == null:
		return
	var consommable := str(details.get("type", "")) == "consumable"
	btn_barre_objets.visible = consommable
	if not consommable:
		return
	if detail_id_courant != "" and Personnage.objet_dans_barre(detail_id_courant):
		btn_barre_objets.text = "Retirer de la barre d'objets"
		btn_barre_objets.disabled = false
	else:
		btn_barre_objets.text = "Placer dans la barre d'objets"
		btn_barre_objets.disabled = Personnage.barre_objets_pleine()

# place le consommable sélectionné dans la barre d'objets du HUD (ou
# le retire s'il y figure déjà) ; la barre se gère ensuite au clic et
# aux touches 1-0 comme celle des sorts
func _on_bouton_barre_objets() -> void:
	if detail_id_courant == "":
		return
	var id := detail_id_courant
	if Personnage.objet_dans_barre(id):
		Personnage.retirer_objet_barre(id)
	else:
		if not Personnage.ajouter_objet_barre(id):
			avertir("La barre d'objets est pleine (%d emplacements)." % [
				Personnage.TAILLE_BARRE_OBJETS])
			return
	maj_detail_item(id)

# utilise le consommable sélectionné dans le détail : applique ses effets
# (points de vie restaurés, bonus temporaires) et le retire de
# l'inventaire
func _on_bouton_utiliser() -> void:
	if detail_id_courant == "":
		return
	var id := detail_id_courant
	var effets: Dictionary = Inventaire.details_objet(id).get("effets", {})
	if bool(effets.get(Personnage.EFFET_REATTRIBUTION, false)):
		_confirmer_reattribution(id)
		return
	_utiliser_consommable(id)

func _confirmer_reattribution(id: String) -> void:
	var points := Personnage.points_recuperables()
	if points == 0:
		avertir("Tu n’as aucun point investi à récupérer.")
		return
	var dialogue := ConfirmationDialog.new()
	dialogue.title = "Réattribuer tes points"
	var unite := "point" if points == 1 else "points"
	dialogue.dialog_text = (
		"Utiliser un parchemin pour récupérer %d %s de caractéristique à redistribuer ?" % [points, unite]
	)
	dialogue.ok_button_text = "Utiliser le parchemin"
	dialogue.cancel_button_text = "Annuler"
	dialogue.confirmed.connect(func(): _utiliser_consommable.call_deferred(id))
	dialogue.visibility_changed.connect(func() -> void:
		if not dialogue.visible:
			dialogue.queue_free())
	add_child(dialogue)
	dialogue.popup_centered()

func _utiliser_consommable(id: String) -> void:
	var nom := Inventaire.nom_objet(id)
	var details := Inventaire.details_objet(id)
	var effets: Dictionary = details.get("effets", {})
	var soin := int(effets.get("heal", 0))
	var points_avant := Personnage.points_statistique
	var message := Personnage.utiliser_objet(id)
	maj_grille()
	if detail_id_courant == id:
		if Inventaire.objets.has(id):
			maj_detail_item(id)
		else:
			maj_detail_aucun()
	if message != "":
		avertir(message)
		return
	var info := AcceptDialog.new()
	info.title = "%s consommé !" % nom
	var texte := "Ses bonus sont actifs temporairement."
	if bool(effets.get(Personnage.EFFET_REATTRIBUTION, false)):
		points_en_attente.clear()
		maj_personnage()
		var points_rendus := Personnage.points_statistique - points_avant
		var unite := "point" if points_rendus == 1 else "points"
		texte = "%d %s à redistribuer dans l’onglet Personnage." % [points_rendus, unite]
	elif soin > 0:
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
	var ui := get_tree().get_first_node_in_group("coffres_ui")
	if ui != null:
		fermer()
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
	var ui := get_tree().get_first_node_in_group("coffres_ui")
	if ui != null:
		fermer()
		ui.ouvrir_contenu(
			"Coffres %s (x%d)" % [str(details.get("sous_type", "commun")).to_lower(), nombre],
			id_coffre, contenu, rarete)

# debug : crédite un million de Berry pour tester la boutique
func _on_debug_berry() -> void:
	Personnage.ajouter_berry(1_000_000)

func _on_emplacement_clique(evenement: InputEvent, emplacement: String) -> void:
	if _activation_case(evenement):
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
			icone.texture = ICONES_EMPLACEMENTS[emplacement] as Texture2D
			slot.tooltip_text = TEXTES_EMPLACEMENTS[emplacement]
		else:
			var details := Inventaire.details_objet(id)
			slot.theme_type_variation = _variation_rarete(int(details.get("id_rarete", 1)))
			icone.texture = _icone_objet(details)
			slot.tooltip_text = "%s\n(%s)" % [Inventaire.nom_objet(id), TEXTES_EMPLACEMENTS[emplacement]]
	_maj_resume_personnage()
	_maj_monnaie_et_compteur()

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
	if chemin == "" or not ResourceLoader.exists(chemin):
		chemin = ICONES_PAR_TYPE.get(details.get("type", "").to_lower(), ICONE_DEFAUT)
	if _cache_icones_objets.has(chemin):
		return _cache_icones_objets[chemin] as Texture2D
	var icone := load(chemin) as Texture2D
	if icone != null:
		_cache_icones_objets[chemin] = icone
	return icone

# --- Wiki des objets : liste complete, details seulement si deja rencontres ---

const ICONE_CADENAS := "res://addons/pixel_ui_fantasy/icons/lock.png"

# types proposés par le filtre du wiki ; "" = tous les types
const ID_ENCYCLOPEDIE_FRUITS := "950"

# l'encyclopédie des fruits du démon est-elle dans l'inventaire ?
func _encyclopedie_fruits_possedee() -> bool:
	return Inventaire.objets.has(ID_ENCYCLOPEDIE_FRUITS)

var types_wiki: Array = [""]
# objet affiché dans la fiche du wiki (cible du bouton debug "Donner x5")
var id_wiki_courant := ""

# remplit le filtre de types avec les types réellement présents en base
func _selectionner_objet_wiki(index: int) -> void:
	maj_detail_wiki(str(liste_wiki.get_item_metadata(index)))

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

func maj_wiki() -> void:
	var montrer_fruits := _encyclopedie_fruits_possedee()
	if _catalogue_wiki.is_empty() or montrer_fruits != _fruit_wiki_visible:
		var ancien_type: String = str(types_wiki[option_type_wiki.selected]) if option_type_wiki.selected >= 0 else ""
		_fruit_wiki_visible = montrer_fruits
		_peupler_types_wiki()
		option_type_wiki.select(maxi(0, types_wiki.find(ancien_type)))
		_catalogue_wiki = BaseDonnees.lire("SELECT id, name, type FROM items WHERE is_active = 1 ORDER BY id;").duplicate()
	_wiki_a_actualiser = false
	liste_wiki.clear()
	var type_choisi := str(types_wiki[option_type_wiki.selected]) if option_type_wiki.selected >= 0 else ""
	var filtre := champ_recherche.text.strip_edges().to_lower()
	var connus := 0
	var affiches := 0
	var index_actuel := -1
	for ligne: Dictionary in _catalogue_wiki:
		var est_fruit := str(ligne["type"]) == "fruit_demon"
		if est_fruit and not montrer_fruits:
			continue
		var nom_item := str(ligne["name"])
		if type_choisi != "" and type_choisi != str(ligne["type"]):
			continue
		if not filtre.is_empty() and not nom_item.to_lower().contains(filtre):
			continue
		var id := str(ligne["id"])
		var index := liste_wiki.add_item(nom_item)
		liste_wiki.set_item_metadata(index, id)
		if id == id_wiki_courant:
			index_actuel = index
		if Inventaire.est_connu(id) or est_fruit:
			connus += 1
		else:
			liste_wiki.set_item_icon(index, preload(ICONE_CADENAS))
		affiches += 1
	var prefixe := ""
	if type_choisi != "":
		prefixe = "Type : %s | " % type_choisi.capitalize()
	if filtre == "":
		compteur_wiki.text = prefixe + "Objets découverts : %d / %d" % [connus, affiches]
	elif affiches > 0:
		compteur_wiki.text = prefixe + "Recherche : %d objet(s) | %d découvert(s)" % [affiches, connus]
	else:
		compteur_wiki.text = prefixe + "Aucun objet ne correspond à « %s »" % filtre
	if index_actuel >= 0:
		liste_wiki.select(index_actuel)
		_selectionner_objet_wiki(index_actuel)
	else:
		maj_detail_aucun_wiki()

func maj_detail_wiki(id: String) -> void:
	id_wiki_courant = id
	btn_donner_item_wiki.visible = OS.is_debug_build()
	nom_wiki.text = Inventaire.nom_objet(id)
	nom_wiki.remove_theme_color_override("font_color")
	type_wiki.remove_theme_color_override("font_color")
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
	nom_wiki.add_theme_color_override("font_color", (details["couleur_rarete"] as Color).darkened(0.48))
	var type_texte: String = details.get("type", "").capitalize()
	if details.get("sous_type", "") != "":
		type_texte += " | %s" % details["sous_type"].capitalize()
	if details.get("rarete", "") != "":
		type_texte += "\n%s" % details["rarete"]
	type_wiki.text = type_texte
	type_wiki.add_theme_color_override("font_color", (details["couleur_rarete"] as Color).darkened(0.48))
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
		encadre.add_theme_stylebox_override("panel", FICHE_MENU)
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
			ligne_ing.add_theme_color_override("font_color", Color(0.55, 0.11, 0.10))
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
	_maj_delai_hotel()
	if not HotelVentes.dernier_message.is_empty():
		info_mise_hotel.text = HotelVentes.dernier_message
		HotelVentes.dernier_message = ""
	_construire_achats_hotel()
	_construire_ventes_joueurs_hotel()
	_construire_ventes_hotel()
	_remplir_forme_hotel()

func _maj_delai_hotel() -> void:
	info_achats_hotel.text = "Prochain réapprovisionnement des vendeurs dans %d s" % HotelVentes.secondes_avant_remplissage()
	_prochaine_maj_hotel_ms = Time.get_ticks_msec() + 1000

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
		encadre.add_theme_stylebox_override("panel", FICHE_MENU)
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
		nom.add_theme_color_override("font_color", (details["couleur_rarete"] as Color).darkened(0.48))
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

# mises en vente des autres joueurs (HDV partagé en ligne)
func _construire_ventes_joueurs_hotel() -> void:
	for enfant in liste_ventes_joueurs.get_children():
		enfant.queue_free()
	var mises := HotelVentes.ventes_joueurs()
	if mises.is_empty():
		info_ventes_joueurs.visible = true
		info_ventes_joueurs.text = ("Aucune mise en vente d'autre joueur pour l'instant."
			if HotelVentes.en_ligne else "Hors ligne : les ventes des joueurs arrivent en ligne.")
		return
	info_ventes_joueurs.visible = false
	for i in mises.size():
		var mise: Dictionary = mises[i]
		var details := Inventaire.details_objet(str(mise.get("item", "")))
		var encadre := PanelContainer.new()
		encadre.add_theme_stylebox_override("panel", FICHE_MENU)
		encadre.theme_type_variation = _variation_rarete(int(details.get("id_rarete", 1)))
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
		nom.text = Inventaire.nom_objet(str(mise.get("item", "")))
		nom.add_theme_color_override("font_color", (details["couleur_rarete"] as Color).darkened(0.48))
		nom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nom.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nom.add_theme_font_size_override("font_size", 22)
		ligne_nom.add_child(icone)
		ligne_nom.add_child(nom)
		var ligne_action := HBoxContainer.new()
		ligne_action.add_theme_constant_override("separation", 12)
		var total := int(mise.get("prix_unite", 0)) * int(mise.get("quantite", 0))
		var prix := Label.new()
		prix.text = "x%d à %d Berry/u - %d Berry - %s" % [
			int(mise.get("quantite", 0)), int(mise.get("prix_unite", 0)),
			total, str(mise.get("vendeur", "?"))]
		prix.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		prix.add_theme_font_size_override("font_size", 20)
		var btn := Button.new()
		btn.text = "Acheter"
		btn.disabled = Personnage.berry < total
		btn.pressed.connect(_on_acheter_joueur_hotel.bind(i))
		ligne_action.add_child(prix)
		ligne_action.add_child(btn)
		colonne.add_child(ligne_nom)
		colonne.add_child(ligne_action)
		encadre.add_child(colonne)
		liste_ventes_joueurs.add_child(encadre)

func _on_acheter_joueur_hotel(index: int) -> void:
	var erreur := HotelVentes.acheter_joueur(index)
	if erreur != "":
		info_mise_hotel.text = erreur
		info_mise_hotel.add_theme_color_override("font_color", Color(0.85, 0.3, 0.3))
		return
	info_mise_hotel.text = "Achat envoyé au serveur..."
	info_mise_hotel.add_theme_color_override("font_color", Color(0.4, 0.7, 0.35))
	maj_hotel()

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
		encadre.add_theme_stylebox_override("panel", FICHE_MENU)
		encadre.theme_type_variation = _variation_rarete(int(details.get("id_rarete", 1)))
		# idem que les offres : nom seul sur sa ligne, détails et bouton dessous
		var colonne := VBoxContainer.new()
		colonne.add_theme_constant_override("separation", 6)
		var nom := Label.new()
		nom.text = Inventaire.nom_objet(str(mise["item"]))
		nom.add_theme_color_override("font_color", (details["couleur_rarete"] as Color).darkened(0.48))
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

func _on_retirer_hotel(index: int) -> void:
	HotelVentes.retirer(index)

func _on_mettre_en_vente() -> void:
	if ids_ventes_hotel.is_empty():
		return
	var id := ids_ventes_hotel[maxi(champ_objet_hotel.selected, 0)]
	var erreur := HotelVentes.mettre_en_vente(
		id, int(nb_quantite_hotel.value), int(nb_prix_hotel.value))
	if erreur != "":
		info_mise_hotel.text = erreur
		info_mise_hotel.add_theme_color_override("font_color", Color(0.55, 0.11, 0.10))
	else:
		info_mise_hotel.text = "Mise en vente créée."
		info_mise_hotel.add_theme_color_override("font_color", Color(0.17, 0.34, 0.13))

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
	if not Equipages.dernier_message.is_empty():
		info_equipage.text += "\n" + Equipages.dernier_message
		Equipages.dernier_message = ""
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
	encadre_capitaine.add_theme_stylebox_override("panel", FICHE_MENU)
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
		encadre.add_theme_stylebox_override("panel", FICHE_MENU)
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
		encadre.add_theme_stylebox_override("panel", FICHE_MENU)
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
			etiquette.add_theme_color_override("font_color", Color(0.17, 0.34, 0.13))
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

func _on_dissoudre_equipage() -> void:
	Equipages.dissoudre()

func _on_quitter_equipage() -> void:
	Equipages.quitter()

func _on_ajouter_membre() -> void:
	var erreur := Equipages.ajouter_membre(champ_nom_membre.text)
	if erreur != "":
		info_equipage.text = erreur
		return
	champ_nom_membre.text = ""

func _on_virer_membre(nom_membre: String) -> void:
	var erreur := Equipages.virer(nom_membre)
	if erreur != "":
		info_equipage.text = erreur

func _on_nommer_vice(nom_membre: String) -> void:
	var erreur := Equipages.nommer_vice(nom_membre)
	if erreur != "":
		info_equipage.text = erreur

func _on_modifier_description() -> void:
	var erreur := Equipages.changer_description(champ_description.text)
	if erreur != "":
		info_equipage.text = erreur

func _on_deposer_caisse() -> void:
	var erreur := Equipages.deposer_berry(int(nb_caisse.value))
	if erreur != "":
		info_caisse.text = erreur

func _on_retirer_caisse() -> void:
	var erreur := Equipages.retirer_berry(int(nb_caisse.value))
	if erreur != "":
		info_caisse.text = erreur

func _on_proposer_alliance(id_equipage: int) -> void:
	var erreur := Equipages.proposer_alliance(id_equipage)
	if erreur != "":
		info_flotte.text = erreur

func _on_rompre_flotte() -> void:
	var erreur := Equipages.rompre_alliance()
	if erreur != "":
		info_flotte.text = erreur
