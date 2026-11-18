# croix_tresor.gd — croix cliquable marquant l'emplacement d'un trésor
#
# Dessinée entièrement en code (deux diagonales + halo) à la couleur de
# la rareté de la carte qui l'a plantée. Cliquer la croix décerne le
# trésor (voir l'autoload CartesTresor) et la fait disparaître.
extends Area2D

# case de sol où la croix est plantée
var case_sol := Vector2i.ZERO
# niveau du trésor (rareté de la carte), 1 à 4
var rarete := 1

const COULEURS := {
	1: Color(0.85, 0.85, 0.75),
	2: Color(0.0, 0.55, 1.0),
	3: Color(0.55, 0.0, 1.0),
	4: Color(1.0, 0.84, 0.0),
}
const BRAS := 13.0     # demi-longueur des diagonales
const EPAISSEUR := 5.0
const RAYON := 24.0    # rayon cliquable

func _ready() -> void:
	input_pickable = true
	add_to_group("croix_tresor")
	z_index = 50
	rarete = clampi(rarete, 1, 4)
	_construire_dessin()
	_construire_collision()
	# pop d'apparition, puis léger battement pour attirer l'œil
	scale = Vector2.ZERO
	var arrivee := create_tween()
	arrivee.tween_property(self, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var battement := create_tween()
	battement.set_loops()
	battement.tween_property(self, "scale", Vector2(1.15, 1.15), 0.7).set_trans(Tween.TRANS_SINE)
	battement.tween_property(self, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_SINE)

# deux diagonales (contour puis couleur) forment la croix
func _construire_dessin() -> void:
	for paire in [[Vector2(-BRAS, -BRAS), Vector2(BRAS, BRAS)], [Vector2(-BRAS, BRAS), Vector2(BRAS, -BRAS)]]:
		var contour := _trait(paire, COULEURS[rarete].darkened(0.6), EPAISSEUR + 3.0)
		add_child(contour)
		var diagonale := _trait(paire, COULEURS[rarete], EPAISSEUR)
		add_child(diagonale)
	# halo circulaire discret autour de la croix
	var halo := Line2D.new()
	halo.width = 2.0
	halo.default_color = Color(COULEURS[rarete].r, COULEURS[rarete].g, COULEURS[rarete].b, 0.55)
	halo.closed = true
	var points := PackedVector2Array()
	for i in range(18):
		var angle := TAU * i / 18.0
		points.append(Vector2.from_angle(angle) * (BRAS + 7.0))
	halo.points = points
	add_child(halo)

func _trait(paire: Array, couleur: Color, largeur: float) -> Line2D:
	var ligne := Line2D.new()
	ligne.width = largeur
	ligne.default_color = couleur
	ligne.begin_cap_mode = Line2D.LINE_CAP_ROUND
	ligne.end_cap_mode = Line2D.LINE_CAP_ROUND
	ligne.points = PackedVector2Array([paire[0], paire[1]])
	return ligne

func _construire_collision() -> void:
	var forme := CollisionShape2D.new()
	var cercle := CircleShape2D.new()
	cercle.radius = RAYON
	forme.shape = cercle
	add_child(forme)

func _input_event(viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	viewport.set_input_as_handled()
	CartesTresor.fouiller(case_sol)
