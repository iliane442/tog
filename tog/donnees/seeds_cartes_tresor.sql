-- Quatre cartes au trésor consommables (raretés 1 à 4).
--
-- « Utiliser » une carte fait apparaître une croix sur la carte du
-- monde à une case de sol aléatoire (voir l'autoload CartesTresor).
-- Cliquer la croix décerne un trésor selon la rareté de la carte :
--   1 usée          : Berry + parfois un consommable commun
--   2 de corsaire   : Berry + une pièce d'équipement rare
--   3 de la Marine  : Berry + une pièce d'équipement épique
--   4 du Roi des pirates : Berry + un objet unique (lame) si un
--                     exemplaire est encore disponible dans le monde
--
-- effects_json porte la clé « tresor » (niveau du trésor) ; utiliser_objet
-- la détecte et délègue à CartesTresor.creer_croix au lieu d'appliquer
-- un soin/buff. effet non vide -> bouton « Utiliser » actif.
--
-- Exécution :  sqlite3 donnees/glo.db < donnees/seeds_cartes_tresor.sql
--
-- Idempotent : INSERT OR IGNORE + UPDATE déterministes.

-- ------------------------------------------------------------------
-- 1. Les 4 cartes
-- ------------------------------------------------------------------
INSERT OR IGNORE INTO items (
  id, name, type, subtype, rarity_id, description, base_price,
  is_active, is_droppable, min_level, effects_json, icon_path
) VALUES
  (971, 'Carte au trésor usée', 'consumable', 'carte_tresor', 1,
   'Une carte froissée aux reliefs effacés. En l''étudier, une croix d''encre bave apparaît : quelque chose est enterré là. Grattant la surface, un trésor modeste attend.',
   200, 1, 1, 1, '{"tresor": 1}', 'addons/pixel_ui_fantasy/icons/quest.png'),
  (972, 'Carte au trésor de corsaire', 'consumable', 'carte_tresor', 2,
   'Pillée sur un navire ennemi. Le capitaine qui la traînait portait de bonnes lames : de quoi dénicher un butin correct.',
   900, 1, 1, 5, '{"tresor": 2}', 'addons/pixel_ui_fantasy/icons/quest.png'),
  (973, 'Carte au trésor de la Marine', 'consumable', 'carte_tresor', 3,
   'Un document de la Marine scellé de cire rouge. Les caches officielles ne sont jamais vides, et rarement décevantes.',
   3200, 1, 1, 15, '{"tresor": 3}', 'addons/pixel_ui_fantasy/icons/quest.png'),
  (974, 'Carte au trésor du Roi des pirates', 'consumable', 'carte_tresor', 4,
   'Une carte du vieux Roger lui-même, à en croire les encoches du parchemin. Ceux qui ont gratté devant ces croix en sont repartis riches — ou pas repartis.',
   12000, 1, 1, 30, '{"tresor": 4}', 'addons/pixel_ui_fantasy/icons/quest.png');

-- ------------------------------------------------------------------
-- 2. Valeurs garanties (relances du seed)
-- ------------------------------------------------------------------
UPDATE items SET
  type = 'consumable', subtype = 'carte_tresor', is_active = 1,
  is_droppable = 1, min_level = 1,
  effects_json = '{"tresor": 1}',
  icon_path = 'addons/pixel_ui_fantasy/icons/quest.png'
WHERE id = 971;
UPDATE items SET
  type = 'consumable', subtype = 'carte_tresor', is_active = 1,
  is_droppable = 1, min_level = 5,
  effects_json = '{"tresor": 2}',
  icon_path = 'addons/pixel_ui_fantasy/icons/quest.png'
WHERE id = 972;
UPDATE items SET
  type = 'consumable', subtype = 'carte_tresor', is_active = 1,
  is_droppable = 1, min_level = 15,
  effects_json = '{"tresor": 3}',
  icon_path = 'addons/pixel_ui_fantasy/icons/quest.png'
WHERE id = 973;
UPDATE items SET
  type = 'consumable', subtype = 'carte_tresor', is_active = 1,
  is_droppable = 1, min_level = 30,
  effects_json = '{"tresor": 4}',
  icon_path = 'addons/pixel_ui_fantasy/icons/quest.png'
WHERE id = 974;
