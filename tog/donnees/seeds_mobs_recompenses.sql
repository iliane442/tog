-- Seeds des mobs récompenses : complète la table `mobs` pour les ennemis
-- de la carte (voir mob_id dans scenes/map.tscn).
-- Idempotent : INSERT OR IGNORE sur l'id explicite.

PRAGMA foreign_keys = ON;

-- Buggy le Clown : récompenses calquées sur la table `bosses` (200 XP,
-- 500-1000 Berry) pour le boss ennemy6_boss de la map.
INSERT OR IGNORE INTO mobs (
  id, name, family, level, health, attack, defense, speed,
  xp_reward, berry_reward_min, berry_reward_max,
  aggro_range, detection_range, drops_json, is_active
) VALUES (
  8, 'Buggy le Clown', 'pirate', 15, 220, 18, 12, 6,
  200, 500, 1000,
  4, 7,
  '[{"item_id": 12, "probability": 1.0, "min_quantity": 2, "max_quantity": 3}, {"item_id": 10, "probability": 0.3, "min_quantity": 1, "max_quantity": 1}]',
  1
);

-- ------------------------------------------------------------------
-- Visuels des ennemis : sprite statique de chaque mob (colonne
-- sprite_path, lue par ennemy.gd — rotations/south des personnages
-- Pixellab 96 px, style des pirates du joueur). Les loups gardent le
-- sprite d'origine.
-- ------------------------------------------------------------------
UPDATE mobs SET sprite_path = 'assets/sprites/ennemis/goon_pirate.png'  WHERE id = 1;
UPDATE mobs SET sprite_path = 'assets/sprites/ennemis/pirate_ivre.png'  WHERE id = 2;
UPDATE mobs SET sprite_path = 'assets/sprites/ennemis/moussaillon.png'  WHERE id = 3;
UPDATE mobs SET sprite_path = 'assets/sprites/ennemis/officier_marine.png' WHERE id = 4 AND COALESCE(sprite_path, '') = '';
UPDATE mobs SET sprite_path = 'assets/sprites/wolf.png'                  WHERE id = 5 AND sprite_path IS NULL;
UPDATE mobs SET sprite_path = 'assets/sprites/ennemis/crabe_geant.png' WHERE id = 6 AND COALESCE(sprite_path, '') = '';
UPDATE mobs SET sprite_path = 'assets/sprites/wolf.png'                  WHERE id = 11 AND sprite_path IS NULL;
UPDATE mobs SET sprite_path = 'assets/sprites/ennemis/buggy_clown.png'  WHERE id = 8;
