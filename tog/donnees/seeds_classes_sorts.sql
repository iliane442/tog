-- Réorganise les sorts de classe : 2 sorts de base + 5 sorts débloqués
-- par le niveau (palier 5, 10, 20, 35, 50) pour chacune des 16 classes.
--
-- Logique suivie :
--   - les sorts Gomu Gomu (3-5) quittent les classes : ce sont les
--     pouvoirs du Fruit du Caoutchouc (table fruit_skills) et ils
--     n'avaient rien à faire chez un Épéiste ou un Archer ;
--   - chaque classe garde Coup Simple (1) comme attaque de base, plus
--     UN sort signature de sa spécialité ;
--   - les sorts orphelins (18-34, jamais utilisés) sont répartis selon
--     la saveur de chaque classe : répétition possible entre classes,
--     à des paliers différents.
--
-- Mécanique :
--   - starting_skills_json = les 2 sorts de base (affichés à la création,
--     placés dans la barre de combat par Personnage.creer) ;
--   - table class_skills (class_id, skill_id, unlock_level) = les 5
--     sorts progressifs, filtrés par Personnage.sorts_de_classe() selon
--     le niveau du personnage.
--
-- Exécution :  sqlite3 donnees/glo.db < donnees/seeds_classes_sorts.sql
--
-- Idempotent : la table est en IF NOT EXISTS, les INSERT en OR IGNORE,
-- les UPDATE de starting_skills_json sont déterministes.

PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS class_skills (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  class_id INTEGER NOT NULL,
  skill_id INTEGER NOT NULL,
  unlock_level INTEGER NOT NULL,
  FOREIGN KEY (class_id) REFERENCES character_classes(id),
  FOREIGN KEY (skill_id) REFERENCES skills(id),
  UNIQUE (class_id, skill_id)
);

-- ------------------------------------------------------------------
-- 1. Sorts de base (2 par classe : Coup Simple + signature)
-- ------------------------------------------------------------------
--    1  Épéiste      : tranchant        9  Forgeron     : rage martelée
--    2  Archer       : illusion/vue    10  Charpentier  : impact marteau
--    3  Canonnier    : onde d'explosion 11 Cuisinier    : brûlure
--    4  Samouraï     : tranchant       12 Sabreur      : haki
--    5  Médecin      : soin            13 Tireur       : projectile sombre
--    6  Infirmière   : soin            14 Combattant   : rage
--    7  Navigateur   : tempête         15 Archéologue  : savoir (faiblesse)
--    8  Timonier     : bouclier        16 Musicien     : voile sonore
-- ------------------------------------------------------------------
UPDATE character_classes SET starting_skills_json = '[1, 7]'  WHERE id = 1;   -- Épéiste : ShakuShaku
UPDATE character_classes SET starting_skills_json = '[1, 9]'  WHERE id = 2;   -- Archer : Mirage Tempo
UPDATE character_classes SET starting_skills_json = '[1, 25]' WHERE id = 3;   -- Canonnier : Onde de choc
UPDATE character_classes SET starting_skills_json = '[1, 7]'  WHERE id = 4;   -- Samouraï : ShakuShaku
UPDATE character_classes SET starting_skills_json = '[1, 10]' WHERE id = 5;   -- Médecin : Soin Mineur
UPDATE character_classes SET starting_skills_json = '[1, 10]' WHERE id = 6;   -- Infirmière : Soin Mineur
UPDATE character_classes SET starting_skills_json = '[1, 16]' WHERE id = 7;   -- Navigateur : Tempête
UPDATE character_classes SET starting_skills_json = '[1, 12]' WHERE id = 8;   -- Timonier : Bouclier
UPDATE character_classes SET starting_skills_json = '[1, 13]' WHERE id = 9;   -- Forgeron : Furie
UPDATE character_classes SET starting_skills_json = '[1, 18]' WHERE id = 10;  -- Charpentier : Fracas
UPDATE character_classes SET starting_skills_json = '[1, 20]' WHERE id = 11;  -- Cuisinier : Flamme vive
UPDATE character_classes SET starting_skills_json = '[1, 6]'  WHERE id = 12;  -- Sabreur : Haki du Roi
UPDATE character_classes SET starting_skills_json = '[1, 8]'  WHERE id = 13;  -- Tireur : Kuro Kabuto
UPDATE character_classes SET starting_skills_json = '[1, 13]' WHERE id = 14;  -- Combattant : Furie
UPDATE character_classes SET starting_skills_json = '[1, 34]' WHERE id = 15;  -- Archéologue : Marque de faiblesse
UPDATE character_classes SET starting_skills_json = '[1, 27]' WHERE id = 16;  -- Musicien : Voile invisible

-- ------------------------------------------------------------------
-- 2. Sorts débloquables par niveau (5 par classe, paliers 5/10/20/35/50)
-- ------------------------------------------------------------------
INSERT OR IGNORE INTO class_skills (class_id, skill_id, unlock_level) VALUES
  -- Épéiste : fracas du taureau, coup ajusté, haki, tranche d'acier, ouverture mortelle
  (1, 18, 5), (1, 33, 10), (1, 6, 20), (1, 31, 35), (1, 34, 50),
  -- Archer : entrave, oeil du tireur, flèche foudroyante, présage, retombée gravitationnelle
  (2, 22, 5), (2, 32, 10), (2, 15, 20), (2, 33, 35), (2, 26, 50),
  -- Canonnier : tir dispersé, poudre à canon, gravité, flash, fracas
  (3, 16, 5), (3, 20, 10), (3, 26, 20), (3, 23, 35), (3, 18, 50),
  -- Samouraï : présage, haki, peau de pierre, garde, marque
  (4, 33, 5), (4, 6, 10), (4, 31, 20), (4, 12, 35), (4, 34, 50),
  -- Médecin : pansement, soin majeur, diagnostics (venin), égide, souffle vital
  (5, 12, 5), (5, 11, 10), (5, 19, 20), (5, 28, 35), (5, 29, 50),
  -- Infirmière : pansement, souffle vital, soin majeur, voile, égide
  (6, 12, 5), (6, 29, 10), (6, 11, 20), (6, 27, 35), (6, 28, 50),
  -- Navigateur : entrave, éclat, onde de choc, prison de givre, rappel gravitationnel
  (7, 22, 5), (7, 23, 10), (7, 25, 20), (7, 21, 35), (7, 26, 50),
  -- Timonier : onde de choc, peau de pierre, fracas, égide, présage
  (8, 25, 5), (8, 31, 10), (8, 18, 20), (8, 28, 35), (8, 33, 50),
  -- Forgeron : flamme de forge, peau de pierre, bouclier forgé, coup ajusté, fracas
  (9, 20, 5), (9, 31, 10), (9, 12, 20), (9, 33, 35), (9, 18, 50),
  -- Charpentier : onde de choc, furie, planches (bouclier), peau de pierre, éclat
  (10, 25, 5), (10, 13, 10), (10, 12, 20), (10, 31, 35), (10, 23, 50),
  -- Cuisinier : furie, saumure (souffle vital), plat revigorant, couteaux empoisonnés, entrave
  (11, 13, 5), (11, 29, 10), (11, 10, 20), (11, 19, 35), (11, 22, 50),
  -- Sabreur : fracas, présage, peau de pierre, marque, bouclier
  (12, 18, 5), (12, 33, 10), (12, 31, 20), (12, 34, 35), (12, 12, 50),
  -- Tireur : oeil du tireur, entrave, présage, flash, foudre
  (13, 32, 5), (13, 22, 10), (13, 33, 20), (13, 23, 35), (13, 15, 50),
  -- Combattant : fracas, présage, haki, peau de pierre, bouclier
  (14, 18, 5), (14, 33, 10), (14, 6, 20), (14, 31, 35), (14, 12, 50),
  -- Archéologue : ère glaciaire, sceau du silence, prison de givre, mains qui jaillissent (entrave), rappel gravitationnel
  (15, 14, 5), (15, 24, 10), (15, 21, 20), (15, 22, 35), (15, 26, 50),
  -- Musicien : onde sonore, entrave, éclat aveuglant, chant revitalisant, silence de la mort
  (16, 25, 5), (16, 22, 10), (16, 23, 20), (16, 29, 35), (16, 24, 50);
