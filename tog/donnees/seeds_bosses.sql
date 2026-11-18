-- Seeds des boss inspirés de l'arc East Blue de One Piece.
-- Chaque boss existe en deux lieux cohérents :
--   - mobs     : la ligne lue par le jeu (récompenses, sprite, étiquette)
--   - bosses   : la référence lore (table d'origine, colonne inspiration)
-- Idempotent : les INSERT sont gardés par existence, les mobs par id explicite.
--
-- Progression : Alvida (4) -> Buggy (15, déjà en place) -> Kuro (8)
-- -> Don Krieg (11) -> Arlong (18, le plus loin sur la carte).

PRAGMA foreign_keys = ON;

INSERT OR IGNORE INTO mobs (
  id, name, family, level, health, attack, defense, speed,
  xp_reward, berry_reward_min, berry_reward_max,
  aggro_range, detection_range, drops_json, sprite_path, is_active
) VALUES
  (9, 'Alvida', 'pirate', 4, 150, 14, 6, 6,
   90, 150, 300, 4, 7,
   '[{"item_id": 12, "probability": 1.0, "min_quantity": 1, "max_quantity": 2}, {"item_id": 4, "probability": 0.15, "min_quantity": 1, "max_quantity": 1}]',
   'assets/sprites/ennemis/alvida.png', 1),
  (10, 'Kuro', 'pirate', 8, 170, 16, 7, 9,
   120, 200, 400, 4, 7,
   '[{"item_id": 12, "probability": 1.0, "min_quantity": 1, "max_quantity": 3}, {"item_id": 3, "probability": 0.1, "min_quantity": 1, "max_quantity": 1}]',
   'assets/sprites/ennemis/kuro.png', 1),
  (11, 'Don Krieg', 'pirate', 11, 210, 17, 14, 5,
   150, 300, 600, 4, 7,
   '[{"item_id": 12, "probability": 1.0, "min_quantity": 2, "max_quantity": 4}, {"item_id": 5, "probability": 0.2, "min_quantity": 1, "max_quantity": 1}, {"item_id": 30, "probability": 0.15, "min_quantity": 1, "max_quantity": 1}]',
   'assets/sprites/ennemis/don_krieg.png', 1),
  (12, 'Arlong', 'fishman', 18, 300, 22, 12, 7,
   260, 900, 1600, 4, 8,
   '[{"item_id": 12, "probability": 1.0, "min_quantity": 2, "max_quantity": 5}, {"item_id": 493, "probability": 0.08, "min_quantity": 1, "max_quantity": 1}]',
   'assets/sprites/ennemis/arlong.png', 1);

-- référence lore dans la table `bosses` (jamais lue par le code actuel,
-- sert de registre : inspiration One Piece, localisation, récompenses)
INSERT INTO bosses (name, inspiration, map_id, level, health, attack, defense, speed,
                    xp_reward, berry_reward_min, berry_reward_max, drops_json, is_active)
SELECT 'Alvida', 'Alvida la Massue de Fer', 4, 4, 150, 14, 6, 6,  90, 150, 300,
       '[{"item_id": 12, "probability": 1.0, "min_quantity": 1, "max_quantity": 2}, {"item_id": 4, "probability": 0.15, "min_quantity": 1, "max_quantity": 1}]', 1
 WHERE NOT EXISTS (SELECT 1 FROM bosses WHERE name = 'Alvida');
INSERT INTO bosses (name, inspiration, map_id, level, health, attack, defense, speed,
                    xp_reward, berry_reward_min, berry_reward_max, drops_json, is_active)
SELECT 'Kuro', 'Kuro des Mille Plans', 4, 8, 170, 16, 7, 9,  120, 200, 400,
       '[{"item_id": 12, "probability": 1.0, "min_quantity": 1, "max_quantity": 3}, {"item_id": 3, "probability": 0.1, "min_quantity": 1, "max_quantity": 1}]', 1
 WHERE NOT EXISTS (SELECT 1 FROM bosses WHERE name = 'Kuro');
INSERT INTO bosses (name, inspiration, map_id, level, health, attack, defense, speed,
                    xp_reward, berry_reward_min, berry_reward_max, drops_json, is_active)
SELECT 'Don Krieg', 'Don Krieg, l''Amiral Piratique', 4, 11, 210, 17, 14, 5,  150, 300, 600,
       '[{"item_id": 12, "probability": 1.0, "min_quantity": 2, "max_quantity": 4}, {"item_id": 5, "probability": 0.2, "min_quantity": 1, "max_quantity": 1}, {"item_id": 30, "probability": 0.15, "min_quantity": 1, "max_quantity": 1}]', 1
 WHERE NOT EXISTS (SELECT 1 FROM bosses WHERE name = 'Don Krieg');
INSERT INTO bosses (name, inspiration, map_id, level, health, attack, defense, speed,
                    xp_reward, berry_reward_min, berry_reward_max, drops_json, is_active)
SELECT 'Arlong', 'Arlong le Requin-scie', 4, 18, 300, 22, 12, 7,  260, 900, 1600,
       '[{"item_id": 12, "probability": 1.0, "min_quantity": 2, "max_quantity": 5}, {"item_id": 493, "probability": 0.08, "min_quantity": 1, "max_quantity": 1}]', 1
 WHERE NOT EXISTS (SELECT 1 FROM bosses WHERE name = 'Arlong');
