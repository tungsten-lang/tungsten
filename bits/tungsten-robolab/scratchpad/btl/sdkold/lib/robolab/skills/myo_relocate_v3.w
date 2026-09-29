# MyoRelocateV3: round-3 variants of the relocate skill, chosen by params so
# one binary carries every challenger (the frozen arena copy of it runs
# whichever the params select). With every switch at 0 it is
# MyoRelocateSkill.
#
#   ff_id   internal model: the static inverse-dynamics drive of the posture
#           table in use (MyoRelocateFF / MyoRelocateFFV3), see
#           MyoRelocateSkill#servo_step and playground/tasks/myo_relocate_ff.py
#   kq_* / kqd_*  joint-space PD on the proximal arm joints (in the base skill)
#   rr_kp / rr_ki resolved-rate correction through the measured palm Jacobian
#           (in the base skill): the servo error steered from the arm's actual
#           configuration rather than through the table's postures
#   tab3    1: the pronation-capped posture table (MyoRelocatePosturesV3).
#           Past pro_sup ~1 rad the pronators sit so short that together they
#           give under 1 N m (5-7 N m at pro_sup 0) while the biceps supinates
#           with 4-7 N m per unit activation as it flexes the elbow: on the
#           round-2 table (pro_sup 1.1-1.47) the hand rolls palm-up whenever
#           the arm works (0.5 rad mean pronation error on the reaching
#           benchmark). The v3 table holds pro_sup <= 0.5 and turns the palm
#           down with the shoulder instead.
#   wrap    1: a power grasp instead of the pinch. The palm comes down over
#           the object with the fingers spread and extended and the thumb
#           abducted, then every finger curls (knuckle, middle, end joints)
#           and the thumb swings under, so whatever lies under the palm and
#           proximal phalanges is swept into the hand: it tolerates the 3 cm
#           the pinch cannot. The servo then steers the palm site throughout,
#           to (ox, oy) from the object and `wz_above` / `wz_grasp` above it.

+ MyoRelocateV3Skill < MyoRelocateSkill
  -> start(frame, ctl)
    @tab3 = param("tab3", ~0.0, ~0.0, ~1.0) > ~0.5
    @wrap = param("wrap", ~0.0, ~0.0, ~1.0) > ~0.5
    @wz_above = ~0.08
    @wz_grasp = ~0.035
    if @wrap
      @wz_above = param("wz_above", ~0.08, ~0.03, ~0.16)
      @wz_grasp = param("wz_grasp", ~0.035, ~0.0, ~0.08)
    super(frame, ctl)

  # ---- tables --------------------------------------------------------------

  -> postures_table
    return MyoRelocatePosturesV3.table if @tab3
    MyoRelocatePostures.table

  -> postures_contractions
    return MyoRelocatePosturesV3.contractions if @tab3
    MyoRelocatePostures.contractions

  -> ff_muscle_names
    MyoRelocateFF.muscles

  -> ff_table
    return MyoRelocateFFV3.acts if @tab3
    MyoRelocateFF.acts

  # ---- wrap grasp ----------------------------------------------------------

  -> open_hand
    return super if !@wrap
    [param("wf_open", ~0.15, ~0.0, ~1.0), param("wpip_open", ~0.1, ~0.0, ~1.0), param("wdip_open", ~0.05, ~0.0, ~1.0), param("wabd_open", ~0.2, ~-0.26, ~0.26), param("wthabd_open", ~0.6, ~-0.5, ~0.78), param("wthflex_open", ~-0.4, ~-0.78, ~0.7), param("wthmp_open", ~0.0, ~-0.78, ~0.7), param("wthip_open", ~0.0, ~-1.3, ~0.43)]

  -> shut_hand
    return super if !@wrap
    [param("wf_close", ~1.4, ~0.5, ~1.57), param("wpip_close", ~1.3, ~0.0, ~1.57), param("wdip_close", ~0.9, ~0.0, ~1.57), param("wabd_close", ~0.0, ~-0.26, ~0.26), param("wthabd_close", ~0.3, ~-0.5, ~0.78), param("wthflex_close", ~0.6, ~-0.78, ~0.7), param("wthmp_close", ~0.5, ~-0.78, ~0.7), param("wthip_close", ~0.3, ~-1.3, ~0.43)]

  -> phase_goal(f)
    return super(f) if !@wrap
    ph = @phase
    oz = f.at("env_obj_pos", 2)
    ox = f.at("env_obj_pos", 0) + @ox
    oy = f.at("env_obj_pos", 1) + @oy
    return [ox, oy, oz + @wz_above] if ph == "reach"
    return [ox + @k_touch * @felt[0], oy + @k_touch * @felt[1], oz + @wz_grasp] if ph == "descend"
    super(f)

  -> control_point(f, k)
    return super(f, k) if !@wrap
    f.at("env_palm_pos", k)
