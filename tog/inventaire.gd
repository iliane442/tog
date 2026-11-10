# inventaire.gd — autoload
extends Node

var objets: Dictionary = {}  # id -> quantité

# Noms affichés dans l'inventaire (déclarez vos objets ici)
var noms: Dictionary = {
	"potion": "Potion de soin",
	"epee": "Épée",
}

signal inventaire_modifie

func _ready() -> void:
	if BaseDonnees.disponible:
		charger_noms_depuis_base()
	_ajouter_objets_depart()

func _ajouter_objets_depart() -> void:
	# Objets de départ pour tester le menu — ids de la table `items`
	ajouter_objet("12", 3)  # Potion de soin
	ajouter_objet("1", 1)   # Épée en bois
	ajouter_objet("3", 1)   # Katana

# remet l'inventaire aux objets de départ (réinitialisation debug du perso)
func reinitialiser() -> void:
	objets.clear()
	inventaire_modifie.emit()
	_ajouter_objets_depart()

func charger_noms_depuis_base() -> void:
	noms.clear()
	for ligne in BaseDonnees.lire("SELECT id, name FROM items;"):
		noms[str(ligne["id"])] = ligne["name"]

func ajouter_objet(id: String, quantite: int = 1) -> void:
	objets[id] = objets.get(id, 0) + quantite
	inventaire_modifie.emit()

func retirer_objet(id: String, quantite: int = 1) -> void:
	if not objets.has(id):
		return
	objets[id] -= quantite
	if objets[id] <= 0:
		objets.erase(id)
	inventaire_modifie.emit()

func nom_objet(id: String) -> String:
	return noms.get(id, id)
