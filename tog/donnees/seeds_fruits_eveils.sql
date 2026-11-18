-- Pouvoirs complets des fruits du démon : 4 sorts + 1 éveil par fruit.
--
-- Structure : chaque fruit possède 5 pouvoirs débloqués par le NIVEAU
-- DU FRUIT (colonne unlock_level), qui progresse à force d'être
-- utilisé en combat (xp_fruit dans Personnage, seuil 10 x n x (n+1) / 2) :
--   sort 1 -> niveau 0 (dès le fruit mangé)
--   sort 2 -> niveau 1, sort 3 -> niveau 2, sort 4 -> niveau 3
--   éveil  -> niveau 4
--
-- Nouveaux sorts : ids 130-177 (3 par fruit : sort 2, sort 3, éveil).
-- Effets visuels : la table `animations` réutilise les spritesheets
-- VFX existants par famille d'élément (le lecteur effet_sort.gd s'en
-- sert tel quel).
--
-- Exécution :  sqlite3 donnees/glo.db < donnees/seeds_fruits_eveils.sql
-- À exécuter après seeds_fruits_demon.sql (il reconstruit la table
-- fruit_skills avec la nouvelle structure).
--
-- Idempotent : seeds et liens en OR IGNORE ; la table fruit_skills est
-- détruite puis recréée à chaque exécution (le seed la redéfinit
-- intégralement).

PRAGMA foreign_keys = ON;

-- ------------------------------------------------------------------
-- 1. Nouveaux sorts (ids 130-177)
--    convention identique aux sorts 100-129 : cout PA = base_cooldown
-- ------------------------------------------------------------------
INSERT OR IGNORE INTO skills (id, name, description, base_damage, base_cooldown, type, range) VALUES
  -- Caoutchouc
  (130, 'Gomu Gomu no Gatling', 'Une rafale de coups élastiques à courte portée.', 60, 2, 'attack', 2),
  (132, 'Gear Fifth — Bajrang Gun', 'Éveil du Caoutchouc : un poing colossal tombe du ciel et écrase tout.', 200, 6, 'attack', 1),
  -- Flamme
  (133, 'Hiken — Poing du Grand Feu', 'Une gerbe de flammes emporte la cible.', 75, 3, 'attack', 3),
  (134, 'Higan — Pluie de Feu', 'Une volée de petites boules de feu criblent la cible.', 90, 3, 'attack', 5),
  (135, 'Éveil de la Flamme — Mer Ardente', 'Éveil de la Flamme : le sol lui-même s''embrase, brûlant tout le champ.', 220, 6, 'attack', 4),
  -- Foudre
  (136, 'Bâton Foudroyant', 'Un arc électrique frappe et étourdit la cible.', 60, 2, 'attack', 2),
  (137, 'Mamaragan — Pluie d''éclairs', 'Des dizaines d''éclairs tombent sur la cible en cascade.', 85, 3, 'attack', 5),
  (138, 'Éveil de la Foudre — Raigo', 'Éveil de la Foudre : un orage gigantesque se condense et explose.', 210, 6, 'attack', 4),
  -- Glace
  (139, 'Sabre de Glace', 'Une lame de glace tranchante sortie du bras.', 60, 2, 'attack', 1),
  (140, 'Tempête de Grêle', 'Une bourrasque de grêlons gèle l''air autour de la cible.', 80, 3, 'attack', 4),
  (141, 'Éveil de la Glace — Monde Gelé', 'Éveil de la Glace : le monde passe sous zéro, tout se fige.', 60, 6, 'control', 4),
  -- Léopard
  (142, 'Bond du Fauve', 'Une ruée éclair du félin pour frapper avant d''être vu.', 55, 2, 'attack', 2),
  (143, 'Griffes Croisées', 'Deux griffes en croix lacèrent la cible en profondeur.', 85, 3, 'attack', 1),
  (144, 'Éveil du Léopard — Fauve Sacré', 'Éveil du Léopard : le prédateur ancestral prend le contrôle, attaque et défense décuplées.', 0, 6, 'buff', 0),
  -- Ténèbres
  (145, 'Nuit Aveuglante', 'Un nuage de ténèbres plonge la cible dans le noir complet.', 30, 2, 'debuff', 4),
  (146, 'Gouffre Noir', 'Les ténèbres s''ouvrent et aspirent la cible.', 60, 3, 'attack', 2),
  (147, 'Éveil des Ténèbres — Trou Noir', 'Éveil des Ténèbres : un gouffre absolu annihile tout ce qu''il touche.', 190, 6, 'attack', 3),
  -- Bistouri
  (148, 'Shambles', 'Une bulle d''opération téléporte la cible malgré elle.', 35, 3, 'control', 3),
  (149, 'Amputation', 'Une coupe chirurgicale qui retire la cible du combat d''un geste.', 80, 3, 'attack', 2),
  (150, 'Éveil du Bistouri — K-Room Fatal', 'Éveil du Bistouri : la salle d''opération traverse la cible de part en part.', 200, 6, 'attack', 3),
  -- Lumière
  (151, 'Reflet Solaire', 'La lumière habite le corps : précision et attaque accrues.', 0, 3, 'buff', 0),
  (152, 'Yasakani — Pluie d''Étoiles', 'Une pluie de projectiles de lumière perfore tout.', 95, 4, 'attack', 5),
  (153, 'Éveil de la Lumière — Ama no Murakumo', 'Éveil de la Lumière : une lame de lumière géante fend le champ de bataille.', 215, 6, 'attack', 4),
  -- Magma
  (154, 'Chien de Feu', 'Un molosse de magma bondit et enflamme la cible.', 70, 3, 'attack', 3),
  (155, 'Pluie de Magma', 'Une bombe de magma éclate en pluie incandescente.', 95, 4, 'attack', 4),
  (156, 'Éveil du Magma — Enfer Volcanique', 'Éveil du Magma : une éruption ouvre le sol sous la cible.', 230, 6, 'attack', 3),
  -- Fleurs
  (157, 'Mille Bras', 'Des bras éclosent de partout et frappent ensemble.', 65, 3, 'attack', 2),
  (158, 'Fleur Épineuse', 'Une fleur d''épines s''ouvre sur la cible et l''empoisonne.', 75, 3, 'debuff', 3),
  (159, 'Éveil des Fleurs — Jardin Écrasant', 'Éveil des Fleurs : une forêt de bras géants étreint et écrase.', 180, 6, 'attack', 3),
  -- Sable
  (160, 'Crocs du Désert', 'Des crocs de sable mordent et aveuglent la cible.', 55, 2, 'attack', 3),
  (161, 'Tempête de Sable', 'Un mur de sable racle le champ, cisaillant tout.', 90, 4, 'attack', 4),
  (162, 'Éveil du Sable — Sécheresse Absolue', 'Éveil du Sable : l''humidité quitte le corps de la cible, qui s''effrite.', 120, 6, 'debuff', 4),
  -- Fumée
  (163, 'Écran de Fumée', 'Un voile de fumée enroule son porteur et encaisse les coups.', 0, 3, 'buff', 0),
  (164, 'Serrement de Fumée', 'La fumée se condense et broie la cible.', 75, 3, 'attack', 2),
  (165, 'Éveil de la Fumée — Asphyxie Totale', 'Éveil de la Fumée : le nuage remplit les poumons de la cible, la coupant de tout.', 110, 6, 'control', 4),
  -- Séisme
  (166, 'Secousse Tellurique', 'Un coup au sol dont l''onde repousse la cible.', 70, 3, 'attack', 3),
  (167, 'Vague Relâchée', 'L''air lui-même se fissure et frappe en rafale.', 100, 4, 'attack', 4),
  (168, 'Éveil du Séisme — Faille du Monde', 'Éveil du Séisme : une faille majeure fend le champ et fend la mer elle-même.', 240, 6, 'attack', 4),
  -- Poison
  (169, 'Venin Paralysant', 'Un venin ralentit la cible et la ronge.', 40, 2, 'debuff', 3),
  (170, 'Champ Toxique', 'Un nuage vénéneux affaiblit tout ce qui le respire.', 80, 3, 'debuff', 4),
  (171, 'Éveil du Poison — Démon Venimeux', 'Éveil du Poison : l''aérogel toxique prend forme de démon et dévore.', 180, 6, 'attack', 4),
  -- Fils
  (172, 'Toile d''Araignée', 'Des fils invisibles prennent la cible au piège.', 50, 2, 'debuff', 4),
  (173, 'Marionnettiste', 'Des fils harnachent la cible et l''attirent sans qu''elle ne choisisse.', 70, 3, 'control', 3),
  (174, 'Éveil des Fils — Cage d''Oiseau', 'Éveil des Fils : une cage de fils indénombrables scie tout ce qui bouge.', 250, 6, 'attack', 5),
  -- Phénix
  (175, 'Vol du Phénix', 'Les flammes bleues protègent et régénèrent leur porteur.', 0, 3, 'buff', 0),
  (176, 'Braises Bleues', 'Une volute de flammes bleues, plus chaudes que le feu rouge.', 80, 3, 'attack', 3),
  (177, 'Éveil du Phénix — Renaissance Éternelle', 'Éveil du Phénix : le corps renaît de ses cendres, purifié (soin massif).', -250, 6, 'heal', 1);

-- note : l'id 131 est volontairement inutilisé (écart de numérotation).

-- ------------------------------------------------------------------
-- 2. Statuts infligés par les nouveaux sorts
--    (ids : 1 étourdissement, 2 empoisonnement, 3 brûlure, 4 gel,
--     5 ralentissement, 7 silence, 8 repousse, 9 attraction,
--     11 bouclier, 12 régénération, 13 boost attaque, 14 boost
--     défense, 15 boost précision, 17 vulnérabilité)
-- ------------------------------------------------------------------
INSERT OR IGNORE INTO skill_status_effects (skill_id, status_effect_id, chance, duration, value) VALUES
  (132, 1,  0.6, 1, 0.00),  -- Bajrang Gun : étourdissement
  (133, 3,  0.4, 2, 0.15),  -- Hiken : brûlure
  (134, 3,  0.5, 2, 0.20),  -- Higan : brûlure
  (135, 3,  1.0, 3, 0.25),  -- Mer Ardente : brûlure
  (136, 1,  0.25, 1, 0.00), -- Bâton Foudroyant : étourdissement
  (138, 1,  0.5, 1, 0.00),  -- Raigo : étourdissement
  (140, 4,  0.4, 2, 0.00),  -- Tempête de Grêle : gel
  (141, 4,  1.0, 2, 0.00),  -- Monde Gelé : gel
  (141, 5,  1.0, 3, 1.00),  -- Monde Gelé : ralentissement
  (141, 17, 0.3, 2, 0.30),  -- Monde Gelé : vulnérabilité
  (143, 17, 0.3, 2, 0.25), -- Griffes Croisées : vulnérabilité
  (144, 13, 1.0, 3, 0.40), -- Fauve Sacré : boost d'attaque
  (144, 14, 1.0, 3, 0.30), -- Fauve Sacré : boost de défense
  (145, 6,  0.7, 2, 0.00), -- Nuit Aveuglante : cécité
  (146, 9,  0.7, 1, 1.00), -- Gouffre Noir : attraction
  (147, 9,  1.0, 2, 1.00), -- Trou Noir : attraction
  (147, 17, 0.4, 2, 0.40),  -- Trou Noir : vulnérabilité
  (148, 8,  0.6, 1, 1.00), -- Shambles : repousse
  (150, 17, 0.5, 2, 0.50), -- K-Room Fatal : vulnérabilité
  (151, 15, 1.0, 3, 0.30), -- Reflet Solaire : boost de précision
  (151, 13, 0.3, 3, 0.20), -- Reflet Solaire : boost d'attaque
  (154, 3,  0.5, 2, 0.20), -- Chien de Feu : brûlure
  (155, 3,  1.0, 2, 0.25), -- Pluie de Magma : brûlure
  (156, 3,  1.0, 3, 0.25), -- Enfer Volcanique : brûlure
  (156, 17, 0.3, 2, 0.30),  -- Enfer Volcanique : vulnérabilité
  (158, 2,  0.6, 2, 0.15), -- Fleur Épineuse : empoisonnement
  (159, 9,  0.7, 2, 1.00), -- Jardin Écrasant : attraction
  (159, 17, 0.3, 2, 0.30),  -- Jardin Écrasant : vulnérabilité
  (160, 6,  0.3, 2, 0.00), -- Crocs du Désert : cécité
  (161, 6,  0.7, 2, 0.00), -- Tempête de Sable : cécité
  (161, 5,  0.5, 2, 0.50), -- Tempête de Sable : ralentissement
  (162, 17, 0.6, 3, 0.60), -- Sécheresse Absolue : vulnérabilité
  (162, 5,  1.0, 3, 1.00), -- Sécheresse Absolue : ralentissement
  (163, 11, 1.0, 3, 0.30), -- Écran de Fumée : bouclier
  (164, 9,  0.5, 1, 1.00), -- Serrement de Fumée : attraction
  (165, 7,  1.0, 2, 0.00), -- Asphyxie Totale : silence
  (165, 2,  0.6, 2, 0.15), -- Asphyxie Totale : empoisonnement
  (166, 8,  0.5, 1, 1.00), -- Secousse Tellurique : repousse
  (167, 8,  1.0, 1, 1.00), -- Vague Relâchée : repousse
  (168, 1,  0.8, 1, 0.00), -- Faille du Monde : étourdissement
  (169, 2,  1.0, 2, 0.15), -- Venin Paralysant : empoisonnement
  (169, 5,  0.5, 2, 0.50), -- Venin Paralysant : ralentissement
  (170, 2,  1.0, 2, 0.20), -- Champ Toxique : empoisonnement
  (170, 17, 0.3, 2, 0.30), -- Champ Toxique : vulnérabilité
  (171, 2,  1.0, 3, 0.25), -- Démon Venimeux : empoisonnement
  (171, 17, 0.5, 2, 0.40), -- Démon Venimeux : vulnérabilité
  (172, 5,  1.0, 2, 1.00), -- Toile d'Araignée : ralentissement
  (173, 9,  0.8, 1, 1.00), -- Marionnettiste : attraction
  (174, 17, 0.5, 2, 0.50), -- Cage d'Oiseau : vulnérabilité
  (175, 14, 1.0, 3, 0.30), -- Vol du Phénix : boost de défense
  (175, 12, 1.0, 3, 0.20), -- Vol du Phénix : régénération
  (176, 3,  1.0, 2, 0.20), -- Braises Bleues : brûlure
  (177, 12, 1.0, 3, 0.30); -- Renaissance Éternelle : régénération

-- ------------------------------------------------------------------
-- 3. Effets visuels des nouveaux sorts (spritesheets existants)
-- ------------------------------------------------------------------
INSERT OR IGNORE INTO animations (name, entity_type, entity_id, animation_type, sprite_sheet_path, frame_width, frame_height, frame_count, frame_delay_ms, loop) VALUES
  -- Caoutchouc : Gatling, Bajrang Gun
  ('fx_gomu_gatling',    'skill', 130, 'attack', 'assets/sprites/vfx/tog_impact_burst.png',  64,  64,  5,  63, 0),
  ('fx_eveil_caoutchouc','skill', 132, 'attack', 'assets/sprites/vfx/tog_slam_pillar.png',   216, 204, 32, 111, 0),
  -- Flamme : Hiken, Higan, Mer Ardente
  ('fx_mera_hiken',      'skill', 133, 'attack', 'assets/sprites/vfx/tog_explosion.png',     96,  96, 10,  71, 0),
  ('fx_mera_higan',      'skill', 134, 'attack', 'assets/sprites/vfx/tog_glint_scatter.png', 168, 128, 30, 125, 0),
  ('fx_eveil_flamme',    'skill', 135, 'attack', 'assets/sprites/vfx/tog_ground_blast.png',  224, 216, 32, 100, 0),
  -- Foudre : Bâton, Mamaragan, Raigo
  ('fx_goro_baton',      'skill', 136, 'attack', 'assets/sprites/vfx/tog_tracer_bolt.png',   246, 116, 31, 33, 0),
  ('fx_goro_mamaragan',  'skill', 137, 'attack', 'assets/sprites/vfx/tog_lightning_strike.png', 96, 128, 8, 71, 0),
  ('fx_eveil_foudre',    'skill', 138, 'attack', 'assets/sprites/vfx/tog_black_hole.png',    232, 212, 32, 100, 0),
  -- Glace : Sabre, Grêle, Monde Gelé
  ('fx_hie_sabre',       'skill', 139, 'attack', 'assets/sprites/vfx/tog_ice_spike_line.png', 272, 104, 32, 111, 0),
  ('fx_hie_grele',       'skill', 140, 'attack', 'assets/sprites/vfx/tog_crystal_bloom.png', 144,  72, 32, 111, 0),
  ('fx_eveil_glace',     'skill', 141, 'control','assets/sprites/vfx/tog_crystal_bloom.png', 144,  72, 32, 111, 0),
  -- Léopard : Bond, Griffes, Fauve Sacré
  ('fx_neko_bond',       'skill', 142, 'attack', 'assets/sprites/vfx/tog_slash_arc.png',     96,  96,  7,  63, 0),
  ('fx_neko_griffes',    'skill', 143, 'attack', 'assets/sprites/vfx/tog_slash_arc.png',     96,  96,  7,  63, 0),
  ('fx_eveil_leopard',   'skill', 144, 'buff',   'assets/sprites/vfx/tog_aura_leopard.png',  96, 112,  8,  83, 1),
  -- Ténèbres : Nuit, Gouffre, Trou Noir
  ('fx_yami_nuit',       'skill', 145, 'debuff', 'assets/sprites/vfx/tog_portal_night.png',  96, 112, 12,  83, 0),
  ('fx_yami_gouffre',    'skill', 146, 'attack', 'assets/sprites/vfx/tog_portal_night.png',  96, 112, 12,  83, 0),
  ('fx_eveil_tenebres',  'skill', 147, 'attack', 'assets/sprites/vfx/tog_black_hole.png',    232, 212, 32, 100, 0),
  -- Bistouri : Shambles, Amputation, K-Room
  ('fx_ope_shambles',    'skill', 148, 'control','assets/sprites/vfx/tog_glint_scatter.png', 168, 128, 30, 125, 0),
  ('fx_ope_amputation',  'skill', 149, 'attack', 'assets/sprites/vfx/tog_slash_arc.png',     96,  96,  7,  63, 0),
  ('fx_eveil_bistouri',  'skill', 150, 'attack', 'assets/sprites/vfx/tog_plasma_beam.png',    297,  84, 32,  67, 0),
  -- Lumière : Reflet, Yasakani, Ama no Murakumo
  ('fx_pika_reflet',     'skill', 151, 'buff',   'assets/sprites/vfx/tog_glint_scatter.png', 168, 128, 30, 125, 0),
  ('fx_pika_yasakani',   'skill', 152, 'attack', 'assets/sprites/vfx/tog_glint_scatter.png', 168, 128, 30, 125, 0),
  ('fx_eveil_lumiere',   'skill', 153, 'attack', 'assets/sprites/vfx/tog_tracer_bolt.png',   246, 116, 31,  33, 0),
  -- Magma : Chien de Feu, Pluie de Magma, Enfer Volcanique
  ('fx_magu_chien',      'skill', 154, 'attack', 'assets/sprites/vfx/tog_explosion_magma.png', 96, 96, 10, 71, 0),
  ('fx_magu_pluie',      'skill', 155, 'attack', 'assets/sprites/vfx/tog_ground_blast.png',  224, 216, 32, 100, 0),
  ('fx_eveil_magma',     'skill', 156, 'attack', 'assets/sprites/vfx/tog_explosion_magma.png', 96, 96, 10, 71, 0),
  -- Fleurs : Mille Bras, Fleur Épineuse, Jardin Écrasant
  ('fx_hana_mille_bras', 'skill', 157, 'attack', 'assets/sprites/vfx/tog_impact_rose.png',   64,  64,  5,  63, 0),
  ('fx_hana_epineuse',   'skill', 158, 'debuff', 'assets/sprites/vfx/tog_smg_rose.png',       112,  60, 32,  33, 0),
  ('fx_eveil_fleurs',    'skill', 159, 'attack', 'assets/sprites/vfx/tog_impact_rose.png',    64,  64,  5,  63, 0),
  -- Sable : Crocs, Tempête, Sécheresse Absolue
  ('fx_suna_crocs',      'skill', 160, 'attack', 'assets/sprites/vfx/tog_spark_sable.png',    75,  51, 31,  33, 0),
  ('fx_suna_tempete',     'skill', 161, 'attack', 'assets/sprites/vfx/tog_spark_sable.png',    75,  51, 31,  33, 0),
  ('fx_eveil_sable',     'skill', 162, 'debuff', 'assets/sprites/vfx/tog_spark_sable.png',    75,  51, 31,  33, 0),
  -- Fumée : Écran, Serrement, Asphyxie
  ('fx_moku_ecran',      'skill', 163, 'buff',   'assets/sprites/vfx/tog_smoke_puff.png',     64,  64,  8,  83, 0),
  ('fx_moku_serrement',  'skill', 164, 'attack', 'assets/sprites/vfx/tog_fumee_beam.png',    297,  84, 32,  67, 0),
  ('fx_eveil_fumee',     'skill', 165, 'control','assets/sprites/vfx/tog_fumee_beam.png',    297,  84, 32,  67, 0),
  -- Séisme : Secousse, Vague, Faille du Monde
  ('fx_gura_secousse',   'skill', 166, 'attack', 'assets/sprites/vfx/tog_shockwave.png',      112,  64,  8,  71, 0),
  ('fx_gura_vague',      'skill', 167, 'attack', 'assets/sprites/vfx/tog_shockwave.png',      112,  64,  8,  71, 0),
  ('fx_eveil_seisme',    'skill', 168, 'attack', 'assets/sprites/vfx/tog_ground_blast.png',  224, 216, 32, 100, 0),
  -- Poison : Venin, Champ Toxique, Démon Venimeux
  ('fx_doku_venin',      'skill', 169, 'debuff', 'assets/sprites/vfx/tog_toxic_puddle.png',  132,  66, 32,  83, 0),
  ('fx_doku_champ',      'skill', 170, 'debuff', 'assets/sprites/vfx/tog_toxic_cloud.png',   148,  80, 32, 125, 0),
  ('fx_eveil_poison',    'skill', 171, 'attack', 'assets/sprites/vfx/tog_toxic_cloud.png',   148,  80, 32, 125, 0),
  -- Fils : Toile, Marionnettiste, Cage d'Oiseau
  ('fx_ito_toile',       'skill', 172, 'debuff', 'assets/sprites/vfx/tog_magic_fils.png',    128, 128, 12,  83, 0),
  ('fx_ito_marionnette', 'skill', 173, 'control','assets/sprites/vfx/tog_magic_fils.png',    128, 128, 12,  83, 0),
  ('fx_eveil_fils',      'skill', 174, 'attack', 'assets/sprites/vfx/tog_magic_fils.png',    128, 128, 12,  83, 0),
  -- Phénix : Vol, Braises, Renaissance
  ('fx_tori_vol',        'skill', 175, 'buff',   'assets/sprites/vfx/tog_heal_phenix.png',    80, 112, 12,  83, 1),
  ('fx_tori_braises',    'skill', 176, 'attack', 'assets/sprites/vfx/tog_slash_bleu.png',     96,  96,  7,  63, 0),
  ('fx_eveil_phenix',    'skill', 177, 'heal',   'assets/sprites/vfx/tog_heal_phenix.png',    80, 112, 12,  83, 1);

-- ------------------------------------------------------------------
-- 4. Table fruit_skills reconstruite : 4 sorts + 1 éveil par fruit
--    niveaux de fruit : 0 (base) / 1 / 2 / 3 / 4 (éveil)
-- ------------------------------------------------------------------
DROP TABLE IF EXISTS fruit_skills;
CREATE TABLE fruit_skills (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  fruit_item_id INTEGER NOT NULL,
  skill_id INTEGER NOT NULL,
  unlock_level INTEGER NOT NULL DEFAULT 1,
  is_eveil BOOLEAN NOT NULL DEFAULT 0,
  FOREIGN KEY (fruit_item_id) REFERENCES items(id),
  FOREIGN KEY (skill_id) REFERENCES skills(id),
  UNIQUE (fruit_item_id, skill_id)
);

INSERT INTO fruit_skills (fruit_item_id, skill_id, unlock_level, is_eveil) VALUES
  -- Caoutchouc : Pistol, Gatling, Rifle, Bazooka, Bajrang Gun
  (900, 3, 0, 0), (900, 130, 1, 0), (900, 4, 2, 0), (900, 5, 3, 0), (900, 132, 4, 1),
  -- Flamme : Poing Ardent, Hiken, Higan, Nova, Mer Ardente
  (901, 100, 0, 0), (901, 133, 1, 0), (901, 134, 2, 0), (901, 101, 3, 0), (901, 135, 4, 1),
  -- Foudre : Éclair céleste, Bâton, Mamaragan, Jugement, Raigo
  (902, 102, 0, 0), (902, 136, 1, 0), (902, 137, 2, 0), (902, 103, 3, 0), (902, 138, 4, 1),
  -- Glace : Lance, Sabre, Grêle, Ère Glaciaire, Monde Gelé
  (903, 104, 0, 0), (903, 139, 1, 0), (903, 140, 2, 0), (903, 105, 3, 0), (903, 141, 4, 1),
  -- Léopard : Griffes, Bond, Griffes Croisées, Forme Hybride, Fauve Sacré
  (904, 106, 0, 0), (904, 142, 1, 0), (904, 143, 2, 0), (904, 107, 3, 0), (904, 144, 4, 1),
  -- Ténèbres : Vortex, Nuit, Gouffre, Étreinte, Trou Noir
  (905, 108, 0, 0), (905, 145, 1, 0), (905, 146, 2, 0), (905, 109, 3, 0), (905, 147, 4, 1),
  -- Bistouri : Scalpel, Shambles, Amputation, Gamma, K-Room Fatal
  (906, 110, 0, 0), (906, 148, 1, 0), (906, 149, 2, 0), (906, 111, 3, 0), (906, 150, 4, 1),
  -- Lumière : Salve, Reflet, Yasakani, Lame Céleste, Ama no Murakumo
  (907, 112, 0, 0), (907, 151, 1, 0), (907, 152, 2, 0), (907, 113, 3, 0), (907, 153, 4, 1),
  -- Magma : Poing, Chien, Pluie, Éruption, Enfer Volcanique
  (908, 114, 0, 0), (908, 154, 1, 0), (908, 155, 2, 0), (908, 115, 3, 0), (908, 156, 4, 1),
  -- Fleurs : Seize Fleur, Mille Bras, Fleur Épineuse, Déluge, Jardin Écrasant
  (909, 116, 0, 0), (909, 157, 1, 0), (909, 158, 2, 0), (909, 117, 3, 0), (909, 159, 4, 1),
  -- Sable : Jet, Crocs, Tempête, Sarcophage, Sécheresse Absolue
  (910, 118, 0, 0), (910, 160, 1, 0), (910, 161, 2, 0), (910, 119, 3, 0), (910, 162, 4, 1),
  -- Fumée : Pistolet, Écran, Serrement, Serpent, Asphyxie
  (911, 120, 0, 0), (911, 163, 1, 0), (911, 164, 2, 0), (911, 121, 3, 0), (911, 165, 4, 1),
  -- Séisme : Fracas, Secousse, Vague, Faille, Faille du Monde
  (912, 122, 0, 0), (912, 166, 1, 0), (912, 167, 2, 0), (912, 123, 3, 0), (912, 168, 4, 1),
  -- Poison : Vague, Venin, Champ, Hydre, Démon Venimeux
  (913, 124, 0, 0), (913, 169, 1, 0), (913, 170, 2, 0), (913, 125, 3, 0), (913, 171, 4, 1),
  -- Fils : Parasites, Toile, Marionnettiste, Bourrasque, Cage d'Oiseau
  (914, 126, 0, 0), (914, 172, 1, 0), (914, 173, 2, 0), (914, 127, 3, 0), (914, 174, 4, 1),
  -- Phénix : Serres, Vol, Braises, Renaissance, Renaissance Éternelle
  (915, 128, 0, 0), (915, 175, 1, 0), (915, 176, 2, 0), (915, 129, 3, 0), (915, 177, 4, 1);
