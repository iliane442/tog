extends Node2D

# Entité miroir d'un joueur distant pendant un duel : ses actions
# arrivent par le réseau (relais du serveur) et sont rejouées ici, sur
# notre propre grille d'arène. Ses pv ne sont qu'une image : les valeurs
# vraies vivent chez son propriétaire, qui annonce sa défaite lui-même.

signal sante_modifiee(vie: int, vie_max: int)

# nombre de dégâts flottant (chiffre qui jaillit, rebondit, s'envole)
const DEGATS_FLOTTANTS := preload("res://scripts/combat/degats_flottants.gd")

const VISUEL_DEFAUT := "humain_pirate"
# planches d'idle et de marche : 4 colonnes/6 colonnes d'animation,
# 4 lignes de direction (cf. player.gd)
const LIGNES := {"sud": 0, "ouest": 1, "est": 2, "nord": 3}
const COLONNES_REPOS := 4
const COLONNES_MARCHE := 6
const FPS_REPOS := 6.0
const FPS_MARCHE := 10.0

var nom := "Adversaire"
var pv := 100
var pv_max := 100
var degats_attaque := 5
var portee_attaque := 4
var pm_max := 4
var pa_max := 6
var defense_pvp := 0
var sorts_noms: Array = []
var distante := true          # marqueur PvP : jamais pilotée par l'IA locale
var allie := false
var visuel := VISUEL_DEFAUT   # planche de sprites du joueur distant

var _sprite: Sprite2D
var _etiquette: Label
var _deplacement: Tween
var _fin_tour_recue := false
var _texture_repos: Texture2D
var _texture_marche: Texture2D
var _ligne := 0
var _colonne := 0.0

func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite2D"
	_appliquer_visuel()
	_sprite.position.y = -24.0
	add_child(_sprite)
	_etiquette = Label.new()
	_etiquette.position.y = _sprite.position.y + _sprite.get_rect().position.y - (19.0 if allie else 14.0)
	_etiquette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_etiquette.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_etiquette.add_theme_font_size_override("font_size", 16 if allie else 12)
	_etiquette.add_theme_color_override("font_color", Color("#8de8e5") if allie else Color("#ff6b6b"))
	if allie:
		_etiquette.add_theme_color_override("font_outline_color", Color("#142433"))
		_etiquette.add_theme_constant_override("outline_size", 6)
	_etiquette.add_theme_color_override("font_shadow_color", Color.BLACK)
	_etiquette.add_theme_constant_override("shadow_offset_x", 1)
	_etiquette.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_etiquette)
	_actualiser_nom()

# anime le miroir : planche de marche pendant le trajet rejoué, puis
# retour à l'animation de repos (dans la direction conservée)
func _process(delta: float) -> void:
	var en_mouvement := _deplacement != null and _deplacement.is_valid()
	var colonnes := COLONNES_MARCHE if en_mouvement else COLONNES_REPOS
	_colonne = fmod(_colonne + delta * (FPS_MARCHE if en_mouvement else FPS_REPOS), float(colonnes))
	var feuille := _texture_marche if en_mouvement else _texture_repos
	if _sprite.texture != feuille:
		_sprite.texture = feuille
		_sprite.hframes = colonnes
	_sprite.frame = _ligne * colonnes + int(_colonne)

# profil envoyé par l'adversaire (pv réels, stats, sorts affichés)
func appliquer_profil(profil: Dictionary) -> void:
	nom = str(profil.get("pseudo", nom))
	# planche de sprites du joueur distant (race/sexe) : le miroir
	# porte son vrai visuel, pas l'humain de base
	var visuel_profil := str(profil.get("visuel", ""))
	if visuel_profil != "" and visuel_profil != visuel:
		definir_visuel(visuel_profil)
	pv_max = maxi(int(profil.get("pv_max", pv_max)), 1)
	pv = clampi(int(profil.get("pv", pv)), 0, pv_max)
	degats_attaque = int(profil.get("attaque", degats_attaque))
	defense_pvp = int(profil.get("defense", defense_pvp))
	pa_max = int(profil.get("pa_max", pa_max))
	pm_max = int(profil.get("pm_max", pm_max))
	sorts_noms = profil.get("sorts", [])
	_actualiser_nom()
	sante_modifiee.emit(pv, pv_max)

func _actualiser_nom() -> void:
	_etiquette.text = ("[G] " if allie else "") + nom
	_etiquette.reset_size()
	_etiquette.position.x = -_etiquette.size.x / 2.0

# planche de sprites du joueur distant (race/sexe) : planches de repos
# et de marche, face sud par défaut
func definir_visuel(prefixe: String) -> void:
	visuel = str(prefixe)
	_appliquer_visuel()

func _appliquer_visuel() -> void:
	if _sprite == null:
		return
	var chemin_repos := "res://assets/sprites/%s/%s_idle.png" % [visuel, visuel]
	var chemin_marche := "res://assets/sprites/%s/%s_walk.png" % [visuel, visuel]
	if not (ResourceLoader.exists(chemin_repos) and ResourceLoader.exists(chemin_marche)):
		visuel = VISUEL_DEFAUT
		chemin_repos = "res://assets/sprites/%s/%s_idle.png" % [visuel, visuel]
		chemin_marche = "res://assets/sprites/%s/%s_walk.png" % [visuel, visuel]
	_texture_repos = load(chemin_repos)
	_texture_marche = load(chemin_marche)
	_sprite.texture = _texture_repos
	_sprite.hframes = COLONNES_REPOS
	_sprite.vframes = LIGNES.size()
	_sprite.frame = _ligne * COLONNES_REPOS

# ligne de direction (sud, ouest, est, nord) d'un vecteur de déplacement
func _ligne_cardinale(direction: Vector2) -> int:
	if absf(direction.x) > absf(direction.y):
		return LIGNES["est"] if direction.x > 0.0 else LIGNES["ouest"]
	return LIGNES["nord"] if direction.y < 0.0 else LIGNES["sud"]

func recevoir_degats(montant: int) -> void:
	pv = maxi(pv - maxi(montant, 0), 0)
	sante_modifiee.emit(pv, pv_max)
	# les dégâts infligés à l'adversaire se voient, comme sur un
	# ennemi de la map : le chiffre jaillit au-dessus du miroir
	_nombre_flottant(self, "-%d" % maxi(montant, 0), "degats")
	# pas de fin automatique : le propriétaire des pv annonce sa
	# défaite lui-même (les pv ici ne sont qu'une image)

func soigner(montant: int) -> void:
	pv = mini(pv + maxi(montant, 0), pv_max)
	sante_modifiee.emit(pv, pv_max)
	_nombre_flottant(self, "+%d" % maxi(montant, 0), "soin")

# affiche un texte flottant au-dessus du miroir puis se libère
func _nombre_flottant(cible: Node2D, texte: String, type: String) -> void:
	if not is_inside_tree() or cible == null or not is_instance_valid(cible):
		return
	var nombre := DEGATS_FLOTTANTS.new()
	nombre.texte = texte
	nombre.type = type
	nombre.position = cible.global_position + Vector2(0, -26)
	get_tree().current_scene.add_child(nombre)

# le tour de l'adversaire : on attend la fin envoyée par le réseau,
# pendant laquelle ses actions (déplacements, sorts) nous parviennent ;
# le drapeau se nettoie en sortie (une fin reçue trop tôt reste valable)
func jouer_tour(_joueur: Node, _sol: TileMapLayer) -> void:
	while not _fin_tour_recue and is_inside_tree():
		var cm := get_tree().current_scene.get_node_or_null("CombatManager")
		if cm == null or not bool(cm.get("en_combat")):
			_fin_tour_recue = false
			return
		await get_tree().process_frame
	_fin_tour_recue = false

# le réseau annonce la fin du tour distant
func terminer_tour_distant() -> void:
	_fin_tour_recue = true

# rejoue le trajet envoyé par le réseau sur notre propre grille
# (chaque étape arrive sous forme [x, y]) ; chaque pas oriente le
# sprite vers sa direction de marche
func rejouer_trajet(trajet: Array, sol: TileMapLayer) -> void:
	arreter_deplacement_combat()
	if trajet.is_empty() or sol == null:
		return
	_deplacement = create_tween()
	for etape_brute in trajet:
		var coordonnee := Vector2i(int(etape_brute[0]), int(etape_brute[1]))
		var position_etape := sol.to_global(sol.map_to_local(coordonnee))
		_deplacement.tween_callback(func():
			_ligne = _ligne_cardinale(position_etape - global_position))
		_deplacement.tween_property(self, "global_position", position_etape, 0.12)

func arreter_deplacement_combat() -> void:
	if _deplacement != null:
		_deplacement.kill()
		_deplacement = null

func est_distant() -> bool:
	return true
