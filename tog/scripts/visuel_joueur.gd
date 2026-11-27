extends RefCounted

const ECHELLE_GEANT := 2.5
const ANCRE_JOUEUR_Y := -24.0
# Dans une case de 96 px, le bas de la silhouette est à 91 px.
const PIEDS_DANS_CASE := 91.0 - 48.0

static func appliquer_gabarit(sprite: Sprite2D, prefixe: String, ancre_normale: float = ANCRE_JOUEUR_Y) -> void:
	var geant := prefixe.begins_with("geant_") or prefixe.begins_with("geante_")
	var echelle := ECHELLE_GEANT if geant else 1.0
	sprite.scale = Vector2.ONE * echelle
	sprite.position.y = ANCRE_JOUEUR_Y - PIEDS_DANS_CASE * (echelle - 1.0) if geant else ancre_normale
