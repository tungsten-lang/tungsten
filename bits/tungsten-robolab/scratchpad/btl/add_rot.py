p = "lib/robolab/skills/dribble_btl.w"
s = open(p).read()
def rep(old, new, count=1):
    global s
    assert s.count(old) == count, (old, s.count(old))
    s = s.replace(old, new)
rep("""#   learn   (bt_ilc > 0) iterative learning across repetitions:""",
"""#   rotate  (bt_rotl / bt_rotr nonzero) the trunk turns into the catch: when a
#           pass leaves the hand, spine rotation joins the trunk's track; it
#           waits bt_rotd s, then twists by bt_rotl (the lead leg's hand
#           catching) or bt_rotr (the other) from the lunge's twist over
#           bt_rott, carrying the catching hand along with the ball, and
#           twists back over bt_rotb when a catch dribble's push releases.
#   learn   (bt_ilc > 0) iterative learning across repetitions:""")
rep("""    @twist = ly(@st_twist)
""", """    @twist = ly(@st_twist)
    # (rotate) the trunk's turn into the catch, authored for a left lead
    @bt_rotl = param("bt_rotl", ~0.0, ~-0.6, ~0.6)
    @bt_rotr = param("bt_rotr", ~0.0, ~-0.6, ~0.6)
    @bt_rotd = param("bt_rotd", ~0.1, ~0.02, ~0.4)
    @bt_rott = param("bt_rott", ~0.25, ~0.06, ~0.5)
    @bt_rotb = param("bt_rotb", ~0.3, ~0.06, ~0.6)
""")
rep("""    trunk = body.mask(["spine_flex"])
    ctl.reflex.set_gains(arms_r, @arm_kp, @arm_kd)""", """    trunk = body.mask(["spine_flex"])
    trunk = body.mask(["spine_flex", "spine_rot"]) if rotating?
    ctl.reflex.set_gains(arms_r, @arm_kp, @arm_kd)""")
rep("""  -> btl?
    @mode > ~5.5
""", """  -> btl?
    @mode > ~5.5

  -> rotating?
    btl? && (@bt_rotl != ~0.0 || @bt_rotr != ~0.0)
""")
rep("""  -> stance_movement
    @t_step = @st_step if btl?
    super
""", """  -> stance_movement
    @t_step = @st_step if btl?
    super

  -> twist_pose(flex, rot)
    p = spine_pose(flex)
    p.set("spine_rot", rot, @t_stiff)
    p

  # (rotate) DribbleV3Skill's quiet lean holding the lunge's twist, plus the
  # turn into each hand's catch (rot_l / rot_r: the wait, then into_l /
  # into_r) and back.
  -> trunk_movement
    return super if !rotating?
    never = Latch.test("never", ->(f, e, c) false)
    hold = twist_pose(@spine, @twist)
    mv = Movement.new("trunk")
    mv.add(Chunk.new("hold", ~0.3).pose(hold).hold_until(never))
    mv.add(Chunk.new("b_up", @t_rec).pose(twist_pose(@b_spine, @twist)).hold_until(never))
    mv.add(Chunk.new("up", @t_rec).pose(hold).hold_until(never))
    mv.add(Chunk.new("rot_l", @bt_rotd).pose(hold).followed_by("into_l"))
    mv.add(Chunk.new("into_l", @bt_rott).pose(twist_pose(@spine, @twist + ly(@bt_rotl))).hold_until(never))
    mv.add(Chunk.new("rot_r", @bt_rotd).pose(hold).followed_by("into_r"))
    mv.add(Chunk.new("into_r", @bt_rott).pose(twist_pose(@spine, @twist + ly(@bt_rotr))).hold_until(never))
    mv.add(Chunk.new("back", @bt_rotb).pose(hold).hold_until(never))
    mv
""")
rep("""    hand.fresh = false
    if @move == "D"
      choose(f, ctl, hand)
      return entry_for(hand)
    other = other_of(hand)
    @active = other""", """    hand.fresh = false
    if @move == "D"
      ctl.track("trunk").jump(ctl, f, "back") if rotating?
      choose(f, ctl, hand)
      return entry_for(hand)
    other = other_of(hand)
    ctl.track("trunk").jump(ctl, f, other.side == lead_side ? "rot_l" : "rot_r") if rotating?
    @active = other""")
open(p, "w").write(s)
print("ok")
