-- Normalisation des sous-types d'équipement (armures et accessoires).
--
-- Historique : le sous-type 'main' servait de fourre-tout (88 accessoires :
-- boussoles, sextants, monocles, instruments de musique, dials...) et
-- les ceintures de puissance étaient rangées en 'cou'.
--
-- Exécution :  sqlite3 donnees/glo.db < donnees/seeds_equipements_sous_types.sql
--
-- Idempotent : des UPDATE par motifs/ids, ré-exécutables sans effet de bord.
--
-- Impact code : Personnage.emplacement_equipement (personnage.gd) a été
-- étendu pour mapper chaque nouveau sous-type vers son emplacement :
-- armure   : protège-bras, bracelet, bouclier -> main
-- accessoire: boussole, longue-vue, sextant, dial, instrument, bracelet
--             -> main ; monocle -> visage ; ceinture -> ceinture
-- Sans ces mappings, un sous-type inconnu d'un accessoire rend l'objet
-- non équipable (emplacement_equipement renvoie "").
--
-- Vocabulaire final :
--   armure     : cape, ceinture, corps, écharpe(pointe->cape), gants,
--                bottes(pieds), protège-bras, bracelet, bouclier
--   accessoire : anneau, bracelet, boussole, ceinture, cou, dial,
--                instrument, longue-vue, monocle, sextant, visage,
--                tête, pieds

PRAGMA foreign_keys = ON;

-- ------------------------------------------------------------------
-- 1. Armures
-- ------------------------------------------------------------------
-- brassards de la série « zones » : portés aux bras
UPDATE items SET subtype = 'protège-bras'
 WHERE type = 'armure' AND subtype = 'corps' AND name LIKE 'Protège-bras%';
-- gants : sous-type explicite (déjà mappé vers l'emplacement main)
UPDATE items SET subtype = 'gants'
 WHERE type = 'armure' AND subtype = 'main' AND name LIKE 'Gants%';
-- bijou de poignet en armure
UPDATE items SET subtype = 'bracelet'
 WHERE type = 'armure' AND subtype = 'main' AND name LIKE 'Bracelet%';
-- bouclier : porté en main, pas sur le corps
UPDATE items SET subtype = 'bouclier'
 WHERE type = 'armure' AND subtype = 'main' AND name LIKE 'Bouclier%';
-- écharpe : se porte sur les épaules comme un manteau court
UPDATE items SET subtype = 'cape'
 WHERE type = 'armure' AND subtype = 'corps' AND name LIKE 'Écharpe%';

-- ------------------------------------------------------------------
-- 2. Accessoires
-- ------------------------------------------------------------------
-- ceintures : rangées en 'cou' par erreur ; emplacement ceinture dédié
UPDATE items SET subtype = 'ceinture'
 WHERE type = 'accessoire' AND subtype = 'cou' AND name LIKE 'Ceinture%';
-- pendentif : porté au cou
UPDATE items SET subtype = 'cou'
 WHERE type = 'accessoire' AND subtype = 'main' AND name LIKE 'Pendentif%';
-- bracelets
UPDATE items SET subtype = 'bracelet'
 WHERE type = 'accessoire' AND subtype = 'main' AND name LIKE 'Bracelet%';
-- dials de Skypiea (tenus en main)
UPDATE items SET subtype = 'dial'
 WHERE type = 'accessoire' AND subtype = 'main' AND name LIKE '%Dial%';
-- instruments de navigation
UPDATE items SET subtype = 'boussole'
 WHERE type = 'accessoire' AND subtype = 'main' AND name LIKE 'Boussole%';
UPDATE items SET subtype = 'longue-vue'
 WHERE type = 'accessoire' AND subtype = 'main' AND name LIKE 'Longue-vue%';
UPDATE items SET subtype = 'sextant'
 WHERE type = 'accessoire' AND subtype = 'main' AND name LIKE 'Sextant%';
-- monocle d'étude : se porte sur l'oeil
UPDATE items SET subtype = 'monocle'
 WHERE type = 'accessoire' AND subtype = 'main' AND name LIKE 'Monocle%';
-- instruments de musique (tenus en main)
UPDATE items SET subtype = 'instrument'
 WHERE type = 'accessoire' AND subtype = 'main'
   AND (name LIKE 'Violon%' OR name LIKE 'Guitare%'
        OR name LIKE 'Tambour%' OR name LIKE 'Ocarina%');
