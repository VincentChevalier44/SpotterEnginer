-- Catalogue des clips de voix : fichier par langue (vox/FR, vox/EN) et texte dit, pour chaque clip. Les annonces sont des
-- suites de clips (phrases composées) ; un clip absent du disque rend l'annonce écrite seulement (radio de l'overlay).
-- Les textes sont ceux réellement dits. Tous les clips sont générés par tools/generer_voix.py (même voix que les clips
-- d'origine 01 à 34 : edge-tts, fr-FR-HenriNeural et en-US-GuyNeural) ; liste : vox/VOICE_CLIPS.md, refaite par
-- tests/run.py à partir de ce fichier. Sous-dossiers : nombres (num/), durées (sec/), positions (pos/) ; bornes et
-- nombre de fichiers attendus définis ici seulement (C.maxNumber, C.maxTenths, C.maxPosition, C.fileCount).
local C={}
C.languages={'FR','EN'}
-- Sous-dossiers des clips dans vox/<LANGUE> (lus par src/port.lua, générés par tools/generer_voix.py).
C.subfolders={'','num/','sec/','pos/'}
-- Nombres dits de 0 à C.maxNumber (num/), durées de 0 à C.maxTenths dixièmes de seconde (sec/).
C.maxNumber=99
C.maxTenths=99
-- Signal d'ouverture de la radio (dossier de l'app).
C.toneFile='sounds/radio.wav'
-- id = {numéro, fichier FR, texte FR, fichier EN, texte EN}
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
 -- À enregistrer : spotter
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
 -- À enregistrer : ingénieur
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
}
-- Précisions écrites seulement sur la radio (jamais dites), par langue : format string.format (src/say.lua, Say.note).
C.notes={
 behind={FR='(derrière %s)',EN='(behind %s)'},
 inMeters={FR='(à %d m)',EN='(in %d m)'},
 sidesFlipped={FR='Côtés gauche / droite inversés automatiquement (piste de CSP).',EN='Left / right swapped automatically (CSP track position).'},
 perLap={FR='/tour',EN='/lap'},
 coverUndercut={FR="(couvrir l'undercut)",EN='(cover the undercut)'},
 neutralised={FR='(neutralisation)',EN='(neutralised)'},
 debriefPlaces={FR='(départ P%d → arrivée P%d)',EN='(start P%d → finish P%d)'},
 debriefBest={FR='(meilleur tour %s)',EN='(best lap %s)'},
 debriefPassed={FR='(dépassé %d fois)',EN='(passed %d times)'},
}
C.clips={}
C.order={}
for k=1,#list do
 local r=list[k]
 C.clips[r[1]]={id=r[1],number=r[2],FR=r[3]..'.wav',textFR=r[4],EN=r[5]..'.wav',textEN=r[6],shipped=r[2]<=34}
 C.order[k]=r[1]
end
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
-- Nombre de fichiers attendus dans vox (toutes langues) : annonces, nombres, durées, positions.
function C.fileCount() return (#C.order+C.maxNumber+1+C.maxTenths+1+C.maxPosition)*#C.languages end
return C
