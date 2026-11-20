extends RefCounted

const DEFINITIONS := {
	"fushia_pont_roux": {
		"titre": "Le pont du Roux",
		"description": "Fais le tour du navire de Shanks. Examine la proue, la lanterne de quart et la poupe sur le pont.",
		"objectif": 3, "recompense_xp": 90, "recompense_berry": 180,
		"recompenses_objets": [{"item_id": 12, "quantity": 2}],
	},
	"fushia_provisions_dadan": {
		"titre": "Les provisions du mont Corvo",
		"description": "Prends l’escalier au nord du village pour rejoindre le mont Corvo. Cueille trois herbes dans les clairières de la forêt, à l’est du repaire de Dadan.",
		"objectif": 3, "recompense_xp": 125, "recompense_berry": 210,
		"recompenses_objets": [{"item_id": 865, "quantity": 1}],
	},
	"fushia_reperes": {
		"titre": "Les trois repères de Fushia",
		"description": "Lis les panneaux au quai des Voiles, dans le verger des Lucioles et au belvédère du phare.",
		"objectif": 3, "recompense_xp": 75, "recompense_berry": 100,
		"recompenses_objets": [{"item_id": 12, "quantity": 2}],
	},
	"fushia_bois": {
		"titre": "De quoi réparer les pontons",
		"description": "Ramasse cinq morceaux de bois flotté sur les plages, à l’ouest du port et autour de la crique du Levant.",
		"objectif": 5, "recompense_xp": 90, "recompense_berry": 160,
		"recompenses_objets": [{"item_id": 865, "quantity": 1}],
	},
	"fushia_nasses": {
		"titre": "La tournée des nasses",
		"description": "Relève trois nasses à poissons. Tu en trouveras au quai des Voiles et à l’anse des Pêcheurs.",
		"objectif": 3, "recompense_xp": 65, "recompense_berry": 125,
		"recompenses_objets": [{"item_id": 135, "quantity": 3}],
	},
	"fushia_guet": {
		"titre": "Le guet des contrebandiers",
		"description": "Repousse trois guetteurs pirates au camp du nord. Le chemin monte derrière la taverne, entre la forêt et le verger.",
		"objectif": 3, "recompense_xp": 150, "recompense_berry": 260,
		"recompenses_objets": [{"item_id": 866, "quantity": 1}],
	},
	"fushia_fanal": {
		"titre": "Le fanal du cap",
		"description": "Passe le camp du nord et examine le vieux fanal, au pied du phare sur la pointe nord-est.",
		"objectif": 1, "recompense_xp": 110, "recompense_berry": 175,
		"recompenses_objets": [{"item_id": 865, "quantity": 1}],
	},
	"shells_patrouille": {
		"titre": "La patrouille de Morgan",
		"description": "Coby veut redonner du courage à la ville. Repousse les trois hommes de la patrouille de Morgan : deux marins rôdent au nord de la rue du port, leur sergent garde l'entrée de l'esplanade de la base.",
		"objectif": 3, "recompense_xp": 160, "recompense_berry": 260,
		"recompenses_objets": [{"item_id": 2, "quantity": 1}],
	},
	"shells_morgan": {
		"titre": "Le roi de la base",
		"description": "Le capitaine Morgan s'est proclamé roi de Shells Town. Grimpe l'esplanade de la base de la Marine, au nord de la place, et remets-lui son galon à sa place.",
		"objectif": 1, "recompense_xp": 300, "recompense_berry": 500,
		"recompenses_objets": [{"item_id": 866, "quantity": 1}],
	},
	"shells_panneaux": {
		"titre": "Les panneaux de Shells Town",
		"description": "Lise t'a conseillé de lire la ville : le panneau du quai, celui de la place du Marché et celui de l'esplanade de la Marine.",
		"objectif": 3, "recompense_xp": 90, "recompense_berry": 130,
		"recompenses_objets": [{"item_id": 16, "quantity": 2}],
	},
	"shells_ravitaillement": {
		"titre": "Le ravitaillement du port",
		"description": "Morgan réquisitionne tout le fer qui débarque. Collecte trois caisses de ravitaillement sur le quai de Shells Town — Lise saura quel meilleur usage leur donner.",
		"objectif": 3, "recompense_xp": 120, "recompense_berry": 200,
		"recompenses_objets": [{"item_id": 12, "quantity": 2}],
	},
	"orange_vivres": {
		"titre": "Les provisions de Chouchou",
		"description": "Chouchou monte la garde devant sa boutique. Récupère trois paniers de vivres au verger, au sud-est de la place.",
		"objectif": 3, "recompense_xp": 165, "recompense_berry": 240,
		"recompenses_objets": [{"item_id": 12, "quantity": 2}],
	},
	"orange_patrouille": {
		"titre": "Les pirates du chapiteau",
		"description": "Iris a repéré trois pirates qui surveillent la montée du camp, au nord-est de la ville. Mets leur patrouille en déroute.",
		"objectif": 3, "recompense_xp": 245, "recompense_berry": 390,
		"recompenses_objets": [{"item_id": 865, "quantity": 1}],
	},
	"orange_baggy": {
		"titre": "Le dernier numéro de Baggy",
		"description": "Le capitaine pirate s’est installé devant le grand chapiteau, au bout du sentier des falaises. Vaincs Baggy le Clown.",
		"objectif": 1, "recompense_xp": 420, "recompense_berry": 720,
		"recompenses_objets": [{"item_id": 866, "quantity": 1}],
	},
}
