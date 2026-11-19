extends Node2D

# Entité miroir d'un joueur distant pendant un duel : ses actions
# arrivent par le réseau (relais du serveur) et sont rejouées ici, sur
# notre propre grille d'arène. Ses pv ne sont qu'une image : les valeurs
# vraies vivent chez son propriétaire, qui annonce sa défaite lui-même.

signal sante_modifiee(vie: int, vie_max: int)

const TEXTURE := preload("res://assets/sprites/humain_pirate/humain_pirate_idle.png")

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

var _sprite: Sprite2D
var _etiquette: Label
var _deplacement: Tween
var _fin_tour_recue := false

func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.texture = TEXTURE
	add_child(_sprite)
	_etiquette = Label.new()
	_etiquette.text = nom
	_etiquette.position = Vector2(-40, -58)
	_etiquette.custom_minimum_size = Vector2(128, 0)
	_etiquette.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_etiquette.add_theme_font_size_override("font_size", 12)
	_etiquette.add_theme_color_override("font_color", Color("#ff6b6b"))
	_etiquette.add_theme_color_override("font_shadow_color", Color.BLACK)
	_etiquette.add_theme_constant_override("shadow_offset_x", 1)
	_etiquette.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_etiquette)

# profil envoyé par l'adversaire (pv réels, stats, sorts affichés)
func appliquer_profil(profil: Dictionary) -> void:
	nom = str(profil.get("pseudo", nom))
	pv_max = maxi(int(profil.get("pv_max", pv_max)), 1)
	pv = clampi(int(profil.get("pv", pv)), 0, pv_max)
	degats_attaque = int(profil.get("attaque", degats_attaque))
	defense_pvp = int(profil.get("defense", defense_pvp))
	pa_max = int(profil.get("pa_max", pa_max))
	pm_max = int(profil.get("pm_max", pm_max))
	sorts_noms = profil.get("sorts", [])
	_etiquette.text = nom
	sante_modifiee.emit(pv, pv_max)

func recevoir_degats(montant: int) -> void:
	pv = maxi(pv - maxi(montant, 0), 0)
	sante_modifiee.emit(pv, pv_max)
	# pas de fin automatique : le propriétaire des pv annonce sa
	# défaite lui-même (les pv ici ne sont qu'une image)

func soigner(montant: int) -> void:
	pv = mini(pv + maxi(montant, 0), pv_max)
	sante_modifiee.emit(pv, pv_max)

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
# (chaque étape arrive sous forme [x, y])
func rejouer_trajet(trajet: Array, sol: TileMapLayer) -> void:
	arreter_deplacement_combat()
	if trajet.is_empty() or sol == null:
		return
	_deplacement = create_tween()
	for etape_brute in trajet:
		var coordonnee := Vector2i(int(etape_brute[0]), int(etape_brute[1]))
		_deplacement.tween_property(self, "global_position",
			sol.to_global(sol.map_to_local(coordonnee)), 0.12)

func arreter_deplacement_combat() -> void:
	if _deplacement != null:
		_deplacement.kill()
		_deplacement = null

func est_distant() -> bool:
	return true
