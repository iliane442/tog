-- Rend les consommables de zones réellement utilisables.
--
-- Avant : les 100 consommables des 10 zones (soins et repas) avaient
-- effects_json vide et un prix nul. Leurs descriptions contiennent déjà
-- les valeurs voulues (« Soin : restaure 679 points de vie »,
-- « Repas : +412 vitalité »), aux mêmes échelles que le reste du jeu
-- (par ex. Potion de soin lvl 1 = 50 PV).
--
-- Deux cas :
--   1. valeur présente dans la description (71 items) : heal extrait du
--      texte — les formules du seed d'origine sont parfaitement
--      régulières (soin : round(3,5 x lvl) + 31, repas : 2 x lvl + 18),
--      la reconstruction est fidèle ;
--   2. description « Provenance : Craft - Médecin » sans valeur
--      (29 items, famille soin) : heal recalculé par la formule commune
--      à leur famille, description régénérée en conséquence.
--
-- Prix : 1 Berry par point de vie restauré (base_price = heal),
-- cohérent avec les items de référence (Ration 30 b, Infusion de Zou
-- 840 b).
--
-- Exécution :  sqlite3 donnees/glo.db < donnees/seeds_consommables_zones.sql
--
-- Idempotent : UPDATE déterministes (valeurs recalculées identiques à
-- chaque exécution), gardés sur les suffixes de zone.

PRAGMA foreign_keys = ON;

-- ------------------------------------------------------------------
-- 1. Soins : « restaure N points de vie » -> {"heal": N}
-- ------------------------------------------------------------------
UPDATE items SET
  effects_json = '{"heal": ' ||
    CAST(substr(substr(description, instr(description, 'restaure ') + 9), 1,
                     instr(substr(description, instr(description, 'restaure ') + 9), ' ') - 1) AS INTEGER)
    || '}',
  base_price = CAST(substr(substr(description, instr(description, 'restaure ') + 9), 1,
                     instr(substr(description, instr(description, 'restaure ') + 9), ' ') - 1) AS INTEGER)
WHERE type = 'consumable' AND description LIKE '%restaure %points de vie%'
  AND (name LIKE '%Flots Calmes' OR name LIKE '%Récif Chantant' OR name LIKE '%Brume Pourpre'
       OR name LIKE '%Île Foudre' OR name LIKE '%Grand Courant' OR name LIKE '%Cités Célestes'
       OR name LIKE '%Volcan Rouge' OR name LIKE '%Profondeurs Royales' OR name LIKE '%Siècle Perdu'
       OR name LIKE '%Aube Nouvelle');

-- ------------------------------------------------------------------
-- 2. Repas : « +N vitalité » -> {"heal": N} (précédent : Ration de
--    nourriture = {"heal": 20}) ; la vitalité est restaurée instantanément
-- ------------------------------------------------------------------
UPDATE items SET
  effects_json = '{"heal": ' ||
    CAST(substr(substr(description, instr(description, 'Repas : +') + 9), 1,
                     instr(substr(description, instr(description, 'Repas : +') + 9), ' ') - 1) AS INTEGER)
    || '}',
  base_price = CAST(substr(substr(description, instr(description, 'Repas : +') + 9), 1,
                     instr(substr(description, instr(description, 'Repas : +') + 9), ' ') - 1) AS INTEGER)
WHERE type = 'consumable' AND description LIKE '%Repas : +% vitalité%'
  AND (name LIKE '%Flots Calmes' OR name LIKE '%Récif Chantant' OR name LIKE '%Brume Pourpre'
       OR name LIKE '%Île Foudre' OR name LIKE '%Grand Courant' OR name LIKE '%Cités Célestes'
       OR name LIKE '%Volcan Rouge' OR name LIKE '%Profondeurs Royales' OR name LIKE '%Siècle Perdu'
       OR name LIKE '%Aube Nouvelle');

-- ------------------------------------------------------------------
-- 3. Soins « Craft - Médecin » sans valeur (29 items) : formule de la
--    famille soin, exacte pour toutes les pièces documentées
--    (round(3,5 x lvl) + 31 : lvl 1 -> 35, lvl 5 -> 49, lvl 193 -> 707)
-- ------------------------------------------------------------------
UPDATE items SET
  effects_json = '{"heal": ' || (CAST(round(3.5 * min_level) AS INTEGER) + 31) || '}',
  description = 'Soin : restaure ' || (CAST(round(3.5 * min_level) AS INTEGER) + 31)
                || ' points de vie.',
  base_price = CAST(round(3.5 * min_level) AS INTEGER) + 31
WHERE type = 'consumable' AND subtype = 'soin' AND description LIKE 'Provenance : Craft - Médecin%'
  AND (name LIKE '%Flots Calmes' OR name LIKE '%Récif Chantant' OR name LIKE '%Brume Pourpre'
       OR name LIKE '%Île Foudre' OR name LIKE '%Grand Courant' OR name LIKE '%Cités Célestes'
       OR name LIKE '%Volcan Rouge' OR name LIKE '%Profondeurs Royales' OR name LIKE '%Siècle Perdu'
       OR name LIKE '%Aube Nouvelle');
