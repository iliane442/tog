-- Seeds des assets récupérés d'un autre jeu (temporaire/images) :
--   - trois nouveaux ennemis issus de la faune récupérée (frames statiques
--     extraites des planches de marche 9x4) : Pirate squelette, Momie,
--     Roi des os ;
--   - icône générique (fruit mythe-oni) pour les fruits du démon, dont la
--     colonne icon_path était vide (affichage inventaire/wiki).
-- Idempotent : INSERT OR IGNORE par id, UPDATE inconditionnels.

PRAGMA foreign_keys = ON;

INSERT OR IGNORE INTO mobs (
  id, name, family, level, health, attack, defense, speed,
  xp_reward, berry_reward_min, berry_reward_max,
  aggro_range, detection_range, drops_json, sprite_path, is_active
) VALUES
  (13, 'Pirate squelette', 'undead', 2, 70, 8, 4, 5,
   30, 15, 40, 3, 6,
   '[{"item_id": 12, "probability": 0.5, "min_quantity": 1, "max_quantity": 1}]',
   'assets/sprites/fauna/squelette-pirate-statique.png', 1),
  (14, 'Momie', 'undead', 6, 110, 12, 6, 4,
   55, 30, 70, 3, 6,
   '[{"item_id": 83, "probability": 1.0, "min_quantity": 1, "max_quantity": 2}]',
   'assets/sprites/fauna/momie-statique.png', 1),
  (15, 'Roi des os', 'undead', 9, 160, 15, 8, 6,
   110, 150, 300, 4, 7,
   '[{"item_id": 12, "probability": 1.0, "min_quantity": 1, "max_quantity": 2}, {"item_id": 3, "probability": 0.08, "min_quantity": 1, "max_quantity": 1}]',
   'assets/sprites/fauna/roi-des-os-statique.png', 1);

-- icône générique pour tous les fruits du démon (inventaire + wiki)
UPDATE items
   SET icon_path = 'assets/sprites/items/fruits-mythe-oni.webp'
 WHERE type = 'fruit_demon'
   AND (icon_path IS NULL OR icon_path = '');
