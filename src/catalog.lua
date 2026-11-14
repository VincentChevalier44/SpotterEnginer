-- Catalogue des clips de voix : fichier par langue (vox/FR, vox/EN) et texte dit, pour chaque clip. Les annonces sont des
-- suites de clips (phrases composées) ; un clip absent du disque rend l'annonce écrite seulement (radio de l'overlay).
-- Les textes sont ceux réellement dits. Tous les clips sont générés par tools/generer_voix.py (même voix que les clips
-- d'origine 01 à 34 : edge-tts, fr-FR-HenriNeural et en-US-GuyNeural) ; liste : vox/VOICE_CLIPS.md, refaite par
-- tests/run.py à partir de ce fichier. Sous-dossiers : nombres (num/), durées (sec/), positions (pos/) ; bornes et
-- nombre de fichiers attendus définis ici seulement (C.maxNumber, C.maxTenths, C.maxPosition, C.fileCount).
local C={}
C.languages={'FR','EN'}
-- Sous-dossiers des clips dans vox/<LANGUE> (lus par src/port.lua, générés par tools/generer_voix.py).
C.subfolders={'','num/','sec/','pos/','F/','F/num/','F/sec/','F/pos/'}
-- Voix du spotter (1.3.9, choix du pilote : voix féminine, Denise en français, Jenny en anglais ; l'ingénieur garde
-- la voix masculine). C.spotterOnly : clips dits seulement par le spotter, en voix féminine à leur place. C.shared :
-- clips dits par les deux rôles (et mots des nombres), en voix masculine à leur place et féminine dans F/ ; nombres,
-- durées et positions aussi (F/num, F/sec, F/pos). Le spotter prend la version de F/ quand elle existe (src/say.lua).
C.femaleDir='F/'
-- Denise et non Vivienne (multilingue) : Vivienne lisait en anglais les nombres et les mots courts (« 7 » : « seven »,
-- constaté en jeu par le pilote le 14/11/2026, même avec la langue française déclarée).
C.femaleVoices={FR='fr-FR-DeniseNeural',EN='en-US-JennyNeural'}
-- Nombres dits de 0 à C.maxNumber (num/ ; jusqu'à C.maxSpoken avec le clip « cent »), durées de 0 à C.maxTenths
-- dixièmes de seconde (sec/).
C.maxNumber=99
C.maxSpoken=999
C.maxTenths=99
-- Signal d'ouverture de la radio (dossier de l'app).
C.toneFile='sounds/radio.wav'
-- id = {numéro, fichier FR, texte FR, fichier EN, texte EN} ; numéros 114 et 193 libres (clips retirés, jamais réutilisés).
local list={
 {'green',1,'01_vert',"Drapeau vert, la piste est claire, on relance.",'01_green',"Green flag, track is clear, push."},
 {'yellow',2,'02_jaune_simple',"Drapeau jaune, lève le pied, interdiction de dépasser.",'02_yellow_single',"Yellow flag, slow down, no overtaking."},
 {'yellow2',3,'03_jaune_double',"Double drapeau jaune, gros danger devant, prépare-toi à t'arrêter.",'03_yellow_double',"Double yellow, major hazard ahead, be prepared to stop."},
 {'red',4,'04_rouge',"Drapeau rouge, séance interrompue. Rentre aux stands immédiatement.",'04_red',"Red flag, session suspended. Box immediately."},
 {'white',5,'05_blanc',"Drapeau blanc, véhicule très lent devant. Sois prudent.",'05_white',"White flag, slow vehicle ahead. Caution."},
 {'slippery',6,'06_jaune_bandes_rouges',"Attention, piste glissante, baisse d'adhérence.",'06_yellow_red_stripes',"Slippery surface, watch your grip."},
 {'sc',7,'07_SC',"Voiture de sécurité déployée. Reste en file, pas de dépassements.",'07_SC',"Safety car deployed. Catch the pack, no overtaking."},
 {'vsc',8,'08_VSC',"Voiture de sécurité virtuelle. Respecte ton delta de temps, lève le pied.",'08_VSC',"Virtual safety car. Watch your delta, keep it positive."},
 {'rs',9,'09_RS',"Départ lancé, garde ta position jusqu'à la ligne.",'09_RS',"Rolling start, hold your position until the line."},
 {'ss',10,'10_SS',"Départ arrêté, mets-toi en place sur la grille.",'10_SS',"Standing start, get on your grid spot."},
 {'blue',11,'11_bleu',"Drapeau bleu, laisse passer la voiture derrière toi.",'11_blue',"Blue flag, let the faster car through."},
 -- Réservé (texte d'origine sur les limites de piste) : le noir et blanc d'AdvancedIA est le dernier avertissement
 -- avant disqualification (clip 125).
 {'blackWhite',12,'12_noir_blanc',"Avertissement pour limites de piste. Fais attention à tes trajectoires.",'12_black_white',"Black and white flag, track limits warning. Keep it clean."},
 {'blackOrange',13,'13_noir_orange',"Drapeau noir et orange. Tu as des dégâts, rentre aux stands pour réparer.",'13_black_orange',"Meatball flag, you have damage. Box for repairs."},
 {'black',14,'14_noir',"Drapeau noir. Tu es disqualifié, rentre aux stands et coupe le moteur.",'14_black',"Black flag. You are disqualified, box and switch off."},
 {'chequered',15,'15_damier',"Drapeau à damier, c'est terminé. Rentre aux stands.",'15_chequered',"Chequered flag, session is over. Bring it home."},
 {'deltaNeg',16,'16_delta_negatif',"Attention, ton delta est négatif, ralentis pour ne pas prendre de pénalité.",'16_delta_negative',"Warning, your delta is negative. Slow down to avoid a penalty."},
 {'deltaPos',17,'17_delta_positif',"Delta positif, garde ce rythme.",'17_delta_positive',"Delta is positive, keep this pace."},
 {'giveBack',18,'18_rendre_place',"Tu as doublé sous drapeau jaune. Rends la position immédiatement pour annuler la pénalité.",'18_give_place_back',"You overtook under a yellow flag. Give the position back immediately to cancel the penalty."},
 {'penaltyThrottle',19,'19_penalite_gaz',"Pénalité reçue, coupure des gaz.",'19_penalty_throttle',"Penalty received, throttle cut."},
 -- Réservé (texte d'origine) : ni AC ni AdvancedIA ne donnent le compte d'infractions de limites de piste du joueur ;
 -- « encore une infraction et c'est la disqualification » ne peut donc pas être affirmé. Les coupes ont le clip 93.
 {'trackLimits',20,'20_limites_piste_avertissement',"Attention, tu as dépassé les limites de la piste. Encore une infraction et c'est la disqualification.",'20_track_limits_warning',"Warning, you exceeded track limits. One more strike and you're disqualified."},
 {'flash',21,'21_appel_phares_recu',"Appel de phares reçu, la voiture devant va s'écarter.",'21_flash_received',"Flash received, the car ahead will move over."},
 {'fasterBehind',22,'22_trafic_rapide_derriere',"Trafic plus rapide en approche derrière, garde ta ligne.",'22_faster_traffic_behind',"Faster traffic approaching from behind, hold your line."},
 {'stoppedAhead',23,'23_voiture_arretee_devant',"Voiture arrêtée sur la piste devant, sois prudent.",'23_stopped_car_ahead',"Stopped car on track ahead, be careful."},
 {'aiMistake',24,'24_erreur_ia_devant',"Erreur de pilotage de l'IA devant toi.",'24_ai_mistake_ahead',"AI driver mistake ahead of you."},
 {'vscEnding',25,'25_fin_vsc_10s',"Fin de la VSC dans 10 secondes, prépare-toi pour la relance.",'25_vsc_ending_10s',"VSC ending in 10 seconds, get ready for the restart."},
 {'scIn',26,'26_sc_rentre_ce_tour',"La voiture de sécurité rentre à la fin de ce tour.",'26_sc_in_this_lap',"Safety car is in at the end of this lap."},
 {'pitOpen',27,'27_pit_window_open',"La fenêtre d'arrêt aux stands est ouverte.",'27_pit_window_open',"The pit window is now open."},
 {'pitClosing',28,'28_pit_window_closing',"La fenêtre de stand ferme bientôt, c'est le moment de rentrer.",'28_pit_window_closing',"The pit window is closing soon, time to box."},
 {'pitLaneClosed',29,'29_pit_lane_closed',"La voie des stands est fermée suite à la neutralisation.",'29_pit_lane_closed',"The pit lane is closed due to the neutralization."},
 {'stintLimit',30,'30_stint_limite',"Fin de ton temps de relais autorisée, tu dois t'arrêter.",'30_stint_limit',"Maximum stint time reached, you need to box."},
 {'drsOn',31,'31_drs_dispo',"DRS disponible.",'31_drs_available',"DRS is available."},
 {'drsOff',32,'32_drs_desactive',"DRS désactivé par la direction de course.",'32_drs_disabled',"DRS disabled by race control."},
 {'rain',33,'33_pluie_intense',"La pluie s'intensifie, on prépare les pneus pluie pour le prochain arrêt.",'33_rain_intensifying',"Rain is intensifying, we're getting wet tires ready for the next stop."},
 {'overtake',34,'34_mode_depassement',"Mode dépassement disponible.",'34_overtake_mode',"Overtake mode is available."},
 -- Spotter
 {'fcy',35,'35_fcy','Full course yellow, ralentis et respecte ton delta.','35_fcy','Full course yellow, slow down and keep your delta.'},
 {'carLeft',36,'36_voiture_gauche','Voiture à gauche.','36_car_left','Car left.'},
 {'carRight',37,'37_voiture_droite','Voiture à droite.','37_car_right','Car right.'},
 {'threeWide',38,'38_trois_de_front','Trois de front, tu es au milieu.','38_three_wide','Three wide, you\'re in the middle.'},
 {'clearLeft',39,'39_degage_gauche','Dégagé à gauche.','39_clear_left','Clear left.'},
 {'clearRight',40,'40_degage_droite','Dégagé à droite.','40_clear_right','Clear right.'},
 {'clear',41,'41_degage','Dégagé.','41_clear','Clear.'},
 {'stillThere',42,'42_toujours_la','Toujours là.','42_still_there','Still there.'},
 {'pitExitClear',43,'43_sortie_stands_libre','Sortie des stands libre.','43_pit_exit_clear','Pit exit is clear.'},
 {'pitExitTraffic',44,'44_sortie_stands_trafic','Trafic à la sortie des stands, attention.','44_pit_exit_traffic','Traffic at pit exit, careful.'},
 {'backmarker',45,'45_retardataire_devant','Retardataire devant.','45_backmarker_ahead','Backmarker ahead.'},
 {'gapAhead',46,'46_ecart_devant','Écart devant :','46_gap_ahead','Gap ahead:'},
 {'gapBehind',47,'47_ecart_derriere','Écart derrière :','47_gap_behind','Gap behind:'},
 {'closing',48,'48_tu_reviens','Tu reviens.','48_closing','You\'re closing.'},
 {'hesClosing',49,'49_il_revient','Il revient sur toi.','49_hes_closing','He\'s closing on you.'},
 {'rivalPenalty',50,'50_penalite_adversaire','Pénalité pour la voiture','50_rival_penalty','Penalty for the car'},
 {'wordAhead',51,'51_devant','devant.','51_ahead','ahead.'},
 {'wordBehind',52,'52_derriere','derrière.','52_behind','behind.'},
 -- Ingénieur
 {'push',53,'53_attaque','Attaque maintenant, c\'est le moment.','53_push_now','Push now, this is the moment.'},
 {'hold',54,'54_garde_position','Garde ta position, gère l\'écart.','54_hold_station','Hold station, manage the gap.'},
 {'liftCoast',55,'55_lift_and_coast','Économise le carburant, lift and coast.','55_lift_and_coast','Save fuel, lift and coast.'},
 {'fuelOk',56,'56_carburant_ok','Carburant bon jusqu\'à l\'arrivée.','56_fuel_ok','Fuel is good to the end.'},
 {'fuelTarget',57,'57_cible_carburant','Cible carburant :','57_fuel_target','Fuel target:'},
 {'boxThisLap',58,'58_box_ce_tour','Box, box, ce tour-ci.','58_box_this_lap','Box, box, this lap.'},
 {'boxNextLap',59,'59_box_tour_prochain','Box au prochain tour.','59_box_next_lap','Box next lap.'},
 {'undercut',60,'60_undercut','Undercut possible.','60_undercut','Undercut is on.'},
 {'overcut',61,'61_overcut','On reste dehors, overcut.','61_overcut','Stay out, overcut.'},
 {'tyresCold',62,'62_pneus_froids','Pneus froids, fais-les chauffer.','62_tyres_cold','Tyres are cold, get some heat in.'},
 {'tyresHot',63,'63_pneus_surchauffe','Pneus en surchauffe, ménage-les.','63_tyres_overheating','Tyres overheating, look after them.'},
 {'tyresOk',64,'64_pneus_temperature','Pneus à température.','64_tyres_in_window','Tyres are in the window.'},
 {'brakesHot',65,'65_freins_chauds','Freins très chauds.','65_brakes_hot','Brakes are very hot.'},
 {'biasRear',66,'66_repartition_arriere','Recule la répartition de freinage.','66_bias_rearward','Move brake bias rearward.'},
 {'biasFront',67,'67_repartition_avant','Avance la répartition de freinage.','67_bias_forward','Move brake bias forward.'},
 {'aeroDamage',68,'68_degats_aero','Dégâts aéro détectés.','68_aero_damage','We see aero damage.'},
 {'abnormalWear',69,'69_usure_anormale','Usure anormale d\'un pneu.','69_abnormal_wear','Abnormal tyre wear.'},
 {'gripDown',70,'70_adherence_baisse','L\'adhérence baisse.','70_grip_dropping','Grip is dropping.'},
 {'gripUp',71,'71_adherence_hausse','La piste s\'améliore.','71_track_improving','Track is improving.'},
 {'rainIn',72,'72_pluie_attendue','Pluie attendue dans','72_rain_expected','Rain expected in'},
 {'minutes',73,'73_minutes','minutes.','73_minutes','minutes.'},
 {'tailwind',74,'74_vent_arriere_freinage','Vent arrière au freinage, freine plus tôt.','74_tailwind_braking','Tailwind into braking, brake earlier.'},
 {'headwind',75,'75_vent_face_freinage','Vent de face au freinage, tu peux freiner plus tard.','75_headwind_braking','Headwind into braking, you can brake later.'},
 {'goodPace',76,'76_bon_rythme','Bon rythme, continue.','76_good_pace','Good pace, keep it up.'},
 {'losingTime',77,'77_tu_perds_du_temps','Tu perds du temps','77_losing_time','You\'re losing time'},
 {'brakeLater',78,'78_freine_plus_tard','Tu freines trop tôt.','78_braking_early','You\'re braking too early.'},
 {'carrySpeed',79,'79_vitesse_en_courbe','Garde plus de vitesse en courbe.','79_carry_more_speed','Carry more speed through the corner.'},
 {'mapSave',80,'80_map_economie','Passe en map économie.','80_map_save','Engine map to save.'},
 {'mapPush',81,'81_map_attaque','Passe en map attaque.','81_map_push','Engine map to push.'},
 {'seconds',82,'82_secondes','secondes.','82_seconds','seconds.'},
 {'point',83,'83_virgule','virgule','83_point','point'},
 {'laps',84,'84_tours','tours.','84_laps','laps.'},
 {'pitWindow',85,'85_fenetre_arret','Fenêtre d\'arrêt du tour','85_pit_window','Pit window from lap'},
 {'toLap',86,'86_au_tour','au tour','86_to_lap','to lap'},
 {'optimalLap',87,'87_tour_optimal','Tour optimal :','87_optimal_lap','Optimal lap:'},
 {'plus',88,'88_plus','plus','88_plus','plus'},
 {'minus',89,'89_moins','moins','89_minus','minus'},
 {'targetDelta',90,'90_delta_cible','Delta sur le temps cible :','90_target_delta','Delta to target lap:'},
 {'atSector',91,'91_au_secteur','au secteur','91_at_sector','in sector'},
 {'rivalPitted',92,'92_adversaire_aux_stands','La voiture devant rentre aux stands.','92_rival_pitted','Car ahead is pitting.'},
 {'trackCut',93,'93_coupe_piste','Coupe de piste, attention aux limites.','93_track_cut','Track limits, watch your lines.'},
 -- Évènements d'AdvancedIA (annonces et panneau du pilote) qui n'avaient pas de voix.
 {'sessionResume',94,'94_reprise_seance',"Drapeau vert, la séance reprend. Sors des stands l'un après l'autre.",'94_session_resume',"Green flag, the session resumes. Leave the pits one after another."},
 {'redRestartSc',95,'95_relance_sc',"Reprise de la course derrière la voiture de sécurité, dépassement interdit.",'95_restart_behind_sc',"Race resumes behind the safety car, no overtaking."},
 {'redRestartVsc',96,'96_relance_vsc',"Reprise de la course sous VSC, respecte ton delta.",'96_restart_under_vsc',"Race resumes under VSC, keep your delta."},
 {'redRestartFcy',97,'97_relance_fcy',"Reprise de la course sous full course yellow, respecte ton delta.",'97_restart_under_fcy',"Race resumes under full course yellow, keep your delta."},
 {'penaltyDelta',98,'98_penalite_delta',"Pénalité, delta négatif sous drapeau. Coupure des gaz.",'98_penalty_delta',"Penalty, negative delta under the flag. Throttle cut."},
 {'penaltyPass',99,'99_penalite_depassement',"Pénalité, dépassement sous drapeau. Coupure des gaz.",'99_penalty_overtake',"Penalty, overtaking under the flag. Throttle cut."},
 {'penaltyRed',100,'100_penalite_drapeau_rouge',"Pénalité, reprise hors des stands après le drapeau rouge.",'100_penalty_red_flag',"Penalty, you rejoined outside the pits after the red flag."},
 {'penaltyStop',101,'101_penalite_arret',"Pénalité, arrêt obligatoire non effectué.",'101_penalty_missed_stop',"Penalty, mandatory pit stop not served."},
 {'penaltyJump',102,'102_penalite_faux_depart',"Pénalité pour faux départ, coupure des gaz.",'102_penalty_jump_start',"Penalty for a jump start, throttle cut."},
 {'drsIn',103,'103_drs_dans',"DRS autorisé dans",'103_drs_in',"DRS enabled in"},
 {'drsEnabled',104,'104_drs_autorise',"DRS autorisé par la direction de course.",'104_drs_enabled',"DRS enabled by race control."},
 {'trackWet',105,'105_piste_humide',"La piste devient humide, pneus pluie au prochain arrêt.",'105_track_wet',"The track is getting wet, rain tyres at the next stop."},
 {'trackDry',106,'106_piste_seche',"La piste sèche, retour aux pneus secs au prochain arrêt.",'106_track_dry',"The track is drying, back to slicks at the next stop."},
 {'pitWaived',107,'107_arret_leve',"Course mouillée, le changement de composé n'est plus obligatoire.",'107_compound_rule_lifted',"Wet race, the compound change is no longer mandatory."},
 {'standingPit',108,'108_depart_stands',"Tu pars depuis la voie des stands.",'108_pit_lane_start',"You start from the pit lane."},
 {'formationLap',109,'109_tour_formation',"Tour de formation, rejoins ta place sur la grille.",'109_formation_lap',"Formation lap, get back to your grid slot."},
 {'lightsOn',110,'110_feux_allumes',"Les feux s'allument, prépare-toi.",'110_lights_on',"Lights are coming on, get ready."},
 {'go',111,'111_go',"Go, go, go !",'111_go',"Go, go, go!"},
 {'jumpStart',112,'112_faux_depart',"Faux départ !",'112_jump_start',"Jump start!"},
 {'scCall',113,'113_sc_appelee',"Voiture de sécurité appelée, ralentis et respecte ton delta.",'113_safety_car_called',"Safety car called, slow down and keep your delta."},
 {'driveThrough',115,'115_drive_through',"Pénalité, drive-through.",'115_drive_through',"Penalty, drive-through."},
 {'penaltyPits',116,'116_retour_stands',"Pénalité, retour aux stands.",'116_back_to_pits',"Penalty, back to the pits."},
 {'lastLap',117,'117_dernier_tour',"Dernier tour !",'117_last_lap',"This is the last lap!"},
 {'giveBackDone',118,'118_place_rendue',"Place rendue, c'est bon.",'118_place_given_back',"Place given back, all good."},
 {'gridPlaced',119,'119_en_place',"Tu es en place.",'119_in_position',"You're in position."},
 {'gridPassed',120,'120_place_depassee',"Tu as dépassé ta place sur la grille.",'120_slot_passed',"You've passed your grid slot."},
 {'aiDq',121,'121_ia_disqualifiee',"Une voiture est disqualifiée.",'121_car_disqualified',"A car has been disqualified."},
 {'andBehind',122,'122_derriere_ecart',"Derrière :",'122_behind_gap',"Behind:"},
 {'defend',123,'123_defends',"Défends ta position.",'123_defend',"Defend your position."},
 {'zoneGreen',124,'124_vert_fin_jaune',"Vert, fin du jaune.",'124_green_yellow_over',"Green, yellow is over."},
 {'lastWarning',125,'125_dernier_avertissement',"Dernier avertissement : la prochaine infraction te disqualifie.",'125_final_warning',"Final warning: the next offence disqualifies you."},
 -- Avis d'arrêt d'AdvancedIA (Beta 1.49, règles F1) : l'arrêt obligatoire ne compte qu'avec un autre composé sec.
 -- Textes vrais quel que soit le nombre d'arrêts obligatoires ; les composés sont écrits sur la radio (texte d'AdvancedIA).
 {'pitCompound',126,'126_changer_compose',"Arrêt obligatoire : change de composé, sinon l'arrêt ne comptera pas.",'126_change_compound',"Mandatory stop: change compound, or the stop won't count."},
 {'pitPlanSame',127,'127_strategie_meme_compose',"Ta stratégie d'arrêt prévoit le même composé. Change-la, sinon l'arrêt ne comptera pas.",'127_plan_same_compound',"Your pit strategy has the same compound. Change it, or the stop won't count."},
 {'pitNotCounted',128,'128_arret_non_compte',"Arrêt non compté, même composé. L'arrêt obligatoire reste à faire.",'128_stop_not_counted',"Stop not counted, same compound. The mandatory stop is still due."},
 {'pitValidated',129,'129_arret_valide',"Arrêt validé, changement de composé pris en compte.",'129_stop_validated',"Stop validated, compound change counted."},
 -- Reprise (AdvancedIA 1.50) : place figée du joueur (suivie du nombre), voiture à suivre (nom écrit, ou la voiture de
 -- sécurité), voiture à doubler pour reprendre sa place (nom écrit).
 {'restartPlace',130,'130_place_reprise',"Place de reprise :",'130_restart_position',"Restart position:"},
 {'behindSc',131,'131_derriere_sc',"derrière la voiture de sécurité.",'131_behind_safety_car',"behind the safety car."},
 {'restartRetake',132,'132_reprends_ta_place',"Reprends ta place : double la voiture devant toi.",'132_retake_your_place',"Take your place back: pass the car ahead."},
 -- Position du joueur (ingénieur, à la ligne quand elle change ; « Tu es P7 » : vox/<LANGUE>/pos/07.wav), puis un
 -- conseil tiré de la course : voiture devant rattrapable, pneus à ménager, place gagnée dans le tour. Dernier tour
 -- (avec « Dernier tour ! » du spotter) : voiture devant à portée, voiture juste derrière, ou ramener la voiture.
 {'posReach',133,'133_a_portee',"Il est à portée, force un peu, tu peux y arriver.",'133_within_reach',"He's within reach, push a little, you can do it."},
 {'posTyres',134,'134_securise_pneus',"Fais attention à tes pneus, sécurise un peu.",'134_mind_your_tyres',"Look after your tyres, take it a bit safer."},
 {'posGained',135,'135_bien_joue',"Bien joué.",'135_nice_job',"Nice job."},
 {'lastReach',136,'136_dernier_tour_attaque',"Il est à portée, donne tout !",'136_last_lap_push',"He's within reach, give it everything!"},
 {'lastDefend',137,'137_dernier_tour_defends',"Il est juste derrière, ferme la porte.",'137_last_lap_defend',"He's right behind you, close the door."},
 {'lastSafe',138,'138_dernier_tour_ramene',"Ramène-la à la maison, sans prendre de risque.",'138_last_lap_bring_home',"Bring it home, no risks."},
 -- Unités au singulier, choisies par src/say.lua selon la valeur dite (« 1,5 tour », « 1 lap ») ; une minute : nombre
 -- et unité dans le même clip (« une minute », féminin en français).
 {'secondOne',139,'139_seconde','seconde.','139_second','second.'},
 {'lapOne',140,'140_tour','tour.','140_lap','lap.'},
 {'oneMinute',141,'141_une_minute','une minute.','141_one_minute','one minute.'},
 -- Essais et qualifications (AdvancedIA 1.51, annonce 'fastCar') : une IA en tour lancé arrive derrière le joueur en
 -- tour de sortie ou de refroidissement.
 {'fastCar',142,'142_voiture_tour_lance',"Voiture en tour lancé derrière, laisse-la passer.",'142_flying_lap_behind',"Car on a flying lap behind, let it through."},
 -- Bilan de fin de course (src/debrief.lua) : arrivée et place (spotter, puis « Tu es P2 »), places gagnées ou perdues
 -- et dépassements (après un nombre, accordés par src/say.lua), meilleur tour de la course, verdict de l'ingénieur.
 {'raceDone',143,'143_damier_course_terminee',"Drapeau à damier, course terminée !",'143_chequered_race_over',"Chequered flag, race over!"},
 {'raceOver',144,'144_course_terminee',"Course terminée.",'144_race_over',"Race over."},
 {'placesGained',145,'145_places_gagnees',"places gagnées depuis le départ.",'145_places_gained',"places gained since the start."},
 {'placeGained',146,'146_place_gagnee',"place gagnée depuis le départ.",'146_place_gained',"place gained since the start."},
 {'placesLost',147,'147_places_perdues',"places perdues depuis le départ.",'147_places_lost',"places lost since the start."},
 {'placeLost',148,'148_place_perdue',"place perdue depuis le départ.",'148_place_lost',"place lost since the start."},
 {'placeKept',149,'149_meme_place',"Même place qu'au départ.",'149_same_place',"Same place as on the grid."},
 {'overtakes',150,'150_depassements',"dépassements en piste.",'150_overtakes',"overtakes on track."},
 {'overtakeOne',151,'151_depassement',"dépassement en piste.",'151_overtake',"overtake on track."},
 {'fastestLap',152,'152_meilleur_tour_course',"Et le meilleur tour de la course !",'152_fastest_lap',"And the fastest lap of the race!"},
 {'debriefWin',153,'153_bilan_victoire',"Victoire ! Une course maîtrisée, bravo, c'est magnifique !",'153_debrief_win',"You won! A controlled race, well done, brilliant!"},
 {'debriefPodium',154,'154_bilan_podium',"Sur le podium, superbe course, bravo !",'154_debrief_podium',"On the podium, superb race, well done!"},
 {'debriefTop5',155,'155_bilan_top5',"Très belle course, bien joué.",'155_debrief_top5',"Very nice race, well done."},
 {'debriefTop10',156,'156_bilan_top10',"Course solide, bien joué.",'156_debrief_top10',"Solid race, good job."},
 {'debriefComeback',157,'157_bilan_remontee',"Belle remontée, c'est encourageant.",'157_debrief_comeback',"Nice comeback, that's encouraging."},
 {'debriefTough',158,'158_bilan_difficile',"Course difficile, on analysera ça ensemble.",'158_debrief_tough',"Tough race, we'll go through it together."},
 {'debriefOther',159,'159_bilan_progresser',"On continue de progresser, chaque course compte.",'159_debrief_keep_going',"We keep improving, every race counts."},
 {'debriefDnf',160,'160_bilan_abandon',"Pas classé cette fois, on repart de l'avant.",'160_debrief_dnf',"Not classified this time, we go again."},
 {'debriefDq',161,'161_bilan_disqualifie',"Disqualifié. On en reparlera au débrief.",'161_debrief_dq',"Disqualified. We'll talk about it at the debrief."},
 -- Radio vivante (1.3.0) : variantes d'une même annonce (of : clip de base du groupe, même sens, autre formulation) et
 -- ton de chaque clip (tone : neutral, calm, urgent, motivating, frustrated ; neutral sans précision). Une variante est
 -- un vrai clip (texte dit = texte écrit) ; src/say.lua choisit selon le ton demandé, jamais la même deux fois de suite.
 -- Le ton donne aussi la prosodie du clip (tools/generer_voix.py : débit et hauteur), jamais un style SSML.
 {'posGained_b',162,'162_bien_joue_superbe',"Superbe dépassement, bravo !",'162_great_move',"Great move, well done!",of='posGained',tone='motivating'},
 {'posGained_c',163,'163_bien_joue_continue',"Joli coup, continue comme ça !",'163_nice_one',"Nice one, keep it going!",of='posGained',tone='motivating'},
 {'posGained_d',164,'164_bien_joue_manoeuvre',"Bien vu, belle manœuvre.",'164_clean_move',"Good job, clean move.",of='posGained'},
 {'goodPace_b',165,'165_bon_rythme_garde',"C'est un bon rythme, garde ça.",'165_good_pace_keep',"That's a good pace, keep it there.",of='goodPace'},
 {'goodPace_c',166,'166_tres_bon_tour',"Très bon tour, tu es dans le coup !",'166_great_lap',"Great lap, you're right on it!",of='goodPace',tone='motivating'},
 {'push_b',167,'167_attaque_allez',"Allez, c'est le moment, attaque !",'167_push_come_on',"Come on, now's the time, push!",of='push',tone='motivating'},
 {'push_c',168,'168_il_faut_pousser',"Il faut pousser maintenant.",'168_need_to_push',"We need to push now.",of='push'},
 {'hold_b',169,'169_tranquille_gere',"Tranquille, gère l'écart, pas de risque.",'169_easy_manage',"Easy now, manage the gap, no risks.",of='hold',tone='calm'},
 {'hold_c',170,'170_position_controle',"On gère, la position est sous contrôle.",'170_under_control',"We're managing it, position is under control.",of='hold',tone='calm'},
 {'defend_b',171,'171_il_attaque_protege',"Il attaque, protège ta position !",'171_protect_position',"He's attacking, protect your position!",of='defend',tone='urgent'},
 {'defend_c',172,'172_couvre_interieur',"Couvre l'intérieur aux freinages.",'172_cover_inside',"Cover the inside into the braking zones.",of='defend'},
 {'closing_b',173,'173_tu_reviens_bien',"Tu reviens bien, continue !",'173_reeling_in',"You're reeling him in, keep going!",of='closing',tone='motivating'},
 {'closing_c',174,'174_ecart_fond',"L'écart fond.",'174_gap_coming_down',"The gap is coming down.",of='closing'},
 {'hesClosing_b',175,'175_il_te_reprend',"Il te reprend du temps.",'175_taking_time',"He's taking time out of you.",of='hesClosing'},
 {'hesClosing_c',176,'176_il_revient_fort',"Il revient fort derrière !",'176_coming_back_hard',"He's coming back hard behind you!",of='hesClosing',tone='urgent'},
 {'clear_b',177,'177_cest_degage',"C'est dégagé.",'177_all_clear',"All clear.",of='clear'},
 {'fasterBehind_b',178,'178_voiture_rapide_place',"Voiture rapide derrière, laisse-lui la place.",'178_quicker_car_room',"Quicker car behind, give it room.",of='fasterBehind'},
 {'backmarker_b',179,'179_attarde_devant',"Attardé devant, attention en le doublant.",'179_lapped_car_ahead',"Lapped car ahead, careful passing it.",of='backmarker'},
 -- Écarts et positions vivants : dans la seconde, écart stable, qui se creuse, place perdue en piste.
 {'inSecond',180,'180_dans_la_seconde',"Tu es dans la seconde, à toi de jouer !",'180_within_a_second',"You're within a second, go for it!",tone='motivating'},
 {'inSecond_b',181,'181_moins_une_seconde',"Moins d'une seconde devant, tu es dans le coup.",'181_under_a_second',"Under a second to the car ahead, you're in range.",of='inSecond'},
 {'heInSecond',182,'182_il_est_dans_ta_seconde',"Il est dans ta seconde, attention derrière !",'182_he_is_within_a_second',"He's within a second behind, watch your mirrors!",tone='urgent'},
 {'heInSecond_b',183,'183_moins_une_seconde_derriere',"Il est à moins d'une seconde derrière.",'183_under_a_second_behind',"He's under a second behind.",of='heInSecond'},
 {'gapStable',184,'184_ecart_stable',"Écart stable.",'184_gap_stable',"Gap is stable.",tone='calm'},
 {'pullingAway',185,'185_tu_creuses',"Tu creuses l'écart, continue !",'185_pulling_away',"You're pulling away, keep it up!",tone='motivating'},
 {'escaping',186,'186_il_s_echappe',"Il s'échappe devant.",'186_he_is_pulling_away',"He's pulling away ahead."},
 {'posLost',187,'187_il_est_passe',"Il est passé. On reste calme, on va le reprendre.",'187_he_got_by',"He got by. Stay calm, we'll get him back.",tone='frustrated'},
 {'posLost_b',188,'188_dommage_remobilise',"Dommage. On se remobilise, il est encore à portée.",'188_shame_regroup',"Shame. Regroup, he's still within reach.",of='posLost',tone='frustrated'},
 {'posLost_c',189,'189_place_perdue_concentre',"Place perdue. Reste concentré.",'189_position_lost_focus',"Position lost. Stay focused.",of='posLost'},
 {'clearBehind',190,'190_rien_derriere',"Rien derrière, tu peux tenter.",'190_nothing_behind',"Nothing behind, you can have a go."},
 -- Dangers devant, annoncés selon le temps pour les atteindre (src/hazards.lua) : nature, puis côté et conseil.
 {'spinAhead',191,'191_tete_a_queue_devant',"Tête-à-queue devant !",'191_spin_ahead',"Car spinning ahead!",tone='urgent'},
 {'wrongWay',192,'192_contresens_devant',"Voiture à contresens devant !",'192_wrong_way_ahead',"Car going the wrong way ahead!",tone='urgent'},
 {'stoppedAhead_b',194,'194_voiture_arretee_devant',"Voiture arrêtée devant !",'194_stopped_car_ahead',"Stopped car ahead!",of='stoppedAhead',tone='urgent'},
 {'onLeft',195,'195_elle_est_a_gauche',"Elle est à gauche.",'195_on_the_left',"It's on the left.",tone='urgent'},
 {'onRight',196,'196_elle_est_a_droite',"Elle est à droite.",'196_on_the_right',"It's on the right.",tone='urgent'},
 {'onMiddle',197,'197_en_pleine_trajectoire',"En pleine trajectoire !",'197_on_the_racing_line',"Right on the racing line!",tone='urgent'},
 {'offTrack',198,'198_hors_de_la_piste',"Hors de la piste.",'198_off_the_track',"Off the track."},
 {'passLeft',199,'199_passe_a_gauche',"Passe à gauche.",'199_go_left',"Go left.",tone='urgent'},
 {'passRight',200,'200_passe_a_droite',"Passe à droite.",'200_go_right',"Go right.",tone='urgent'},
 -- Accrochage entre deux voitures devant (contact suivi d'une forte perte de vitesse) : jamais « débris », qu'AC ne
 -- simule pas.
 {'tangleAhead',201,'201_accrochage_devant',"Accrochage devant, prudence !",'201_contact_ahead',"Contact between cars ahead, careful!",tone='urgent'},
 -- Voiture qui arrive à côté depuis l'arrière, avant le côte à côte ; dépassement fini (la voiture est derrière).
 {'incomingLeft',202,'202_il_arrive_a_gauche',"Il arrive à gauche !",'202_coming_up_left',"Coming up on your left!",tone='urgent'},
 {'incomingRight',203,'203_il_arrive_a_droite',"Il arrive à droite !",'203_coming_up_right',"Coming up on your right!",tone='urgent'},
 {'clearPassed',204,'204_tu_es_passe',"C'est bon, tu es passé, rabats-toi.",'204_you_are_clear',"You're clear, you can move over."},
 -- Urgences du joueur (src/emergency.lua) : contact, choc, bilan des dégâts, crevaison, tête-à-queue et reprise.
 {'contact',205,'205_contact',"Contact !",'205_contact',"Contact!",tone='urgent'},
 {'wallHit',206,'206_gros_choc',"Gros choc ! On regarde les dégâts.",'206_big_hit',"Big hit! We're checking the damage.",tone='urgent'},
 {'damageNone',207,'207_pas_de_degats',"Pas de dégâts, c'est bon, continue.",'207_no_damage',"No damage, you're fine, carry on.",tone='calm'},
 {'damageLight',208,'208_degats_legers',"Dégâts légers, tu peux continuer.",'208_light_damage',"Light damage, you can carry on.",tone='calm'},
 {'damageMedium',209,'209_degats_moyens',"Dégâts moyens, la voiture est touchée. On surveille.",'209_moderate_damage',"Moderate damage, the car's hurt. We'll keep an eye on it.",tone='frustrated'},
 {'damageHeavy',210,'210_gros_degats',"Gros dégâts. Rentre aux stands.",'210_heavy_damage',"Heavy damage. Box, box.",tone='urgent'},
 {'damageSuspension',211,'211_suspension_touchee',"Suspension touchée. Rentre doucement aux stands.",'211_suspension_damage',"Suspension damage. Bring it back to the pits carefully.",tone='urgent'},
 {'puncture',212,'212_crevaison',"Crevaison ! Rentre doucement aux stands.",'212_puncture',"Puncture! Bring it back to the pits slowly.",tone='urgent'},
 {'spunYou',213,'213_tete_a_queue_freins',"Tête-à-queue ! Reste sur les freins, voitures en approche.",'213_spun_brakes',"You've spun! Stay on the brakes, cars coming.",tone='urgent'},
 {'spunClear',214,'214_tete_a_queue_libre',"Tête-à-queue. C'est libre, repars quand tu es prêt.",'214_spun_clear',"You've spun. It's clear, go when you're ready.",tone='calm'},
 {'waitTraffic',215,'215_attends_voiture',"Voiture qui arrive, attends !",'215_car_coming_wait',"Car coming, wait!",tone='urgent'},
 {'goNow',216,'216_cest_libre_vas_y',"C'est libre, vas-y.",'216_clear_go',"It's clear, go now."},
 {'rejoinCareful',217,'217_attention_reprise',"Attention en reprenant la piste, voiture qui arrive !",'217_careful_rejoining',"Careful rejoining, car coming!",tone='urgent'},
 {'youWrongWay',218,'218_tu_es_a_contresens',"Tu es à contresens ! Fais demi-tour quand c'est libre.",'218_you_are_wrong_way',"You're facing the wrong way! Turn around when it's clear.",tone='urgent'},
 {'stoppedYou',219,'219_tu_es_arrete',"Tu es arrêté sur la piste, attention aux voitures.",'219_you_are_stopped',"You're stopped on track, watch the traffic.",tone='urgent'},
 -- Stratégie argumentée (src/strategist.lua) : l'ingénieur décide seul et dit pourquoi.
 {'undercutGo',220,'220_on_tente_undercut',"On tente l'undercut.",'220_going_for_undercut',"We're going for the undercut.",tone='motivating'},
 {'overcutStay',221,'221_on_reste_overcut',"On reste dehors, on fait l'overcut.",'221_stay_out_overcut',"Stay out, we'll do the overcut."},
 {'scBoxGain',222,'222_on_profite_neutralisation',"On profite de la neutralisation.",'222_use_neutralisation',"Let's use the neutralisation.",tone='motivating'},
 {'stayOutNeutral',223,'223_on_reste_dehors_neutralisation',"On reste dehors, l'arrêt ne vaut pas le coup.",'223_stay_out_not_worth',"Stay out, a stop isn't worth it.",tone='calm'},
 {'coverThreat',224,'224_menace_undercut',"La voiture derrière peut tenter l'undercut, pousse ce tour !",'224_undercut_threat',"The car behind could try the undercut, push this lap!",tone='urgent'},
 {'coverStop',225,'225_il_rentre_on_couvre',"Il rentre, on couvre.",'225_he_pits_we_cover',"He's pitting, we cover."},
 {'noMoreStops',226,'226_plus_d_arret',"Plus d'arrêt prévu, on va jusqu'au bout.",'226_no_more_stops',"No more stops, we go to the end.",tone='calm'},
 {'weGain',227,'227_on_gagne_environ',"On gagne environ",'227_gains_us_about',"That gains us about"},
 -- Centaines (nombres de 100 à 999, src/say.lua) : « cent » + reste, « deux » + « cent » + reste ; « one » + « hundred ».
 {'hundred',228,'228_cent',"cent",'228_hundred',"hundred"},
 -- Tour de formation avant un départ lancé (AdvancedIA 1.60, annonce « formation », extra 1) : la place se garde dans
 -- la file (le clip 109 parle de la grille : départ arrêté).
 {'formationRoll',229,'229_tour_formation_lance',"Tour de formation, garde ta place dans la file, le départ sera lancé.",'229_formation_rolling',"Formation lap, hold your place in the queue, it's a rolling start."},
 -- Drapeau bleu en deux temps et classe plus rapide (AdvancedIA 1.61, nuance des classes) ; bascule de pneus annoncée
 -- à l'avance (météo en direct d'AdvancedIA), suivie du nombre de minutes.
 {'blueAdvise',230,'230_bleu_approche',"Voiture plus rapide en approche, prépare-toi à la laisser passer.",'230_blue_advise',"Faster car closing in, get ready to let it through."},
 {'blueClass',231,'231_classe_plus_rapide',"Classe plus rapide derrière, garde ta ligne et laisse-la passer.",'231_faster_class',"Faster class behind, hold your line and let it through."},
 {'crossWet',232,'232_passage_pneus_pluie',"Passage aux pneus pluie dans",'232_rain_tyres_in',"Rain tyres in"},
 {'crossDry',233,'233_retour_pneus_secs',"Retour aux pneus secs dans",'233_slicks_in',"Back to slicks in"},
 -- SetupLab (1.3.9, app facultative, src/setuplab.lua) : verdict des tours d'essai, groupe de réglages changé, version prête.
 {'setupBetter',234,'234_reglage_plus_rapide',"Le nouveau réglage est plus rapide, de",'234_setup_faster',"The new setup is faster, by"},
 {'setupWorse',235,'235_reglage_plus_lent',"Le nouveau réglage est plus lent, de",'235_setup_slower',"The new setup is slower, by"},
 {'setupSame',236,'236_reglage_pareil',"Pas de différence nette avec le nouveau réglage.",'236_setup_same',"No clear difference with the new setup."},
 {'setupReady',237,'237_version_prete',"Nouvelle version du setup prête, à essayer au stand.",'237_setup_ready',"New setup version ready, try it in the pits."},
 {'setupAero',238,'238_principal_aero',"Changement principal : l'aéro.",'238_main_aero',"Main change: aero."},
 {'setupSprings',239,'239_principal_ressorts',"Changement principal : les ressorts.",'239_main_springs',"Main change: springs."},
 {'setupDampers',240,'240_principal_amortisseurs',"Changement principal : les amortisseurs.",'240_main_dampers',"Main change: dampers."},
 {'setupArb',241,'241_principal_barres',"Changement principal : les barres antiroulis.",'241_main_arb',"Main change: anti-roll bars."},
 {'setupHeight',242,'242_principal_hauteur',"Changement principal : la hauteur de caisse.",'242_main_height',"Main change: ride height."},
 {'setupAlignment',243,'243_principal_geometrie',"Changement principal : la géométrie.",'243_main_alignment',"Main change: alignment."},
 {'setupPressure',244,'244_principal_pressions',"Changement principal : les pressions des pneus.",'244_main_pressures',"Main change: tyre pressures."},
 {'setupDiff',245,'245_principal_differentiel',"Changement principal : le différentiel.",'245_main_diff',"Main change: differential."},
 {'setupBrakes',246,'246_principal_freins',"Changement principal : les freins.",'246_main_brakes',"Main change: brakes."},
 {'setupGears',247,'247_principal_rapports',"Changement principal : les rapports de boîte.",'247_main_gears',"Main change: gear ratios."},
 {'setupFuel',248,'248_principal_carburant',"Changement principal : le carburant.",'248_main_fuel',"Main change: fuel load."},
 -- Arrêt obligatoire levé en course trop courte (AdvancedIA Beta 1.63).
 {'pitShort',249,'249_course_trop_courte',"Course trop courte, pas d'arrêt obligatoire.",'249_race_too_short',"Race too short, no mandatory stop."},
 -- Jaune d'avertissement (AdvancedIA Beta 1.63) : voiture lente au bord, dépassement permis.
 {'slowWarn',250,'250_jaune_avertissement',"Jaune d'avertissement, voiture lente au bord de la piste. Prudence, dépassement permis.",'250_warning_yellow',"Warning yellow, slow car on the edge of the track. Take care, overtaking allowed."},
 -- Course sprint (AdvancedIA 1.64, 100 km au plus) : arrêt obligatoire levé.
 {'pitSprint',251,'251_course_sprint',"Course sprint, pas d'arrêt obligatoire.",'251_sprint_race',"Sprint race, no mandatory stop."},
 -- Départ interrompu (AdvancedIA 1.64) : un tour de plus, puis départ arrêté ou lancé.
 {'startDelayed',252,'252_depart_interrompu',"Départ interrompu, on refait un tour. Nouveau départ arrêté ensuite.",'252_start_aborted',"Start aborted, one more lap. Then a new standing start."},
 {'startDelayedRoll',253,'253_depart_interrompu_lance',"Départ interrompu, on refait un tour. Départ lancé ensuite.",'253_start_aborted_rolling',"Start aborted, one more lap. Then a rolling start."},
}
-- Précisions écrites seulement sur la radio (jamais dites), par langue : format string.format (src/say.lua, Say.note).
C.notes={
 behind={FR='(derrière %s)',EN='(behind %s)'},
 inMeters={FR='(à %d m)',EN='(in %d m)'},
 sidesFlipped={FR='Côtés gauche / droite inversés automatiquement (piste de CSP).',EN='Left / right swapped automatically (CSP track position).'},
 perLap={FR='/tour',EN='/lap'},
 coverUndercut={FR="(couvrir l'undercut)",EN='(cover the undercut)'},
 undercutMargin={FR='(devant de %s s après les arrêts)',EN='(ahead by %s s after the stops)'},
 neutralised={FR='(neutralisation)',EN='(neutralised)'},
 debriefPlaces={FR='(départ P%d → arrivée P%d)',EN='(start P%d → finish P%d)'},
 debriefBest={FR='(meilleur tour %s)',EN='(best lap %s)'},
 debriefPassed={FR='(dépassé %d fois)',EN='(passed %d times)'},
}
C.spotterOnly={
 'green','yellow','yellow2','slippery','sc','vsc','rs','ss','blue','blackWhite','blackOrange','black','chequered',
 'deltaNeg','deltaPos','giveBack','penaltyThrottle','flash','fasterBehind','stoppedAhead','aiMistake','vscEnding',
 'scIn','pitClosing','pitLaneClosed','stintLimit','drsOn','drsOff','fcy','carLeft','carRight','threeWide','clearLeft',
 'clearRight','clear','stillThere','pitExitClear','pitExitTraffic','backmarker','gapAhead','gapBehind','rivalPenalty',
 'wordAhead','wordBehind','trackCut','sessionResume','redRestartSc','redRestartVsc','redRestartFcy','penaltyDelta',
 'penaltyPass','penaltyRed','penaltyStop','penaltyJump','drsIn','drsEnabled','trackWet','trackDry','pitWaived',
 'standingPit','formationLap','lightsOn','go','jumpStart','scCall','driveThrough','penaltyPits','lastLap',
 'giveBackDone','gridPlaced','gridPassed','aiDq','andBehind','zoneGreen','lastWarning','pitCompound','pitPlanSame',
 'pitNotCounted','pitValidated','restartPlace','behindSc','restartRetake','fastCar','raceDone','clear_b',
 'fasterBehind_b','backmarker_b','gapStable','pullingAway','escaping','clearBehind','spinAhead','wrongWay',
 'stoppedAhead_b','onLeft','onRight','onMiddle','offTrack','passLeft','passRight','tangleAhead','incomingLeft',
 'incomingRight','clearPassed','formationRoll','blueAdvise','blueClass','pitShort','slowWarn','pitSprint',
 'startDelayed','startDelayedRoll',}
C.shared={
 'red','white','pitOpen','closing','hesClosing','boxThisLap','tyresCold','tyresHot','brakesHot','laps','lastDefend',
 'lastSafe','closing_b','closing_c','hesClosing_b','hesClosing_c','inSecond','inSecond_b','heInSecond','heInSecond_b',
 'contact','wallHit','damageNone','damageLight','damageMedium','damageHeavy','damageSuspension','puncture','spunYou',
 'spunClear','waitTraffic','goNow','rejoinCareful','youWrongWay','stoppedYou','trackLimits','seconds','point',
 'secondOne','lapOne','hundred',}
C.clips={}
C.order={}
-- Groupes de variantes (1.3.0) : clip de base, puis ses variantes, dans l'ordre du catalogue. Tons connus.
C.groups={}
C.tones={neutral=true,calm=true,urgent=true,motivating=true,frustrated=true}
for k=1,#list do
 local r=list[k]
 local tone=r.tone or 'neutral'
 assert(C.tones[tone],'ton inconnu : '..tostring(tone))
 C.clips[r[1]]={id=r[1],number=r[2],FR=r[3]..'.wav',textFR=r[4],EN=r[5]..'.wav',textEN=r[6],shipped=r[2]<=34,tone=tone,of=r.of}
 C.order[k]=r[1]
 if r.of then
  assert(C.clips[r.of] and not C.clips[r.of].of,'variante sans clip de base : '..r[1])
  local g=C.groups[r.of]; if not g then g={r.of}; C.groups[r.of]=g end
  g[#g+1]=r[1]
 end
end
C.isSpotterOnly={}; C.isShared={}
for _,id in ipairs(C.spotterOnly) do assert(C.clips[id],'clip du spotter inconnu : '..id); C.isSpotterOnly[id]=true end
for _,id in ipairs(C.shared) do assert(C.clips[id] and not C.isSpotterOnly[id],'clip commun inconnu ou en double : '..id); C.isShared[id]=true end
-- Nombres 0 à C.maxNumber (dits « un », « deux »… dans la langue) : vox/<LANGUE>/num/NN.wav.
local unitsFR={'zéro','un','deux','trois','quatre','cinq','six','sept','huit','neuf','dix','onze','douze','treize','quatorze','quinze','seize'}
local tensFR={[2]='vingt',[3]='trente',[4]='quarante',[5]='cinquante',[6]='soixante'}
local unitsEN={'zero','one','two','three','four','five','six','seven','eight','nine','ten','eleven','twelve','thirteen','fourteen','fifteen','sixteen','seventeen','eighteen','nineteen'}
local tensEN={[2]='twenty',[3]='thirty',[4]='forty',[5]='fifty',[6]='sixty',[7]='seventy',[8]='eighty',[9]='ninety'}
function C.numberFR(n)
 if n<=16 then return unitsFR[n+1] end
 if n<20 then return 'dix-'..unitsFR[n-9] end
 local t,u=math.floor(n/10),n%10
 if t==7 or t==9 then
  local base=t==7 and 'soixante' or 'quatre-vingt'
  local rest=n-(t==7 and 60 or 80)
  if t==7 and rest==11 then return 'soixante et onze' end
  return base..'-'..C.numberFR(rest)
 end
 local word=t==8 and 'quatre-vingt' or tensFR[t]
 if u==0 then return t==8 and 'quatre-vingts' or word end
 if u==1 and t~=8 then return word..' et un' end
 return word..'-'..unitsFR[u+1]
end
function C.numberEN(n)
 if n<20 then return unitsEN[n+1] end
 local t,u=math.floor(n/10),n%10
 return u==0 and tensEN[t] or tensEN[t]..'-'..unitsEN[u+1]
end
function C.numberFile(n) return string.format('num/%02d.wav',n) end
-- Durée en dixièmes de seconde (0 à C.maxTenths : 0,0 à 9,9 s), nombre et unité dans un seul clip (lecture rapide des
-- écarts).
function C.secondsFile(tenths) return string.format('sec/%03d.wav',tenths) end
-- Position du joueur (1 à C.maxPosition, autant que de voitures dans le pont), « Tu es P7. » en un seul clip. Texte
-- dit par edge-tts : « Pé 7 » en français (« P7 » y est mal prononcé), « P7 » en anglais.
C.maxPosition=require('src/bridge_layout').maxCars
function C.positionFile(n) return string.format('pos/%02d.wav',n) end
function C.positionText(lang,n) return lang=='FR' and ('Tu es P'..n..'.') or ("You're P"..n..'.') end
function C.positionSpoken(lang,n) return lang=='FR' and ('Tu es Pé '..n..'.') or ("You're P"..n..'.') end
-- Clips de sécurité préchargés au lancement et au changement de langue (1.3.1, src/port.lua : radio instantanée) :
-- côte à côte, drapeaux et neutralisations, départ, box, dangers devant, urgences, virgule des écarts.
C.hot={'carLeft','carRight','threeWide','clearLeft','clearRight','clear','clear_b','stillThere','incomingLeft','incomingRight',
 'clearPassed','yellow','yellow2','red','sc','vsc','fcy','scCall','go','jumpStart','boxThisLap','stoppedAhead','stoppedAhead_b',
 'spinAhead','wrongWay','onLeft','onRight','onMiddle','offTrack','passLeft','passRight','tangleAhead','contact','waitTraffic',
 'goNow','spunYou','rejoinCareful','deltaNeg','blue','point'}
for _,id in ipairs(C.hot) do assert(C.clips[id],'clip préchargé inconnu : '..id) end
-- Nombre de fichiers attendus dans vox (toutes langues) : annonces, nombres, durées, positions.
function C.fileCount() return (#C.order+#C.shared+2*(C.maxNumber+1+C.maxTenths+1+C.maxPosition))*#C.languages end
-- Chaque fichier attendu (« FR/01_vert.wav », « EN/num/07.wav »…), donné à fn : clips présents (src/port.lua).
function C.eachFile(fn)
 for _,lang in ipairs(C.languages) do
  for k=1,#C.order do fn(lang..'/'..C.clips[C.order[k]][lang]) end
  for n=0,C.maxNumber do fn(lang..'/'..C.numberFile(n)) end
  for n=0,C.maxTenths do fn(lang..'/'..C.secondsFile(n)) end
  for n=1,C.maxPosition do fn(lang..'/'..C.positionFile(n)) end
  -- Voix féminine du spotter : clips communs, nombres, durées, positions.
  for k=1,#C.shared do fn(lang..'/'..C.femaleDir..C.clips[C.shared[k]][lang]) end
  for n=0,C.maxNumber do fn(lang..'/'..C.femaleDir..C.numberFile(n)) end
  for n=0,C.maxTenths do fn(lang..'/'..C.femaleDir..C.secondsFile(n)) end
  for n=1,C.maxPosition do fn(lang..'/'..C.femaleDir..C.positionFile(n)) end
 end
end
return C
