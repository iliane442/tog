-- Nettoyage des doublons et lignes parasites de la base.
-- Idempotent et gardé par nom : chaque DELETE ne s'applique que si la
-- ligne correspond encore exactement au doublon identifié.
--
-- Exécution :  sqlite3 donnees/glo.db < donnees/seeds_nettoyage_doublons.sql

PRAGMA foreign_keys = ON;

-- mob 7 'Aloys_goon' : mob de test (niveau 1000, 5 000 000 XP),
-- aucune référence (entity_skills, drop_rates, map_entities)
DELETE FROM mobs WHERE id = 7 AND name = 'Aloys_goon';

-- mob 11 'loup' : doublon du 'Loup marin' (id 5), aucune référence
DELETE FROM mobs WHERE id = 11 AND lower(name) = 'loup';

-- skill 30 'Furie' : doublon du skill 13 'Furie' — le 13 est celui des
-- classes (Forgeron, Charpentier), plus fort (boost 0.30 vs 0.25), avec
-- son animation fx_furie ; le 30 n'est référencé nulle part
DELETE FROM skill_status_effects WHERE skill_id = 30 AND skill_id IN (SELECT id FROM skills WHERE name = 'Furie' AND id = 30);
DELETE FROM skills WHERE id = 30 AND name = 'Furie';
