extends Node
# Touches : les raccourcis clavier du jeu, configurables depuis le
# panneau du même nom (barre de navigation) et sauvegardés dans
# user://touches.cfg pour survivre aux relancements

signal touches_modifiees

const CHEMIN_CFG := "user://touches.cfg"
const SECTION := "touches"

# actions bindables, dans l'ordre d'affichage du panneau
var actions: Dictionary = {
	"sort_1": "Sort - emplacement 1",
	"sort_2": "Sort - emplacement 2",
	"sort_3": "Sort - emplacement 3",
	"sort_4": "Sort - emplacement 4",
	"sort_5": "Sort - emplacement 5",
	"sort_6": "Sort - emplacement 6",
	"sort_7": "Sort - emplacement 7",
	"sort_8": "Sort - emplacement 8",
	"sort_9": "Sort - emplacement 9",
	"sort_10": "Sort - emplacement 10",
	"fin_tour": "Fin du tour / valider le placement",
	"cible_suivante": "Cible suivante",
	"cible_precedente": "Cible précédente",
}

# touches par défaut (Keycodes Godot)
var _defauts: Dictionary = {
	"sort_1": KEY_1,
	"sort_2": KEY_2,
	"sort_3": KEY_3,
	"sort_4": KEY_4,
	"sort_5": KEY_5,
	"sort_6": KEY_6,
	"sort_7": KEY_7,
	"sort_8": KEY_8,
	"sort_9": KEY_9,
	"sort_10": KEY_0,
	"fin_tour": KEY_ENTER,
	"cible_suivante": KEY_TAB,
	"cible_precedente": KEY_LEFT,
}

# action -> keycode courant
var _touches: Dictionary = {}

func _ready() -> void:
	charger()

# charge touches.cfg (les touches manquantes gardent leur défaut)
func charger() -> void:
	_touches = {}
	var cfg := ConfigFile.new()
	var erreur := cfg.load(CHEMIN_CFG)
	for action in actions:
		var defaut: int = int(_defauts.get(action, KEY_NONE))
		var valeur: int = defaut if erreur != OK else int(cfg.get_value(SECTION, action, defaut))
		_touches[action] = valeur
	# migration : valider le placement et fin du tour partagent désormais
	# la même touche ; une ancienne config qui n'avait personnalisé que
	# « valider_placement » reporte sa touche sur « fin_tour »
	if erreur == OK \
			and not cfg.has_section_key(SECTION, "fin_tour") \
			and cfg.has_section_key(SECTION, "valider_placement"):
		_touches["fin_tour"] = int(cfg.get_value(SECTION, "valider_placement", _defauts["fin_tour"]))

func sauvegarder() -> void:
	var cfg := ConfigFile.new()
	for action in _touches:
		cfg.set_value(SECTION, action, int(_touches[action]))
	cfg.save(CHEMIN_CFG)

# le keycode actuellement bindé sur une action
func touche(action: String) -> int:
	if not _touches.has(action):
		_touches[action] = int(_defauts.get(action, KEY_NONE))
	return int(_touches[action])

# assigne une action à une touche (et purge les autres actions qui
# l'utilisaient : une touche = une action)
func definir(action: String, keycode: int) -> void:
	if not actions.has(action):
		return
	for autre in _touches:
		if autre != action and int(_touches[autre]) == keycode:
			_touches[autre] = KEY_NONE
	_touches[action] = keycode
	sauvegarder()
	touches_modifiees.emit()

func reinitialiser() -> void:
	_touches = {}
	for action in actions:
		_touches[action] = int(_defauts.get(action, KEY_NONE))
	sauvegarder()
	touches_modifiees.emit()

# l'action bindée sur un événement clavier ("" si aucune)
func action_de_evenement(evenement: InputEvent) -> String:
	if not (evenement is InputEventKey) or not evenement.pressed or evenement.echo:
		return ""
	if evenement.keycode == KEY_NONE or evenement.keycode == KEY_ESCAPE:
		return ""
	for action in _touches:
		if int(_touches[action]) == evenement.keycode:
			return str(action)
	for action in actions:
		if not _touches.has(action) and int(_defauts.get(action, KEY_NONE)) == evenement.keycode:
			return str(action)
	return ""

# le libellé affichable d'une touche ("Entrée", "Tab", "1"...)
func libelle(keycode: int) -> String:
	if keycode == KEY_NONE:
		return "aucune"
	var evenement := InputEventKey.new()
	evenement.keycode = keycode as Key
	return evenement.as_text().strip_edges()

# le libellé de la touche bindée sur une action
func libelle_action(action: String) -> String:
	return libelle(touche(action))
