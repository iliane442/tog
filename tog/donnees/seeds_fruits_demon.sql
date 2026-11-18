-- Seeds des Fruits du Démon (items uniques à pouvoirs).
-- Idempotent : chaque INSERT est protégé (OR IGNORE), les tables par
-- IF NOT EXISTS. Ré-appliquer ce fichier ne duplique rien.
--
-- Exécution :  sqlite3 donnees/glo.db < donnees/seeds_fruits_demon.sql
--
-- Convention d'ids :
--   items  fruits : 900+   skills fruits : 100+
--   (les Gomu Gomu no Pistol/Rifle/Bazooka existants, ids skills 3-5,
--    sont réutilisés tels quels pour le Fruit du Caoutchouc)

PRAGMA foreign_keys = ON;

-- ------------------------------------------------------------------
-- 1. Pouvoirs des fruits (table `skills`)
--    cout PA = base_cooldown (même convention que les sorts existants)
-- ------------------------------------------------------------------
INSERT OR IGNORE INTO skills (id, name, description, base_damage, base_cooldown, type, range) VALUES
  -- Mera Mera no Mi (Flamme)
  (100, 'Poing Ardent',      'Un poing de flammes qui enflamme la cible.',             55,  2, 'attack', 2),
  (101, 'Nova de Flammes',    'Une explosion de feu qui rend la cible vulnérable.',      110, 4, 'attack', 4),
  -- Goro Goro no Mi (Foudre)
  (102, 'Éclair céleste',     'Une décharge de plusieurs millions de volts.',           60,  3, 'attack', 5),
  (103, 'Jugement Divin',     'Un pilier de foudre tombé du ciel, étourdissant.',       130, 5, 'attack', 4),
  -- Hie Hie no Mi (Glace)
  (104, 'Lance de Givre',     'Un épieu de glace qui gèle l''adversaire.',              50,  2, 'attack', 3),
  (105, 'Ère Glaciaire',      'Le sol et l''air se glacent autour de la cible.',        90,  5, 'attack', 3),
  -- Neko Neko no Mi, modèle Léopard (Zoan)
  (106, 'Griffes du Fauve',   'Une volée de griffes qui lacère l''adversaire.',         65,  2, 'attack', 1),
  (107, 'Forme Hybride',      'Transformation partielle : attaque et défense accrues.', 0,   4, 'buff',    0),
  -- Yami Yami no Mi (Ténèbres)
  (108, 'Vortex Noir',        'Un tourbillon de ténèbres qui attire la cible.',        40,  3, 'attack', 2),
  (109, 'Étreinte des Ténèbres', 'Les ténèbres happent la cible et la fragilisent.',   120, 5, 'attack', 3);

INSERT OR IGNORE INTO skill_status_effects (skill_id, status_effect_id, chance, duration, value) VALUES
  -- 1=Étourdissement 3=Brûlure 4=Gel 5=Ralentissement 9=Attraction
  -- 13=Boost d'attaque 14=Boost de défense 17=Vulnérabilité
  (100, 3,  0.5, 2, 0.15),  -- Poing Ardent : brûlure
  (101, 3,  1.0, 2, 0.20),  -- Nova de Flammes : brûlure
  (101, 17, 0.4, 2, 0.30),  -- Nova de Flammes : vulnérabilité
  (102, 1,  0.3, 1, 0.00),  -- Éclair céleste : étourdissement
  (103, 1,  0.5, 1, 0.00),  -- Jugement Divin : étourdissement
  (103, 17, 0.5, 2, 0.30),  -- Jugement Divin : vulnérabilité
  (104, 4,  0.4, 1, 0.00),  -- Lance de Givre : gel
  (105, 4,  0.6, 2, 0.00),  -- Ère Glaciaire : gel
  (105, 5,  1.0, 2, 1.00),  -- Ère Glaciaire : ralentissement
  (106, 17, 0.3, 2, 0.25),  -- Griffes du Fauve : vulnérabilité
  (107, 13, 1.0, 3, 0.30),  -- Forme Hybride : boost d'attaque
  (107, 14, 1.0, 3, 0.20),  -- Forme Hybride : boost de défense
  (108, 9,  0.7, 1, 1.00),  -- Vortex Noir : attraction
  (109, 17, 1.0, 2, 0.40);  -- Étreinte des Ténèbres : vulnérabilité

-- ------------------------------------------------------------------
-- 2. Les fruits (table `items`)
--    type 'fruit_demon', sous-type = catégorie (paramecia/logia/zoan)
--    rarité 6 = Mythique ; non échangeables ; trouvables (droppables)
--    Passifs via effects_json (clés lues par Personnage.recalculer_stats)
-- ------------------------------------------------------------------
INSERT OR IGNORE INTO items (
  id, name, type, subtype, rarity_id, description,
  base_price, is_craftable, is_tradable, is_droppable,
  min_level, effects_json, is_active
) VALUES
  (900, 'Fruit du Caoutchouc — Gomu Gomu no Mi', 'fruit_demon', 'paramecia', 6,
   'Le corps devient élastique : les impacts sont amortis. Qui le mange devient un homme-caoutchouc, incapable de nager. Un seul fruit par personne : en manger un second est mortel.',
   50000, 0, 0, 0, 5, '{"defense": 10, "vie": 20}', 1),
  (901, 'Fruit de la Flamme — Mera Mera no Mi', 'fruit_demon', 'logia', 6,
   'Le corps devient flammes : feu éternel. L''utilisateur contrôle le feu à volonté mais l''eau le rend impuissant. Un seul fruit par personne : en manger un second est mortel.',
   50000, 0, 0, 0, 5, '{"attack": 15}', 1),
  (902, 'Fruit de la Foudre — Goro Goro no Mi', 'fruit_demon', 'logia', 6,
   'Le corps devient électricité : l''utilisateur foudroie à distance et se déplace à la vitesse de l''éclair. Un seul fruit par personne : en manger un second est mortel.',
   50000, 0, 0, 0, 5, '{"intelligence": 10, "speed": 5}', 1),
  (903, 'Fruit de la Glace — Hie Hie no Mi', 'fruit_demon', 'logia', 6,
   'Le corps devient glace : l''utilisateur gèle tout ce qu''il touche. Un seul fruit par personne : en manger un second est mortel.',
   50000, 0, 0, 0, 5, '{"defense": 10}', 1),
  (904, 'Fruit du Léopard — Neko Neko no Mi, modèle Léopard', 'fruit_demon', 'zoan', 6,
   'Transformation en léopard : force, vitesse et instincts prédateurs décuplés. Un fruit Zoan accroît les capacités physiques de son utilisateur. Un seul fruit par personne : en manger un second est mortel.',
   50000, 0, 0, 0, 5, '{"force": 10, "speed": 10}', 1),
  (905, 'Fruit des Ténèbres — Yami Yami no Mi', 'fruit_demon', 'paramecia', 6,
   'Ténèbres qui aspirent et annihilent tout. Contrairement aux Logia, son utilisateur ne devient pas intangible : il attire la douleur comme un aimant. Un seul fruit par personne : en manger un second est mortel.',
   50000, 0, 0, 0, 10, '{"attack": 10, "vie": 20}', 1);

-- ------------------------------------------------------------------
-- 3. Lien fruit -> pouvoirs
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS fruit_skills (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  fruit_item_id INTEGER NOT NULL,
  skill_id INTEGER NOT NULL,
  unlock_level INTEGER NOT NULL DEFAULT 1,
  is_eveil BOOLEAN NOT NULL DEFAULT 0,
  FOREIGN KEY (fruit_item_id) REFERENCES items(id),
  FOREIGN KEY (skill_id) REFERENCES skills(id),
  UNIQUE (fruit_item_id, skill_id)
);

-- liens de base : la structure complète (4 sorts + 1 éveil par fruit)
-- est définie dans seeds_fruits_eveils.sql, à exécuter après ce fichier
INSERT OR IGNORE INTO fruit_skills (fruit_item_id, skill_id, unlock_level, is_eveil) VALUES
  -- Fruit du Caoutchouc : sorts existants 3-5
  (900, 3,   0, 0), (900, 4, 2, 0), (900, 5, 3, 0),
  -- Flamme
  (901, 100, 0, 0), (901, 101, 3, 0),
  -- Foudre
  (902, 102, 0, 0), (902, 103, 3, 0),
  -- Glace
  (903, 104, 0, 0), (903, 105, 3, 0),
  -- Léopard
  (904, 106, 0, 0), (904, 107, 3, 0),
  -- Ténèbres
  (905, 108, 0, 0), (905, 109, 3, 0);

-- ------------------------------------------------------------------
-- 4. Registre d'unicité mondiale
--    Une ligne par item unique ; l'absence de ligne ou is_consumed=0
--    signifie « disponible dans le monde ». Le champ owner_player_id
--    sert lors de l'implémentation de la consommation (étape GDScript).
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS unique_items (
  item_id INTEGER PRIMARY KEY,
  owner_player_id INTEGER,
  is_consumed BOOLEAN NOT NULL DEFAULT 0,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (item_id) REFERENCES items(id)
);

INSERT OR IGNORE INTO unique_items (item_id, owner_player_id, is_consumed) VALUES
  (900, NULL, 0),
  (901, NULL, 0),
  (902, NULL, 0),
  (903, NULL, 0),
  (904, NULL, 0),
  (905, NULL, 0);

-- ------------------------------------------------------------------
-- 5. Deuxième fournée : fruits 906-915, pouvoirs 110-129
-- ------------------------------------------------------------------

INSERT OR IGNORE INTO skills (id, name, description, base_damage, base_cooldown, type, range) VALUES
  -- Ope Ope no Mi (Bistouri)
  (110, 'Scalpel Affûté', 'Une entaille chirurgicale qui fragilise la cible.',        45,  2, 'attack', 2),
  (111, 'Gamma Scalpel',  'Une onde qui tranche de l''intérieur — dégâts internes.',   95,  5, 'attack', 3),
  -- Pika Pika no Mi (Lumière)
  (112, 'Salve de Lumière',     'Des rayons tirés à la vitesse de la lumière.',       65,  3, 'attack', 5),
  (113, 'Lame Céleste',         'Une épée de lumière qui éblouit et étourdit.',       120, 5, 'attack', 4),
  -- Magu Magu no Mi (Magma)
  (114, 'Poing de Magma',       'Un magma en fusion qui brûle plus que la flamme.',    75,  2, 'attack', 2),
  (115, 'Éruption',             'Le sol se fend et engloutit la cible sous le magma.', 140, 5, 'attack', 3),
  -- Hana Hana no Mi (Fleurs)
  (116, 'Seize Fleur — Prise',  'Des bras éclosent sur la cible et l''immobilisent.',  30,  2, 'attack', 2),
  (117, 'Déluge de Mains',      'Une nuée de poings s''abat sur l''adversaire.',       100, 5, 'attack', 3),
  -- Suna Suna no Mi (Sable)
  (118, 'Jet de Sable',         'Un sable tranchant projeté à distance.',             50,  2, 'attack', 4),
  (119, 'Sarcophage des Sables','Les sables ensevelissent et aspirent la cible.',     85,  5, 'attack', 3),
  -- Moku Moku no Mi (Fumée)
  (120, 'Pistolet de Fumée',    'Un jet dense de fumée qui ralentit la cible.',        45,  2, 'attack', 3),
  (121, 'Serpent de Fumée',     'Un reptile de fumée enserre et aveugle l''ennemi.',   90,  4, 'attack', 4),
  -- Gura Gura no Mi (Séisme)
  (122, 'Fracas Sismique',     'Un coup qui fait trembler l''air et repousse tout.',  100, 4, 'attack', 3),
  (123, 'Faille Sismique',      'Une fissure de la taille d''un quai s''ouvre.',      160, 6, 'attack', 3),
  -- Doku Doku no Mi (Poison)
  (124, 'Vague de Poison',      'Un poison visqueux qui ronge l''ennemi au fil du temps.', 35, 2, 'attack', 3),
  (125, 'Hydre de Poison',      'Un démon de venin qui corrompt tout ce qu''il touche.',   95, 5, 'attack', 4),
  -- Ito Ito no Mi (Fils)
  (126, 'Fils Parasites',       'Des fils manipulent le corps adverse comme une marionnette.', 25, 3, 'attack', 4),
  (127, 'Bourrasque de Fils',   'Un cocon de fils lacère l''adversaire de part en part.',    110, 5, 'attack', 4),
  -- Tori Tori no Mi, modèle Phénix (Zoan mythique)
  (128, 'Serres de Feu Bleu',   'Des serres ardentes qui embrasent la cible.',         55,  2, 'attack', 2),
  (129, 'Renaissance Ardente',  'Les flammes bleues du phénix régénèrent le corps.',   -100, 5, 'heal',   1);

INSERT OR IGNORE INTO skill_status_effects (skill_id, status_effect_id, chance, duration, value) VALUES
  (110, 17, 0.4, 2, 0.30),   -- Scalpel : vulnérabilité
  (111, 17, 0.5, 2, 0.40),   -- Gamma Scalpel : vulnérabilité
  (112, 6,  0.3, 1, 0.50),   -- Salve de Lumière : cécité
  (113, 6,  0.5, 1, 0.60),   -- Lame Céleste : cécité
  (113, 1,  0.3, 1, 0.00),   -- Lame Céleste : étourdissement
  (114, 3,  0.7, 2, 0.25),   -- Poing de Magma : brûlure
  (115, 3,  1.0, 3, 0.30),   -- Éruption : brûlure
  (115, 17, 0.5, 2, 0.30),   -- Éruption : vulnérabilité
  (116, 1,  0.35, 1, 0.00),  -- Seize Fleur : étourdissement
  (117, 5,  0.5, 2, 1.00),   -- Déluge de Mains : ralentissement
  (118, 6,  0.3, 1, 0.40),   -- Jet de Sable : cécité
  (119, 5,  1.0, 2, 1.00),   -- Sarcophage : ralentissement
  (119, 8,  0.6, 1, 2.00),   -- Sarcophage : repousse de 2 cases
  (120, 5,  0.5, 2, 1.00),   -- Pistolet de Fumée : ralentissement
  (121, 6,  0.4, 1, 0.50),   -- Serpent de Fumée : cécité
  (121, 5,  0.6, 2, 1.00),   -- Serpent de Fumée : ralentissement
  (122, 8,  0.8, 1, 2.00),   -- Fracas Sismique : repousse
  (123, 8,  1.0, 1, 3.00),   -- Faille Sismique : repousse de 3 cases
  (123, 17, 0.4, 2, 0.30),   -- Faille Sismique : vulnérabilité
  (124, 2,  0.6, 3, 0.20),   -- Vague de Poison : empoisonnement
  (125, 2,  1.0, 3, 0.30),   -- Hydre de Poison : empoisonnement
  (125, 17, 0.4, 2, 0.30),   -- Hydre de Poison : vulnérabilité
  (126, 1,  0.4, 1, 0.00),   -- Fils Parasites : étourdissement
  (126, 5,  1.0, 2, 1.00),   -- Fils Parasites : ralentissement
  (127, 1,  0.5, 1, 0.00),   -- Bourrasque de Fils : étourdissement
  (128, 3,  0.4, 2, 0.15),   -- Serres de Feu Bleu : brûlure
  (129, 12, 1.0, 2, 0.10);   -- Renaissance Ardente : régénération (10 % PV / tour)

INSERT OR IGNORE INTO items (
  id, name, type, subtype, rarity_id, description,
  base_price, is_craftable, is_tradable, is_droppable,
  min_level, effects_json, is_active
) VALUES
  (906, 'Fruit du Bistouri — Ope Ope no Mi', 'fruit_demon', 'paramecia', 6,
   'Le fruit ultime : une sphère dans laquelle l''utilisateur peut découper et réarranger toute chose. Surnommé le fruit qui peut soigner le monde — ou le détruire. Un seul fruit par personne : en manger un second est mortel.',
   120000, 0, 0, 0, 10, '{"agilite": 10, "intelligence": 10}', 1),
  (907, 'Fruit de la Lumière — Pika Pika no Mi', 'fruit_demon', 'logia', 6,
   'Le corps devient lumière : l''utilisateur se déplace et frappe à une vitesse inégalée. Un seul fruit par personne : en manger un second est mortel.',
   60000, 0, 0, 0, 5, '{"speed": 15}', 1),
  (908, 'Fruit du Magma — Magu Magu no Mi', 'fruit_demon', 'logia', 6,
   'Le corps devient magma : l''utilisateur est intouchable et son magma surpasse même les flammes. À bout portant, rien ne lui résiste. Un seul fruit par personne : en manger un second est mortel.',
   70000, 0, 0, 0, 8, '{"attack": 20, "defense": -5}', 1),
  (909, 'Fruit des Fleurs — Hana Hana no Mi', 'fruit_demon', 'paramecia', 6,
   'Des bras éclosent n''importe où sur le corps de l''utilisateur — et sur tout ce qu''il touche. Un seul fruit par personne : en manger un second est mortel.',
   55000, 0, 0, 0, 5, '{"force": 10}', 1),
  (910, 'Fruit du Sable — Suna Suna no Mi', 'fruit_demon', 'logia', 6,
   'Le corps devient sable : l''utilisateur contrôle les déserts et absorbe l''eau. Sauf sous la pluie. Un seul fruit par personne : en manger un second est mortel.',
   55000, 0, 0, 0, 5, '{"intelligence": 10}', 1),
  (911, 'Fruit de la Fumée — Moku Moku no Mi', 'fruit_demon', 'logia', 6,
   'Le corps devient fumée : impossible à saisir, l''utilisateur enlace ses ennemis de nuées cendrées. Un seul fruit par personne : en manger un second est mortel.',
   50000, 0, 0, 0, 5, '{"defense": 10, "speed": 5}', 1),
  (912, 'Fruit du Séisme — Gura Gura no Mi', 'fruit_demon', 'paramecia', 6,
   'Le fruit le plus puissant des Paramecia : celui qui le mange peut détruire le monde. Chaque coup fend l''air et la mer. Un seul fruit par personne : en manger un second est mortel.',
   100000, 0, 0, 0, 10, '{"force": 15, "vie": 30}', 1),
  (913, 'Fruit du Poison — Doku Doku no Mi', 'fruit_demon', 'paramecia', 6,
   'L''utilisateur génère et contrôle les poisons les plus virulents ; son corps reste de chair, mais ses toxines tuent en un souffle. Un seul fruit par personne : en manger un second est mortel.',
   65000, 0, 0, 0, 10, '{"intelligence": 15}', 1),
  (914, 'Fruit des Fils — Ito Ito no Mi', 'fruit_demon', 'paramecia', 6,
   'Des fils invisibles dont l''utilisateur fait des armes, des ailes et des marionnettes. Un seul fruit par personne : en manger un second est mortel.',
   60000, 0, 0, 0, 10, '{"agilite": 15, "intelligence": 5}', 1),
  (915, 'Fruit du Phénix — Tori Tori no Mi, modèle Phénix', 'fruit_demon', 'zoan', 6,
   'Un Zoan mythique : des flammes bleues qui ne brûlent pas — elles régénèrent. L''utilisateur renaît de ses cendres. Un seul fruit par personne : en manger un second est mortel.',
   80000, 0, 0, 0, 10, '{"vie": 50, "speed": 10}', 1);

INSERT OR IGNORE INTO fruit_skills (fruit_item_id, skill_id, unlock_level, is_eveil) VALUES
  (906, 110, 0, 0), (906, 111, 3, 0),  -- Bistouri
  (907, 112, 0, 0), (907, 113, 3, 0),  -- Lumière
  (908, 114, 0, 0), (908, 115, 3, 0),  -- Magma
  (909, 116, 0, 0), (909, 117, 3, 0),  -- Fleurs
  (910, 118, 0, 0), (910, 119, 3, 0),  -- Sable
  (911, 120, 0, 0), (911, 121, 3, 0),  -- Fumée
  (912, 122, 0, 0), (912, 123, 3, 0),  -- Séisme
  (913, 124, 0, 0), (913, 125, 3, 0),  -- Poison
  (914, 126, 0, 0), (914, 127, 3, 0),  -- Fils
  (915, 128, 0, 0), (915, 129, 3, 0);  -- Phénix (Renaissance = signature)

INSERT OR IGNORE INTO unique_items (item_id, owner_player_id, is_consumed) VALUES
  (906, NULL, 0),
  (907, NULL, 0),
  (908, NULL, 0),
  (909, NULL, 0),
  (910, NULL, 0),
  (911, NULL, 0),
  (912, NULL, 0),
  (913, NULL, 0),
  (914, NULL, 0),
  (915, NULL, 0);

-- ------------------------------------------------------------------
-- 6. Fruits exclus du tirage normal des coffres
--    Les fruits n'apparaissent QUE par le tirage dédié de coffres.gd
--    (Coffres.proba_fruit = 1/10000 par ouverture) : ils ne doivent
--    donc pas être éligibles au tirage pondéré par rareté (Mythique).
--    Ce UPDATE rattrape aussi les bases seedées par une révision
--    antérieure du fichier (is_droppable = 1).
-- ------------------------------------------------------------------
UPDATE items
   SET is_droppable = 0
 WHERE type = 'fruit_demon' AND is_droppable != 0;

-- ------------------------------------------------------------------
-- 7. Aucun niveau minimum sur les fruits : un fruit trouvé est
--    immédiatement mangeable, quel que soit le niveau du perso
--    (rattrape aussi les bases seedées avec min_level > 1).
-- ------------------------------------------------------------------
UPDATE items
   SET min_level = 1
 WHERE type = 'fruit_demon' AND min_level != 1;

-- ------------------------------------------------------------------
-- 8. Icônes individuelles des fruits dans l'inventaire et le wiki
-- ------------------------------------------------------------------
WITH icones(item_id, fichier) AS (
  VALUES
    (900, '900_fruit_du_caoutchouc.png'),
    (901, '901_fruit_de_la_flamme.png'),
    (902, '902_fruit_de_la_foudre.png'),
    (903, '903_fruit_de_la_glace.png'),
    (904, '904_fruit_du_leopard.png'),
    (905, '905_fruit_des_tenebres.png'),
    (906, '906_fruit_du_bistouri.png'),
    (907, '907_fruit_de_la_lumiere.png'),
    (908, '908_fruit_du_magma.png'),
    (909, '909_fruit_des_fleurs.png'),
    (910, '910_fruit_du_sable.png'),
    (911, '911_fruit_de_la_fumee.png'),
    (912, '912_fruit_du_seisme.png'),
    (913, '913_fruit_du_poison.png'),
    (914, '914_fruit_des_fils.png'),
    (915, '915_fruit_du_phenix.png')
)
UPDATE items
   SET icon_path = 'assets/items/fruits_demon/' || icones.fichier
  FROM icones
 WHERE items.id = icones.item_id
   AND items.type = 'fruit_demon'
   AND COALESCE(items.icon_path, '') IN ('', 'assets/sprites/items/fruits-mythe-oni.webp');
