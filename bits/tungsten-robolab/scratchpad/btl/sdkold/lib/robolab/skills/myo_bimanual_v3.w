# MyoBimanualV3: the bimanual handover skill (MyoBimanualSkill) with the
# round-3 arm machinery of the relocate skill, each opt-in by params (all 0:
# MyoBimanualSkill):
#
#   ff_id   static inverse-dynamics drive for the arm muscles at the palm
#           command (MyoBimanualFF / MyoBimanualFFV3; the drive carries the
#           arm's weight so the reflexes need no standing error)
#   kq_* / kqd_*  joint-space PD on the proximal arm joints
#   tab3    1: the pronation-capped posture table (MyoBimanualPosturesV3;
#           the pronators are nearly powerless past pro_sup ~1 rad, so the
#           round-2 table's pronated hand rolls over as the biceps works)

+ MyoBimanualV3Skill < MyoBimanualSkill
  -> start(frame, ctl)
    @tab3 = param("tab3", ~0.0, ~0.0, ~1.0) > ~0.5
    super(frame, ctl)

  -> postures_table
    return MyoBimanualPosturesV3.table if @tab3
    MyoBimanualPostures.table

  -> postures_contractions
    return MyoBimanualPosturesV3.contractions if @tab3
    MyoBimanualPostures.contractions

  -> ff_muscle_names
    MyoBimanualFF.muscles

  -> ff_table
    return MyoBimanualFFV3.acts if @tab3
    MyoBimanualFF.acts
