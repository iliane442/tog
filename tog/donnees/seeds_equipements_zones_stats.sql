-- Uniformise les équipements de zones (10 zones x 23 pieces : armes,
-- armures, accessoires).
--
-- Avant : les 230 pieces avaient effects_json vide et base_price a 0 ;
-- leurs decriptions decrivaient un systeme parallele ("+X % de precision
-- maritime", "moral d'equipage"...) sans cle dans le moteur, avec des
-- valeurs faibles (max 28 attaque au niveau 200 quand une lame standard
-- du jeu donne 86 au niveau 96).
--
-- Apres : chaque piece recoit des effets reels alignes sur la courbe du
-- jeu (attack/defense/force/agilite/... proportionnels au min_level,
-- cf. Fusil lvl 55 = 43 attaque, Yoru lvl 95 = 95 attaque), une
-- description qui decrit ces effets reels, et un prix unique :
--   base_price = round(30 * min_level^1.45)
--
-- Exécution :  sqlite3 donnees/glo.db < donnees/seeds_equipements_zones_stats.sql
--
-- Idempotent : UPDATE deterministes (meme formule -> meme valeur), sans
-- clause de rangement : re-executable sans effet de bord.
--
-- Garde : chaque UPDATE ne cible que les pieces dont le nom finit par un
-- suffixe de zone, pour ne jamais toucher les items hors zones
-- (ex. "Boussole de Grand Line instable", "Sabre de la Marine standard").

PRAGMA foreign_keys = ON;

-- ------------------------------------------------------------------
-- Lames (type arme) — reference courbe jeu : attack ~ 0.8x niveau
-- ------------------------------------------------------------------
UPDATE items SET
  effects_json = '{"attack": ' || CAST(round(0.7 * min_level) AS INTEGER) || ', "agilite": ' || MAX(1, CAST(round(min_level / 12.0) AS INTEGER)) || '}',
  description = 'Sabre : +' || CAST(round(0.7 * min_level) AS INTEGER) || ' attaque tranchante et +' || MAX(1, CAST(round(min_level / 12.0) AS INTEGER)) || ' agilité',
  base_price = CAST(round(30 * pow(min_level, 1.45)) AS INTEGER)
WHERE name LIKE 'Sabre %' AND (name LIKE '%Flots Calmes' OR name LIKE '%Récif Chantant' OR name LIKE '%Brume Pourpre' OR name LIKE '%Île Foudre' OR name LIKE '%Grand Courant' OR name LIKE '%Cités Célestes' OR name LIKE '%Volcan Rouge' OR name LIKE '%Profondeurs Royales' OR name LIKE '%Siècle Perdu' OR name LIKE '%Aube Nouvelle');

UPDATE items SET
  effects_json = '{"attack": ' || CAST(round(0.75 * min_level) AS INTEGER) || ', "force": ' || MAX(1, CAST(round(min_level / 10.0) AS INTEGER)) || '}',
  description = 'Katana : +' || CAST(round(0.75 * min_level) AS INTEGER) || ' attaque tranchante et +' || MAX(1, CAST(round(min_level / 10.0) AS INTEGER)) || ' force',
  base_price = CAST(round(30 * pow(min_level, 1.45)) AS INTEGER)
WHERE name LIKE 'Katana %' AND (name LIKE '%Flots Calmes' OR name LIKE '%Récif Chantant' OR name LIKE '%Brume Pourpre' OR name LIKE '%Île Foudre' OR name LIKE '%Grand Courant' OR name LIKE '%Cités Célestes' OR name LIKE '%Volcan Rouge' OR name LIKE '%Profondeurs Royales' OR name LIKE '%Siècle Perdu' OR name LIKE '%Aube Nouvelle');

UPDATE items SET
  effects_json = '{"attack": ' || CAST(round(0.7 * min_level) AS INTEGER) || ', "agilite": ' || MAX(1, CAST(round(min_level / 10.0) AS INTEGER)) || '}',
  description = 'Lame courte : +' || CAST(round(0.7 * min_level) AS INTEGER) || ' attaque tranchante et +' || MAX(1, CAST(round(min_level / 10.0) AS INTEGER)) || ' agilité',
  base_price = CAST(round(30 * pow(min_level, 1.45)) AS INTEGER)
WHERE name LIKE 'Lame courte %' AND (name LIKE '%Flots Calmes' OR name LIKE '%Récif Chantant' OR name LIKE '%Brume Pourpre' OR name LIKE '%Île Foudre' OR name LIKE '%Grand Courant' OR name LIKE '%Cités Célestes' OR name LIKE '%Volcan Rouge' OR name LIKE '%Profondeurs Royales' OR name LIKE '%Siècle Perdu' OR name LIKE '%Aube Nouvelle');

UPDATE items SET
  effects_json = '{"attack": ' || CAST(round(0.8 * min_level) AS INTEGER) || ', "force": ' || MAX(1, CAST(round(min_level / 10.0) AS INTEGER)) || '}',
  description = 'Nodachi : +' || CAST(round(0.8 * min_level) AS INTEGER) || ' attaque tranchante et +' || MAX(1, CAST(round(min_level / 10.0) AS INTEGER)) || ' force',
  base_price = CAST(round(30 * pow(min_level, 1.45)) AS INTEGER)
WHERE name LIKE 'Nodachi %' AND (name LIKE '%Flots Calmes' OR name LIKE '%Récif Chantant' OR name LIKE '%Brume Pourpre' OR name LIKE '%Île Foudre' OR name LIKE '%Grand Courant' OR name LIKE '%Cités Célestes' OR name LIKE '%Volcan Rouge' OR name LIKE '%Profondeurs Royales' OR name LIKE '%Siècle Perdu' OR name LIKE '%Aube Nouvelle');

UPDATE items SET
  effects_json = '{"attack": ' || CAST(round(0.65 * min_level) AS INTEGER) || ', "defense": ' || MAX(1, CAST(round(min_level / 8.0) AS INTEGER)) || '}',
  description = 'Garde-lame : +' || CAST(round(0.65 * min_level) AS INTEGER) || ' attaque tranchante et +' || MAX(1, CAST(round(min_level / 8.0) AS INTEGER)) || ' défense',
  base_price = CAST(round(30 * pow(min_level, 1.45)) AS INTEGER)
WHERE name LIKE 'Garde-lame %' AND (name LIKE '%Flots Calmes' OR name LIKE '%Récif Chantant' OR name LIKE '%Brume Pourpre' OR name LIKE '%Île Foudre' OR name LIKE '%Grand Courant' OR name LIKE '%Cités Célestes' OR name LIKE '%Volcan Rouge' OR name LIKE '%Profondeurs Royales' OR name LIKE '%Siècle Perdu' OR name LIKE '%Aube Nouvelle');

-- ------------------------------------------------------------------
-- Armes de corps a corps et de tir (type arme)
-- ------------------------------------------------------------------
UPDATE items SET
  effects_json = '{"attack": ' || CAST(round(0.75 * min_level) AS INTEGER) || ', "defense": ' || MAX(1, CAST(round(0.2 * min_level) AS INTEGER)) || '}',
  description = 'Combat : +' || CAST(round(0.75 * min_level) AS INTEGER) || ' attaque au corps à corps et +' || MAX(1, CAST(round(0.2 * min_level) AS INTEGER)) || ' défense',
  base_price = CAST(round(30 * pow(min_level, 1.45)) AS INTEGER)
WHERE name LIKE 'Gants de frappe%' AND (name LIKE '%Flots Calmes' OR name LIKE '%Récif Chantant' OR name LIKE '%Brume Pourpre' OR name LIKE '%Île Foudre' OR name LIKE '%Grand Courant' OR name LIKE '%Cités Célestes' OR name LIKE '%Volcan Rouge' OR name LIKE '%Profondeurs Royales' OR name LIKE '%Siècle Perdu' OR name LIKE '%Aube Nouvelle');

UPDATE items SET
  effects_json = '{"attack": ' || CAST(round(0.7 * min_level) AS INTEGER) || '}',
  description = 'Tir : +' || CAST(round(0.7 * min_level) AS INTEGER) || ' attaque à distance',
  base_price = CAST(round(30 * pow(min_level, 1.45)) AS INTEGER)
WHERE name LIKE 'Pistolet %' AND (name LIKE '%Flots Calmes' OR name LIKE '%Récif Chantant' OR name LIKE '%Brume Pourpre' OR name LIKE '%Île Foudre' OR name LIKE '%Grand Courant' OR name LIKE '%Cités Célestes' OR name LIKE '%Volcan Rouge' OR name LIKE '%Profondeurs Royales' OR name LIKE '%Siècle Perdu' OR name LIKE '%Aube Nouvelle');

UPDATE items SET
  effects_json = '{"attack": ' || CAST(round(0.75 * min_level) AS INTEGER) || '}',
  description = 'Tir : +' || CAST(round(0.75 * min_level) AS INTEGER) || ' attaque à distance',
  base_price = CAST(round(30 * pow(min_level, 1.45)) AS INTEGER)
WHERE name LIKE 'Fusil %' AND (name LIKE '%Flots Calmes' OR name LIKE '%Récif Chantant' OR name LIKE '%Brume Pourpre' OR name LIKE '%Île Foudre' OR name LIKE '%Grand Courant' OR name LIKE '%Cités Célestes' OR name LIKE '%Volcan Rouge' OR name LIKE '%Profondeurs Royales' OR name LIKE '%Siècle Perdu' OR name LIKE '%Aube Nouvelle');

UPDATE items SET
  effects_json = '{"attack": ' || CAST(round(0.7 * min_level) AS INTEGER) || ', "force": ' || MAX(1, CAST(round(min_level / 15.0) AS INTEGER)) || '}',
  description = 'Tir : +' || CAST(round(0.7 * min_level) AS INTEGER) || ' attaque à distance et +' || MAX(1, CAST(round(min_level / 15.0) AS INTEGER)) || ' force',
  base_price = CAST(round(30 * pow(min_level, 1.45)) AS INTEGER)
WHERE name LIKE 'Mousquet%' AND (name LIKE '%Flots Calmes' OR name LIKE '%Récif Chantant' OR name LIKE '%Brume Pourpre' OR name LIKE '%Île Foudre' OR name LIKE '%Grand Courant' OR name LIKE '%Cités Célestes' OR name LIKE '%Volcan Rouge' OR name LIKE '%Profondeurs Royales' OR name LIKE '%Siècle Perdu' OR name LIKE '%Aube Nouvelle');

UPDATE items SET
  effects_json = '{"attack": ' || CAST(round(0.8 * min_level) AS INTEGER) || ', "agilite": ' || MAX(1, CAST(round(min_level / 20.0) AS INTEGER)) || '}',
  description = 'Tir : +' || CAST(round(0.8 * min_level) AS INTEGER) || ' attaque à distance et +' || MAX(1, CAST(round(min_level / 20.0) AS INTEGER)) || ' agilité',
  base_price = CAST(round(30 * pow(min_level, 1.45)) AS INTEGER)
WHERE name LIKE 'Carabine%' AND (name LIKE '%Flots Calmes' OR name LIKE '%Récif Chantant' OR name LIKE '%Brume Pourpre' OR name LIKE '%Île Foudre' OR name LIKE '%Grand Courant' OR name LIKE '%Cités Célestes' OR name LIKE '%Volcan Rouge' OR name LIKE '%Profondeurs Royales' OR name LIKE '%Siècle Perdu' OR name LIKE '%Aube Nouvelle');

UPDATE items SET
  effects_json = '{"attack": ' || CAST(round(0.85 * min_level) AS INTEGER) || ', "force": ' || MAX(1, CAST(round(min_level / 12.0) AS INTEGER)) || '}',
  description = 'Tir : +' || CAST(round(0.85 * min_level) AS INTEGER) || ' attaque à distance et +' || MAX(1, CAST(round(min_level / 12.0) AS INTEGER)) || ' force',
  base_price = CAST(round(30 * pow(min_level, 1.45)) AS INTEGER)
WHERE name LIKE 'Canon portatif%' AND (name LIKE '%Flots Calmes' OR name LIKE '%Récif Chantant' OR name LIKE '%Brume Pourpre' OR name LIKE '%Île Foudre' OR name LIKE '%Grand Courant' OR name LIKE '%Cités Célestes' OR name LIKE '%Volcan Rouge' OR name LIKE '%Profondeurs Royales' OR name LIKE '%Siècle Perdu' OR name LIKE '%Aube Nouvelle');

-- ------------------------------------------------------------------
-- Armure : protège-bras (reference courbe jeu : defense ~ 0.8x niveau)
-- ------------------------------------------------------------------
UPDATE items SET
  effects_json = '{"defense": ' || CAST(round(0.8 * min_level) AS INTEGER) || ', "force": ' || MAX(1, CAST(round(0.1 * min_level) AS INTEGER)) || '}',
  description = 'Combat : +' || CAST(round(0.8 * min_level) AS INTEGER) || ' défense et +' || MAX(1, CAST(round(0.1 * min_level) AS INTEGER)) || ' force',
  base_price = CAST(round(30 * pow(min_level, 1.45)) AS INTEGER)
WHERE name LIKE 'Protège-bras%' AND (name LIKE '%Flots Calmes' OR name LIKE '%Récif Chantant' OR name LIKE '%Brume Pourpre' OR name LIKE '%Île Foudre' OR name LIKE '%Grand Courant' OR name LIKE '%Cités Célestes' OR name LIKE '%Volcan Rouge' OR name LIKE '%Profondeurs Royales' OR name LIKE '%Siècle Perdu' OR name LIKE '%Aube Nouvelle');

-- ------------------------------------------------------------------
-- Accessoires
-- ------------------------------------------------------------------
UPDATE items SET
  effects_json = '{"defense": ' || CAST(round(0.4 * min_level) AS INTEGER) || ', "speed": ' || MAX(1, CAST(round(0.1 * min_level) AS INTEGER)) || '}',
  description = 'Équipement : +' || CAST(round(0.4 * min_level) AS INTEGER) || ' défense et +' || MAX(1, CAST(round(0.1 * min_level) AS INTEGER)) || ' vitesse',
  base_price = CAST(round(30 * pow(min_level, 1.45)) AS INTEGER)
WHERE name LIKE 'Bottes d''assaut%' AND (name LIKE '%Flots Calmes' OR name LIKE '%Récif Chantant' OR name LIKE '%Brume Pourpre' OR name LIKE '%Île Foudre' OR name LIKE '%Grand Courant' OR name LIKE '%Cités Célestes' OR name LIKE '%Volcan Rouge' OR name LIKE '%Profondeurs Royales' OR name LIKE '%Siècle Perdu' OR name LIKE '%Aube Nouvelle');

UPDATE items SET
  effects_json = '{"agilite": ' || CAST(round(0.3 * min_level) AS INTEGER) || ', "defense": ' || MAX(1, CAST(round(0.2 * min_level) AS INTEGER)) || '}',
  description = 'Combat : +' || CAST(round(0.3 * min_level) AS INTEGER) || ' agilité et +' || MAX(1, CAST(round(0.2 * min_level) AS INTEGER)) || ' défense',
  base_price = CAST(round(30 * pow(min_level, 1.45)) AS INTEGER)
WHERE name LIKE 'Bandeau de duel%' AND (name LIKE '%Flots Calmes' OR name LIKE '%Récif Chantant' OR name LIKE '%Brume Pourpre' OR name LIKE '%Île Foudre' OR name LIKE '%Grand Courant' OR name LIKE '%Cités Célestes' OR name LIKE '%Volcan Rouge' OR name LIKE '%Profondeurs Royales' OR name LIKE '%Siècle Perdu' OR name LIKE '%Aube Nouvelle');

UPDATE items SET
  effects_json = '{"force": ' || CAST(round(0.4 * min_level) AS INTEGER) || ', "vie": ' || CAST(round(0.3 * min_level) AS INTEGER) || '}',
  description = 'Combat : +' || CAST(round(0.4 * min_level) AS INTEGER) || ' force et +' || CAST(round(0.3 * min_level) AS INTEGER) || ' vie',
  base_price = CAST(round(30 * pow(min_level, 1.45)) AS INTEGER)
WHERE name LIKE 'Ceinture de puissance%' AND (name LIKE '%Flots Calmes' OR name LIKE '%Récif Chantant' OR name LIKE '%Brume Pourpre' OR name LIKE '%Île Foudre' OR name LIKE '%Grand Courant' OR name LIKE '%Cités Célestes' OR name LIKE '%Volcan Rouge' OR name LIKE '%Profondeurs Royales' OR name LIKE '%Siècle Perdu' OR name LIKE '%Aube Nouvelle');

UPDATE items SET
  effects_json = '{"sagesse": ' || MAX(1, CAST(round(0.1 * min_level) AS INTEGER)) || ', "chance": ' || MAX(1, CAST(round(0.05 * min_level) AS INTEGER)) || '}',
  description = 'Navigation : +' || MAX(1, CAST(round(0.1 * min_level) AS INTEGER)) || ' sagesse et +' || MAX(1, CAST(round(0.05 * min_level) AS INTEGER)) || ' chance',
  base_price = CAST(round(30 * pow(min_level, 1.45)) AS INTEGER)
WHERE name LIKE 'Boussole%' AND (name LIKE '%Flots Calmes' OR name LIKE '%Récif Chantant' OR name LIKE '%Brume Pourpre' OR name LIKE '%Île Foudre' OR name LIKE '%Grand Courant' OR name LIKE '%Cités Célestes' OR name LIKE '%Volcan Rouge' OR name LIKE '%Profondeurs Royales' OR name LIKE '%Siècle Perdu' OR name LIKE '%Aube Nouvelle');

UPDATE items SET
  effects_json = '{"chance": ' || MAX(1, CAST(round(0.1 * min_level) AS INTEGER)) || ', "sagesse": ' || MAX(1, CAST(round(0.05 * min_level) AS INTEGER)) || '}',
  description = 'Exploration : +' || MAX(1, CAST(round(0.1 * min_level) AS INTEGER)) || ' chance et +' || MAX(1, CAST(round(0.05 * min_level) AS INTEGER)) || ' sagesse',
  base_price = CAST(round(30 * pow(min_level, 1.45)) AS INTEGER)
WHERE name LIKE 'Longue-vue%' AND (name LIKE '%Flots Calmes' OR name LIKE '%Récif Chantant' OR name LIKE '%Brume Pourpre' OR name LIKE '%Île Foudre' OR name LIKE '%Grand Courant' OR name LIKE '%Cités Célestes' OR name LIKE '%Volcan Rouge' OR name LIKE '%Profondeurs Royales' OR name LIKE '%Siècle Perdu' OR name LIKE '%Aube Nouvelle');

UPDATE items SET
  effects_json = '{"sagesse": ' || MAX(1, CAST(round(0.15 * min_level) AS INTEGER)) || '}',
  description = 'Navigation : +' || MAX(1, CAST(round(0.15 * min_level) AS INTEGER)) || ' sagesse',
  base_price = CAST(round(30 * pow(min_level, 1.45)) AS INTEGER)
WHERE name LIKE 'Sextant%' AND (name LIKE '%Flots Calmes' OR name LIKE '%Récif Chantant' OR name LIKE '%Brume Pourpre' OR name LIKE '%Île Foudre' OR name LIKE '%Grand Courant' OR name LIKE '%Cités Célestes' OR name LIKE '%Volcan Rouge' OR name LIKE '%Profondeurs Royales' OR name LIKE '%Siècle Perdu' OR name LIKE '%Aube Nouvelle');

UPDATE items SET
  effects_json = '{"intelligence": ' || MAX(1, CAST(round(0.15 * min_level) AS INTEGER)) || ', "chance": ' || MAX(1, CAST(round(0.05 * min_level) AS INTEGER)) || '}',
  description = 'Exploration : +' || MAX(1, CAST(round(0.15 * min_level) AS INTEGER)) || ' intelligence et +' || MAX(1, CAST(round(0.05 * min_level) AS INTEGER)) || ' chance',
  base_price = CAST(round(30 * pow(min_level, 1.45)) AS INTEGER)
WHERE name LIKE 'Monocle%' AND (name LIKE '%Flots Calmes' OR name LIKE '%Récif Chantant' OR name LIKE '%Brume Pourpre' OR name LIKE '%Île Foudre' OR name LIKE '%Grand Courant' OR name LIKE '%Cités Célestes' OR name LIKE '%Volcan Rouge' OR name LIKE '%Profondeurs Royales' OR name LIKE '%Siècle Perdu' OR name LIKE '%Aube Nouvelle');

-- instruments de musique : sagesse et chance
UPDATE items SET
  effects_json = '{"sagesse": ' || MAX(1, CAST(round(0.1 * min_level) AS INTEGER)) || ', "chance": ' || MAX(1, CAST(round(0.05 * min_level) AS INTEGER)) || '}',
  description = 'Mélodie : +' || MAX(1, CAST(round(0.1 * min_level) AS INTEGER)) || ' sagesse et +' || MAX(1, CAST(round(0.05 * min_level) AS INTEGER)) || ' chance',
  base_price = CAST(round(30 * pow(min_level, 1.45)) AS INTEGER)
WHERE (name LIKE 'Violon%' OR name LIKE 'Guitare%' OR name LIKE 'Tambour%' OR name LIKE 'Ocarina%')
  AND (name LIKE '%Flots Calmes' OR name LIKE '%Récif Chantant' OR name LIKE '%Brume Pourpre' OR name LIKE '%Île Foudre' OR name LIKE '%Grand Courant' OR name LIKE '%Cités Célestes' OR name LIKE '%Volcan Rouge' OR name LIKE '%Profondeurs Royales' OR name LIKE '%Siècle Perdu' OR name LIKE '%Aube Nouvelle');
