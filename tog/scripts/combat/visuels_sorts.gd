extends RefCounted

enum Trajet { LOCAL, ESTOC, PROJECTILE, SALVE, RAYON, CHUTE, VAGUE, POING, CHUTE_POING, COMETE, ORBE }
enum Impact {
	TAILLE, FRAPPE, EXPLOSION, ONDE, PRISON, VORTEX, AURA, SOINS,
	GARDE, SCEAU, OEIL, FLEURS, TOILE, NOTES, METEO, FAILLE, PHENIX, ARMEMENT, CAGE
}

# Cœur lumineux, matière et contour. Les teintes sont communes aux pouvoirs
# d'un même fruit et la trajectoire, le rythme et l'impact distinguent ses sorts.
const PALETTES := {
	"acier": [Color("#fff5e0"), Color("#a5d7e3"), Color("#3d5570")],
	"ambre": [Color("#fff2ac"), Color("#edaa57"), Color("#8e3d29")],
	"feu": [Color("#fff1a2"), Color("#ff8a37"), Color("#9f2637")],
	"magma": [Color("#ffec94"), Color("#f5542b"), Color("#542338")],
	"caoutchouc": [Color("#fff0be"), Color("#edaa78"), Color("#98583d")],
	"gear": [Color("#ffffee"), Color("#cee5ff"), Color("#7672b3")],
	"foudre": [Color("#ffffd9"), Color("#ffe36f"), Color("#6b50ac")],
	"glace": [Color("#f0ffff"), Color("#72dfff"), Color("#2671a9")],
	"leopard": [Color("#ffe8ac"), Color("#d58e50"), Color("#76383b")],
	"ombre": [Color("#ebc9ff"), Color("#9561df"), Color("#281942")],
	"ope": [Color("#eaffef"), Color("#6ceccc"), Color("#237482")],
	"lumiere": [Color("#ffffe3"), Color("#ffe389"), Color("#ac7047")],
	"rose": [Color("#fff2f1"), Color("#f59ac3"), Color("#87376e")],
	"sable": [Color("#fff1bd"), Color("#d7a26c"), Color("#79523c")],
	"fumee": [Color("#edfaff"), Color("#aec2cd"), Color("#4f4c67")],
	"seisme": [Color("#f5fdff"), Color("#a4b6ff"), Color("#4e5389")],
	"poison": [Color("#f0ffc0"), Color("#a6d660"), Color("#56316b")],
	"venin": [Color("#f5daff"), Color("#c680ec"), Color("#572861")],
	"fils": [Color("#fff5f9"), Color("#f5b6cb"), Color("#8c536c")],
	"phenix": [Color("#fff4bc"), Color("#44e4ff"), Color("#3364b0")],
	"haki": [Color("#fff2e4"), Color("#ec5365"), Color("#291d3b")],
	"armement": [Color("#ffedc9"), Color("#a69ecb"), Color("#27243a")],
	"vent": [Color("#edfff4"), Color("#76ebd5"), Color("#36808e")],
	"soin": [Color("#faffd5"), Color("#8deba1"), Color("#397a61")],
	"chant": [Color("#fff7c6"), Color("#bc9cf5"), Color("#564b9d")],
	"bois": [Color("#ffe8bd"), Color("#c79358"), Color("#674637")],
	"pierre": [Color("#fff4c3"), Color("#baac9b"), Color("#635062")],
}

# Départ, impact, palette, nombre de frappes ou de motifs, amplitude.
const SORTS := {
	0: [Trajet.ORBE, Impact.EXPLOSION, "feu", 1, 0.94], # Boule de feu
	1: [Trajet.ESTOC, Impact.TAILLE, "acier", 1, 0.74], # Coup simple
	2: [Trajet.ORBE, Impact.EXPLOSION, "magma", 1, 1.18], # Buggy Ball
	6: [Trajet.VAGUE, Impact.ONDE, "haki", 3, 1.22],
	7: [Trajet.ESTOC, Impact.TAILLE, "glace", 2, 0.90],
	8: [Trajet.PROJECTILE, Impact.FRAPPE, "ombre", 1, 0.92],
	9: [Trajet.LOCAL, Impact.VORTEX, "vent", 3, 0.84],
	10: [Trajet.LOCAL, Impact.SOINS, "soin", 2, 0.75],
	11: [Trajet.LOCAL, Impact.SOINS, "soin", 4, 1.03],
	12: [Trajet.LOCAL, Impact.GARDE, "ambre", 2, 0.88],
	13: [Trajet.LOCAL, Impact.AURA, "feu", 3, 0.92],
	14: [Trajet.LOCAL, Impact.PRISON, "glace", 3, 0.80],
	15: [Trajet.CHUTE, Impact.FRAPPE, "foudre", 1, 1.00],
	16: [Trajet.VAGUE, Impact.VORTEX, "vent", 3, 1.03],
	17: [Trajet.LOCAL, Impact.VORTEX, "ombre", 3, 0.86],
	18: [Trajet.CHUTE, Impact.FAILLE, "pierre", 2, 0.96],
	19: [Trajet.VAGUE, Impact.AURA, "poison", 3, 0.87],
	20: [Trajet.PROJECTILE, Impact.AURA, "feu", 1, 0.82],
	21: [Trajet.LOCAL, Impact.PRISON, "glace", 6, 1.02],
	22: [Trajet.VAGUE, Impact.TOILE, "vent", 3, 0.76],
	23: [Trajet.SALVE, Impact.OEIL, "lumiere", 3, 0.81],
	24: [Trajet.LOCAL, Impact.SCEAU, "ombre", 4, 0.98],
	25: [Trajet.VAGUE, Impact.ONDE, "vent", 2, 0.93],
	26: [Trajet.RAYON, Impact.VORTEX, "ombre", 2, 1.02],
	27: [Trajet.LOCAL, Impact.VORTEX, "fumee", 2, 0.72],
	28: [Trajet.LOCAL, Impact.GARDE, "lumiere", 3, 1.00],
	29: [Trajet.LOCAL, Impact.SOINS, "vent", 3, 0.93],
	31: [Trajet.LOCAL, Impact.GARDE, "pierre", 2, 0.83],
	32: [Trajet.LOCAL, Impact.OEIL, "lumiere", 2, 0.76],
	33: [Trajet.LOCAL, Impact.SCEAU, "chant", 5, 0.84],
	34: [Trajet.LOCAL, Impact.SCEAU, "haki", 3, 0.95],

	# Caoutchouc
	3: [Trajet.POING, Impact.FRAPPE, "caoutchouc", 1, 0.92],
	4: [Trajet.POING, Impact.ONDE, "caoutchouc", 1, 1.06],
	5: [Trajet.POING, Impact.EXPLOSION, "caoutchouc", 2, 1.08],
	130: [Trajet.POING, Impact.FRAPPE, "caoutchouc", 6, 1.04],
	132: [Trajet.CHUTE_POING, Impact.FAILLE, "gear", 3, 1.42],
	# Flamme
	100: [Trajet.POING, Impact.EXPLOSION, "feu", 1, 1.00],
	101: [Trajet.CHUTE, Impact.EXPLOSION, "feu", 3, 1.17],
	133: [Trajet.POING, Impact.ONDE, "feu", 2, 1.20],
	134: [Trajet.SALVE, Impact.METEO, "feu", 6, 0.95],
	135: [Trajet.VAGUE, Impact.EXPLOSION, "feu", 5, 1.36],
	# Foudre
	102: [Trajet.RAYON, Impact.FRAPPE, "foudre", 1, 0.94],
	103: [Trajet.CHUTE, Impact.ONDE, "foudre", 3, 1.19],
	136: [Trajet.ESTOC, Impact.TAILLE, "foudre", 2, 0.88],
	137: [Trajet.CHUTE, Impact.METEO, "foudre", 6, 1.10],
	138: [Trajet.COMETE, Impact.EXPLOSION, "foudre", 5, 1.41],
	# Glace
	104: [Trajet.PROJECTILE, Impact.PRISON, "glace", 2, 0.99],
	105: [Trajet.VAGUE, Impact.PRISON, "glace", 6, 1.20],
	139: [Trajet.ESTOC, Impact.TAILLE, "glace", 1, 0.94],
	140: [Trajet.CHUTE, Impact.METEO, "glace", 5, 1.04],
	141: [Trajet.VAGUE, Impact.PRISON, "glace", 9, 1.39],
	# Léopard
	106: [Trajet.ESTOC, Impact.TAILLE, "leopard", 3, 0.95],
	107: [Trajet.LOCAL, Impact.AURA, "leopard", 3, 0.92],
	142: [Trajet.POING, Impact.TAILLE, "leopard", 2, 0.95],
	143: [Trajet.ESTOC, Impact.TAILLE, "leopard", 4, 1.06],
	144: [Trajet.LOCAL, Impact.AURA, "leopard", 6, 1.38],
	# Ténèbres
	108: [Trajet.LOCAL, Impact.VORTEX, "ombre", 2, 1.01],
	109: [Trajet.VAGUE, Impact.VORTEX, "ombre", 4, 1.09],
	145: [Trajet.LOCAL, Impact.OEIL, "ombre", 2, 0.87],
	146: [Trajet.CHUTE, Impact.VORTEX, "ombre", 3, 0.95],
	147: [Trajet.LOCAL, Impact.VORTEX, "ombre", 6, 1.42],
	# Bistouri
	110: [Trajet.ESTOC, Impact.TAILLE, "ope", 1, 0.86],
	111: [Trajet.RAYON, Impact.TAILLE, "ope", 2, 1.10],
	148: [Trajet.RAYON, Impact.SCEAU, "ope", 4, 0.96],
	149: [Trajet.ESTOC, Impact.TAILLE, "ope", 3, 1.01],
	150: [Trajet.RAYON, Impact.PRISON, "ope", 5, 1.40],
	# Lumière
	112: [Trajet.SALVE, Impact.FRAPPE, "lumiere", 4, 1.01],
	113: [Trajet.CHUTE, Impact.TAILLE, "lumiere", 2, 1.11],
	151: [Trajet.LOCAL, Impact.GARDE, "lumiere", 2, 0.85],
	152: [Trajet.SALVE, Impact.METEO, "lumiere", 7, 1.18],
	153: [Trajet.RAYON, Impact.TAILLE, "lumiere", 4, 1.39],
	# Magma
	114: [Trajet.POING, Impact.EXPLOSION, "magma", 1, 1.08],
	115: [Trajet.LOCAL, Impact.PRISON, "magma", 4, 1.08],
	154: [Trajet.VAGUE, Impact.EXPLOSION, "magma", 2, 1.11],
	155: [Trajet.CHUTE, Impact.METEO, "magma", 5, 1.15],
	156: [Trajet.COMETE, Impact.EXPLOSION, "magma", 6, 1.42],
	# Fleurs
	116: [Trajet.LOCAL, Impact.FLEURS, "rose", 4, 0.91],
	117: [Trajet.SALVE, Impact.FLEURS, "rose", 6, 1.06],
	157: [Trajet.POING, Impact.FLEURS, "rose", 6, 0.96],
	158: [Trajet.VAGUE, Impact.FLEURS, "venin", 3, 0.91],
	159: [Trajet.LOCAL, Impact.FLEURS, "rose", 9, 1.39],
	# Sable
	118: [Trajet.SALVE, Impact.OEIL, "sable", 4, 0.89],
	119: [Trajet.LOCAL, Impact.PRISON, "sable", 5, 1.11],
	160: [Trajet.ESTOC, Impact.TAILLE, "sable", 2, 0.98],
	161: [Trajet.VAGUE, Impact.VORTEX, "sable", 4, 1.04],
	162: [Trajet.VAGUE, Impact.FAILLE, "sable", 6, 1.39],
	# Fumée
	120: [Trajet.PROJECTILE, Impact.FRAPPE, "fumee", 1, 0.89],
	121: [Trajet.VAGUE, Impact.VORTEX, "fumee", 3, 1.09],
	163: [Trajet.LOCAL, Impact.GARDE, "fumee", 3, 0.94],
	164: [Trajet.RAYON, Impact.TOILE, "fumee", 3, 0.96],
	165: [Trajet.VAGUE, Impact.PRISON, "fumee", 7, 1.38],
	# Séisme
	122: [Trajet.ESTOC, Impact.FAILLE, "seisme", 2, 0.92],
	123: [Trajet.CHUTE, Impact.FAILLE, "seisme", 4, 1.12],
	166: [Trajet.LOCAL, Impact.FAILLE, "seisme", 3, 0.91],
	167: [Trajet.VAGUE, Impact.ONDE, "seisme", 4, 1.11],
	168: [Trajet.VAGUE, Impact.FAILLE, "seisme", 8, 1.42],
	# Poison
	124: [Trajet.VAGUE, Impact.AURA, "venin", 3, 0.97],
	125: [Trajet.SALVE, Impact.PRISON, "venin", 3, 1.09],
	169: [Trajet.PROJECTILE, Impact.TOILE, "poison", 2, 0.90],
	170: [Trajet.LOCAL, Impact.AURA, "poison", 5, 1.10],
	171: [Trajet.VAGUE, Impact.PRISON, "venin", 7, 1.41],
	# Fils
	126: [Trajet.RAYON, Impact.TOILE, "fils", 4, 0.91],
	127: [Trajet.SALVE, Impact.TAILLE, "fils", 4, 1.07],
	172: [Trajet.LOCAL, Impact.TOILE, "fils", 6, 0.98],
	173: [Trajet.RAYON, Impact.VORTEX, "fils", 3, 1.09],
	174: [Trajet.CHUTE, Impact.CAGE, "fils", 9, 1.42],
	# Phénix
	128: [Trajet.ESTOC, Impact.TAILLE, "phenix", 3, 0.96],
	129: [Trajet.LOCAL, Impact.PHENIX, "phenix", 4, 1.12],
	175: [Trajet.LOCAL, Impact.AURA, "phenix", 4, 1.00],
	176: [Trajet.SALVE, Impact.METEO, "phenix", 4, 1.04],
	177: [Trajet.LOCAL, Impact.PHENIX, "phenix", 7, 1.40],
	# Haki
	178: [Trajet.LOCAL, Impact.OEIL, "glace", 3, 0.98],
	179: [Trajet.LOCAL, Impact.ARMEMENT, "armement", 4, 1.02],

	# Sabreur
	200: [Trajet.ESTOC, Impact.TAILLE, "acier", 2, 0.83],
	201: [Trajet.LOCAL, Impact.GARDE, "acier", 2, 0.91],
	202: [Trajet.RAYON, Impact.TAILLE, "acier", 1, 0.94],
	203: [Trajet.ESTOC, Impact.FRAPPE, "acier", 3, 1.03],
	204: [Trajet.VAGUE, Impact.TAILLE, "glace", 3, 1.13],
	# Tireur
	205: [Trajet.PROJECTILE, Impact.ONDE, "ambre", 1, 0.82],
	206: [Trajet.PROJECTILE, Impact.OEIL, "lumiere", 1, 0.90],
	207: [Trajet.PROJECTILE, Impact.TOILE, "acier", 3, 0.84],
	208: [Trajet.SALVE, Impact.FRAPPE, "ambre", 2, 0.85],
	209: [Trajet.SALVE, Impact.FRAPPE, "ambre", 6, 1.05],
	# Bosco
	210: [Trajet.ESTOC, Impact.FRAPPE, "caoutchouc", 1, 0.77],
	211: [Trajet.LOCAL, Impact.GARDE, "bois", 2, 0.89],
	212: [Trajet.POING, Impact.FRAPPE, "ambre", 1, 0.92],
	213: [Trajet.POING, Impact.FAILLE, "bois", 2, 0.98],
	214: [Trajet.VAGUE, Impact.ONDE, "acier", 3, 1.10],
	# Médecin
	215: [Trajet.LOCAL, Impact.SOINS, "acier", 2, 0.83],
	216: [Trajet.PROJECTILE, Impact.FRAPPE, "ope", 1, 0.71],
	217: [Trajet.LOCAL, Impact.GARDE, "soin", 3, 0.94],
	218: [Trajet.LOCAL, Impact.SOINS, "ope", 3, 0.93],
	219: [Trajet.LOCAL, Impact.SOINS, "soin", 6, 1.13],
	# Cuisinier
	220: [Trajet.ESTOC, Impact.FRAPPE, "feu", 1, 0.82],
	221: [Trajet.LOCAL, Impact.SOINS, "ambre", 3, 0.83],
	222: [Trajet.VAGUE, Impact.OEIL, "fumee", 4, 0.92],
	223: [Trajet.LOCAL, Impact.AURA, "soin", 4, 0.97],
	224: [Trajet.VAGUE, Impact.EXPLOSION, "feu", 2, 1.06],
	# Musicien
	225: [Trajet.VAGUE, Impact.NOTES, "acier", 2, 0.83],
	226: [Trajet.LOCAL, Impact.NOTES, "chant", 3, 0.91],
	227: [Trajet.LOCAL, Impact.NOTES, "soin", 4, 0.98],
	228: [Trajet.RAYON, Impact.NOTES, "ombre", 5, 1.06],
	229: [Trajet.VAGUE, Impact.NOTES, "vent", 6, 1.16],
	# Charpentier
	230: [Trajet.ESTOC, Impact.FRAPPE, "bois", 2, 0.87],
	231: [Trajet.LOCAL, Impact.GARDE, "bois", 3, 0.90],
	232: [Trajet.PROJECTILE, Impact.PRISON, "bois", 3, 0.85],
	233: [Trajet.VAGUE, Impact.ONDE, "bois", 2, 1.06],
	234: [Trajet.LOCAL, Impact.PRISON, "bois", 5, 1.10],
	# Forgeron
	235: [Trajet.CHUTE, Impact.FRAPPE, "feu", 2, 0.92],
	236: [Trajet.LOCAL, Impact.GARDE, "acier", 3, 1.00],
	237: [Trajet.SALVE, Impact.OEIL, "feu", 5, 0.98],
	238: [Trajet.ESTOC, Impact.TAILLE, "magma", 2, 1.05],
	239: [Trajet.LOCAL, Impact.AURA, "magma", 5, 1.13],
	# Navigateur
	240: [Trajet.VAGUE, Impact.ONDE, "vent", 3, 0.86],
	241: [Trajet.LOCAL, Impact.OEIL, "vent", 3, 0.96],
	242: [Trajet.VAGUE, Impact.VORTEX, "vent", 2, 0.93],
	243: [Trajet.CHUTE, Impact.METEO, "vent", 4, 1.04],
	244: [Trajet.VAGUE, Impact.VORTEX, "vent", 5, 1.19],
	# Archéologue
	245: [Trajet.PROJECTILE, Impact.FAILLE, "pierre", 2, 0.88],
	246: [Trajet.LOCAL, Impact.SCEAU, "pierre", 4, 0.98],
	247: [Trajet.LOCAL, Impact.GARDE, "pierre", 4, 1.05],
	248: [Trajet.LOCAL, Impact.SCEAU, "venin", 5, 1.10],
	249: [Trajet.CHUTE, Impact.PRISON, "pierre", 6, 1.19],
}

static func pour_sort(id: int, type: String, portee: int) -> Array:
	if SORTS.has(id):
		return SORTS[id]
	match type:
		"heal":
			return [Trajet.LOCAL, Impact.SOINS, "soin", 2, 0.90]
		"defense":
			return [Trajet.LOCAL, Impact.GARDE, "acier", 2, 0.90]
		"buff":
			return [Trajet.LOCAL, Impact.AURA, "lumiere", 3, 0.90]
		"control", "debuff":
			return [Trajet.LOCAL, Impact.SCEAU, "ombre", 3, 0.90]
	return [Trajet.PROJECTILE if portee > 2 else Trajet.ESTOC, Impact.FRAPPE, "acier", 1, 0.90]
