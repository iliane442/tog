-- Seeds des ennemis issus des planches faune restantes (temporaire/images) :
--   - 9 nouveaux ennemis (mobs 16-24) avec frames statiques extraites des
--     planches de marche 9x4 (cellule ligne 0, colonne 0, même convention que
--     Pirate squelette / Momie / Roi des os) :
--       Colombe (1), Poule (1), Chien errant (2), Cerf (3), Cheval sauvage (4),
--       Élan (5), Ours brun (7), Fantôme (10), Chevalier zombie (12).
--   - progression : animaux dociles près du village, bêtes plus fortes au
--     centre de la map, morts-vivants au sud-est (zone du Roi des os).
-- Idempotent : INSERT OR IGNORE par id, UPDATE inconditionnels.

PRAGMA foreign_keys = ON;

INSERT OR IGNORE INTO mobs (
  id, name, family, level, health, attack, defense, speed,
  xp_reward, berry_reward_min, berry_reward_max,
  aggro_range, detection_range, drops_json, sprite_path, is_active
) VALUES
  (16, 'Colombe', 'beast', 1, 40, 4, 2, 6,
   15, 5, 20, 2, 5, '[]',
   'assets/sprites/fauna/colombe-statique.png', 1),
  (17, 'Poule', 'beast', 1, 45, 5, 2, 5,
   18, 8, 25, 2, 5, '[]',
   'assets/sprites/fauna/poule-statique.png', 1),
  (18, 'Chien errant', 'beast', 2, 60, 7, 3, 7,
   25, 10, 30, 3, 6,
   '[{"item_id": 12, "probability": 0.25, "min_quantity": 1, "max_quantity": 1}]',
   'assets/sprites/fauna/chien-statique.png', 1),
  (19, 'Cerf', 'beast', 3, 75, 9, 3, 7,
   35, 15, 40, 3, 6, '[]',
   'assets/sprites/fauna/cerf-statique.png', 1),
  (20, 'Cheval sauvage', 'beast', 4, 95, 10, 4, 8,
   45, 20, 50, 3, 6,
   '[{"item_id": 12, "probability": 0.25, "min_quantity": 1, "max_quantity": 1}]',
   'assets/sprites/fauna/cheval-statique.png', 1),
  (21, 'Élan', 'beast', 5, 110, 12, 5, 7,
   55, 25, 60, 3, 6,
   '[{"item_id": 12, "probability": 0.2, "min_quantity": 1, "max_quantity": 1}]',
   'assets/sprites/fauna/elan-statique.png', 1),
  (22, 'Ours brun', 'beast', 7, 140, 15, 6, 5,
   80, 40, 90, 4, 7,
   '[{"item_id": 12, "probability": 0.3, "min_quantity": 1, "max_quantity": 2}]',
   'assets/sprites/fauna/ours-brun-statique.png', 1),
  (23, 'Fantôme', 'undead', 10, 170, 17, 8, 6,
   125, 80, 160, 4, 7,
   '[{"item_id": 83, "probability": 0.4, "min_quantity": 1, "max_quantity": 1}]',
   'assets/sprites/fauna/fantome-statique.png', 1),
  (24, 'Chevalier zombie', 'undead', 12, 220, 20, 11, 5,
   170, 150, 300, 4, 7,
   '[{"item_id": 83, "probability": 0.6, "min_quantity": 1, "max_quantity": 2}, {"item_id": 12, "probability": 0.3, "min_quantity": 1, "max_quantity": 1}]',
   'assets/sprites/fauna/zombie-chevalier-statique.png', 1);

-- assurances en cas de ré-exécution partielle
UPDATE mobs SET sprite_path = 'assets/sprites/fauna/colombe-statique.png' WHERE id = 16;
UPDATE mobs SET sprite_path = 'assets/sprites/fauna/poule-statique.png' WHERE id = 17;
UPDATE mobs SET sprite_path = 'assets/sprites/fauna/chien-statique.png' WHERE id = 18;
UPDATE mobs SET sprite_path = 'assets/sprites/fauna/cerf-statique.png' WHERE id = 19;
UPDATE mobs SET sprite_path = 'assets/sprites/fauna/cheval-statique.png' WHERE id = 20;
UPDATE mobs SET sprite_path = 'assets/sprites/fauna/elan-statique.png' WHERE id = 21;
UPDATE mobs SET sprite_path = 'assets/sprites/fauna/ours-brun-statique.png' WHERE id = 22;
UPDATE mobs SET sprite_path = 'assets/sprites/fauna/fantome-statique.png' WHERE id = 23;
UPDATE mobs SET sprite_path = 'assets/sprites/fauna/zombie-chevalier-statique.png' WHERE id = 24;
