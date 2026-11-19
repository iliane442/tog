-- Supprime les 6 classes inactives (is_active = 0) — Épéiste (1),
-- Archer (2), Canonnier (3), Samouraï (4), Infirmière (6), Timonier (8) —
-- et répartit leurs sorts encore libres entre les classes restantes.
--
-- À exécuter APRÈS seeds_classes_sorts.sql.
--
-- Répartition des sorts rendus orphelins :
--   tous les sorts des kits supprimés avaient déjà un autre porteur
--   (Bouclier, Furie, Fracas, Haki, Peau de pierre...) SAUF :
--   - ShakuShaku (7), la signature d'Épéiste/Samouraï -> le Sabreur
--     en fait sa signature de base ; son Haki du Roi descend au
--     palier 5 (remplace Fracas, déjà très répandu) ;
--   - Mirage Tempo (9), la signature d'Archer -> palier 5 du
--     Navigateur (mirages météo, remplace Entrave, conservé par
--     quatre autres classes).
--   - Ténèbres (17), sort du Canonnier d'origine resté sans porteur
--     -> palier 50 du Sabreur (les lames maudites des Kitetsu),
--     remplace Bouclier, encore porté par trois classes.
--
-- Exécution :  sqlite3 donnees/glo.db < donnees/seeds_classes_nettoyage.sql
--
-- Idempotent : DELETE par ids et UPDATE ciblés, ré-exécutables.

PRAGMA foreign_keys = ON;

-- ------------------------------------------------------------------
-- 1. Sorts et références des classes supprimées
-- ------------------------------------------------------------------
DELETE FROM class_skills WHERE class_id IN (1, 2, 3, 4, 6, 8);
-- les 9 templates de characters référencent tous ces classes (guerriers,
-- archères, médecins) : aucun n'est utilisable sans elles
DELETE FROM character_templates WHERE class_id IN (1, 2, 3, 4, 6, 8);

-- ------------------------------------------------------------------
-- 2. Suppression des classes inactives
-- ------------------------------------------------------------------
DELETE FROM character_classes WHERE id IN (1, 2, 3, 4, 6, 8);

-- ------------------------------------------------------------------
-- 3. Répartition des sorts orphelins
-- ------------------------------------------------------------------
-- Sabreur : ShakuShaku en signature, Haki du Roi au palier 5
UPDATE character_classes SET starting_skills_json = '[1, 7]' WHERE id = 12;
UPDATE class_skills SET skill_id = 6 WHERE class_id = 12 AND unlock_level = 5;
-- Navigateur : Mirage Tempo au palier 5
UPDATE class_skills SET skill_id = 9 WHERE class_id = 7 AND unlock_level = 5;
-- Sabreur : Ténèbres au palier 50 (lames maudites)
UPDATE class_skills SET skill_id = 17 WHERE class_id = 12 AND unlock_level = 50;
