-- Seeds de l'Encyclopédie des fruits du démon (métier d'Archéologue).
--
-- L'encyclopédie est un livre crafted par l'Archéologue : en votre
-- possession, le wiki révèle les fruits du démon (fiches complètes,
-- pouvoirs inclus) sans qu'il faille les avoir trouvés.
--
-- Idempotent : chaque INSERT est protégé (OR IGNORE), ids explicites.
-- Ré-appliquer ce fichier ne duplique rien.
--
-- Exécution :  sqlite3 donnees/glo.db < donnees/seeds_encyclopedie_fruits_demon.sql
--
-- Convention d'ids :
--   item  encyclopédie : 950   (les fruits du démon sont 900+)
--   recette            : 531 / ARC-051 (suite des ARC-001..050)
--   ingrédients        : 1769-1772 (suite des ids existants)

PRAGMA foreign_keys = ON;

-- ------------------------------------------------------------------
-- 1. L'item (table `items`)
--    outil/livre, rareté 4 (légendaire), non droppable (craft uniquement)
-- ------------------------------------------------------------------
INSERT OR IGNORE INTO items (
  id, name, type, subtype, rarity_id, description,
  base_price, is_craftable, is_tradable, is_droppable,
  min_level, effects_json, icon_path, is_active
) VALUES (
  950, 'Encyclopédie des fruits du démon', 'outil', 'livre', 4,
  'Compilation des recherches archéologiques sur les fruits du démon. En votre possession, le wiki révèle leurs caractéristiques et leurs pouvoirs.',
  2500, 1, 1, 0,
  1, '{}', 'res://addons/pixel_ui_fantasy/icons/scroll.png', 1
);

-- ------------------------------------------------------------------
-- 2. La recette (table `crafts`) — profession 33 = Archéologue
--    coût Berry 0 comme les autres recettes du métier
-- ------------------------------------------------------------------
INSERT OR IGNORE INTO crafts (
  id, name, display_name, description,
  profession_id, required_profession_level, craft_time_seconds,
  result_item_id, result_quantity, xp_reward, berry_cost, is_active
) VALUES (
  531, 'ARC-051', 'Rédiger l''Encyclopédie des fruits du démon',
  'Compile les témoignages des archéologues sur les fruits du démon.',
  33, 1, 20,
  950, 1, 120, 0, 1
);

-- ------------------------------------------------------------------
-- 3. Les ingrédients (table `item_craft_ingredients`)
-- ------------------------------------------------------------------
INSERT OR IGNORE INTO item_craft_ingredients (id, item_id, ingredient_id, quantity) VALUES
  (1769, 950, 639, 2),  -- Argile ancienne
  (1770, 950, 640, 2),  -- Charbon de frottage
  (1771, 950, 156, 1),  -- Encre de cartographe
  (1772, 950, 179, 1);  -- Journal de navigateur anonyme
