extends Node
# serveur_monde : point d'entrée du serveur dédié. Lancement :
#   godot --headless --path . scenes/serveur_monde.tscn
# Écoute via l'autoload Reseau (comptes, persos, positions, chat).

func _ready() -> void:
	var port := Reseau.PORT_DEFAUT
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0].is_valid_int():
		port = int(args[0])
	if not Reseau.demarrer_serveur(port):
		get_tree().quit(1)
	print("Tape Ctrl+C pour arrêter le serveur.")
