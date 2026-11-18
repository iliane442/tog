-- Seeds des animations d'effets pour les sorts (spritesheets PixelLab VFX).
-- Idempotent : les noms étant UNIQUE, INSERT OR IGNORE protège les ré-exécutions.
--
-- Exécution :  sqlite3 donnees/glo.db < donnees/seeds_animations_sorts.sql
--
-- Les spritesheets viennent de scène VFX de PixelLab (preset exportés) :
--   tog/assets/sprites/vfx/tog_<effet>.png  +  .json (atlas : frames + ancre)
-- Le lecteur GDScript (scripts/combat/effet_sort.gd) lit le .json pour
-- découper les frames et positionner l'effet sur l'ancre.
--
-- frame_count : les frames entièrement vides en fin d'effet signalées à
-- l'export (2 par effet concerné) sont exclues du compte.

PRAGMA foreign_keys = ON;

INSERT OR IGNORE INTO animations (name, entity_type, entity_id, animation_type, sprite_sheet_path, frame_width, frame_height, frame_count, frame_delay_ms, loop) VALUES
  -- sorts de classe
  ('fx_coup_simple',       'skill', 1,   'attack',  'assets/sprites/vfx/tog_slash_arc.png',       96,  96,  7,  63, 0),
  ('fx_gomu_pistol',       'skill', 3,   'attack',  'assets/sprites/vfx/tog_impact_burst.png',    64,  64,  5,  63, 0),
  ('fx_gomu_rifle',        'skill', 4,   'attack',  'assets/sprites/vfx/tog_spark_hit.png',       75,  51,  31, 33, 0),
  ('fx_gomu_bazooka',      'skill', 5,   'attack',  'assets/sprites/vfx/tog_explosion.png',       96,  96,  10, 71, 0),
  ('fx_haki_du_roi',       'skill', 6,   'attack',  'assets/sprites/vfx/tog_shockwave.png',        112, 64,  8,  71, 0),
  ('fx_soin_mineur',       'skill', 10,  'heal',    'assets/sprites/vfx/tog_heal_pillar.png',      80,  112, 12, 83, 1),
  ('fx_soin_majeur',       'skill', 11,  'heal',    'assets/sprites/vfx/tog_heal_pillar.png',      80,  112, 12, 83, 1),
  ('fx_bouclier',          'skill', 12,  'defense', 'assets/sprites/vfx/tog_shield_bubble.png',    96,  96,  8,  100, 1),
  ('fx_furie',             'skill', 13,  'buff',    'assets/sprites/vfx/tog_aura.png',            96,  112, 8,  83, 1),
  ('fx_foudre',            'skill', 15,  'attack',  'assets/sprites/vfx/tog_lightning_strike.png', 96,  128, 8,  71, 0),
  ('fx_tenebres',          'skill', 17,  'attack',  'assets/sprites/vfx/tog_black_hole.png',       232, 212, 32, 100, 0),
  -- boule de feu codée en dur dans player.gd (id 0 = hors table skills)
  ('fx_boule_de_feu',      'skill', 0,   'attack',  'assets/sprites/vfx/tog_explosion.png',       96,  96,  10, 71, 0),
  -- pouvoirs des fruits du démon
  ('fx_poing_ardent',       'skill', 100, 'attack', 'assets/sprites/vfx/tog_explosion.png',        96,  96,  10, 71, 0),
  ('fx_nova_de_flammes',    'skill', 101, 'attack', 'assets/sprites/vfx/tog_ground_blast.png',     224, 216, 32, 100, 0),
  ('fx_eclair_celeste',     'skill', 102, 'attack', 'assets/sprites/vfx/tog_tracer_bolt.png',      246, 116, 31, 33, 0),
  ('fx_jugement_divin',     'skill', 103, 'attack', 'assets/sprites/vfx/tog_lightning_strike.png', 96,  128, 8,  71, 0),
  ('fx_lance_de_givre',     'skill', 104, 'attack', 'assets/sprites/vfx/tog_ice_spike_line.png',   272, 104, 32, 111, 0),
  ('fx_ere_glaciaire',      'skill', 105, 'attack', 'assets/sprites/vfx/tog_crystal_bloom.png',    144, 72,  32, 111, 0),
  ('fx_griffes_du_fauve',   'skill', 106, 'attack', 'assets/sprites/vfx/tog_slash_arc.png',        96,  96,  7,  63, 0),
  ('fx_forme_hybride',      'skill', 107, 'buff',   'assets/sprites/vfx/tog_aura_leopard.png',     96,  112, 8,  83, 1),
  ('fx_vortex_noir',        'skill', 108, 'attack', 'assets/sprites/vfx/tog_portal_night.png',    96,  112, 12, 83, 0),
  ('fx_etreinte_tenebres',  'skill', 109, 'attack', 'assets/sprites/vfx/tog_black_hole.png',       232, 212, 32, 100, 0),
  ('fx_scalpel_affute',     'skill', 110, 'attack', 'assets/sprites/vfx/tog_slash_arc.png',        96,  96,  7,  63, 0),
  ('fx_gamma_scalpel',      'skill', 111, 'attack', 'assets/sprites/vfx/tog_plasma_beam.png',      297, 84,  32, 67, 0),
  ('fx_salve_de_lumiere',   'skill', 112, 'attack', 'assets/sprites/vfx/tog_glint_scatter.png',    168, 128, 30, 125, 0),
  ('fx_lame_celeste',       'skill', 113, 'attack', 'assets/sprites/vfx/tog_slam_pillar.png',      216, 204, 32, 111, 0),
  ('fx_poing_de_magma',     'skill', 114, 'attack', 'assets/sprites/vfx/tog_explosion_magma.png',  96,  96,  10, 71, 0),
  ('fx_eruption',           'skill', 115, 'attack', 'assets/sprites/vfx/tog_ground_blast.png',     224, 216, 32, 100, 0),
  ('fx_seize_fleur_prise',  'skill', 116, 'attack', 'assets/sprites/vfx/tog_impact_rose.png',     64,  64,  5,  63, 0),
  ('fx_deluge_de_mains',    'skill', 117, 'attack', 'assets/sprites/vfx/tog_smg_rose.png',         112, 60,  32, 33, 0),
  ('fx_jet_de_sable',       'skill', 118, 'attack', 'assets/sprites/vfx/tog_spark_sable.png',      75,  51,  31, 33, 0),
  ('fx_sarcophage_des_sables', 'skill', 119, 'attack', 'assets/sprites/vfx/tog_shockwave.png',   112, 64,  8,  71, 0),
  ('fx_pistolet_de_fumee',  'skill', 120, 'attack', 'assets/sprites/vfx/tog_smoke_puff.png',      64,  64,  8,  83, 0),
  ('fx_serpent_de_fumee',   'skill', 121, 'attack', 'assets/sprites/vfx/tog_fumee_beam.png',     297, 84,  32, 67, 0),
  ('fx_fracas_sismique',    'skill', 122, 'attack', 'assets/sprites/vfx/tog_shockwave.png',        112, 64,  8,  71, 0),
  ('fx_faille_sismique',    'skill', 123, 'attack', 'assets/sprites/vfx/tog_ground_blast.png',     224, 216, 32, 100, 0),
  ('fx_vague_de_poison',    'skill', 124, 'attack', 'assets/sprites/vfx/tog_toxic_cloud.png',      148, 80,  32, 125, 0),
  ('fx_hydre_de_poison',    'skill', 125, 'attack', 'assets/sprites/vfx/tog_toxic_puddle.png',     132, 66,  32, 83, 0),
  ('fx_fils_parasites',     'skill', 126, 'attack', 'assets/sprites/vfx/tog_magic_fils.png',      128, 128, 12, 83, 0),
  ('fx_bourrasque_de_fils', 'skill', 127, 'attack', 'assets/sprites/vfx/tog_slash_arc.png',        96,  96,  7,  63, 0),
  ('fx_serres_de_feu_bleu', 'skill', 128, 'attack', 'assets/sprites/vfx/tog_slash_bleu.png',      96,  96,  7,  63, 0),
  ('fx_renaissance_ardente','skill', 129, 'heal',   'assets/sprites/vfx/tog_heal_phenix.png',     80,  112, 12, 83, 1);

-- ------------------------------------------------------------------
-- Réparation de la ligne préexistante « buggy ball » (skill 2) : son
-- spritesheet d'origine (assets/sprites/ball-1792936543089-...png)
-- n'existe plus dans le dépôt. Réaffectée vers l'explosion générée
-- ici, visuellement équivalente (boule qui explose sur la cible).
-- ------------------------------------------------------------------
UPDATE animations
   SET sprite_sheet_path = 'assets/sprites/vfx/tog_explosion.png',
       animation_type = 'attack',
       frame_width = 96, frame_height = 96,
       frame_count = 10, frame_delay_ms = 71, loop = 0
 WHERE name = 'buggy ball';

-- ------------------------------------------------------------------
-- Migration : les sorts des fruits du démon pointent vers leurs effets
-- dédiés recolorés (rampe par fruit) au lieu des presets génériques.
-- Rattrape une base seedée par une révision antérieure du fichier.
-- ------------------------------------------------------------------
UPDATE animations SET sprite_sheet_path = 'assets/sprites/vfx/tog_aura_leopard.png',     frame_width = 96,  frame_height = 112, frame_count = 8,  frame_delay_ms = 83,  loop = 1 WHERE name = 'fx_forme_hybride';
UPDATE animations SET sprite_sheet_path = 'assets/sprites/vfx/tog_portal_night.png',    frame_width = 96,  frame_height = 112, frame_count = 12, frame_delay_ms = 83,  loop = 0 WHERE name = 'fx_vortex_noir';
UPDATE animations SET sprite_sheet_path = 'assets/sprites/vfx/tog_explosion_magma.png', frame_width = 96,  frame_height = 96,  frame_count = 10, frame_delay_ms = 71,  loop = 0 WHERE name = 'fx_poing_de_magma';
UPDATE animations SET sprite_sheet_path = 'assets/sprites/vfx/tog_impact_rose.png',     frame_width = 64,  frame_height = 64,  frame_count = 5,  frame_delay_ms = 63,  loop = 0 WHERE name = 'fx_seize_fleur_prise';
UPDATE animations SET sprite_sheet_path = 'assets/sprites/vfx/tog_smg_rose.png',        frame_width = 112, frame_height = 60,  frame_count = 32, frame_delay_ms = 33,  loop = 0 WHERE name = 'fx_deluge_de_mains';
UPDATE animations SET sprite_sheet_path = 'assets/sprites/vfx/tog_spark_sable.png',     frame_width = 75,  frame_height = 51,  frame_count = 31, frame_delay_ms = 33,  loop = 0 WHERE name = 'fx_jet_de_sable';
UPDATE animations SET sprite_sheet_path = 'assets/sprites/vfx/tog_fumee_beam.png',     frame_width = 297, frame_height = 84,  frame_count = 32, frame_delay_ms = 67,  loop = 0 WHERE name = 'fx_serpent_de_fumee';
UPDATE animations SET sprite_sheet_path = 'assets/sprites/vfx/tog_magic_fils.png',      frame_width = 128, frame_height = 128, frame_count = 12, frame_delay_ms = 83,  loop = 0 WHERE name = 'fx_fils_parasites';
UPDATE animations SET sprite_sheet_path = 'assets/sprites/vfx/tog_slash_bleu.png',       frame_width = 96,  frame_height = 96,  frame_count = 7,  frame_delay_ms = 63,  loop = 0 WHERE name = 'fx_serres_de_feu_bleu';
UPDATE animations SET sprite_sheet_path = 'assets/sprites/vfx/tog_heal_phenix.png',      frame_width = 80,  frame_height = 112, frame_count = 12, frame_delay_ms = 83,  loop = 1 WHERE name = 'fx_renaissance_ardente';
