# Dribble between the legs: DribbleV3Skill (skills/dribble_v3.w: the arms
# dribble, the trunk leans quietly, strokes are via-chained, the receiving
# hand waits where the rising ball will cross its strike height) with a
# lunge the ball can pass under and a through-the-legs pass on every push.
#
#   stance  a staggered lunge, the lead leg's foot forward (st_fx, st_fy) and
#           the back foot back (st_bx, st_by), both solved on the controller's
#           own leg model (DribbleBtlLeg) for a flat front foot on the floor
#           under the fixed-height pelvis. The feet step into it while the
#           ball is still held, before the launch. The ball passes under the
#           lead leg's thigh, between the front shin and the back knee.
#   spots   each hand dribbles from its own spot: the hand on the back leg's
#           side (right, for a left lead) out in front of its hip (bt_fx,
#           bt_fy), the other behind the lead leg's hip (bt_bx, bt_by). A
#           straight line between the spots passes under the crotch, so a
#           push aimed from one spot to the other bounces between the feet.
#   move    every push is a between-the-legs pass to the other hand (mode 6):
#           the pushing hand rolls over the ball's outer top (the crossover
#           cycle, x_*), its palm tilted toward the horizontal velocity that
#           carries the ball to the other spot in bt_t seconds (bt_kv,
#           bt_tmax; bt_steer sweeps the palm along it); the other hand runs
#           the receiving cycle from its spot, its palm moved over the point
#           where the rising ball will cross its strike height, and strikes
#           when the ball is bt_lead seconds from it.
#   plan    (bt_plan 1) the pass as a planned contact: once the ball rises
#           from its bounce (ball_rise predicts the crossing to ~1 mm), the
#           contact is planned where its centre reaches bt_kzc (or bt_kph
#           past its apex): a quintic knot (k_strike, retimed to the
#           predicted time less bt_klead) ends with the palm on the ball's
#           far top at a prescribed palm velocity (joint rates from the arm
#           model's Jacobian), from a backswing hover bt_khov back along that
#           path; a second knot (k_push) carries it on to rest. The plain
#           reflex damps absolute contraction velocity and so brakes a fast
#           knot; bt_vref switches the arms to the SDK's velocity-referenced
#           damping (Reflex#set_velocity_reference), which damps about the
#           commanded velocity. bt_kilt / bt_kila learn each hand's timing
#           lead and aim from its touches (lateness, palm miss).
#   receive (bt_rplan 1) the absorbing receive of a pass: planned when the
#           incoming ball rises from its bounce, the palm meets its leading
#           side (bt_rb above the equator, bt_rin inside) at bt_rmatch of
#           its velocity (r_meet), rides on with it decelerating to rest over
#           bt_rt (r_absorb), then pushes it back through the legs (r_push)
#           and rests (r_follow) until it leaves.
#   rotate  (bt_rotl / bt_rotr nonzero) the trunk turns into the catch: when a
#           pass leaves the hand, spine rotation joins the trunk's track; it
#           waits bt_rotd s, then twists by bt_rotl (the lead leg's hand
#           catching) or bt_rotr (the other) from the lunge's twist over
#           bt_rott, carrying the catching hand along with the ball, and
#           twists back over bt_rotb when a catch dribble's push releases.
#   program (pg_on 1, ORACLE class) a pass's stroke replayed from a table of arm
#           activations found by a muscle-level trajectory search
#           (scratchpad/btl2/oracle_*.py): pass pg_first + p (p = 0..pg_n - 1)
#           starts pg_lead s before the ball's predicted rising crossing of bt_rh
#           and plays pg{p}_{m}_{k} (16 arm muscles, a knot every pg_dk s) as the
#           hand's activations (reflex gain pg_gain, 0: the program alone); the
#           hand's touch and release hand the ball over as ever. Everything
#           else (the launch, the waits, the other passes) is the reflex controller.
#           pg_gs 1: each table is T0 + ux Tx + uy Ty, u the predicted crossing
#           position's offset from the stage's nominal (pgc, pgs), knot values
#           bounded to [0, 1] and the gains to +-pg_gmax; pg_first 0 programs the
#           launch pass too; pg_stages / pg_per cycle the last tables.
#   servo   (pg_fb > 0, scratchpad/btl3/) a tracking servo around the table: while a stage's
#           program runs, the stroking arm's muscles take the stage's NOMINAL contractions
#           (pgn / pgnx / pgny / pgnz: the conditional-mean contraction trajectory given the
#           schedule's own features, fitted from closed-loop traces) as reflex targets with a
#           small gain (pg_fb x pg_fbs<stage> x pg_fbw<joint>), damping about the nominal's
#           own rate (pg_fbv); the table stays the drive. Further opt-in keys of the same
#           study, every one neutral by default: pg_dt / pgdt (additive offset tables),
#           pg_fk / pgfw / pgfa / pgft / pgfg (predict-then-cancel feedback on the offsets),
#           pg_gfrom / pg_gu / pg_gz (play a stage only inside its schedule's design range),
#           pg_lead<stage> (per-stage trigger lead).
#   legs    (round 4, scratchpad/btl4/, every key neutral at zero) the ball that rises after a release clips the lead thigh (13-17 % of the
#           right returns and the left second strokes) or crosses outside the gate: after the release of passes ll_from .. ll_from + ll_n - 1
#           (3 and 4: the right return and the left second stroke) the lead leg's hip is flexed ll_hip and abducted ll_abd (ll_knee, ll_rot; with
#           ll_two 1 the later windows use ll_hip1 / ll_abd1 / ll_knee1 / ll_rot1) for ll_win s (ramped by ll_ramp, from ll_t0), as contraction
#           offsets on the stance track; lb_* do the same for the back leg. Motion during a table stroke breaks that stroke (l2_* window for the left
#           return's flight, ls_* a static offset from the start: both measured and harmful), so the window starts at the table's release.
#           Other round-4 opt-in keys: bl_trec / bt_trec (the x_recover duration of a reflex stroke), pg_vn / pgvk / pgvs / pgv (a hinge feature of the
#           incoming ball's vertical speed times a block added to a table: fitted in the replay, no closed-loop gain), bl_dax / bl_day / bt_dax / bt_day
#           (aim offsets of the reflex strokes after the tables), bl_ck* (cock offsets of the left second stroke), lt_* (trunk offsets in the leg windows).
#   round 5 (scratchpad/btl5/, params only except one neutral key) the SECOND strokes of the cycle are tables too: stage 3 = the left hand's second stroke (pg_n 4), stage 4 = the
#           right hand's second stroke (pg_n 5), same family as stages 0-2 (gain-scheduled on the predicted crossing and the arm's posture, 16 muscles x 17 knots,
#           pg_gmax 4, pg_fbs3 / pg_fbs4 0 = no servo). A stage's trigger (pg_lead<stage>) may fire BEFORE the ball's bounce (ball_rise predicts the post-bounce state), so a lead
#           above ~0.2 s starts the table before the reflex's own swing latch (stage 3: pg_lead3 0.24). pg_trec<stage> sets the x_recover duration before a programmed stage
#           (default t_rec: neutral). Fitted in the replay (scratchpad/btl5/fit3.py) on closed-loop records of the chain that precedes the stage.
#   round 6 (scratchpad/btl6/, three neutral keys + params) a ball that peaks below the strike height is where the chain breaks: the tables touch every ball that peaks above 0.66 m
#           and 13-36 % of those below 0.62 (the tables' contact is planned at the ball's crossing of z 0.62, which such a ball never makes), and the chain's energy decays by ~0.1 m of
#           apex per stage. pg_vn's hinge block (pgv<stage>_m_k) now has: pg_vsel<stage> 1 = the hinge's argument is the incoming ball's APEX, uv = clip((pgvk - apex) / pgvs, 0, 2.5)
#           (2 = turned over, a block for strong balls); pg_vts<stage> = clock shift (s) per unit of uv; pg_gv<stage> = play the reflex instead of the table when the incoming ball's
#           vertical speed at the crossing is below it (0.15 = a ball that never reaches the strike height; measured +0.036 streak on 840 training starts).
#   learn   (bt_ilc > 0) iterative learning across repetitions: after each
#           pass the receiving hand measures where the ball actually rose
#           (its position as it crossed the strike height) against the spot
#           it was sent to, and the next push from the same hand aims that
#           much the other way (per hand, gain bt_ilc, bounded by bt_ilc_max).
#
# Modes 0-5 are DribbleV3Skill's, unchanged.

# The controller's model of one leg: hip 0.09 m either side of the pelvis
# centre, thigh and shin 0.43 m, joints hip flex / abd / rot, knee, ankle
# (axes as playground/body.py). `fk` gives the ankle and the foot's up axis;
# `solve` places the ankle on a point with the foot flat, near a seed.
+ DribbleBtlLeg
  ro :side
  ro :joints
  -> new(@body, @side)
    s = @side
    b = @body
    @joints = ["hip_flex", "hip_abd", "hip_rot", "knee", "ankle"].map -> s + "_" + item
    @ls = s == "r" ? ~-1.0 : ~1.0
    @lo = @joints.map -> b.muscle(b.pos_index(item)).qmin + ~0.01
    @hi = @joints.map -> b.muscle(b.pos_index(item)).qmax - ~0.01

  -> fk(h, q)
    r = DribbleV3Math.ry(~0.0 - q[0])
    r = DribbleV3Math.mul(r, DribbleV3Math.rx(@ls * q[1]))
    r = DribbleV3Math.mul(r, DribbleV3Math.rz(~0.0 - @ls * q[2]))
    p = DribbleV3Math.move([~0.0, ~0.09 * @ls, h], r, ~0.0, ~0.0, ~-0.43)
    r = DribbleV3Math.mul(r, DribbleV3Math.ry(q[3]))
    p = DribbleV3Math.move(p, r, ~0.0, ~0.0, ~-0.43)
    r = DribbleV3Math.mul(r, DribbleV3Math.ry(q[4]))
    [p[0], p[1], p[2], r[2], r[5]]

  -> residual(h, q, target)
    a = fk(h, q)
    [a[0] - target[0], a[1] - target[1], a[2] - target[2], ~0.3 * a[3], ~0.3 * a[4]]

  # Damped Gauss-Newton (numeric Jacobian) from `seed`, lightly regularised
  # toward it, clamped to the joint ranges.
  -> solve(h, seed, target)
    q = seed.map -> item
    eps = ~0.0001
    k = 0
    while k < 60
      r = residual(h, q, target)
      jac = (0...25).map -> ~0.0
      c = 0
      while c < 5
        q2 = q.map -> item
        q2[c] = q2[c] + eps
        r2 = residual(h, q2, target)
        m = 0
        while m < 5
          jac[5 * m + c] = (r2[m] - r[m]) / eps
          m += 1
        c += 1
      a = (0...25).map -> ~0.0
      g = (0...5).map -> ~0.0
      i = 0
      while i < 5
        j = 0
        while j < 5
          s = ~0.0
          m = 0
          while m < 5
            s = s + jac[5 * m + i] * jac[5 * m + j]
            m += 1
          a[5 * i + j] = s
          j += 1
        a[6 * i] = a[6 * i] + ~0.001
        s = ~0.0
        m = 0
        while m < 5
          s = s + jac[5 * m + i] * r[m]
          m += 1
        g[i] = ~0.0 - s - ~0.001 * (q[i] - seed[i])
        i += 1
      dq = DribbleV3Math.solve_spd(a, g, 5)
      i = 0
      while i < 5
        q[i] = DribbleV3Math.clamp(q[i] + dq[i], @lo[i], @hi[i])
        i += 1
      k += 1
    q

# A chunk whose duration is set when it is planned (a contact knot is timed
# to the predicted contact).
+ BtlChunk < Chunk
  -> retime(seconds)
    @duration = seconds
    self

+ DribbleBtlSkill < DribbleV3Skill
  -> read_params
    super
    # stance (authored for a left lead: + y is the lead side)
    @st_lead = param("st_lead", ~0.0, ~0.0, ~1.0)
    @st_fx = param("st_fx", ~0.35, ~0.15, ~0.55)
    @st_fy = param("st_fy", ~0.17, ~0.08, ~0.35)
    @st_bx = param("st_bx", ~-0.4, ~-0.55, ~-0.1)
    @st_by = param("st_by", ~-0.24, ~-0.4, ~-0.1)
    # a step: each of its chunks (lift, place, lift the other, place) takes
    # st_step seconds; a lifted leg flexes st_lhip at the hip, st_lknee at the knee
    @st_step = param("st_step", ~0.4, ~0.12, ~0.6)
    @st_lhip = param("st_lhip", ~0.5, ~0.1, ~0.8)
    @st_lknee = param("st_lknee", ~1.0, ~0.2, ~1.4)
    @st_hold = param("st_hold", ~0.8, ~0.3, ~3.0)
    # the trunk's twist toward the lead leg (spine rotation, authored for a
    # left lead): the back leg's shoulder comes forward and the lead leg's
    # shoulder back, so both hands reach the ball where a pass between the
    # legs starts and ends
    @st_twist = param("st_twist", ~0.0, ~-0.8, ~0.8)
    @twist = ly(@st_twist)
    # (rotate) the trunk's turn into the catch, authored for a left lead
    @bt_rotl = param("bt_rotl", ~0.0, ~-0.6, ~0.6)
    @bt_rotr = param("bt_rotr", ~0.0, ~-0.6, ~0.6)
    @bt_rotd = param("bt_rotd", ~0.1, ~0.02, ~0.4)
    @bt_rott = param("bt_rott", ~0.25, ~0.06, ~0.5)
    @bt_rotb = param("bt_rotb", ~0.3, ~0.06, ~0.6)
    # 1: step from the athletic crouch into the lunge (lift and place each
    # foot); 0: the task starts the body in the lunge, which is held
    @st_stepin = param("st_stepin", ~0.0, ~0.0, ~1.0)
    # the hands' spots (authored for a left lead: the front spot is the back
    # leg's hand, out in front of its hip; the back spot the lead leg's hand,
    # behind the lead hip)
    @bt_fx = param("bt_fx", ~0.35, ~0.1, ~0.6)
    @bt_fy = param("bt_fy", ~-0.4, ~-0.5, ~-0.2)
    @bt_bx = param("bt_bx", ~-0.15, ~-0.3, ~0.2)
    @bt_by = param("bt_by", ~0.44, ~0.25, ~0.55)
    # the pass: tilt gain, flight time, tilt limit, palm sweep; the strike's
    # lead on the rising ball; ILC gain and bound
    @bt_kv = param("bt_kv", ~0.43, ~0.0, ~1.0)
    @bt_t = param("bt_t", ~0.45, ~0.2, ~1.0)
    @bt_tmax = param("bt_tmax", ~0.73, ~0.0, ~0.9)
    @bt_steer = param("bt_steer", ~0.06, ~0.0, ~0.2)
    @bt_lead = param("bt_lead", ~0.13, ~0.0, ~0.25)
    # what starts the pass stroke's swing: 0 the rising ball is bt_lead s
    # from the strike height (DribbleV3Skill's predictive latch); 1 its centre
    # rises within bt_lz of the strike height; 2 it has slowed below bt_lvz
    # m/s on its way up (near the apex)
    @bt_latch = param("bt_latch", ~0.0, ~0.0, ~2.0)
    @bt_lz = param("bt_lz", ~0.1, ~0.0, ~0.3)
    @bt_lvz = param("bt_lvz", ~1.5, ~0.2, ~3.0)
    # 1: a pass aims from where the ball will be met: the palm normal's
    # horizontal part turns from the spot-to-spot direction to the direction
    # from the predicted meeting point to the target (the stroke's tilt kept)
    @bt_aim = param("bt_aim", ~0.0, ~0.0, ~1.0)
    # static aim offsets of each hand's passes (added to the other spot, x
    # and y authored for a left lead): where the ball should be sent so it
    # arrives where the other hand can reach it
    @bt_ax = param("bt_ax", ~0.0, ~-0.3, ~0.3)
    @bt_ay = param("bt_ay", ~0.0, ~-0.3, ~0.3)
    @bl_ax = param("bl_ax", ~0.0, ~-0.3, ~0.3)
    @bl_ay = param("bl_ay", ~0.0, ~-0.3, ~0.3)
    # adaptive strike height (bt_dzup > 0): the pass stroke meets the ball
    # bt_aoff below its predicted apex (ball top), so the palm reaches it at
    # the same phase of its rise whatever the bounce gave it: the stroke may
    # rise up to bt_dzup above its planned strike height (DribbleV3Skill's
    # correction only lowers it, for a ball that will not rise that far)
    @bt_dzup = param("bt_dzup", ~0.0, ~0.0, ~0.2)
    @bt_aoff = param("bt_aoff", ~0.03, ~0.0, ~0.15)
    # planned contact (bt_plan 1): the pass stroke is a quintic knot planned
    # when the predicted time to contact falls to bt_kt: the palm on the
    # ball's far top (normal tilted bt_knt from straight down toward the
    # pass's target) where the ball will be bt_kph s past its apex, moving at
    # bt_kspd m/s tilted bt_kang from straight down toward the target; the
    # knot reaches it bt_klead s early (the servo lags), then a second knot
    # carries the palm bt_kfd on along its path to rest over bt_kpt and holds
    # until the ball leaves it. bt_kdrv scales the feed-forward burst.
    @bt_plan = param("bt_plan", ~0.0, ~0.0, ~1.0)
    # which hands use the planned contact: 0 both, 1 only the lead leg's hand
    # (the return of a pass), 2 only the other hand
    @bt_pside = param("bt_pside", ~0.0, ~0.0, ~2.0)
    @bt_kt = param("bt_kt", ~0.12, ~0.05, ~0.3)
    @bt_kph = param("bt_kph", ~0.03, ~-0.1, ~0.15)
    @bt_kspd = param("bt_kspd", ~1.5, ~0.0, ~4.0)
    @bt_kang = param("bt_kang", ~0.5, ~0.0, ~1.3)
    @bt_knt = param("bt_knt", ~0.8, ~0.0, ~1.4)
    @bt_kfd = param("bt_kfd", ~0.12, ~0.0, ~0.3)
    @bt_kpt = param("bt_kpt", ~0.08, ~0.03, ~0.25)
    @bt_kdrv = param("bt_kdrv", ~0.5, ~0.0, ~1.0)
    @bt_klead = param("bt_klead", ~0.02, ~0.0, ~0.1)
    # during a planned knot (k_*, r_* chunks) the arm's reflexes damp about
    # the commanded velocity (weight bt_vref, the SDK's opt-in
    # Reflex#set_velocity_reference) instead of braking every fast
    # movement: the knot's planned velocity is tracked; elsewhere (the
    # launch, recoveries, waits) they damp as usual
    @bt_vref = param("bt_vref", ~0.0, ~0.0, ~1.0)
    # the absorbing receive (bt_rplan 1, a hand receiving a pass): planned
    # once the ball rises from its bounce, where its centre reaches bt_rh:
    # the palm on the ball's leading side (bt_rb above its equator) arriving
    # at bt_rmatch of the ball's velocity (knot r_meet, bt_rlead early, from
    # a hover bt_rpre ahead of the receive point); moving on with the ball it
    # decelerates to rest over bt_rt (r_absorb; bt_rabs x the distance a
    # linear deceleration takes), then pushes the ball back through the legs
    # (r_push: the palm turned bt_rnt toward the other spot, reaching bt_rspd
    # tilted bt_rang from straight down over bt_rpd along that line in
    # bt_rpt) and comes to rest (r_follow) until the ball leaves it
    @bt_rplan = param("bt_rplan", ~0.0, ~0.0, ~1.0)
    # which hands use the absorbing receive: 0 both, 1 only the back-leg
    # side's (the catch of the return), 2 only the lead leg's
    @bt_rside = param("bt_rside", ~0.0, ~0.0, ~2.0)
    @bt_rh = param("bt_rh", ~0.62, ~0.45, ~0.85)
    @bt_rb = param("bt_rb", ~0.35, ~0.0, ~1.0)
    # the palm planned bt_rin inside the ball's surface (the arm lags its
    # plan; the contact must happen)
    @bt_rin = param("bt_rin", ~0.03, ~0.0, ~0.1)
    @bt_rmatch = param("bt_rmatch", ~0.8, ~0.0, ~1.2)
    @bt_rpre = param("bt_rpre", ~0.06, ~0.0, ~0.2)
    @bt_rlead = param("bt_rlead", ~0.03, ~0.0, ~0.1)
    @bt_rt1 = param("bt_rt1", ~0.18, ~0.06, ~0.3)
    @bt_rt = param("bt_rt", ~0.15, ~0.05, ~0.25)
    @bt_rabs = param("bt_rabs", ~1.0, ~0.3, ~1.5)
    @bt_rnt = param("bt_rnt", ~0.9, ~0.0, ~1.4)
    @bt_rspd = param("bt_rspd", ~2.5, ~0.0, ~4.5)
    @bt_rang = param("bt_rang", ~0.8, ~0.0, ~1.3)
    @bt_rpd = param("bt_rpd", ~0.12, ~0.02, ~0.3)
    @bt_rpt = param("bt_rpt", ~0.08, ~0.03, ~0.2)
    # while it waits, the hand hovers bt_khov back along its path from the
    # planned contact point (its backswing), aimed past its measured miss by
    # hand_fb
    @bt_khov = param("bt_khov", ~0.12, ~0.0, ~0.3)
    # bt_kzc > 0: the contact is planned where the rising ball's centre
    # reaches bt_kzc (its apex, if it will not rise so far) instead of by
    # bt_kph (the forearm hangs over a ball that rises to its apex)
    @bt_kzc = param("bt_kzc", ~0.0, ~0.0, ~0.9)
    # iterative learning across repetitions on the planned contact: per
    # hand, the touch's lateness moves the knot's lead (gain bt_kilt,
    # bounded 0.08 s) and the palm's miss at the touch against the plan
    # moves the aim (gain bt_kila, bounded 0.1 m)
    @bt_kilt = param("bt_kilt", ~0.0, ~0.0, ~1.0)
    @bt_kila = param("bt_kila", ~0.0, ~0.0, ~1.0)
    @bt_ilc = param("bt_ilc", ~0.0, ~0.0, ~1.0)
    @bt_ilc_max = param("bt_ilc_max", ~0.12, ~0.0, ~0.25)
    # the stroke along the pass: the palm normal tilted bt_angc (cocked) and
    # bt_angl (low end) from straight down toward the other spot, the palm on
    # the ball's far top bt_dzc above the strike height bt_zh, meeting it at
    # bt_zh, sweeping bt_sweep along the pass to bt_dzl below it (heights of
    # the ball's top: its centre plus its radius)
    # (these are the back leg's hand's; the lead leg's hand has its own,
    # bl_*, defaulting to the same). The stroke's poses are solved from an
    # arm posture seed (shoulder flexion, abduction, rotation, elbow: bt_s*
    # and bl_s*), which picks the posture branch; a hand beside the hip
    # meets the ball from its outer side (a large tilt) with the arm hanging
    @bt_angc = param("bt_angc", ~0.35, ~0.0, ~1.5)
    @bt_angl = param("bt_angl", ~0.55, ~0.0, ~1.5)
    @bt_zh = param("bt_zh", ~0.8, ~0.6, ~1.2)
    @bt_zc = @bt_zh + param("bt_dzc", ~0.15, ~0.03, ~0.35)
    @bt_zl = @bt_zh - param("bt_dzl", ~0.25, ~0.05, ~0.45)
    @bt_sweep = param("bt_sweep", ~0.12, ~0.0, ~0.3)
    @bt_sf = param("bt_sf", @sf0, ~-0.6, ~1.8)
    @bt_sa = param("bt_sa", @sa0, ~-0.3, ~1.4)
    @bt_sr = param("bt_sr", @rot0, ~-1.4, ~1.4)
    @bt_se = param("bt_se", ~1.4, ~0.0, ~2.5)
    @bl_angc = param("bl_angc", @bt_angc, ~0.0, ~1.5)
    @bl_angl = param("bl_angl", @bt_angl, ~0.0, ~1.5)
    @bl_zh = param("bl_zh", @bt_zh, ~0.6, ~1.2)
    @bl_zc = @bl_zh + param("bl_dzc", @bt_zc - @bt_zh, ~0.03, ~0.35)
    @bl_zl = @bl_zh - param("bl_dzl", @bt_zh - @bt_zl, ~0.05, ~0.45)
    @bl_sweep = param("bl_sweep", @bt_sweep, ~0.0, ~0.3)
    # the lead leg's hand's pass law and swing lead (it meets a ball coming
    # at it fast from the other side, and sends it back)
    @bl_kv = param("bl_kv", @bt_kv, ~0.0, ~1.0)
    @bl_t = param("bl_t", @bt_t, ~0.2, ~1.0)
    @bl_tmax = param("bl_tmax", @bt_tmax, ~0.0, ~0.9)
    @bl_steer = param("bl_steer", @bt_steer, ~0.0, ~0.2)
    @bl_lead = param("bl_lead", @bt_lead, ~0.0, ~0.25)
    # (bt_ychain 1) the back-leg side's hand has a second pass stroke and
    # law, br_*, for the passes it makes after catching one (a ball arriving
    # with the return's sideways speed, not the launch's rebound); they
    # default to the first pass's
    @bt_ychain = param("bt_ychain", ~0.0, ~0.0, ~1.0)
    # (mode 8) the reset dribble after a caught return: 1 on the catch stroke
    # (y chain, br_* law), 0 on DribbleV3Skill's dribble stroke at the spot
    # with its catch law (c_kv, c_tmax; stroke heights z_cock, z_hit, z_low)
    @bt_dy = param("bt_dy", ~1.0, ~0.0, ~1.0)
    @br_angc = param("br_angc", @bt_angc, ~0.0, ~1.5)
    @br_angl = param("br_angl", @bt_angl, ~0.0, ~1.5)
    @br_zh = param("br_zh", @bt_zh, ~0.6, ~1.2)
    @br_zc = @br_zh + param("br_dzc", @bt_zc - @bt_zh, ~0.03, ~0.35)
    @br_zl = @br_zh - param("br_dzl", @bt_zh - @bt_zl, ~0.05, ~0.45)
    @br_sweep = param("br_sweep", @bt_sweep, ~0.0, ~0.3)
    @br_kv = param("br_kv", @bt_kv, ~0.0, ~1.0)
    @br_t = param("br_t", @bt_t, ~0.2, ~1.0)
    @br_tmax = param("br_tmax", @bt_tmax, ~0.0, ~0.9)
    @br_steer = param("br_steer", @bt_steer, ~0.0, ~0.2)
    @br_lead = param("br_lead", @bt_lead, ~0.0, ~0.25)
    @br_ax = param("br_ax", @bt_ax, ~-0.3, ~0.3)
    @br_ay = param("br_ay", @bt_ay, ~-0.3, ~0.3)
    # the feed-forward drive of the lead leg's hand's pass stroke and of the
    # back-leg side's pass after a catch, as multiples of the first pass's
    @bl_drv = param("bl_drv", ~1.0, ~0.0, ~2.5)
    # the lead leg's hand's dribble stroke (its catch of a pass, received
    # rising and struck from above: DribbleV3Skill's cycle with the catch
    # law), overriding the shared z_cock, dx_cock, pitch_cock, z_hit, z_low,
    # dx_low, pitch_low at its spot
    @dl_zcock = param("dl_zcock", @z_cock, ~0.5, ~1.3)
    @dl_dxc = param("dl_dxc", @dx_cock, ~-0.2, ~0.2)
    @dl_pc = param("dl_pc", @pitch_cock, ~-0.8, ~0.8)
    @dl_zhit = param("dl_zhit", @z_hit, ~0.5, ~1.2)
    @dl_zlow = param("dl_zlow", @z_low, ~0.3, ~0.95)
    @dl_dxl = param("dl_dxl", @dx_low, ~-0.2, ~0.2)
    @dl_pl = param("dl_pl", @pitch_low, ~-0.8, ~0.8)
    @br_drv = param("br_drv", ~1.0, ~0.0, ~2.5)
    @bl_sf = param("bl_sf", @bt_sf, ~-0.6, ~1.8)
    @bl_sa = param("bl_sa", @bt_sa, ~-0.3, ~1.4)
    @bl_sr = param("bl_sr", @bt_sr, ~-1.4, ~1.4)
    @bl_se = param("bl_se", @bt_se, ~0.0, ~2.5)
    # 1: the pass stroke keeps the offset it took while meeting the ball, so
    # the stroke's own shape (behind the ball, sweeping along the pass) does
    # the push; 0: DribbleV3Skill's stroke correction (re-aimed at the ball)
    @bt_hold = param("bt_hold", ~1.0, ~0.0, ~1.0)
    # plain dribbles after the launch before the first pass (the launch's
    # drift is caught and the ball walked to the right hand's spot)
    @bt_settle = param("bt_settle", ~0.0, ~0.0, ~3.0)
    # 1: in BTL mode a plain dribble (mode 7's catch after a pass) uses the
    # pass stroke from the outer side of the ball, its palm tilt aimed by the
    # catch law (c_kv, c_tmax) at the hand's own spot; 0: DribbleV3Skill's
    # dribble stroke at the spot
    @bt_dside = param("bt_dside", ~1.0, ~0.0, ~1.0)
    # the launch: the ball thrown straight down at the right hand's spot,
    # the palm level, from bt_lzc to bt_lzl (the grip opens at z_rel)
    @bt_lzc = param("bt_lzc", ~1.15, ~0.8, ~1.3)
    @bt_lzl = param("bt_lzl", ~0.8, ~0.45, ~0.95)
    @bt_lt = param("bt_lt", ~0.15, ~0.05, ~0.3)
    @bt_ldrv = param("bt_ldrv", ~0.0, ~0.0, ~1.0)
    # where the throw's palm is aimed, from the spot: held and cocked at
    # (bt_lhx, bt_lhy), thrown down to (bt_ldx, bt_ldy) (the arm droops and
    # lags its model, so the aim is practised)
    @bt_lhx = param("bt_lhx", ~0.0, ~-0.2, ~0.2)
    @bt_lhy = param("bt_lhy", ~0.0, ~-0.2, ~0.2)
    @bt_ldx = param("bt_ldx", ~0.0, ~-0.2, ~0.2)
    @bt_ldy = param("bt_ldy", ~0.0, ~-0.2, ~0.2)
    # 1: while the launch holds, lifts and throws the ball, a hand-space
    # correction keeps the palm over the spot (the arm lags and droops, and a
    # joint-space stroke curves), so the ball is thrown straight down
    @bt_lfix = param("bt_lfix", ~0.0, ~0.0, ~1.0)
    # 1: the launch drops the ball instead of throwing it: the hand lifts it
    # to bt_lzc over the spot (plus the launch aim), holds still bt_lset s,
    # and opens (a drop from rest is reproducible; the rebound's apex is set
    # by the height)
    @bt_ldrop = param("bt_ldrop", ~0.0, ~0.0, ~1.0)
    @bt_lset = param("bt_lset", ~0.25, ~0.05, ~0.6)
    # (reflex-stroke recovery, round 4) the duration of the x_recover chunk of a pass stroke that is NOT a programmed stage (the reflex
    # strokes after the tables), for the lead leg's hand (bl_trec) and the other hand (bt_trec); the default is t_rec, the plain behavior.
    # The ball of a table-driven pass arrives sooner than the reflex strokes were tuned for, so a full t_rec recovery starts the swing late.
    @bl_trec = param("bl_trec", @t_rec, ~0.03, ~0.4)
    @bt_trec = param("bt_trec", @t_rec, ~0.03, ~0.4)
    # (round 5) the duration of the x_recover chunk that precedes a PROGRAMMED stage (pg_trec<stage>, default t_rec): a hand that has to start its table from the
    # ready posture needs a recovery that ends before the table's trigger
    @pg_trecs = []
    zi = 0
    while zi < 8
      @pg_trecs.push(param("pg_trec" + zi.to_s, @t_rec, ~0.03, ~0.4))
      zi += 1
    # (leg clearance, round 4) after the release of passes ll_from .. ll_from + ll_n - 1 the lead leg's hip and knee are shifted by ll_hip /
    # ll_knee radians (ramped over ll_ramp s, from ll_t0 to ll_win s after the release): a ball that rises after its bounce passes under the lead
    # thigh with a few centimetres to spare, and clips it on 13-17 % of the right returns and the left second strokes. Neutral at zero.
    @ll_hip = param("ll_hip", ~0.0, ~-0.4, ~0.4)
    @ll_knee = param("ll_knee", ~0.0, ~-0.6, ~0.6)
    @ll_abd = param("ll_abd", ~0.0, ~-0.4, ~0.4)
    # the same for the back leg (lb_*): its thigh is hit by 5 of 21 stage-2 body failures
    @ll_rot = param("ll_rot", ~0.0, ~-0.4, ~0.4)
    # (round 4) aim offsets of the REFLEX pass strokes after the programmed stages (pass number >= pg_first + pg_n), added to bl_ax / bl_ay (the lead leg's
    # hand) and bt_ax / bt_ay (the other hand): unlike bl_ax, they leave the programmed stages' posture untouched
    @bl_dax = param("bl_dax", ~0.0, ~-0.3, ~0.3)
    @bl_day = param("bl_day", ~0.0, ~-0.3, ~0.3)
    @bt_dax = param("bt_dax", ~0.0, ~-0.3, ~0.3)
    @bt_day = param("bt_day", ~0.0, ~-0.3, ~0.3)
    # ll_two 1: the passes after the first window pass (ll_from) use ll_hip1 / ll_abd1 / ll_knee1 / ll_rot1 (the left second stroke's flight differs
    # from the right return's)
    @ll_two = param("ll_two", ~0.0, ~0.0, ~1.0)
    @ll_hip1 = param("ll_hip1", ~0.0, ~-0.4, ~0.4)
    @ll_abd1 = param("ll_abd1", ~0.0, ~-0.4, ~0.4)
    @ll_knee1 = param("ll_knee1", ~0.0, ~-0.6, ~0.6)
    @ll_rot1 = param("ll_rot1", ~0.0, ~-0.4, ~0.4)
    # a second, independent clearance window (l2_*): the lead leg's hip / abduction / knee shifted from l2_t0 to l2_win s after the release of
    # pass l2_pass (the left return's flight clips the lead thigh / shin on 13 % of the starts, but a lift during the right return's stroke disturbs it)
    @l2_hip = param("l2_hip", ~0.0, ~-0.4, ~0.4)
    @l2_abd = param("l2_abd", ~0.0, ~-0.4, ~0.4)
    @l2_knee = param("l2_knee", ~0.0, ~-0.6, ~0.6)
    @l2_pass = param("l2_pass", ~2.0, ~0.0, ~12.0).round
    @l2_t0 = param("l2_t0", ~0.0, ~0.0, ~0.6)
    @l2_win = param("l2_win", ~0.3, ~0.05, ~1.0)
    @l2_ramp = param("l2_ramp", ~0.04, ~0.01, ~0.3)
    # trunk offsets in the same windows: the left hand's second stroke meets arrivals up to 0.46 m out (it reaches 0.43): a twist toward it or a lean
    # may extend its reach (the trunk joints spine_rot / spine_flex / spine_lat, radians)
    @lt_rot = param("lt_rot", ~0.0, ~-0.4, ~0.4)
    @lt_flex = param("lt_flex", ~0.0, ~-0.4, ~0.4)
    @lt_lat = param("lt_lat", ~0.0, ~-0.4, ~0.4)
    # a STATIC lead leg offset from the start (ramped over ls_ramp s): a different stance for the whole run (no motion during any stroke)
    @ls_hip = param("ls_hip", ~0.0, ~-0.4, ~0.4)
    @ls_abd = param("ls_abd", ~0.0, ~-0.4, ~0.4)
    @ls_knee = param("ls_knee", ~0.0, ~-0.6, ~0.6)
    @ls_ramp = param("ls_ramp", ~0.5, ~0.05, ~1.0)
    # (round 4) a different cock for the reflex strokes after the tables (pass number >= pg_first + pg_n) of the lead leg's hand: joint offsets (radians)
    # added to its commanded posture through its recovery, wait and the first bl_ckf s of its swing (the table strokes cock higher and more flexed)
    @bl_cksf = param("bl_cksf", ~0.0, ~-0.6, ~0.6)
    @bl_cksa = param("bl_cksa", ~0.0, ~-0.6, ~0.6)
    @bl_cksr = param("bl_cksr", ~0.0, ~-0.6, ~0.6)
    @bl_ckel = param("bl_ckel", ~0.0, ~-0.6, ~0.6)
    @bl_ckwf = param("bl_ckwf", ~0.0, ~-0.6, ~0.6)
    @bl_ckwd = param("bl_ckwd", ~0.0, ~-0.6, ~0.6)
    @bl_ckr = param("bl_ckr", ~0.08, ~0.01, ~0.3)
    @bl_ckf = param("bl_ckf", ~0.05, ~0.0, ~0.3)
    @lb_hip1 = param("lb_hip1", ~0.0, ~-0.4, ~0.4)
    @lb_abd1 = param("lb_abd1", ~0.0, ~-0.4, ~0.4)
    @lb_knee1 = param("lb_knee1", ~0.0, ~-0.6, ~0.6)
    @lb_hip = param("lb_hip", ~0.0, ~-0.4, ~0.4)
    @lb_abd = param("lb_abd", ~0.0, ~-0.4, ~0.4)
    @lb_knee = param("lb_knee", ~0.0, ~-0.6, ~0.6)
    @ll_from = param("ll_from", ~3.0, ~0.0, ~12.0).round
    @ll_n = param("ll_n", ~2.0, ~0.0, ~12.0).round
    @ll_t0 = param("ll_t0", ~0.0, ~0.0, ~0.6)
    @ll_win = param("ll_win", ~0.55, ~0.1, ~1.0)
    @ll_ramp = param("ll_ramp", ~0.08, ~0.01, ~0.3)
    # (program) see the header
    @pg_on = param("pg_on", ~0.0, ~0.0, ~1.0)
    @pg_first = param("pg_first", ~1.0, ~0.0, ~8.0).round
    @pg_n = param("pg_n", ~1.0, ~0.0, ~40.0).round
    # the tables hold pg_stages stages; a longer run cycles through the last pg_per of them (0: the reflex controller
    # takes over after the last stage)
    @pg_stages = param("pg_stages", @pg_n * ~1.0, ~0.0, ~8.0).round
    @pg_per = param("pg_per", ~0.0, ~0.0, ~8.0).round
    @pg_nk = param("pg_nk", ~17.0, ~2.0, ~40.0).round
    @pg_dk = param("pg_dk", ~0.025, ~0.005, ~0.1)
    @pg_lead = param("pg_lead", ~0.165, ~0.0, ~0.5)
    # pg_align 1: the stage's table clock is aligned to the ball's predicted crossing instead of to the trigger tick: the trigger fires on the first
    # control tick with the predicted time to the crossing <= the lead, so that time is anywhere in (lead - 0.005, lead]; the clock starts at
    # (lead - pg_acd) - (that time), removing the tick quantisation (pg_acd 0.0025: the same mean start)
    @pg_align = param("pg_align", ~0.0, ~0.0, ~1.0)
    # (apex schedule) the incoming ball's predicted apex height da = apex - pg_ap0<stage> moves the stage's schedule position by
    # (pg_apx<stage>, pg_apy<stage>) sigma per metre and its clock by pg_apt<stage> s per metre: a ball that will not rise to the strike height
    # meets the palm lower and later
    @pg_ap0 = []
    @pg_apx = []
    @pg_apy = []
    @pg_apt = []
    # (round 6) pg_vts<stage>: the stage's clock is shifted by pg_vts seconds per unit of the energy-hinge feature uvv (pg_vn 1): a weak ball's predicted crossing
    # time is the time to its apex, so the stroke meets it at another phase; neutral at 0
    @pg_vts = []
    # (round 6) pg_gv<stage>: a stage whose incoming ball's vertical speed at the crossing (receive_state's c[6]) is below pg_gv is not played: the reflex strokes
    # that pass (a weak ball hovers at the strike height: the open-loop table touches 34 % of them, the reflex more); neutral at its default -1
    @pg_gvs = []
    # (round 6) pg_vsel<stage> 1: the energy-hinge feature's argument is the incoming ball's predicted APEX (its rise's z + vz^2 / 2g) instead of its vertical speed
    # at the crossing: uvv = clip((pgvk - apex) / pgvs, 0, 2.5), so the block pgv<stage>_m_k can lower the stroke for a ball that peaks below the strike height
    # (the tables touch every ball that peaks above 0.66 m and 13-36 % of those below 0.62); neutral at 0
    # pg_vsel<stage> 2: the same apex argument with the hinge turned over, uv = clip((apex - pgvk) / pgvs, 0, 2.5): a block for the STRONG balls
    @pg_vsel = []
    zi = 0
    while zi < 8
      @pg_ap0.push(param("pg_ap0" + zi.to_s, ~0.7, ~0.4, ~1.0))
      @pg_apx.push(param("pg_apx" + zi.to_s, ~0.0, ~-100.0, ~100.0))
      @pg_apy.push(param("pg_apy" + zi.to_s, ~0.0, ~-100.0, ~100.0))
      @pg_apt.push(param("pg_apt" + zi.to_s, ~0.0, ~-1.0, ~1.0))
      @pg_vts.push(param("pg_vts" + zi.to_s, ~0.0, ~-0.2, ~0.2))
      @pg_gvs.push(param("pg_gv" + zi.to_s, ~-1.0, ~-1.0, ~3.0))
      @pg_vsel.push(param("pg_vsel" + zi.to_s, ~0.0, ~0.0, ~2.0))
      zi += 1
    @pg_acd = param("pg_acd", ~0.0025, ~-0.005, ~0.005)
    @pg_acds = []
    zi = 0
    while zi < 8
      @pg_acds.push(param("pg_acd" + zi.to_s, @pg_acd, ~-0.005, ~0.005))
      zi += 1
    # per stage (table ordinal) trigger lead, defaulting to pg_lead
    @pg_leads = []
    zi = 0
    while zi < 8
      @pg_leads.push(param("pg_lead" + zi.to_s, @pg_lead, ~0.0, ~0.5))
      zi += 1
    @pg_gain = param("pg_gain", ~0.0, ~0.0, ~1.0)
    @pg_dbg = param("pg_dbg", ~0.0, ~0.0, ~1.0)
    # gain-scheduled program (pg_gs 1): each stage's table is T0 + ux Tx + uy Ty, u the predicted crossing position's
    # offset from the stage's nominal (pgc<p>x, pgc<p>y) in units of pgs<p>x, pgs<p>y
    @pg_gs = param("pg_gs", ~0.0, ~0.0, ~1.0)
    @pg_gmax = param("pg_gmax", ~1000.0, ~0.0, ~1000.0)
    # pg_nz posture features: the stroking arm's joint pgzj<i> (0 shoulder flex, 1 abd, 2 rot, 3 elbow, 4 wrist flex, 5 dev,
    # 6 finger mcp, 7 pip) as its muscle pair's contraction difference at the trigger, (q - pgzn) / pgzs per stage, each with its own
    # gain block pgz<p>_<i>_<m>_<k> (the body's state before the stroke moves what the same stroke does)
    @pg_nz = param("pg_nz", ~0.0, ~0.0, ~4.0).round
    @pg_zj = []
    zi = 0
    while zi < @pg_nz
      @pg_zj.push(param("pgzj" + zi.to_s, ~4.0, ~0.0, ~7.0).round)
      zi += 1
    # (incoming-energy block, round 4) pg_vn 1: a hinge feature of the stage's predicted vertical speed at the crossing vzc,
    # uv = clip((pgvk<stage> - vzc) / pgvs<stage>, 0, 2.5), multiplies a block pgv<stage>_<m>_<k> that is added to the table's knots (a ball that
    # arrives with less energy than the table was fitted for is met with a different stroke); neutral at pg_vn 0 or a zero block
    @pg_vn = param("pg_vn", ~0.0, ~0.0, ~1.0)
    @pg_tv = []
    @pg_vk = []
    @pg_vs = []
    @pg_tz = []
    @pg_zn = []
    @pg_tx = []
    @pg_ty = []
    @pg_nom = []
    @pg_tab = []
    if @pg_on > ~0.5
      pp = 0
      while pp < @pg_stages
        rows = []
        mm = 0
        while mm < 16
          row = []
          kk = 0
          while kk < @pg_nk
            row.push(param("pg" + pp.to_s + "_" + mm.to_s + "_" + kk.to_s, ~0.0, ~0.0, ~1.0))
            kk += 1
          rows.push(row)
          mm += 1
        @pg_tab.push(rows)
        if @pg_gs > ~0.5
          rx = []
          ry = []
          mm = 0
          while mm < 16
            cx = []
            cy = []
            kk = 0
            while kk < @pg_nk
              cx.push(param("pgx" + pp.to_s + "_" + mm.to_s + "_" + kk.to_s, ~0.0, ~-1.0, ~1.0))
              cy.push(param("pgy" + pp.to_s + "_" + mm.to_s + "_" + kk.to_s, ~0.0, ~-1.0, ~1.0))
              kk += 1
            rx.push(cx)
            ry.push(cy)
            mm += 1
          @pg_tx.push(rx)
          @pg_ty.push(ry)
          @pg_nom.push([param("pgc" + pp.to_s + "x", ~0.0, ~-1.0, ~1.0), param("pgc" + pp.to_s + "y", ~0.0, ~-1.0, ~1.0), param("pgs" + pp.to_s + "x", ~0.05, ~0.005, ~0.3), param("pgs" + pp.to_s + "y", ~0.05, ~0.005, ~0.3)])
          rz = []
          zn = []
          zi = 0
          while zi < @pg_nz
            zrows = []
            mm = 0
            while mm < 16
              cz = []
              kk = 0
              while kk < @pg_nk
                cz.push(param("pgz" + pp.to_s + "_" + zi.to_s + "_" + mm.to_s + "_" + kk.to_s, ~0.0, ~-1.0, ~1.0))
                kk += 1
              zrows.push(cz)
              mm += 1
            rz.push(zrows)
            zn.push([param("pgzn" + pp.to_s + "_" + zi.to_s, ~0.0, ~-2.0, ~2.0), param("pgzs" + pp.to_s + "_" + zi.to_s, ~0.05, ~0.002, ~1.0)])
            zi += 1
          @pg_tz.push(rz)
          @pg_zn.push(zn)
          if @pg_vn > ~0.5
            rv = []
            mm = 0
            while mm < 16
              cv = []
              kk = 0
              while kk < @pg_nk
                cv.push(param("pgv" + pp.to_s + "_" + mm.to_s + "_" + kk.to_s, ~0.0, ~-1.0, ~1.0))
                kk += 1
              rv.push(cv)
              mm += 1
            @pg_tv.push(rv)
            @pg_vk.push(param("pgvk" + pp.to_s, ~1.5, ~0.0, ~3.0))
            @pg_vs.push(param("pgvs" + pp.to_s, ~0.2, ~0.02, ~2.0))
        pp += 1
    # (feedback) a tracking servo around the table (pg_fb > 0): while a stage's program runs, the stroking arm's 16 muscles get the
    # stage's NOMINAL contractions (tables pgn / pgnx / pgny / pgnz: the contraction trajectory of the table-driven stroke given the
    # schedule's features, fitted from closed-loop traces) as reflex targets with gain pg_fb (x pg_fbw<joint>), from pg_fbt0 to pg_fbt1
    # after the trigger (ramps of pg_fbr); the damping is about the nominal's own rate (weight pg_fbv). Every key neutral at pg_fb 0.
    @pg_fb = param("pg_fb", ~0.0, ~0.0, ~4.0)
    @pg_fbt0 = param("pg_fbt0", ~0.03, ~0.0, ~0.4)
    @pg_fbt1 = param("pg_fbt1", ~0.4, ~0.0, ~0.4)
    @pg_fbr = param("pg_fbr", ~0.03, ~0.001, ~0.2)
    @pg_fbv = param("pg_fbv", ~1.0, ~0.0, ~1.0)
    # the servo gain is multiplied by pg_fbm from pg_fbtl after the trigger on (ramped by pg_fbr): a different gain over the contact
    @pg_fbm = param("pg_fbm", ~1.0, ~0.0, ~8.0)
    @pg_fbtl = param("pg_fbtl", ~0.15, ~0.0, ~0.4)
    @pg_fbw = []
    zi = 0
    while zi < 8
      @pg_fbw.push(param("pg_fbw" + zi.to_s, ~1.0, ~0.0, ~4.0))
      zi += 1
    # per stage multipliers of the servo gain (stage p = pass number - pg_first)
    @pg_fbs = []
    zi = 0
    while zi < 8
      @pg_fbs.push(param("pg_fbs" + zi.to_s, ~1.0, ~0.0, ~4.0))
      zi += 1
    # (additive offsets) pg_dt 1: every stage adds an offset table pgdt<p>_<m>_<j> (activation, 16 arm muscles, pg_dtn knots pg_dtk s apart
    # from the trigger, linear in between, zero after the last) to the table's drive: the excitation of the closed-loop sensitivity
    # identification (scratchpad/btl3/), and the static bias of the stroke
    @pg_dt = param("pg_dt", ~0.0, ~0.0, ~1.0)
    @pg_dtn = param("pg_dtn", ~6.0, ~2.0, ~12.0).round
    @pg_dtk = param("pg_dtk", ~0.05, ~0.01, ~0.1)
    @pg_dtt = []
    if @pg_on > ~0.5 && @pg_dt > ~0.5
      pp = 0
      while pp < @pg_stages
        rows = []
        mm = 0
        while mm < 16
          row = []
          kk = 0
          while kk < @pg_dtn
            row.push(param("pgdt" + pp.to_s + "_" + mm.to_s + "_" + kk.to_s, ~0.0, ~-1.0, ~1.0))
            kk += 1
          rows.push(row)
          mm += 1
        @pg_dtt.push(rows)
        pp += 1
    # (predict-then-cancel feedback) pg_fk > 0: at pg_fq decision times pg_fd<q> after the trigger, the stage's predicted outcome error
    # (3 numbers: the next stage's input, e.g. crossing x, y and vertical speed) is formed from the live features (the ball's predicted
    # crossing x, y; the stroking arm's 8 joint proxies c(pos) - c(neg) and their rates) by a fitted linear map
    # (pgfw<p>_<q>_<i>_<f>, pgfa<p>_<q>_<i>, minus the target pgft<p>_<i>), and the offset table of the running stage is changed by
    # -pg_fk * G (pgfg<p>_<q>_<m>_<k>_<i>) times it: the offsets of pg_dt are the knots of that table
    @pg_fk = param("pg_fk", ~0.0, ~0.0, ~2.0)
    @pg_fq = param("pg_fq", ~1.0, ~0.0, ~3.0).round
    @pg_fd = [param("pg_fd0", ~0.06, ~0.0, ~0.3), param("pg_fd1", ~0.10, ~0.0, ~0.3), param("pg_fd2", ~0.14, ~0.0, ~0.3)]
    @pg_fw = []
    @pg_fa = []
    @pg_ft = []
    @pg_fg = []
    if @pg_on > ~0.5 && @pg_fk > ~0.0
      pp = 0
      while pp < @pg_stages
        tg = []
        i3 = 0
        while i3 < 3
          tg.push(param("pgft" + pp.to_s + "_" + i3.to_s, ~0.0, ~-10.0, ~10.0))
          i3 += 1
        @pg_ft.push(tg)
        fwq = []
        faq = []
        fgq = []
        qq = 0
        while qq < @pg_fq
          fw3 = []
          fa3 = []
          i3 = 0
          while i3 < 3
            fr = []
            ff = 0
            while ff < 18
              fr.push(param("pgfw" + pp.to_s + "_" + qq.to_s + "_" + i3.to_s + "_" + ff.to_s, ~0.0, ~-100.0, ~100.0))
              ff += 1
            fw3.push(fr)
            fa3.push(param("pgfa" + pp.to_s + "_" + qq.to_s + "_" + i3.to_s, ~0.0, ~-100.0, ~100.0))
            i3 += 1
          fwq.push(fw3)
          faq.push(fa3)
          gm = []
          mm = 0
          while mm < 16
            gk = []
            kk = 0
            while kk < @pg_dtn
              gk.push([param("pgfg" + pp.to_s + "_" + qq.to_s + "_" + mm.to_s + "_" + kk.to_s + "_0", ~0.0, ~-10.0, ~10.0), param("pgfg" + pp.to_s + "_" + qq.to_s + "_" + mm.to_s + "_" + kk.to_s + "_1", ~0.0, ~-10.0, ~10.0), param("pgfg" + pp.to_s + "_" + qq.to_s + "_" + mm.to_s + "_" + kk.to_s + "_2", ~0.0, ~-10.0, ~10.0)])
              kk += 1
            gm.push(gk)
            mm += 1
          fgq.push(gm)
          qq += 1
        @pg_fw.push(fwq)
        @pg_fa.push(faq)
        @pg_fg.push(fgq)
        pp += 1
    # (gate) from pass pg_gfrom on (pass number - pg_first), a stage whose schedule features at the trigger lie outside the table's design
    # range (|ux|, |uy| > pg_gu or any |z_i| > pg_gz, in the stage's units) is not played: the reflex strokes that pass
    @pg_gfrom = param("pg_gfrom", ~99.0, ~0.0, ~99.0).round
    @pg_gu = param("pg_gu", ~2.0, ~0.0, ~2.5)
    @pg_gz = param("pg_gz", ~2.0, ~0.0, ~2.5)
    @pg_nt = []
    @pg_nx = []
    @pg_ny = []
    @pg_nzt = []
    if @pg_on > ~0.5 && @pg_fb > ~0.0
      pp = 0
      while pp < @pg_stages
        rt = []
        rx = []
        ry = []
        mm = 0
        while mm < 16
          ct = []
          cx = []
          cy = []
          kk = 0
          while kk < @pg_nk
            ct.push(param("pgn" + pp.to_s + "_" + mm.to_s + "_" + kk.to_s, ~0.0, ~-1.0, ~2.0))
            cx.push(param("pgnx" + pp.to_s + "_" + mm.to_s + "_" + kk.to_s, ~0.0, ~-1.0, ~1.0))
            cy.push(param("pgny" + pp.to_s + "_" + mm.to_s + "_" + kk.to_s, ~0.0, ~-1.0, ~1.0))
            kk += 1
          rt.push(ct)
          rx.push(cx)
          ry.push(cy)
          mm += 1
        rz = []
        zi = 0
        while zi < @pg_nz
          zrows = []
          mm = 0
          while mm < 16
            cz = []
            kk = 0
            while kk < @pg_nk
              cz.push(param("pgnz" + pp.to_s + "_" + zi.to_s + "_" + mm.to_s + "_" + kk.to_s, ~0.0, ~-1.0, ~1.0))
              kk += 1
            zrows.push(cz)
            mm += 1
          rz.push(zrows)
          zi += 1
        @pg_nt.push(rt)
        @pg_nx.push(rx)
        @pg_ny.push(ry)
        @pg_nzt.push(rz)
        pp += 1

  -> btl?
    @mode > ~5.5

  -> rotating?
    btl? && (@bt_rotl != ~0.0 || @bt_rotr != ~0.0)

  # The planned contact (bt_plan) for this hand (bt_pside).
  -> planned?(hand)
    return false if @bt_plan < ~0.5
    return true if @bt_pside < ~0.5
    return hand.side == lead_side if @bt_pside < ~1.5
    hand.side != lead_side

  # 6: a pass between the legs on every push; 7: a pass, then one dribble
  # by the receiving hand; 8: a pass and its return, then one dribble by
  # the first hand (it resets the ball to the full-height rebound its pass
  # is made from)
  -> token(k)
    return "D" if btl? && k < @bt_settle.round
    super(k)

  # (9: a pass, then the receiving hand's catch and one more dribble, back
  # to full height, before its own pass)
  -> script_for(mode)
    return "B D D" if mode > ~8.5
    return "B B D" if mode > ~7.5
    return "B D" if mode > ~6.5
    return "B" if mode > ~5.5
    super(mode)

  # Lead side "l" or "r"; y of a spot authored for a left lead, for this lead.
  -> lead_side
    @st_lead > ~0.5 ? "r" : "l"

  -> ly(y)
    return y if lead_side == "l"
    ~0.0 - y

  # A hand's spot: the back leg's hand in front, the lead leg's hand behind.
  -> spot_of(side)
    return [@bt_bx, ly(@bt_by)] if side == lead_side
    [@bt_fx, ly(@bt_fy)]

  -> start(frame, ctl)
    read_params
    @radius = ~0.12
    @g = ~9.81
    @pelvis = [frame.at("pelvis_pos", 0), frame.at("pelvis_pos", 1), frame.at("pelvis_pos", 2)]
    home = [frame.at("ball_home", 0), frame.at("ball_home", 1)]
    rhome = home
    lhome = [home[0], ~0.0 - home[1]]
    if btl?
      rhome = spot_of("r")
      lhome = spot_of("l")
      solve_stance
    @right = DribbleV3Hand.new(body, "r", rhome)
    @left = DribbleV3Hand.new(body, "l", lhome)
    @ilc = {"r" => [~0.0, ~0.0], "l" => [~0.0, ~0.0]}
    @kch = {}
    @rch = {}
    @xrc = {}
    @rel_t = ~-1.0
    @ck_sw = ~-1.0
    @kplan = {"r" => nil, "l" => nil}
    @ktouch = {"r" => false, "l" => false}
    @kplanned = {"r" => false, "l" => false}
    @pass_no = 0
    @pg_state = {"r" => nil, "l" => nil}
    @pg_vref = {"r" => false, "l" => false}
    @pg_skip = -1
    @pg_mus = {}
    if @pg_on > ~0.5
      ["r", "l"].each ->(sd)
        idx = []
        ["shoulder_flex", "shoulder_abd", "shoulder_rot", "elbow", "wrist_flex", "wrist_dev", "finger_mcp", "finger_pip"].each ->(j)
          idx.push(body.pos_index(sd + "_" + j))
          idx.push(body.neg_index(sd + "_" + j))
        @pg_mus[sd] = idx
    @kil = {"r" => [~0.0, ~0.0, ~0.0, ~0.0], "l" => [~0.0, ~0.0, ~0.0, ~0.0]}
    @sent = nil
    @fingers = body.has_joint?("r_finger_mcp")
    @reg = [@sh_reg, @sh_reg, @rot_reg, ~0.002, ~0.002, ~0.002]
    @meet_reg = [@m_reg, @m_reg, @m_reg, @m_reg, @m_reg, @m_reg]
    @pose_reg = [~0.002, ~0.002, ~0.002, ~0.002, ~0.002, ~0.002]
    @script = script_for(@mode).split(" ")
    @step = 0
    @active = @right
    @move = "D"
    @target = rhome
    @stance = "a"
    @stance_pending = ""
    @hold_stance = false
    @setup = false
    @trunk_low = false
    arms_r = body.mask(["r_shoulder", "r_elbow", "r_wrist", "r_finger"])
    arms_l = body.mask(["l_shoulder", "l_elbow", "l_wrist", "l_finger"])
    trunk = body.mask(["spine_flex"])
    trunk = body.mask(["spine_flex", "spine_rot"]) if rotating?
    ctl.reflex.set_gains(arms_r, @arm_kp, @arm_kd)
    ctl.reflex.set_gains(arms_l, @arm_kp, @arm_kd) if @mode > ~0.5
    ctl.reflex.set_gains(body.mask(["r_finger", "l_finger"]), @f_kp, @f_kd) if @fingers
    ctl.reflex.set_gains(body.mask(["l_hip", "r_hip", "l_knee", "r_knee", "l_ankle", "r_ankle"]), @leg_kp, @leg_kd) if @mode > ~0.5
    used = []
    arms_r.each -> used.push(item)
    arms_l.each -> used.push(item)
    trunk.each -> used.push(item)
    ctl.add_track(Track.new("stance", stance_movement, rest_of(used)))
    ctl.add_track(Track.new("trunk", trunk_movement, trunk))
    ctl.add_track(Track.new("right", hand_movement(@right), arms_r))
    ctl.add_track(Track.new("left", hand_movement(@left), arms_l))
    @arm_mask = {"r" => arms_r, "l" => arms_l}
    if btl?
      # step into the lunge while the ball is still held, or hold the one the
      # body starts in
      if @st_stepin > ~0.5
        set_stance(frame, ctl, lead_side)
      else
        ctl.track("stance").jump(ctl, frame, lead_side + "_lead")
        @stance = lead_side
      ctl.emit(@stance_note)
    choose(frame, ctl, @right)

  # The lunge's leg angles on the controller's leg model: the lead foot at
  # (st_fx, st_fy), the back foot at (st_bx, st_by), ankles 0.078 m up.
  -> solve_stance
    h = @pelvis[2]
    ls = lead_side
    bs = ls == "l" ? "r" : "l"
    lead = DribbleBtlLeg.new(body, ls)
    back = DribbleBtlLeg.new(body, bs)
    @front_q = lead.solve(h, [~0.8, ~0.1, ~0.0, ~0.7, ~0.1], [@st_fx, ly(@st_fy), ~0.078])
    @back_q = back.solve(h, [~-0.3, ~0.1, ~0.05, ~0.3, ~-0.59], [@st_bx, ly(@st_by), ~0.078])
    fq = @front_q.map -> item.to_s
    bq = @back_q.map -> item.to_s
    @stance_note = "stance_q:" + fq.join(",") + ":" + bq.join(",")
    nil

  # DribbleV3Skill's stance chunks with this lunge's legs.
  -> leg(kind, lifted)
    return super(kind, lifted) if !btl?
    q = [~0.57, ~0.1, ~0.0, ~1.14, ~-0.57]
    if kind == "front"
      q = @front_q.map -> item
    elsif kind == "back"
      q = @back_q.map -> item
    if lifted
      q[0] = q[0] + @st_lhip
      q[3] = q[3] + @st_lknee
    q

  -> stance_movement
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

  # The arm model's base for planned poses: the pelvis, the trunk's lean
  # and (BTL mode) its twist.
  -> pose_base(spine)
    tw = ~0.0
    tw = @twist if btl?
    [@pelvis[0], @pelvis[1], @pelvis[2], ~0.0, spine, ~0.0, tw]

  -> arm_solve_reg(hand, x, y, z, pitch, roll, spine, reg)
    seed = [@sf0, @sa0, @rot0, ~1.4, ~-0.05, ~0.1]
    normal = DribbleV3Math.unit(Math.sin(pitch), hand.ys(Math.sin(roll)), ~0.0 - Math.cos(pitch) * Math.cos(roll))
    hand.arm.solve(pose_base(spine), seed, [x, y, z], normal, 40, reg)

  -> stroke_low(hand, q_cock, x, y, z, pitch, roll, spine)
    normal = DribbleV3Math.unit(Math.sin(pitch), hand.ys(Math.sin(roll)), ~0.0 - Math.cos(pitch) * Math.cos(roll))
    hand.arm.solve(pose_base(spine), q_cock, [x, y, z], normal, 40, @reg)

  -> palm_at(hand, q, spine)
    hand.arm.fk(pose_base(spine), q)

  # DribbleV3Skill's stance pose with the trunk twisted (BTL mode).
  -> stance_pose(lq, rq)
    return super(lq, rq) if !btl?
    p = Pose.new
    names = ["hip_flex", "hip_abd", "hip_rot", "knee", "ankle"]
    i = 0
    while i < 5
      p.set("l_" + names[i], lq[i], @stiff)
      p.set("r_" + names[i], rq[i], @stiff)
      i += 1
    p.set("pelvis_yaw", ~0.0, @stiff)
    p.set("spine_lat", ~0.0, @t_stiff)
    p.set("spine_rot", @twist, @t_stiff)
    p

  # Arm angles with the palm contact point at (x, y, z) facing `normal`.
  -> arm_solve_n(hand, seed, x, y, z, normal, reg)
    hand.arm.solve(pose_base(@spine), seed, [x, y, z], normal, 40, reg)

  # The palm normal tilted `a` from straight down toward (ux, uy).
  -> tilted(ux, uy, a)
    DribbleV3Math.unit(ux * Math.sin(a), uy * Math.sin(a), ~0.0 - Math.cos(a))

  # BTL mode: each hand dribbles from its own spot, and its pass stroke runs
  # along the line to the other spot: cocked with the palm on the far top of
  # a ball at the spot (behind it, seen along the pass), the low end bt_sweep
  # further along the pass, the palm tilted toward it. The right hand also
  # launches the ball: held over its spot until the feet are set (st_hold),
  # thrown straight down, and its first stroke is a pass. A plain dribble
  # (mode 7) is DribbleV3Skill's stroke at the hand's spot.
  -> hand_movement(hand)
    return super(hand) if !btl?
    @t_hold = @st_hold
    hx = hand.home[0]
    hy = hand.home[1]
    sp = @spine
    ot = spot_of(hand.side == "r" ? "l" : "r")
    dl = Math.sqrt((ot[0] - hx) * (ot[0] - hx) + (ot[1] - hy) * (ot[1] - hy))
    ux = (ot[0] - hx) / dl
    uy = (ot[1] - hy) / dl
    lh = hand.side == lead_side
    if lh
      q_cock = arm_solve(hand, hx + @dl_dxc, hy, @dl_zcock, @dl_pc, ~0.0, sp)
      q_low = stroke_low(hand, q_cock, hx + @dl_dxl, hy, @dl_zlow, @dl_pl, ~0.0, sp)
    else
      q_cock = arm_solve(hand, hx + @dx_cock, hy, @z_cock, @pitch_cock, ~0.0, sp)
      q_low = stroke_low(hand, q_cock, hx + @dx_low, hy, @z_low, @pitch_low, ~0.0, sp)
    angc = lh ? @bl_angc : @bt_angc
    angl = lh ? @bl_angl : @bt_angl
    zc = lh ? @bl_zc : @bt_zc
    zl = lh ? @bl_zl : @bt_zl
    sw = lh ? @bl_sweep : @bt_sweep
    seed = lh ? [@bl_sf, @bl_sa, @bl_sr, @bl_se, ~0.0, ~0.0] : [@bt_sf, @bt_sa, @bt_sr, @bt_se, ~0.0, ~0.0]
    nc = tilted(ux, uy, angc)
    nl = tilted(ux, uy, angl)
    r = @radius
    q_bc = arm_solve_n(hand, seed, hx - r * nc[0], hy - r * nc[1], zc - r * nc[2] - r, nc, @pose_reg)
    q_bl = arm_solve_n(hand, q_bc, hx + sw * ux - r * nl[0], hy + sw * uy - r * nl[1], zl - r * nl[2] - r, nl, @reg)
    fo = @f_open
    ff = @f_flick
    cock = hand_pose(hand, q_cock, @arm_stiff, fo)
    low = hand_pose(hand, q_low, @push_stiff, ff)
    bcock = hand_pose(hand, q_bc, @arm_stiff, fo)
    blow = hand_pose(hand, q_bl, @push_stiff, ff)
    drv = burst(hand, q_cock, q_low, fo, ff)
    bdrv = burst(hand, q_bc, q_bl, fo, ff)
    if lh && @bl_drv != ~1.0
      bk = @bl_drv
      bdrv = bdrv.map -> item * bk
    meet = ->(f, c) hand_fix(f, c, hand, :meet)
    carry = ->(f, c) hand_fix(f, c, hand, :carry)
    idle = ->(f, c) nil
    over = ->(f, c) handoff(f, c, hand)
    k = hand.touch_k
    touch = Latch.above("ball_touch", k, @touch_thr)
    released = Latch.below("ball_touch", k, @release_thr).after_min(@push_min)
    arrive = Latch.test("arrive", ->(f, e, c) arrival(f, hand) < lead(hand))
    strike = Latch.test("strike", ->(f, e, c) strike_now?(f, hand))
    never = Latch.test("never", ->(f, e, c) false)
    zh = lh ? @dl_zhit : @z_hit
    bzh = lh ? @bl_zh : @bt_zh
    tp = @t_push
    tc = @t_carry
    g = @push_gain
    pm = @push_max
    mv = Movement.new(hand.name)
    if hand.side == "r"
      q_hold = arm_solve(hand, hx + @bt_lhx, hy + @bt_lhy, @pelvis[2] + ~0.19, ~0.0, ~0.0, sp)
      q_lc = arm_solve(hand, hx + @bt_lhx, hy + @bt_lhy, @bt_lzc, ~0.0, ~0.0, sp)
      q_ll = arm_solve_n(hand, q_lc, hx + @bt_ldx, hy + @bt_ldy, @bt_lzl, [~0.0, ~0.0, ~-1.0], @pose_reg)
      hold = hand_pose(hand, q_hold, @arm_stiff, fo)
      lcock = hand_pose(hand, q_lc, @arm_stiff, ~0.0)
      llow = hand_pose(hand, q_ll, @push_stiff, ~0.0)
      ld = @bt_ldrv
      ldrv = burst(hand, q_lc, q_ll, ~0.0, ~0.0).map -> item * ld
      held = ->(f, c) launch_fix(f, c, hand, false)
      launch = ->(f, c) launch_fix(f, c, hand, true)
      mv.add(Chunk.new("hold", ~0.3).pose(hold).hold_until(Latch.after(@t_hold)).correct(held, @spring))
      mv.add(Chunk.new("lift", @t_lift).pose(lcock).correct(held, @spring))
      lt = @bt_lt
      if @bt_ldrop > ~0.5
        mv.add(Chunk.new("settle", @bt_lset).pose(lcock).correct(held, @spring))
        mv.add(Chunk.new("let_go", ~0.08).pose(lcock).on_enter(->(f, c) let_go(f, c, hand)).correct(held, @spring).branch(->(f, c) entry_for(hand)))
      else
        mv.add(Chunk.new("throw", lt).pose(llow).drive(ldrv).gain(g).hold_until(Latch.below("r_hand_pos", 2, @z_rel), lt * ~2.0).correct(launch, @spring))
        mv.add(Chunk.new("let_go", lt).pose(llow).drive(ldrv).gain(g).on_enter(->(f, c) let_go(f, c, hand)).correct(launch, @spring).branch(->(f, c) entry_for(hand)))
    else
      mv.add(Chunk.new("rest", ~0.3).pose(bcock).hold_until(never).correct(idle, @spring))
    # the plain dribble at the spot
    mv.add(Chunk.new("recover", @t_rec).pose(cock).correct(meet, @spring).on_enter(->(f, c) entering(f, c, hand, zh)))
    mv.add(Chunk.new("wait", ~0.05).pose(cock).hold_until(arrive, ~1.5).correct(meet, @spring))
    mv.add(shape(Chunk.new("swing", tp).pose(low).drive(drv).gain(g).hold_until(touch, pm).correct(carry, @spring).on_enter(->(f, c) striking(f, c, hand, false))))
    mv.add(shape(Chunk.new("carry", tc).pose(low).drive(drv).gain(g).hold_until(released, pm).correct(carry, @spring).followed_by("recover").branch(over)))
    # the pass between the legs
    if planned?(hand)
      # (planned: the contact may be planned while the hand is still
      # recovering, going straight to its knot)
      plan_early = Latch.test("plan_early", ->(f, e, c) e >= @t_rec || plan_ready?(f, c, hand))
      mv.add(Chunk.new("x_recover", @t_rec).pose(bcock).hold_until(plan_early, ~1.5).correct(meet, @spring).on_enter(->(f, c) entering(f, c, hand, bzh)).branch(->(f, c) planned_next(hand)))
    else
      xr = BtlChunk.new("x_recover", @t_rec).pose(bcock).correct(meet, @spring).on_enter(->(f, c) entering(f, c, hand, bzh))
      @xrc[hand.side] = xr
      mv.add(xr)
    if planned?(hand)
      plan = Latch.test("plan", ->(f, e, c) plan_ready?(f, c, hand))
      mv.add(Chunk.new("x_wait", ~0.05).pose(bcock).hold_until(plan, ~1.5).correct(meet, @spring).followed_by("k_strike"))
    else
      mv.add(Chunk.new("x_wait", ~0.05).pose(bcock).hold_until(strike, ~1.5).correct(meet, @spring))
    mv.add(shape(Chunk.new("x_swing", tp).pose(blow).drive(bdrv).gain(g).hold_until(touch, pm).correct(carry, @spring).on_enter(->(f, c) striking(f, c, hand, false))))
    mv.add(shape(Chunk.new("x_carry", tc).pose(blow).drive(bdrv).gain(g).hold_until(released, pm).correct(carry, @spring).followed_by("idle").branch(over)))
    mv.add(Chunk.new("idle", @t_rec).pose(bcock).hold_until(never).correct(idle, @spring))
    if !lh
      # the pass after a catch (bt_ychain): the same cycle on the br_* stroke
      ync = tilted(ux, uy, @br_angc)
      ynl = tilted(ux, uy, @br_angl)
      bsw = @br_sweep
      q_yc = arm_solve_n(hand, seed, hx - r * ync[0], hy - r * ync[1], @br_zc - r * ync[2] - r, ync, @pose_reg)
      q_yl = arm_solve_n(hand, q_yc, hx + bsw * ux - r * ynl[0], hy + bsw * uy - r * ynl[1], @br_zl - r * ynl[2] - r, ynl, @reg)
      ycock = hand_pose(hand, q_yc, @arm_stiff, fo)
      ylow = hand_pose(hand, q_yl, @push_stiff, ff)
      yk = @br_drv
      ydrv = burst(hand, q_yc, q_yl, fo, ff).map -> item * yk
      yzh = @br_zh
      mv.add(Chunk.new("y_recover", @t_rec).pose(ycock).correct(meet, @spring).on_enter(->(f, c) entering(f, c, hand, yzh)))
      mv.add(Chunk.new("y_wait", ~0.05).pose(ycock).hold_until(strike, ~1.5).correct(meet, @spring))
      mv.add(shape(Chunk.new("y_swing", tp).pose(ylow).drive(ydrv).gain(g).hold_until(touch, pm).correct(carry, @spring).on_enter(->(f, c) striking(f, c, hand, false))))
      mv.add(shape(Chunk.new("y_carry", tc).pose(ylow).drive(ydrv).gain(g).hold_until(released, pm).correct(carry, @spring).followed_by("idle").branch(over)))
    # the planned contact (bt_plan): knots set by plan_strike
    kdone = Latch.test("k_released", ->(f, e, c) k_released?(f, hand))
    ks = BtlChunk.new("k_strike", @bt_kt).pose(bcock).knot(zeros, nil).via.drive(zeros).gain(g).correct(carry, @spring).on_enter(->(f, c) striking(f, c, hand, false))
    kp = BtlChunk.new("k_push", @bt_kpt).pose(blow).knot(zeros, nil).gain(g).hold_until(kdone, pm).correct(carry, @spring).followed_by("idle").branch(over)
    mv.add(ks)
    mv.add(kp)
    @kch[hand.side] = [ks, kp]
    # the absorbing receive (bt_rplan): knots set by plan_receive
    rready = Latch.test("r_plan", ->(f, e, c) receive_ready?(f, c, hand))
    rhover = ->(f, c) receive_hover(f, c, hand)
    mv.add(Chunk.new("r_recover", @t_rec).pose(bcock).hold_until(rready, ~1.5).correct(rhover, @spring).on_enter(->(f, c) entering(f, c, hand, bzh)))
    r1 = BtlChunk.new("r_meet", @bt_rt1).pose(bcock).knot(zeros, nil).via.gain(g).correct(carry, @spring)
    r2 = BtlChunk.new("r_absorb", @bt_rt).pose(bcock).knot(zeros, nil).via.gain(g).correct(carry, @spring)
    r3 = BtlChunk.new("r_push", @bt_rpt).pose(bcock).knot(zeros, nil).via.drive(zeros).gain(g).correct(carry, @spring).on_enter(->(f, c) striking(f, c, hand, false))
    r4 = BtlChunk.new("r_follow", @bt_kpt).pose(blow).knot(zeros, nil).gain(g).hold_until(kdone, pm).correct(carry, @spring).followed_by("idle").branch(over)
    mv.add(r1)
    mv.add(r2)
    mv.add(r3)
    mv.add(r4)
    @rch[hand.side] = [r1, r2, r3, r4]
    # the muscle program's stroke: the reflexes off (pg_gain), the table's activations added as drive by `before`
    if @pg_on > ~0.5
      mv.add(Chunk.new("g_run", @pg_dk * ((@pg_nk - 1) * ~1.0)).pose(bcock).gain(@pg_gain).on_enter(->(f, c) striking(f, c, hand, false)).followed_by("idle"))
    mv

  -> choose(f, ctl, hand)
    return super(f, ctl, hand) if !btl?
    @move = token(@step)
    @step += 1
    @setup = false
    ctl.emit("plan:" + @move + ":" + hand.label)
    if @move == "D"
      @target = hand.home
      return nil
    other = other_of(hand)
    sp = other.home
    off = @ilc[hand.side]
    ax = hand.side == lead_side ? @bl_ax : @bt_ax
    ay = hand.side == lead_side ? ly(@bl_ay) : ly(@bt_ay)
    if ychain?(hand)
      ax = @br_ax
      ay = ly(@br_ay)
    if @pg_on > ~0.5 && @pass_no >= @pg_first + @pg_n
      ax = ax + (hand.side == lead_side ? @bl_dax : @bt_dax)
      ay = ay + ly(hand.side == lead_side ? @bl_day : @bt_day)
    @target = [sp[0] + off[0] + ax, sp[1] + off[1] + ay]
    @sent = [hand.side, sp[0], sp[1]]
    nil

  # DribbleV3Skill's :meet correction (see its hand_fix) with the adaptive
  # strike height: hand.dz follows the predicted apex, bt_aoff below it,
  # between -dz_max and +bt_dzup.
  -> meet_fix(f, ctl, hand)
    return nil if f.get("ball_held") > ~0.5
    base = base_now(f)
    q = arm_command(ctl, hand)
    h = hand.arm.fk(base, q)
    hand.dz = DribbleV3Math.clamp(f.at("ball_apex", 2) + @radius - @bt_aoff - hand.zh, ~0.0 - @dz_max, @bt_dzup)
    aim = meet_point(f, hand.zh - @radius + hand.dz)
    bx = aim[0]
    by = aim[1]
    law = move_law(hand)
    hand.ix = hand.ix + (f.at("ball_pos", 0) - law[0]) * ctl.dt
    hand.iy = hand.iy + (f.at("ball_pos", 1) - law[1]) * ctl.dt
    tilt = palm_tilt(f, hand, law)
    n = DribbleV3Math.unit(h[3] + tilt[0], h[4] + tilt[1], h[5])
    m = hand.arm.fk(base, arm_measured(f, hand))
    hand.palm_prev = m
    tx = bx - @radius * n[0]
    ty = by - @radius * n[1]
    tx = tx + @hand_fb * (tx - m[0])
    ty = ty + @hand_fb * (ty - m[1])
    tx = DribbleV3Math.clamp(tx, h[0] - @reach, h[0] + @reach)
    ty = DribbleV3Math.clamp(ty, h[1] - @reach, h[1] + @reach)
    hand.aim = [tx, ty]
    qd = hand.arm.solve(base, q, [tx, ty, h[2] + hand.dz], n, 2, @meet_reg)
    hand.qoff = (0...6).map ->(i) qd[i] - q[i]
    off = zeros
    i = 0
    while i < 6
      joint_offset(off, hand.arm.joints[i], qd[i] - q[i])
      i += 1
    off

  # The launch's correction (bt_lfix): the palm held over the spot plus the
  # launch aim (bt_lhx, bt_lhy) while it holds and lifts the ball; through
  # the throw it follows the straight line down to (bt_ldx, bt_ldy) from the
  # spot, by the commanded palm height; aimed past the measured miss by
  # hand_fb, facing down. The aim's offset sets the throw's drift.
  -> launch_fix(f, ctl, hand, throwing)
    return nil if @bt_lfix < ~0.5
    base = base_now(f)
    q = arm_command(ctl, hand)
    h = hand.arm.fk(base, q)
    m = hand.arm.fk(base, arm_measured(f, hand))
    tx = hand.home[0] + @bt_lhx
    ty = hand.home[1] + @bt_lhy
    if throwing
      fr = DribbleV3Math.clamp((@bt_lzc - h[2]) / (@bt_lzc - @bt_lzl), ~0.0, ~1.0)
      tx = tx + fr * (@bt_ldx - @bt_lhx)
      ty = ty + fr * (@bt_ldy - @bt_lhy)
    tx = tx + @hand_fb * (tx - m[0])
    ty = ty + @hand_fb * (ty - m[1])
    tx = DribbleV3Math.clamp(tx, h[0] - @reach, h[0] + @reach)
    ty = DribbleV3Math.clamp(ty, h[1] - @reach, h[1] + @reach)
    qd = hand.arm.solve(base, q, [tx, ty, h[2]], [~0.0, ~0.0, ~-1.0], 2, @meet_reg)
    off = zeros
    i = 0
    while i < 6
      joint_offset(off, hand.arm.joints[i], qd[i] - q[i])
      i += 1
    off

  # BTL stroke (bt_hold): through the swing and the carry the arm keeps the
  # offset the meeting correction took, so the palm comes down along the
  # stroke from behind the ball instead of being pulled back onto its top.
  -> hand_fix(f, ctl, hand, mode)
    # (the reset dribble on DribbleV3Skill's stroke keeps its corrections)
    return super(f, ctl, hand, mode) if @move == "D" && btl? && @bt_dy < ~0.5 && active?(hand) && hand.fresh
    return hover_fix(f, ctl, hand) if mode == :meet && btl? && planned?(hand) && active?(hand) && @move == "B"
    return meet_fix(f, ctl, hand) if mode == :meet && btl? && @bt_dzup > ~0.0 && active?(hand) && @move == "B"
    return super(f, ctl, hand, mode) if !btl? || @bt_hold < ~0.5 || mode != :carry || !active?(hand)
    return super(f, ctl, hand, mode) if @move != "B" && @bt_dside < ~0.5 && !(@bt_rplan > ~0.5 && hand.fresh)
    return nil if f.get("ball_held") > ~0.5
    off = zeros
    qo = hand.qoff
    i = 0
    while i < 6
      joint_offset(off, hand.arm.joints[i], qo[i])
      i += 1
    off

  # The absorbing receive's hands (bt_rside).
  -> rplan_hand?(hand)
    return true if @bt_rside < ~0.5
    return hand.side != lead_side if @bt_rside < ~1.5
    hand.side == lead_side

  # A back-leg-side hand passing a ball it has just caught (bt_ychain).
  -> ychain?(hand)
    btl? && @bt_ychain > ~0.5 && hand.fresh && hand.side != lead_side

  -> entry_for(hand)
    return "y_recover" if @move == "B" && ychain?(hand)
    return "y_recover" if @move == "D" && ychain?(hand) && @bt_dy > ~0.5
    return "recover" if @move == "D" && btl? && hand.fresh && @bt_dy < ~0.5
    return "r_recover" if btl? && @bt_rplan > ~0.5 && (@move == "B" || @move == "D") && hand.fresh && rplan_hand?(hand)
    return "x_recover" if btl? && (@move == "B" || @bt_dside > ~0.5)
    super(hand)

  # The end of a carry: the other hand starts its receiving cycle (the
  # crossover's, from its own spot).
  -> handoff(f, ctl, hand)
    return super(f, ctl, hand) if !btl?
    return "idle" if !active?(hand)
    hand.fresh = false
    if @move == "D"
      ctl.track("trunk").jump(ctl, f, "back") if rotating?
      choose(f, ctl, hand)
      return entry_for(hand)
    other = other_of(hand)
    @pass_no = @pass_no + 1
    @rel_t = f.t
    ctl.track("trunk").jump(ctl, f, other.side == lead_side ? "rot_l" : "rot_r") if rotating?
    @active = other
    other.ix = ~0.0
    other.iy = ~0.0
    other.aim = nil
    other.fresh = true
    choose(f, ctl, other)
    ctl.track(other.name).jump(ctl, f, entry_for(other))
    "idle"

  -> entering(f, ctl, hand, zh)
    @kplanned[hand.side] = false if btl?
    retime_recover(hand) if btl?
    super(f, ctl, hand, zh)

  # (reflex-stroke recovery) The x_recover chunk of a reflex-driven pass stroke lasts bl_trec (the lead leg's hand) or bt_trec (the other
  # hand); a programmed stage's, and every other chunk's entry, keep t_rec.
  -> retime_recover(hand)
    xr = @xrc[hand.side]
    return nil if xr == nil
    t = @t_rec
    if @move == "B"
      o = pg_ordinal
      if o < 0
        t = @bt_trec
        t = @bl_trec if hand.side == lead_side
      else
        t = @pg_trecs[o]
    xr.retime(t)
    nil

  -> striking(f, ctl, hand, redirect)
    return super(f, ctl, hand, redirect) if !btl?
    ctl.emit("move:" + @move + ":" + hand.label) if active?(hand)
    nil

  # Pass aiming (bt_aim): the law's tilt plus the turn of the commanded palm
  # normal's horizontal part onto the line from the predicted meeting point
  # to the pass's target.
  -> palm_tilt(f, hand, law)
    t = super(f, hand, law)
    return t if !btl? || @bt_aim < ~0.5 || !active?(hand) || @move != "B" || @ctl_now == nil
    h = hand.arm.fk(base_now(f), arm_command(@ctl_now, hand))
    aim = meet_point(f, hand.zh - @radius + hand.dz)
    dx = law[0] - aim[0]
    dy = law[1] - aim[1]
    dl = Math.sqrt(dx * dx + dy * dy)
    return t if dl < ~0.01
    mh = Math.sqrt(h[3] * h[3] + h[4] * h[4])
    [t[0] + mh * dx / dl - h[3], t[1] + mh * dy / dl - h[4]]

  # ---- the planned contact (bt_plan) -------------------------------------------

  # The ball at the planned contact, bt_kph s past the apex of its next rise:
  # [seconds from now, x, y, z, vx, vy, vz], or nil (a ball that will not rise).
  -> contact_state(f)
    return nil if !f.has?("ball_rise")
    vz = f.at("ball_rise", 5)
    return nil if vz <= ~0.5
    tr = f.at("ball_rise", 6)
    vx = f.at("ball_rise", 3)
    vy = f.at("ball_rise", 4)
    s = vz / @g + @bt_kph
    if @bt_kzc > ~0.0
      disc = vz * vz - ~2.0 * @g * (@bt_kzc - f.at("ball_rise", 2))
      s = vz / @g
      s = (vz - Math.sqrt(disc)) / @g if disc > ~0.0
    [tr + s, f.at("ball_rise", 0) + vx * s, f.at("ball_rise", 1) + vy * s, f.at("ball_rise", 2) + vz * s - ~0.5 * @g * s * s, vx, vy, vz - @g * s]

  # The plan latch: once the ball rises from its bounce (an exact
  # prediction), when the predicted contact is bt_kt away (less the hand's
  # lead), plan the knots and go.
  -> plan_ready?(f, ctl, hand)
    return false if f.at("ball_vel", 2) <= ~0.0
    c = contact_state(f)
    return false if c == nil
    return false if c[0] - @bt_klead - @kil[hand.side][0] > @bt_kt
    plan_strike(f, ctl, hand, c)
    true

  # Joint rates (rad/s) that move the palm point at `v` (m/s) from arm angles
  # q: damped least squares on the position Jacobian of the arm model.
  -> joint_rates(hand, base, q, v)
    h0 = hand.arm.fk(base, q)
    eps = ~0.0001
    jac = (0...18).map -> ~0.0
    c = 0
    while c < 6
      q2 = q.map -> item
      q2[c] = q2[c] + eps
      h = hand.arm.fk(base, q2)
      m = 0
      while m < 3
        jac[6 * m + c] = (h[m] - h0[m]) / eps
        m += 1
      c += 1
    a = (0...36).map -> ~0.0
    g = (0...6).map -> ~0.0
    i = 0
    while i < 6
      j = 0
      while j < 6
        sm = ~0.0
        m = 0
        while m < 3
          sm = sm + jac[6 * m + i] * jac[6 * m + j]
          m += 1
        a[6 * i + j] = sm
        j += 1
      a[7 * i] = a[7 * i] + ~0.01
      sm = ~0.0
      m = 0
      while m < 3
        sm = sm + jac[6 * m + i] * v[m]
        m += 1
      g[i] = sm
      i += 1
    DribbleV3Math.solve_spd(a, g, 6)

  # The planned palm contact for the ball state c: [x, y, z, normal, hand
  # velocity direction], the palm on the ball's far top toward the target,
  # plus the hand's learned aim.
  -> contact_palm(c, hand)
    kl = @kil[hand.side]
    dx = @target[0] - c[1]
    dy = @target[1] - c[2]
    dl = Math.sqrt(dx * dx + dy * dy)
    dl = ~0.001 if dl < ~0.001
    ux = dx / dl
    uy = dy / dl
    n = tilted(ux, uy, @bt_knt)
    w = tilted(ux, uy, @bt_kang)
    r = @radius
    [c[1] - r * n[0] + kl[1], c[2] - r * n[1] + kl[2], c[3] - r * n[2] + kl[3], n, w]

  # The wait before a planned contact: the palm hovers bt_khov above the
  # planned contact point, facing as it will at contact (the offset is kept
  # through the knots, see hand_fix).
  -> hover_fix(f, ctl, hand)
    return nil if f.get("ball_held") > ~0.5
    base = base_now(f)
    q = arm_command(ctl, hand)
    c = contact_state(f)
    if c != nil
      cp = contact_palm(c, hand)
      m = hand.arm.fk(base, arm_measured(f, hand))
      # the backswing: bt_khov back along the hand's path at contact
      w = cp[4]
      tx = cp[0] - @bt_khov * w[0]
      ty = cp[1] - @bt_khov * w[1]
      tz = cp[2] - @bt_khov * w[2]
      tx = tx + @hand_fb * (tx - m[0])
      ty = ty + @hand_fb * (ty - m[1])
      qd = hand.arm.solve(base, q, [tx, ty, tz], cp[3], 2, @meet_reg)
      hand.qoff = (0...6).map ->(i) qd[i] - q[i]
    off = zeros
    i = 0
    while i < 6
      joint_offset(off, hand.arm.joints[i], hand.qoff[i])
      i += 1
    off

  # Plan the contact knot and the push knot for the ball state c.
  -> plan_strike(f, ctl, hand, c)
    side = hand.side
    dur = DribbleV3Math.clamp(c[0] - @bt_klead - @kil[side][0], ~0.03, @bt_kt + ~0.05)
    cp = contact_palm(c, hand)
    px = cp[0]
    py = cp[1]
    pz = cp[2]
    n = cp[3]
    w = cp[4]
    base = base_now(f)
    q = arm_command(ctl, hand)
    qo = hand.qoff
    qn = (0...6).map ->(i) q[i] + qo[i]
    qc = hand.arm.solve(base, qn, [px, py, pz], n, 30, @pose_reg)
    sp = @bt_kspd
    qd = joint_rates(hand, base, qc, [sp * w[0], sp * w[1], sp * w[2]])
    fd = @bt_kfd
    qp = hand.arm.solve(base, qc, [px + fd * w[0], py + fd * w[1], pz + fd * w[2]], n, 20, @reg)
    g1 = (0...6).map ->(i) qc[i] - qo[i]
    g2 = (0...6).map ->(i) qp[i] - qo[i]
    kv = zeros
    i = 0
    while i < 6
      joint_offset(kv, hand.arm.joints[i], qd[i])
      i += 1
    kd = @bt_kdrv
    ch = @kch[side]
    ch[0].retime(dur)
    ch[0].pose(hand_pose(hand, g1, @push_stiff, @f_flick))
    ch[0].knot(kv, nil)
    ch[0].drive(rate_burst(hand, qd, kd))
    ch[1].pose(hand_pose(hand, g2, @push_stiff, @f_flick))
    ch[1].knot(zeros, nil)
    @kplan[side] = [f.t + c[0], px, py, pz]
    @ktouch[side] = false
    @kplanned[side] = true
    nil

  # Feed-forward burst for a planned knot: each arm joint's shortening muscle
  # gets its group's drive level (drive_sh, drive_el, drive_wr) scaled by the
  # joint rate the contact needs (full at 6 rad/s), times kd.
  -> rate_burst(hand, qd, kd)
    levels = [@drive_sh, @drive_sh, @drive_sh, @drive_el, @drive_wr, @drive_wr]
    drv = zeros
    i = 0
    while i < 6
      j = hand.arm.joints[i]
      k = body.pos_index(j)
      k = body.neg_index(j) if qd[i] < ~0.0
      drv[k] = kd * levels[i] * DribbleV3Math.clamp(qd[i].abs / ~6.0, ~0.0, ~1.0)
      i += 1
    drv

  # ---- the absorbing receive (bt_rplan) ------------------------------------------

  # The incoming ball where its rising centre reaches bt_rh (its apex if it
  # will not rise so far): [seconds from now, x, y, z, vx, vy, vz], or nil.
  -> receive_state(f)
    return nil if !f.has?("ball_rise")
    vz = f.at("ball_rise", 5)
    return nil if vz <= ~0.5
    disc = vz * vz - ~2.0 * @g * (@bt_rh - f.at("ball_rise", 2))
    s = vz / @g
    s = (vz - Math.sqrt(disc)) / @g if disc > ~0.0
    vx = f.at("ball_rise", 3)
    vy = f.at("ball_rise", 4)
    [f.at("ball_rise", 6) + s, f.at("ball_rise", 0) + vx * s, f.at("ball_rise", 1) + vy * s, f.at("ball_rise", 2) + vz * s - ~0.5 * @g * s * s, vx, vy, vz - @g * s]

  # The receive geometry for ball state c: [palm x, y, z, normal, d (the
  # ball's horizontal heading)]: the palm on the ball's leading side, bt_rb
  # above its equator and bt_rin inside its surface, facing it.
  -> receive_palm(c, hand)
    vx = c[4]
    vy = c[5]
    vh = Math.sqrt(vx * vx + vy * vy)
    if vh < ~0.3
      o = other_of(hand).home
      vx = hand.home[0] - o[0]
      vy = hand.home[1] - o[1]
      vh = Math.sqrt(vx * vx + vy * vy)
    dx = vx / vh
    dy = vy / vh
    b = @bt_rb
    lx = dx * Math.cos(b)
    ly_ = dy * Math.cos(b)
    lz = Math.sin(b)
    r = @radius - @bt_rin
    [c[1] + r * lx, c[2] + r * ly_, c[3] + r * lz, [~0.0 - lx, ~0.0 - ly_, ~0.0 - lz], [dx, dy]]

  # While the pass comes: the palm hovers bt_rpre ahead of the receive
  # point, facing the incoming ball.
  -> receive_hover(f, ctl, hand)
    return nil if f.get("ball_held") > ~0.5
    base = base_now(f)
    q = arm_command(ctl, hand)
    c = receive_state(f)
    if c != nil
      rp = receive_palm(c, hand)
      m = hand.arm.fk(base, arm_measured(f, hand))
      d = rp[4]
      tx = rp[0] + @bt_rpre * d[0]
      ty = rp[1] + @bt_rpre * d[1]
      tx = tx + @hand_fb * (tx - m[0])
      ty = ty + @hand_fb * (ty - m[1])
      qd = hand.arm.solve(base, q, [tx, ty, rp[2]], rp[3], 2, @meet_reg)
      hand.qoff = (0...6).map ->(i) qd[i] - q[i]
    off = zeros
    i = 0
    while i < 6
      joint_offset(off, hand.arm.joints[i], hand.qoff[i])
      i += 1
    off

  -> receive_ready?(f, ctl, hand)
    return false if f.at("ball_vel", 2) <= ~0.0
    c = receive_state(f)
    return false if c == nil
    return false if c[0] - @bt_rlead > @bt_rt1
    plan_receive(f, ctl, hand, c)
    true

  # Contraction rates of arm joint rates qd.
  -> knot_rates(hand, qd)
    kv = zeros
    i = 0
    while i < 6
      joint_offset(kv, hand.arm.joints[i], qd[i])
      i += 1
    kv

  # Plan the receive's four knots for the incoming ball state c: meet (at
  # bt_rmatch of its velocity), absorb (on with it to rest over bt_rt), push
  # (back toward the other spot at bt_rspd) and follow (to rest).
  -> plan_receive(f, ctl, hand, c)
    side = hand.side
    base = base_now(f)
    q = arm_command(ctl, hand)
    qo = hand.qoff
    qn = (0...6).map ->(i) q[i] + qo[i]
    rp = receive_palm(c, hand)
    d = rp[4]
    n1 = rp[3]
    mt = @bt_rmatch
    v1 = [mt * c[4], mt * c[5], mt * c[6]]
    q1 = hand.arm.solve(base, qn, [rp[0], rp[1], rp[2]], n1, 30, @pose_reg)
    qd1 = joint_rates(hand, base, q1, v1)
    tt = @bt_rt
    vh = Math.sqrt(c[4] * c[4] + c[5] * c[5])
    run = @bt_rabs * vh * tt * ~0.5
    dz = c[6] * tt - ~0.5 * @g * tt * tt
    p2 = [rp[0] + run * d[0], rp[1] + run * d[1], rp[2] + dz]
    q2 = hand.arm.solve(base, q1, p2, n1, 20, @reg)
    bx = p2[0] - @radius * n1[0]
    by = p2[1] - @radius * n1[1]
    ux = @target[0] - bx
    uy = @target[1] - by
    ul = Math.sqrt(ux * ux + uy * uy)
    ul = ~0.001 if ul < ~0.001
    ux = ux / ul
    uy = uy / ul
    n3 = tilted(ux, uy, @bt_rnt)
    w3 = tilted(ux, uy, @bt_rang)
    bz = p2[2] - @radius * n1[2]
    p3s = [bx - @radius * n3[0], by - @radius * n3[1], bz - @radius * n3[2]]
    pd = @bt_rpd
    p3 = [p3s[0] + pd * w3[0], p3s[1] + pd * w3[1], p3s[2] + pd * w3[2]]
    q3 = hand.arm.solve(base, q2, p3, n3, 20, @reg)
    sp = @bt_rspd
    qd3 = joint_rates(hand, base, q3, [sp * w3[0], sp * w3[1], sp * w3[2]])
    fd = @bt_kfd
    q4 = hand.arm.solve(base, q3, [p3[0] + fd * w3[0], p3[1] + fd * w3[1], p3[2] + fd * w3[2]], n3, 20, @reg)
    ch = @rch[side]
    g1 = (0...6).map ->(i) q1[i] - qo[i]
    g2 = (0...6).map ->(i) q2[i] - qo[i]
    g3 = (0...6).map ->(i) q3[i] - qo[i]
    g4 = (0...6).map ->(i) q4[i] - qo[i]
    ch[0].retime(DribbleV3Math.clamp(c[0] - @bt_rlead, ~0.03, @bt_rt1 + ~0.05))
    ch[0].pose(hand_pose(hand, g1, @push_stiff, @f_open))
    ch[0].knot(knot_rates(hand, qd1), nil)
    ch[1].retime(tt)
    ch[1].pose(hand_pose(hand, g2, @push_stiff, @f_open))
    ch[1].knot(zeros, nil)
    ch[2].pose(hand_pose(hand, g3, @push_stiff, @f_flick))
    ch[2].knot(knot_rates(hand, qd3), nil)
    ch[2].drive(rate_burst(hand, qd3, @bt_kdrv))
    ch[3].pose(hand_pose(hand, g4, @push_stiff, @f_flick))
    ch[3].knot(zeros, nil)
    @kplan[side] = [f.t + c[0], rp[0], rp[1], rp[2]]
    @ktouch[side] = false
    nil

  # After the recovery: to the contact knot if it was planned meanwhile.
  -> planned_next(hand)
    return "k_strike" if @kplanned[hand.side]
    "x_wait"

  # The push knot holds until the ball, touched, leaves the palm.
  -> k_released?(f, hand)
    return false if !@ktouch[hand.side]
    f.at("ball_touch", hand.touch_k) < @release_thr

  # Each tick of a planned stroke: the first touch closes the plan; its
  # lateness and the palm's miss (the arm model on the measured angles)
  # update that hand's learned lead and aim (bt_kilt, bt_kila).
  -> watch_contact(f, ctl, hand)
    side = hand.side
    return nil if @kplan[side] == nil || @ktouch[side]
    name = ctl.track(hand.name).chunk_name
    return nil if name != "k_strike" && name != "k_push" && !name.starts_with?("r_")
    return nil if f.at("ball_touch", hand.touch_k) < @touch_thr
    @ktouch[side] = true
    if name.starts_with?("r_")
      ctl.emit("ktouch:" + side + ":" + (f.t - @kplan[side][0]).to_s + ":0:0:0")
      return nil
    pl = @kplan[side]
    m = hand.arm.fk(base_now(f), arm_measured(f, hand))
    kl = @kil[side]
    et = f.t - pl[0]
    kl[0] = DribbleV3Math.clamp(kl[0] + @bt_kilt * et, ~-0.08, ~0.08)
    kl[1] = DribbleV3Math.clamp(kl[1] - @bt_kila * (m[0] - pl[1]), ~-0.1, ~0.1)
    kl[2] = DribbleV3Math.clamp(kl[2] - @bt_kila * (m[1] - pl[2]), ~-0.1, ~0.1)
    kl[3] = DribbleV3Math.clamp(kl[3] - @bt_kila * (m[2] - pl[3]), ~-0.1, ~0.1)
    ctl.emit("ktouch:" + side + ":" + et.to_s + ":" + (m[0] - pl[1]).to_s + ":" + (m[1] - pl[2]).to_s + ":" + (m[2] - pl[3]).to_s)
    nil

  # The pass stroke's swing latch (bt_latch).
  -> strike_now?(f, hand)
    return arrival(f, hand) < lead(hand) if @bt_latch < ~0.5
    vz = f.at("ball_vel", 2)
    return false if vz <= ~0.0
    return f.at("ball_pos", 2) > hand.zh - @radius + hand.dz - @bt_lz if @bt_latch < ~1.5
    vz < @bt_lvz && f.at("ball_pos", 2) > ~0.3

  -> lead(hand)
    return @br_lead if active?(hand) && @move == "D" && ychain?(hand) && @bt_dy > ~0.5
    if btl? && active?(hand) && @move == "B"
      return @bl_lead if hand.side == lead_side
      return @br_lead if ychain?(hand)
      return @bt_lead
    super(hand)

  -> move_law(hand)
    # (a caught ball's reset dribble, mode 8: the catch stroke's law, aimed
    # at the hand's own spot)
    if active?(hand) && @move == "D" && ychain?(hand) && @bt_dy > ~0.5
      return [@target[0], @target[1], @br_kv, @br_t, @br_tmax, @br_steer, ~0.0, ~1.0]
    if btl? && active?(hand) && @move == "B"
      return [@target[0], @target[1], @bl_kv, @bl_t, @bl_tmax, @bl_steer, ~0.0, ~1.0] if hand.side == lead_side
      return [@target[0], @target[1], @br_kv, @br_t, @br_tmax, @br_steer, ~0.0, ~1.0] if ychain?(hand)
      return [@target[0], @target[1], @bt_kv, @bt_t, @bt_tmax, @bt_steer, ~0.0, ~1.0]
    super(hand)

  # ---- the muscle program (pg_on) ------------------------------------------------

  # The programmed stroke of the pass about to be made (pass number @pass_no, 0 the launch), or -1.
  -> pg_ordinal
    return -1 if @pg_on < ~0.5
    p = @pass_no - @pg_first
    return -1 if p < 0 || p >= @pg_n
    if p >= @pg_stages
      return -1 if @pg_per < 1
      while p >= @pg_stages
        p = p - @pg_per
    p

  # Start the program for the receiving hand once the ball's predicted rising crossing of bt_rh is pg_lead away.
  -> pg_trigger(f, ctl)
    return nil if (@pass_no < 1 && @pg_first > 0) || @pg_state[@active.side] != nil || @pg_skip == @pass_no
    return nil if f.get("ball_held") > ~0.5
    o = pg_ordinal
    return nil if o < 0
    return nil if @move != "B"
    # (the sensors' prediction is not to be trusted while the ball is on the floor: its velocity ramps up)
    return nil if f.at("ball_pos", 2) < ~0.14
    c = receive_state(f)
    ctl.emit("dbg:pgc:" + (c == nil ? "nil" : c[0].to_s)) if @pg_dbg > ~0.5
    return nil if c == nil || c[0] > @pg_leads[o]
    if @pg_gvs[o] > ~0.0 && c[6] < @pg_gvs[o]
      @pg_skip = @pass_no
      return nil
    hand = @active
    ux = ~0.0
    uy = ~0.0
    if @pg_gs > ~0.5
      nm = @pg_nom[o]
      ux = DribbleV3Math.clamp((c[1] - nm[0]) / nm[2], ~-2.5, ~2.5)
      uy = DribbleV3Math.clamp((c[2] - nm[1]) / nm[3], ~-2.5, ~2.5)
    zs = []
    if @pg_gs > ~0.5 && @pg_nz > 0
      mus = @pg_mus[hand.side]
      zi = 0
      while zi < @pg_nz
        j = @pg_zj[zi]
        zq = f.c(mus[2 * j]) - f.c(mus[2 * j + 1])
        zp = @pg_zn[o][zi]
        zs.push(DribbleV3Math.clamp((zq - zp[0]) / zp[1], ~-2.5, ~2.5))
        zi += 1
    da = ~0.0
    if @pg_apx[o] != ~0.0 || @pg_apy[o] != ~0.0 || @pg_apt[o] != ~0.0
      da = f.at("ball_apex", 2) - @pg_ap0[o]
      ux = DribbleV3Math.clamp(ux + @pg_apx[o] * da, ~-2.5, ~2.5)
      uy = DribbleV3Math.clamp(uy + @pg_apy[o] * da, ~-2.5, ~2.5)
    if @pass_no - @pg_first >= @pg_gfrom
      far = ux.abs > @pg_gu || uy.abs > @pg_gu
      gi = 0
      while gi < zs.size
        far = true if zs[gi].abs > @pg_gz
        gi += 1
      if far
        @pg_skip = @pass_no
        return nil
    offs = nil
    offs = pg_offsets_init(o) if @pg_dt > ~0.5 || @pg_fk > ~0.0
    shift = ~0.0
    shift = @pg_leads[o] - @pg_acds[o] - c[0] if @pg_align > ~0.5
    shift = shift + @pg_apt[o] * da
    uvv = ~0.0
    if @pg_vn > ~0.5 && @pg_gs > ~0.5
      fv = c[6]
      if @pg_vsel[o] > ~0.5
        vzr = f.at("ball_rise", 5)
        fv = f.at("ball_rise", 2) + vzr * vzr / (~2.0 * @g)
      uvv = DribbleV3Math.clamp((@pg_vk[o] - fv) / @pg_vs[o], ~0.0, ~2.5)
      uvv = DribbleV3Math.clamp((fv - @pg_vk[o]) / @pg_vs[o], ~0.0, ~2.5) if @pg_vsel[o] > ~1.5
      shift = shift + @pg_vts[o] * uvv if @pg_vts[o] != ~0.0
    @pg_state[hand.side] = [f.t, o, false, false, ux, uy, zs, offs, 0, c[1], c[2], @pass_no - @pg_first, shift, uvv]
    ctl.emit("dbg:pgu:" + ux.to_s + ":" + uy.to_s + ":" + zs.join(":")) if @pg_dbg > ~0.5
    ctl.track(hand.name).jump(ctl, f, "g_run")
    nil

  # Each tick of a running program: its activations as drive, the release hands the ball over.
  -> pg_step(f, ctl, hand)
    st = @pg_state[hand.side]
    return nil if st == nil
    tt = f.t - st[0]
    te = tt + st[12]
    tab = @pg_tab[st[1]]
    nk = @pg_nk
    x = te / @pg_dk
    x = ~0.0 if x < ~0.0
    if x >= (nk - 1) * ~1.0
      @pg_state[hand.side] = nil
      return nil
    i = x.floor
    w = x - i * ~1.0
    mus = @pg_mus[hand.side]
    pg_decide(f, st, mus, te) if @pg_fk > ~0.0 && st[8] < @pg_fq && te >= @pg_fd[st[8]] - ~0.0025
    m = 0
    while m < 16
      row = tab[m]
      v = row[i] + (row[i + 1] - row[i]) * w
      if @pg_gs > ~0.5
        # (the table's knot values T0 + ux Tx + uy Ty are formed and bounded at the knots, then interpolated)
        rx = @pg_tx[st[1]][m]
        ry = @pg_ty[st[1]][m]
        gm = @pg_gmax
        a0 = row[i] + st[4] * DribbleV3Math.clamp(rx[i], ~0.0 - gm, gm) + st[5] * DribbleV3Math.clamp(ry[i], ~0.0 - gm, gm)
        a1 = row[i + 1] + st[4] * DribbleV3Math.clamp(rx[i + 1], ~0.0 - gm, gm) + st[5] * DribbleV3Math.clamp(ry[i + 1], ~0.0 - gm, gm)
        zi = 0
        while zi < @pg_nz
          rzz = @pg_tz[st[1]][zi][m]
          a0 = a0 + st[6][zi] * DribbleV3Math.clamp(rzz[i], ~0.0 - gm, gm)
          a1 = a1 + st[6][zi] * DribbleV3Math.clamp(rzz[i + 1], ~0.0 - gm, gm)
          zi += 1
        if @pg_vn > ~0.5 && st[13] > ~0.0
          rv = @pg_tv[st[1]][m]
          a0 = a0 + st[13] * DribbleV3Math.clamp(rv[i], ~0.0 - gm, gm)
          a1 = a1 + st[13] * DribbleV3Math.clamp(rv[i + 1], ~0.0 - gm, gm)
        a0 = DribbleV3Math.clamp(a0, ~0.0, ~1.0)
        a1 = DribbleV3Math.clamp(a1, ~0.0, ~1.0)
        v = a0 + (a1 - a0) * w
      v = v + pg_offset(st, m, te) if st[7] != nil
      ctl.add_drive(mus[m], v)
      m += 1
    k = hand.touch_k
    fk = f.at("ball_touch", k)
    st[2] = true if fk >= @touch_thr
    if st[2] && !st[3] && fk < @release_thr && tt > @push_min
      st[3] = true
      handoff_prog(f, ctl, hand)
    nil

  # The additive offset (pg_dt) of arm muscle m at time tt of the running program: the stage's offset table, linear between knots
  # pg_dtk apart, falling to zero after the last knot.
  -> pg_offset(st, m, tt)
    x = tt / @pg_dtk
    i = x.floor
    return ~0.0 if i >= @pg_dtn
    a = st[7][m]
    w = x - i * ~1.0
    return a[i] * (~1.0 - w) if i + 1 >= @pg_dtn
    a[i] * (~1.0 - w) + a[i + 1] * w

  # A fresh offset table for a starting stage: the static pgdt table's values (pg_dt) or zeros.
  -> pg_offsets_init(o)
    rows = []
    m = 0
    while m < 16
      row = []
      k = 0
      while k < @pg_dtn
        v = ~0.0
        v = @pg_dtt[o][m][k] if @pg_dt > ~0.5
        row.push(v)
        k += 1
      rows.push(row)
      m += 1
    rows

  # One decision of the feedback: the predicted outcome error from the live features, cancelled through the stage's offset table.
  -> pg_decide(f, st, mus, tt)
    q = st[8]
    o = st[1]
    x = [st[9], st[10]]
    j = 0
    while j < 8
      x.push(f.c(mus[2 * j]) - f.c(mus[2 * j + 1]))
      j += 1
    j = 0
    while j < 8
      x.push(f.cdot(mus[2 * j]) - f.cdot(mus[2 * j + 1]))
      j += 1
    yh = []
    i = 0
    while i < 3
      wv = @pg_fw[o][q][i]
      e = @pg_fa[o][q][i] - @pg_ft[o][i]
      k = 0
      while k < 18
        e = e + wv[k] * x[k]
        k += 1
      yh.push(e)
      i += 1
    g = @pg_fg[o][q]
    offs = st[7]
    m = 0
    while m < 16
      k = 0
      while k < @pg_dtn
        d = g[m][k]
        offs[m][k] = offs[m][k] - @pg_fk * (d[0] * yh[0] + d[1] * yh[1] + d[2] * yh[2])
        k += 1
      m += 1
    st[8] = q + 1
    nil

  # The release of a programmed pass: the other hand starts its receiving (as `handoff`, the hand itself carries on
  # with the program's follow-through).
  -> handoff_prog(f, ctl, hand)
    hand.fresh = false
    other = other_of(hand)
    @pass_no = @pass_no + 1
    @rel_t = f.t
    @active = other
    other.ix = ~0.0
    other.iy = ~0.0
    other.aim = nil
    other.fresh = true
    choose(f, ctl, other)
    ctl.track(other.name).jump(ctl, f, entry_for(other))
    nil

  # The nominal contraction of arm muscle m at knot i of the running stage's program, for this start's features (the table's own
  # structure: N0 + ux Nx + uy Ny + sum_k z_k Nz_k).
  -> pg_nominal(st, m, i)
    o = st[1]
    v = @pg_nt[o][m][i] + st[4] * @pg_nx[o][m][i] + st[5] * @pg_ny[o][m][i]
    zi = 0
    while zi < @pg_nz
      v = v + st[6][zi] * @pg_nzt[o][zi][m][i]
      zi += 1
    v

  # The servo around the table (pg_fb > 0), after the tracks of every tick: while the hand's program runs (between pg_fbt0 and pg_fbt1
  # of its time, ramped), its 16 arm muscles take the nominal contractions as targets and the servo gain, so a deviation from the
  # nominal stroke is pulled back by the stretch reflex while the table stays the drive; the damping is about the nominal's own rate.
  -> pg_servo(f, ctl, hand)
    st = @pg_state[hand.side]
    if st == nil
      pg_vref(ctl, hand, false)
      return nil
    tt = f.t - st[0] + st[12]
    ramp = DribbleV3Math.clamp((tt - @pg_fbt0) / @pg_fbr, ~0.0, ~1.0) * DribbleV3Math.clamp((@pg_fbt1 - tt) / @pg_fbr, ~0.0, ~1.0)
    pg_vref(ctl, hand, true)
    x = tt / @pg_dk
    x = ~0.0 if x < ~0.0
    i = x.floor
    w = x - i * ~1.0
    mus = @pg_mus[hand.side]
    cmd = ctl.command
    late = DribbleV3Math.clamp((tt - @pg_fbtl) / @pg_fbr, ~0.0, ~1.0)
    gs = @pg_fb * ramp * @pg_fbs[st[1]] * (~1.0 + (@pg_fbm - ~1.0) * late)
    j = 0
    while j < 8
      g = gs * @pg_fbw[j]
      s = 0
      while s < 2
        m = 2 * j + s
        c0 = pg_nominal(st, m, i)
        c1 = pg_nominal(st, m, i + 1)
        cmd[mus[m]] = c0 + (c1 - c0) * w
        ctl.set_gain(mus[m], g)
        s += 1
      j += 1
    nil

  # The velocity reference (damping about the commanded rate) of the stroking arm, switched only when it changes.
  -> pg_vref(ctl, hand, running)
    return nil if @pg_fbv <= ~0.0 || running == @pg_vref[hand.side]
    @pg_vref[hand.side] = running
    ctl.reflex.set_velocity_reference(@arm_mask[hand.side], running ? @pg_fbv : ~0.0)
    nil

  -> after(frame, ctl)
    if btl? && @pg_on > ~0.5 && @pg_fb > ~0.0
      pg_servo(frame, ctl, @right)
      pg_servo(frame, ctl, @left)
    cock_off(frame, ctl) if btl? && @pg_on > ~0.5 && (@bl_cksf != ~0.0 || @bl_cksa != ~0.0 || @bl_cksr != ~0.0 || @bl_ckel != ~0.0 || @bl_ckwf != ~0.0 || @bl_ckwd != ~0.0)
    leg_static(frame, ctl) if btl? && (@ls_hip != ~0.0 || @ls_abd != ~0.0 || @ls_knee != ~0.0)
    leg_clear2(frame, ctl) if btl? && (@l2_hip != ~0.0 || @l2_abd != ~0.0 || @l2_knee != ~0.0)
    leg_clear(frame, ctl) if btl? && (@ll_hip != ~0.0 || @ll_knee != ~0.0 || @ll_abd != ~0.0 || @ll_rot != ~0.0 || @lb_hip1 != ~0.0 || @lb_abd1 != ~0.0 || @lb_knee1 != ~0.0 || @lt_rot != ~0.0 || @lt_flex != ~0.0 || @lt_lat != ~0.0 || @lb_hip != ~0.0 || @lb_abd != ~0.0 || @lb_knee != ~0.0 || @ll_two > ~0.5)
    super(frame, ctl)

  # (cock) The lead leg's hand's joint offsets through the recovery, the wait and the start of the swing of a reflex stroke after the tables.
  -> cock_off(f, ctl)
    return nil if @pass_no < @pg_first + @pg_n || @rel_t < ~0.0
    hand = @left
    hand = @right if lead_side == "r"
    return nil if !active?(hand) || @move != "B"
    nm = ctl.track(hand.name).chunk_name
    w = ~0.0
    if nm == "x_recover" || nm == "x_wait"
      w = DribbleV3Math.clamp((f.t - @rel_t) / @bl_ckr, ~0.0, ~1.0)
      @ck_sw = ~-1.0
    elsif nm == "x_swing" && @bl_ckf > ~0.0
      @ck_sw = f.t if @ck_sw < ~0.0
      w = DribbleV3Math.clamp(~1.0 - (f.t - @ck_sw) / @bl_ckf, ~0.0, ~1.0)
    return nil if w <= ~0.0
    side = hand.side
    off = zeros
    joint_offset(off, side + "_shoulder_flex", @bl_cksf * w)
    joint_offset(off, side + "_shoulder_abd", @bl_cksa * w)
    joint_offset(off, side + "_shoulder_rot", @bl_cksr * w)
    joint_offset(off, side + "_elbow", @bl_ckel * w)
    joint_offset(off, side + "_wrist_flex", @bl_ckwf * w)
    joint_offset(off, side + "_wrist_dev", @bl_ckwd * w)
    i = 0
    while i < off.size
      ctl.add_offset(i, off[i]) if off[i] != ~0.0
      i += 1
    nil

  # (static lead leg offset) from the start: the lead leg's hip / abduction / knee shifted for the whole run.
  -> leg_static(f, ctl)
    w = DribbleV3Math.clamp(f.t / @ls_ramp, ~0.0, ~1.0)
    off = zeros
    joint_offset(off, lead_side + "_hip_flex", @ls_hip * w)
    joint_offset(off, lead_side + "_hip_abd", @ls_abd * w)
    joint_offset(off, lead_side + "_knee", @ls_knee * w)
    i = 0
    while i < off.size
      ctl.add_offset(i, off[i]) if off[i] != ~0.0
      i += 1
    nil

  # (leg clearance 2) The lead leg's offsets in the window after the release of pass l2_pass.
  -> leg_clear2(f, ctl)
    return nil if @rel_t < ~0.0 || @pass_no != @l2_pass
    tt = f.t - @rel_t - @l2_t0
    return nil if tt < ~0.0 || tt > @l2_win
    w = DribbleV3Math.clamp(tt / @l2_ramp, ~0.0, ~1.0) * DribbleV3Math.clamp((@l2_win - tt) / @l2_ramp, ~0.0, ~1.0)
    off = zeros
    joint_offset(off, lead_side + "_hip_flex", @l2_hip * w)
    joint_offset(off, lead_side + "_hip_abd", @l2_abd * w)
    joint_offset(off, lead_side + "_knee", @l2_knee * w)
    i = 0
    while i < off.size
      ctl.add_offset(i, off[i]) if off[i] != ~0.0
      i += 1
    nil

  # (leg clearance) The lead leg's hip and knee offsets in the window after the release of the passes ll_from ...
  -> leg_clear(f, ctl)
    return nil if @rel_t < ~0.0
    p = @pass_no - @ll_from
    return nil if p < 0 || p >= @ll_n
    tt = f.t - @rel_t - @ll_t0
    return nil if tt < ~0.0 || tt > @ll_win
    w = DribbleV3Math.clamp(tt / @ll_ramp, ~0.0, ~1.0) * DribbleV3Math.clamp((@ll_win - tt) / @ll_ramp, ~0.0, ~1.0)
    off = zeros
    bs = "l"
    bs = "r" if lead_side == "l"
    hh = @ll_hip
    ha = @ll_abd
    hk = @ll_knee
    hr = @ll_rot
    if @ll_two > ~0.5 && p >= 1
      hh = @ll_hip1
      ha = @ll_abd1
      hk = @ll_knee1
      hr = @ll_rot1
    joint_offset(off, "spine_rot", @lt_rot * w)
    joint_offset(off, "spine_flex", @lt_flex * w)
    joint_offset(off, "spine_lat", @lt_lat * w)
    joint_offset(off, lead_side + "_hip_flex", hh * w)
    joint_offset(off, lead_side + "_hip_abd", ha * w)
    joint_offset(off, lead_side + "_hip_rot", hr * w)
    joint_offset(off, lead_side + "_knee", hk * w)
    bh = @lb_hip
    ba = @lb_abd
    bk = @lb_knee
    if @ll_two > ~0.5 && p >= 1
      bh = @lb_hip1
      ba = @lb_abd1
      bk = @lb_knee1
    joint_offset(off, bs + "_hip_flex", bh * w)
    joint_offset(off, bs + "_hip_abd", ba * w)
    joint_offset(off, bs + "_knee", bk * w)
    i = 0
    while i < off.size
      ctl.add_offset(i, off[i]) if off[i] != ~0.0
      i += 1
    nil

  # ILC: as the ball rises through the receiving hand's strike height after a
  # pass, the miss against the spot it was sent to corrects the sender's next
  # aim (per hand).
  -> before(frame, ctl)
    @ctl_now = ctl
    if btl? && @pg_on > ~0.5
      pg_trigger(frame, ctl)
      pg_step(frame, ctl, @right)
      pg_step(frame, ctl, @left)
    super(frame, ctl)
    if btl? && @bt_vref > ~0.0
      [@right, @left].each ->(hand)
        nm = ctl.track(hand.name).chunk_name
        w = ~0.0
        w = @bt_vref if nm.starts_with?("k_") || nm.starts_with?("r_m") || nm.starts_with?("r_a") || nm.starts_with?("r_p") || nm.starts_with?("r_f")
        ctl.reflex.set_velocity_reference(@arm_mask[hand.side], w)
    if btl? && @bt_plan > ~0.5
      watch_contact(frame, ctl, @right)
      watch_contact(frame, ctl, @left)
    return nil if !btl? || @bt_ilc <= ~0.0 || @sent == nil
    return nil if frame.at("ball_vel", 2) <= ~0.0
    zc = @active.zh - @radius + @active.dz
    return nil if frame.at("ball_pos", 2) < zc
    s = @sent
    @sent = nil
    return nil if s[0] == @active.side
    off = @ilc[s[0]]
    ex = frame.at("ball_pos", 0) - s[1]
    ey = frame.at("ball_pos", 1) - s[2]
    m = @bt_ilc_max
    @ilc[s[0]] = [DribbleV3Math.clamp(off[0] - @bt_ilc * ex, ~0.0 - m, m), DribbleV3Math.clamp(off[1] - @bt_ilc * ey, ~0.0 - m, m)]
    nil
