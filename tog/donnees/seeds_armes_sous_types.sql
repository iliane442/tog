-- Normalisation des sous-types d'armes (table `items`, type = 'arme').
-- Historiquement, presque toutes les armes étaient enregistrées avec le
-- sous-type 'épée', y compris les armes à feu, gants, lances, canons...
-- Ce fichier réattribue un sous-type fidèle à chaque arme.
--
-- Idempotent : des UPDATE par ids explicites, ré-exécutables sans effet
-- de bord.
--
-- Exécution :  sqlite3 donnees/glo.db < donnees/seeds_armes_sous_types.sql
--
-- Impact code (vérifié) : seul script concerné, le tirage des lames
-- uniques dans coffres.gd sélectionne désormais les uniques via le
-- registre `unique_items` (type = 'arme'), plus via le sous-type.
-- L'emplacement d'équipement ne dépend que du type 'arme' (personnage.gd).
--
-- Lames/poings de bretteur (katana, sabre, nodachi, wakizashi, lame
-- courte, garde-lame) : sous-type 'épée' inchangé.

PRAGMA foreign_keys = ON;

-- ------------------------------------------------------------------
-- 1. Armes à feu
-- ------------------------------------------------------------------
UPDATE items SET subtype = 'pistolet' WHERE id IN (
  33, 34, 204, 576, 582, 589, 594, 601, 607, 613, 620, 626, 632);
UPDATE items SET subtype = 'fusil' WHERE id IN (
  35, 36, 577, 583, 590, 596, 602, 608, 615, 621, 627, 634);
UPDATE items SET subtype = 'mousquet' WHERE id IN (
  578, 584, 591, 597, 603, 610, 616, 622, 629, 635);
UPDATE items SET subtype = 'carabine' WHERE id IN (
  579, 586, 592, 598, 605, 611, 617, 624, 630, 636);

-- ------------------------------------------------------------------
-- 2. Artillerie
-- ------------------------------------------------------------------
UPDATE items SET subtype = 'canon' WHERE id IN (
  38, 581, 587, 593, 600, 606, 612, 619, 625, 631, 638);
UPDATE items SET subtype = 'lance-roquettes' WHERE id IN (37);

-- ------------------------------------------------------------------
-- 3. Armes d'hast (manche) et contondantes
-- ------------------------------------------------------------------
UPDATE items SET subtype = 'hache' WHERE id IN (30);
UPDATE items SET subtype = 'masse' WHERE id IN (31);
UPDATE items SET subtype = 'bâton' WHERE id IN (32);
UPDATE items SET subtype = 'lance' WHERE id IN (29, 47);
UPDATE items SET subtype = 'trident' WHERE id IN (41);

-- ------------------------------------------------------------------
-- 4. Armes de pugilat
-- ------------------------------------------------------------------
UPDATE items SET subtype = 'gants' WHERE id IN (
  39, 407, 413, 420, 427, 437, 446, 454, 463, 472, 481);
UPDATE items SET subtype = 'griffes' WHERE id IN (40);

-- ------------------------------------------------------------------
-- 5. Lames uniques : Murakumogiri est un bisento, pas une épée
--    (les autres restent des 'épée')
-- ------------------------------------------------------------------
UPDATE items SET subtype = 'bisento' WHERE id IN (952);
