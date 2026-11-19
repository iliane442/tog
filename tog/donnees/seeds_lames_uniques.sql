-- Seeds des 20 lames uniques (armes mythiques, un exemplaire par monde).
-- Idempotent : les ids étant explicites, INSERT OR IGNORE protège les
-- ré-exécutions.
--
-- Exécution :  sqlite3 donnees/glo.db < donnees/seeds_lames_uniques.sql
--
-- Convention d'ids :
--   items lames uniques : 951+ (fruits : 900+, fruits 910-915, 950 wiki)
--
-- Même mécanique que les fruits du démon :
--   - rarity_id 6 = Mythique, is_droppable = 0 : sortent uniquement du
--     tirage dédié _tirer_lame_unique() de coffres.gd (coffres légendaires),
--     jamais du tirage de rareté normal ;
--   - une ligne dans `unique_items` : registre d'unicité mondiale ;
--   - is_tradable = 0 : une lame unique ne se vend ni s'échange.
--
-- L'absence d'icône retombe sur l'icône générique d'arme dans l'UI
-- (menu.gd, ICONES_EMPLACEMENTS["arme"]).
--
-- grades canoniques : Saijo O Wazamono (suprême, 12 lames),
-- O Wazamono (excellent, 21), Ryo Wazamono (habile, 50).

PRAGMA foreign_keys = ON;

-- ------------------------------------------------------------------
-- 1. Les lames (table `items`)
--    effets via effects_json (clés lues par Personnage.recalculer_stats :
--    attack / defense / speed / vie / force / agilite / chance ...)
-- ------------------------------------------------------------------
INSERT OR IGNORE INTO items (
  id, name, type, subtype, rarity_id, description,
  base_price, is_craftable, is_tradable, is_droppable,
  min_level, effects_json, is_active
) VALUES
  -- Saijo O Wazamono (grade suprême)
  (951, 'Yoru', 'arme', 'épée', 6,
   'Lame noire de Mihawk, « le plus fort bretteur du monde ». Saijo O Wazamono : l''une des douze lames de grade suprême. Sa taille démesurée tranche les galères en deux d''un seul geste, à distance.',
   250000, 0, 0, 0, 95, '{"attack": 95, "agilite": 25}', 1),
  (952, 'Murakumogiri', 'arme', 'bisento', 6,
   'Le bisento colossal de Barbe Blanche. Saijo O Wazamono : l''une des douze lames de grade suprême, capable d''engloutir des flottes entières quand son porteur frappe le ciel et la mer.',
   230000, 0, 0, 0, 85, '{"attack": 88, "force": 22}', 1),
  -- Kitetsu : lignée de lames maudites
  (953, 'Shodai Kitetsu', 'arme', 'épée', 6,
   'La première-née de la lignée maudite des Kitetsu, portée disparue depuis des décennies. Sa soif de sang choisit son maître : quiconque n''en est pas digne y laisse un membre.',
   200000, 0, 0, 0, 80, '{"attack": 78, "agilite": 18}', 1),
  (954, 'Nidai Kitetsu', 'arme', 'épée', 6,
   'Deuxième lame maudite des Kitetsu, conservée à Wano. Même tranchant surnaturel, même malédiction : elle échappe à la mort pour frapper sans être arrêtée.',
   150000, 0, 0, 0, 62, '{"attack": 60, "force": 12}', 1),
  (955, 'Sandai Kitetsu', 'arme', 'épée', 6,
   'Troisième lame maudite des Kitetsu. Un bretteur digne peut l''apprivoiser ; les autres perdent leurs doigts un à un. La lame choisit, jamais l''inverse.',
   80000, 0, 0, 0, 32, '{"attack": 31, "force": 6}', 1),
  -- O Wazamono (grade excellent)
  (956, 'Enma', 'arme', 'épée', 6,
   'Lame d''Oden qui « tranche jusqu''au fond des choses ». O Wazamono : elle aspire le Haki du bretteur et refuse les coups tièdes. Même Mihawk la juge digne d''une lame noire.',
   210000, 0, 0, 0, 78, '{"attack": 74, "force": 16}', 1),
  (957, 'Ame no Habakiri', 'arme', 'épée', 6,
   'La seconde lame d''Oden. O Wazamono : « sabre qui tranche le ciel ». Elle trancha le seigneur des mers Kaido, aucun obstacle n''y a résisté depuis.',
   195000, 0, 0, 0, 75, '{"attack": 72, "force": 14}', 1),
  (958, 'Shusui', 'arme', 'épée', 6,
   'Lame noire du samouraï Ryuma, le légendaire tueur du dragon de Wano. O Wazamono devenue lame noire : plus lourde, plus rigide, elle refuse de trancher ce que son porteur ne juge pas juste.',
   170000, 0, 0, 0, 58, '{"attack": 56, "force": 10, "defense": 4}', 1),
  (959, 'Wado Ichimonji', 'arme', 'épée', 6,
   '« Lame de la voie droite ». O Wazamono léguée par Kuina, promesse de devenir le plus fort bretteur du monde. Trois épées en main, celle-ci est le serment.',
   140000, 0, 0, 0, 44, '{"attack": 42, "force": 8, "vie": 15}', 1),
  -- Lames canoniques célèbres hors classement
  (960, 'Kikoku', 'arme', 'épée', 6,
   'Le nodachi maudit du Chirurgien de la Mort. On murmure qu''il égorge les âmes faibles qui l''approchent ; seuls les esprits solides osent la dégainer.',
   185000, 0, 0, 0, 68, '{"attack": 66, "agilite": 14}', 1),
  (961, 'Napoleon', 'arme', 'épée', 6,
   'Le chapeau-lame d''une empereur des mers. Nourri d''âmes, il durcit en lame capable d''envoyer une île à terre en un seul coup de bord.',
   190000, 0, 0, 0, 70, '{"attack": 68, "defense": 8, "vie": 30}', 1),
  (962, 'Soul Solid', 'arme', 'épée', 6,
   'La canne-épée de Brook, fine comme une lame de rasoir. Imprégnée du pouvoir de l''au-delà, son tranchant glacial traverse le bois et la chair sans effort.',
   120000, 0, 0, 0, 48, '{"attack": 45, "speed": 8}', 1),
  -- Ryo Wazamono (grade habile)
  (963, 'Shigure', 'arme', 'épée', 6,
   'Lame de la lance des brumes. Ryo Wazamono : plus fine qu''un crin, elle fend la pluie avant que les gouttes ne retombent.',
   90000, 0, 0, 0, 36, '{"attack": 35, "agilite": 8}', 1),
  (964, 'Yamaoroshi', 'arme', 'épée', 6,
   '« Celle qui abat les montagnes ». Ryo Wazamono saisie dans un magasin de Loguetown : une lame de marine que les experts traquent depuis des années.',
   70000, 0, 0, 0, 28, '{"attack": 27, "force": 5}', 1),
  (965, 'Yubashiri', 'arme', 'épée', 6,
   '« Lame de mille chevaux ». Ryo Wazamono, légère et fiable, offerte à Loguetown par un marchand qui reconnut un bretteur digne de ce nom.',
   65000, 0, 0, 0, 26, '{"attack": 25, "agilite": 6}', 1),
  (966, 'Kashu', 'arme', 'épée', 6,
   '« Lame fleurissante ». Ryo Wazamono, réputée pour sa tenue de lame impeccable du pommeau à la pointe.',
   60000, 0, 0, 0, 24, '{"attack": 23, "force": 4}', 1),
  -- Lames originales du Grand Line
  (967, 'Veuve des Mers', 'arme', 'épée', 6,
   'Forgée dans l''épave d''un navire de la rançon de Florian. On dit que sa pointe cherche le cœur des hommes qui ont déjà menti à leur équipage.',
   160000, 0, 0, 0, 66, '{"attack": 64, "chance": 12}', 1),
  (968, 'Croc du Léviathan', 'arme', 'épée', 6,
   'Une dent de serpent de mer géant, polie en lame par les forgerons de Wano. Elle garde l''odeur du large et la morsure qui va avec.',
   130000, 0, 0, 0, 52, '{"attack": 50, "force": 12}', 1),
  (969, 'Sillage d''Argent', 'arme', 'épée', 6,
   'Katana du Nouveau Monde : sa lame moirée laisse un sillage dans l''air, et chaque coup une éraflure de plus sur les boucliers de ses victimes.',
   100000, 0, 0, 0, 40, '{"attack": 38, "agilite": 10, "speed": 5}', 1),
  (970, 'Aube Pourpre', 'arme', 'épée', 6,
   'Lame de l''aube appartenant à un bretteur venu de nulle part. Portée à travers les Blues, elle ouvrit la voie vers le Grand Line à plus d''un mousse.',
   60000, 0, 0, 0, 20, '{"attack": 20, "force": 4, "vie": 10}', 1);

-- ------------------------------------------------------------------
-- 2. Registre d'unicité mondiale
--    Une ligne par lame ; disponible tant que is_consumed = 0 et que le
--    joueur ne la possède pas (exclusion gérée par coffres.gd).
-- ------------------------------------------------------------------
INSERT OR IGNORE INTO unique_items (item_id) VALUES
  (951), (952), (953), (954), (955), (956), (957), (958), (959), (960),
  (961), (962), (963), (964), (965), (966), (967), (968), (969), (970);
