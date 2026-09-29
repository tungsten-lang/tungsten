# Bat: a left-handed batter's swing on the pivot body.
#
# The right (bottom) hand closes around the bat for good; the left (top)
# hand holds the handle through a grip the skill opens with `grip:l:0` and
# closes with `grip:l:1`. Three tracks run on disjoint muscle masks so the
# swing is a kinetic chain, each segment firing a little after the one
# below it:
#
#   hips   pelvis shift (toward the mound), pelvis yaw and legs (with the
#          toes and biarticular leg muscles on the human-calibrated body)
#   torso  spine
#   arms   shoulders, elbows and wrists (one track: both hands are on the
#          bat, so the arms and wrists form one closed loop and move through
#          grip-consistent postures together)
#
# Every track runs the same chunk sequence (the arms track adds the regrip):
#
#   lift     bat out over the plate -> up to the back shoulder
#   set      stance, bat cocked; `ready` asks the pitcher to deliver
#   ready    hold, LATCHED on the pitcher's delivery (the pitch_windup
#            sensor) reaching `lift_at` s
#   leglift  front knee up, hips and shoulders coil back, weight back;
#            LATCHED on the delivery reaching `stride_at` s (or the release)
#   stride   the front foot reaches toward the mound, toe down, while the
#            pelvis shifts forward (timed, with a push on the shift muscles)
#   plant    toe first, then the foot flattens; LATCHED on front-foot
#            contact
#   load     landed, hands back; hold LATCHED on the predicted time-to-plate
#            falling to the track's trigger (hips first, then torso, then
#            arms: the kinetic chain). While the hips open the torso holds
#            the shoulders closed (a proprioceptive correction on pelvis yaw):
#            hip-shoulder separation, released when the torso fires.
#   swing    trunk: a fast ease past the contact posture with a feed-forward
#            burst on the muscles the swing shortens and the stretch
#            reflexes turned down (a ballistic movement). Arms: into the
#            slot (bat flat and lagging, wrists cocked), then
#   whip     (arms) through the mid waypoint and the release (barrel coming
#   release  round below the hands on the swing plane, wrists uncocking),
#   drive    (arms) and on up through contact, on plane with the pitch
#   follow   the trunk keeps turning through the ball; (arms) LATCHED on the
#            bat coming round to point back at the pitcher (knob -> tip)
#   let_go   `grip:l:0`: the top hand lets go, the bottom arm carries the bat
#            up and around over the lead shoulder
#   finish   hold the one-handed finish
#   recover  bring the bat back out over the plate; LATCHED on the top hand
#            feeling the handle again (grip_l)
#   regrip   (arms) steer the top hand onto the handle: an integrating
#            hand-space servo on the grip_err sensor, LATCHED on it closing
#            within 3 cm, then
#   close    (arms) `grip:l:1`; everyone loops back to `set`
#
# `prop 1` latches the chain's handoffs on proprioception: the torso fires
# when the pelvis has turned `turn_torso` rad since the hips fired and its
# turning rate has dropped below `pk_torso` of its peak (below 1: the
# proximal segment decelerating), the arms likewise on the torso's turn and
# rate (`turn_arms`, `pk_arms`),
# and the whip holds until the hands have passed `hands_front` m in front of
# the pelvis before the wrists uncock (the wrist muscles `wrist_delay` s
# late, a per-group stagger); each still fires on its time lag +0.12 s if
# the sensation never comes.
#
# `flow 1` (the default) makes the swing one motion. The load is a via chunk
# (TimedChunk) whose duration is kept, until it starts, at the predicted time
# until the track's swing is due, so it never eases in and holds: the
# command makes a small counter-movement (the Catmull-Rom tangent at its end
# already points at the swing's goal) and is moving toward the swing when
# the swing begins. load -> swing (trunk) and load -> slot -> whip ->
# release -> drive (arms) are via chunks, one velocity-continuous cubic
# spline through those keyframes, and the follow inherits its velocity and
# eases to rest. The upper body starts aiming during the stride (the pitch
# is released then) on the pre-swing spring `spring_pre`, and `step_delay`
# moves the whole step later on the delivery (its shape unchanged) so the
# plant lands about 0.1 s before the swing. Under `prop`, the torso and arms
# may still fire early on proprioception (the latch cuts the via chunk and
# the swing inherits its velocity), at the latest on their time lag, and the
# whip's hands-front latch can only cut it short. `flow 0` is the ease-then-
# hold load with per-chunk easings of the params practised before
# 2026-09-26 (they set it).
#
# The follow-through has three more ingredients (params `through`,
# `trunk_through`, `gain_ease`; see read_params). Without them the follow
# eased to rest at the extension, the arms then held still until the bat
# came round before the top hand let go, the trunk's plan ended just past
# contact (a swing goal far past it, then back), and the stiff standing
# gains came back as the follow began: a stop between contact and the
# finish that also cost bat speed. With them the motion runs on through
# the extension into the finish, the top hand lets go on the way, and the
# gains ease back over the let_go.
#
# v5 (2026-09-27, each opt-in; the arena's bat_flow measures the motion as
# SEEN, the measured contraction speed from the leg lift to the finish):
#   lift_via     the leg lift is a via keyframe timed (on the delivery clock)
#                to end when the stride is due: no hold at the top
#   stride_load  the hands load back and the front shoulder closes DURING the
#                stride (`gather` of the way to q_gather), while the stride
#                goes forward
#   plant_via    stride -> plant -> load is one via chain, the plant a
#                `dur_plant` keyframe: the foot lands without a slam or a stop
#   hip_open     the hips' load, from the plant (latched on the front foot's
#                contact) until their timed swing, opens `hip_open` of the
#                hip turn: the hips begin turning as the foot lands and are
#                moving when they fire (the shoulders held closed by the
#                torso's separation)
#   plant_swing  the hips' swing starts on the front foot's plant (latched on
#                its contact; at the latest the plant's duration) and turns
#                until `hips_end` s before the pitch reaches the plate:
#                plant -> hip turn -> torso -> arms, no settle
#   knot         contact is a PLANNED keyframe: the arms' drive and the
#                torso's swing end at the contact posture with a prescribed
#                velocity (the sweet spot moving along the swing plane at
#                `con_speed` m/s, `u_contact` solved offline, zero
#                acceleration: a quintic knot), and each track's swing starts
#                when the predicted time to the plate equals its planned
#                duration plus `con_lead`: the plan runs backward from
#                contact (the hips `hips_lead` s before the first of them)
#   arc          the follow-through is one quintic arc from the contact knot
#                to the finish (q_wrap: no joint turns back on the way) over
#                `dur_arc` (no extension keyframe to slow at, no let_go
#                chunk), hips and trunk turning on to the finish; the top
#                hand lets go as an event when the bat comes round (at the
#                latest `rel_frac` of the way) and the gains ease back over
#                the arc
#   (knot: `con_trunk` and `con_wrist` scale the trunk's and the wrists'
#   share of the contact velocity; `limit_brake`: in the follow-through a
#   joint running into the end of its range is braked by its antagonist
#   before it gets there, instead of stopping on the limit)
#
# `stride 0` skips the leg lift and stride (the ready chunk then latches on
# the pitch release, as in the first version); `uppercut 0` swings through
# the first version's level waypoints instead of the on-plane ones.
#
# Real-time correction. `before` predicts where the pitch will cross the
# front of the plate (gravity plus quadratic drag, closed form), how long
# until it does, and its vertical approach angle there. From the release
# until `t_lock` seconds before it arrives (the batter's visuomotor delay)
# the predicted miss of the designed swing, in height (dz) and in/out (dx),
# is turned into joint offsets through sensitivity vectors solved offline
# around the contact posture (the joint change that moves the bat's sweet
# spot 1 m up, or 1 m out, with the top hand still on the handle), and the
# swing plane is tilted to meet the pitch's approach: attack angle =
# `att_bias` - approach angle, applied through per-waypoint tilt vectors
# (the joint change per radian of attack angle that keeps contact where it
# is). The offsets go through each chunk's critically damped spring, so the
# swing bends toward the ball instead of stepping. The in/out error also
# shifts the swing trigger: an inside pitch is met earlier, an outside one
# later.

# Posture tables (radians; pelvis_shift in metres toward the mound). Upper
# body (`joints`) and legs (`leg_joints`) are solved separately offline by
# inverse kinematics on the task's MJCF: upper-body postures keep the top
# hand on the handle wherever both hands hold the bat (grip closure does not
# depend on the trunk, so a posture's arms can ride any trunk); leg postures
# put the feet where the stance, lift, stride and swing need them. The `_u`
# postures are the on-plane uppercut: the bat rotating about a swing plane
# tilted 32 deg from horizontal through a contact point at (0.80, -0.70,
# 0.82) with the bat 30 deg below horizontal and the head rising at 10 deg.
+ BatPostures
  -> .joints
    ["pelvis_yaw", "spine_flex", "spine_lat", "spine_rot", "l_shoulder_flex", "l_shoulder_abd", "l_shoulder_rot", "l_elbow", "l_wrist_flex", "l_wrist_dev", "r_shoulder_flex", "r_shoulder_abd", "r_shoulder_rot", "r_elbow", "r_wrist_flex", "r_wrist_dev"]

  -> .leg_joints
    ["pelvis_shift", "l_hip_flex", "l_hip_abd", "l_hip_rot", "l_knee", "l_ankle", "r_hip_flex", "r_hip_abd", "r_hip_rot", "r_knee", "r_ankle"]

  -> .q_set
    [~0.050, ~0.200, ~0.000, ~0.300, ~-0.082, ~-0.184, ~0.559, ~2.106, ~-0.460, ~-0.127, ~-0.473, ~-0.642, ~0.290, ~1.979, ~-0.693, ~-0.200]

  -> .q_load
    [~0.200, ~0.200, ~0.050, ~0.500, ~-0.082, ~-0.184, ~0.559, ~2.106, ~-0.460, ~-0.127, ~-0.473, ~-0.642, ~0.290, ~1.979, ~-0.693, ~-0.200]

  -> .q_coil
    [~0.200, ~0.200, ~0.050, ~0.550, ~-0.082, ~-0.184, ~0.559, ~2.106, ~-0.460, ~-0.127, ~-0.473, ~-0.642, ~0.290, ~1.979, ~-0.693, ~-0.200]

  -> .q_slot
    [~-0.350, ~0.200, ~-0.100, ~0.100, ~0.128, ~-0.176, ~0.145, ~1.372, ~-0.325, ~-0.033, ~0.265, ~-0.167, ~0.414, ~1.114, ~-0.509, ~0.000]

  -> .q_release
    [~-0.625, ~0.200, ~-0.175, ~-0.150, ~0.487, ~-0.489, ~-0.556, ~1.061, ~-0.528, ~0.342, ~0.362, ~-0.481, ~0.150, ~0.871, ~-0.161, ~0.324]

  -> .q_contact
    [~-0.900, ~0.200, ~-0.250, ~-0.400, ~0.884, ~-0.497, ~-1.380, ~0.796, ~-0.721, ~0.730, ~0.422, ~-0.683, ~-0.172, ~0.732, ~0.146, ~0.642]

  -> .q_extend
    [~-1.150, ~0.150, ~-0.200, ~-0.700, ~0.884, ~-0.497, ~-1.380, ~0.796, ~-0.721, ~0.730, ~0.422, ~-0.683, ~-0.172, ~0.732, ~0.146, ~0.642]

  -> .q_finish
    [~-1.150, ~0.050, ~0.100, ~-0.750, ~0.600, ~0.300, ~0.000, ~0.800, ~0.000, ~0.000, ~2.300, ~0.200, ~-1.000, ~1.200, ~0.000, ~-0.200]

  -> .q_recover
    [~0.000, ~0.150, ~0.000, ~0.100, ~0.112, ~-0.474, ~0.170, ~1.119, ~0.804, ~0.578, ~-0.099, ~-0.623, ~-0.217, ~1.058, ~-0.966, ~0.730]

  -> .q_mid_u
    [~-0.535, ~-0.048, ~-0.288, ~-0.093, ~0.407, ~-0.568, ~-0.564, ~1.021, ~-0.526, ~0.346, ~0.385, ~-0.204, ~0.389, ~0.938, ~-0.091, ~0.004]

  -> .q_release_u
    [~-0.720, ~-0.297, ~-0.476, ~-0.286, ~0.785, ~-0.615, ~-1.380, ~0.716, ~-0.711, ~0.730, ~0.407, ~-0.183, ~0.375, ~0.862, ~0.296, ~-0.065]

  -> .q_contact_u
    [~-0.900, ~0.182, ~-0.401, ~-0.540, ~1.154, ~-0.495, ~-1.272, ~0.719, ~-0.687, ~0.687, ~0.844, ~-0.444, ~0.165, ~0.718, ~0.430, ~0.355]

  -> .q_extend_u
    [~-1.100, ~0.565, ~-0.312, ~-0.756, ~1.669, ~-0.475, ~-1.096, ~0.669, ~-0.633, ~0.602, ~1.346, ~-0.568, ~-0.010, ~0.768, ~0.294, ~0.717]

  # v5 stride_load: the stride's load, solved from q_coil: the front shoulder
  # closed further (pelvis 0.25, spine rotation 0.68) and the top hand 8 cm
  # back toward the catcher and 3 cm up, the bat's angle kept, grip closed.
  -> .q_gather
    [~0.250, ~0.200, ~0.050, ~0.680, ~0.153, ~-0.230, ~0.418, ~2.003, ~-0.417, ~-0.092, ~-0.248, ~-0.608, ~0.380, ~1.998, ~-0.109, ~0.142]

  # v5 knot: joint velocity (rad per metre of sweet-spot travel) at the
  # uppercut contact as the bat turns in the swing plane (the plane's
  # rotation, R = 1 m: m/s = rad/s), top hand on the handle; IK at +-4 deg
  # of bat rotation about the plane normal (over `joints`).
  -> .u_contact
    [~-0.336, ~0.797, ~0.054, ~-0.299, ~0.822, ~0.031, ~0.315, ~-0.050, ~0.048, ~-0.109, ~0.693, ~-0.195, ~-0.279, ~0.178, ~-0.351, ~0.599]

  # v5 arc: the follow-through's finish. q_finish, except that the joints
  # the swing moves one way to the extension and q_finish would bring back
  # (spine flexion, the lead shoulder's flexion, the lead elbow, the rear
  # shoulder's abduction and wrist deviation) stay at their extension
  # values: no joint reverses on the way from contact, so the arc can carry
  # the contact speed down to rest without slowing, turning and speeding up
  # again (the extension is only 35 deg of bat turn past contact). The
  # pelvis and the bottom wrist's deviation stop short of their limits
  # (-1.2 rad yaw, 0.75 rad ulnar), which they would otherwise hit and
  # stop on.
  -> .q_wrap
    [~-1.080, ~0.565, ~0.100, ~-0.750, ~1.669, ~0.300, ~0.000, ~0.669, ~0.000, ~0.000, ~2.300, ~-0.568, ~-1.000, ~1.200, ~0.000, ~0.550]

  -> .legs_stance
    [~0.000, ~0.547, ~0.289, ~-0.142, ~0.930, ~-0.346, ~0.512, ~0.295, ~-0.124, ~0.927, ~-0.376]

  -> .legs_lift
    [~0.000, ~0.593, ~0.263, ~-0.143, ~0.927, ~-0.309, ~1.096, ~-0.179, ~0.391, ~1.912, ~0.450]

  -> .legs_stride
    [~0.180, ~0.481, ~0.566, ~-0.580, ~0.658, ~0.036, ~0.879, ~0.553, ~0.100, ~1.310, ~0.300]

  -> .legs_landed
    [~0.180, ~0.481, ~0.566, ~-0.580, ~0.658, ~0.036, ~0.407, ~0.561, ~-0.507, ~0.756, ~-0.132]

  -> .legs_swing
    [~0.200, ~0.161, ~0.289, ~0.198, ~1.055, ~0.450, ~0.691, ~-0.095, ~0.424, ~0.615, ~0.015]

  -> .legs_swing0
    [~0.000, ~0.509, ~0.119, ~0.187, ~1.361, ~0.450, ~0.706, ~-0.001, ~0.001, ~0.860, ~-0.180]

  -> .k_joints
    ["spine_flex", "spine_lat", "spine_rot", "l_shoulder_flex", "l_shoulder_abd", "l_shoulder_rot", "l_elbow", "l_wrist_flex", "l_wrist_dev", "r_shoulder_flex", "r_shoulder_abd", "r_shoulder_rot", "r_elbow", "r_wrist_flex", "r_wrist_dev"]

  -> .k_z
    [~-1.074, ~0.320, ~-0.183, ~-0.289, ~-0.037, ~-0.070, ~-0.017, ~-0.005, ~0.017, ~-0.409, ~0.178, ~0.129, ~0.096, ~0.111, ~-0.549]

  -> .k_x
    [~1.233, ~-0.393, ~0.991, ~1.545, ~-0.076, ~0.356, ~0.625, ~-0.168, ~-0.052, ~1.730, ~-0.614, ~-0.348, ~-0.042, ~-0.696, ~0.756]

  -> .k_z_u
    [~-0.885, ~0.301, ~-0.170, ~-0.008, ~-0.097, ~0.001, ~0.060, ~-0.031, ~0.020, ~-0.030, ~0.142, ~-0.024, ~0.100, ~0.046, ~-0.555]

  -> .k_x_u
    [~0.859, ~-0.325, ~0.854, ~0.845, ~0.046, ~0.336, ~0.280, ~-0.060, ~-0.063, ~0.491, ~-0.651, ~-0.772, ~0.246, ~-0.836, ~1.166]

  -> .k_att_release
    [~0.000, ~0.186, ~-0.200, ~-0.125, ~-0.219, ~0.001, ~-0.061, ~-0.120, ~0.031, ~0.000, ~-0.169, ~0.159, ~0.178, ~0.011, ~0.060, ~-0.097]

  -> .k_att_contact
    [~0.000, ~0.000, ~0.000, ~0.000, ~0.000, ~0.000, ~0.000, ~0.000, ~0.000, ~0.000, ~0.000, ~0.000, ~0.000, ~0.000, ~0.000, ~0.000]

  -> .k_att_extend
    [~0.000, ~-0.125, ~-0.004, ~0.138, ~0.198, ~-0.034, ~0.070, ~0.036, ~-0.007, ~-0.017, ~0.138, ~-0.022, ~-0.092, ~0.096, ~-0.150, ~0.000]

  # Regrip servo: left-arm joint change per metre of hand displacement in
  # world axes (6 x 3, row-major), the damped pseudo-inverse of the top
  # hand's Jacobian at the regrip posture.
  -> .regrip_joints
    ["l_shoulder_flex", "l_shoulder_abd", "l_shoulder_rot", "l_elbow", "l_wrist_flex", "l_wrist_dev"]

  -> .regrip_pinv
    [~3.463, ~-0.609, ~-1.911, ~0.398, ~1.412, ~-0.955, ~-0.305, ~-0.763, ~0.573, ~-2.960, ~2.256, ~5.023, ~-0.680, ~0.209, ~0.599, ~-0.853, ~0.656, ~1.087]

# A chunk whose duration the skill sets at run time (`flow`'s load: timed to
# end when the swing is due, from the pitch's predicted time to the plate).
# It never holds past its duration: the duration is also its latch timeout,
# so a via load always hands its velocity on instead of stopping.
+ TimedChunk < Chunk
  -> retime(seconds)
    @duration = seconds
    self

  -> timeout
    @duration

+ BatSkill < Skill
  -> start(frame, ctl)
    read_params
    @timed = []
    @lifts = []
    @hip_swings = []
    @plate_x = frame.at("plate", 0)
    @plate_y = frame.at("plate", 1)
    @lock_z = @z_nom
    @lock_x = @x_nom
    @lock_att = @att_nom
    @aiming = false
    @locked = false
    @aim_ticks = 0
    @hips_fired = false
    @pelvis_now = ~0.0
    @torso_now = ~0.0
    @yaw_ref_pelvis = ~0.0
    @yaw_ref_torso = ~0.0
    @p_max = ~0.0
    @t_max = ~0.0
    @rg = [~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0]
    @dt = ctl.dt
    @ctl = ctl
    normal_gains
    ctl.add_track(Track.new("hips", movement(:hips), track_mask(:hips)))
    ctl.add_track(Track.new("torso", movement(:torso), track_mask(:torso)))
    ctl.add_track(Track.new("arms", movement(:arms), track_mask(:arms)))

  -> read_params
    @stride = param("stride", ~1.0, ~0.0, ~1.0) > ~0.5
    @uppercut = param("uppercut", ~1.0, ~0.0, ~1.0) > ~0.5
    # prop 1: the chain's handoffs latch on proprioception (each segment
    # fires once the one below it has turned far enough and stopped
    # speeding up; the wrists uncock when the hands pass in front of the
    # pelvis) instead of fixed time lags. 0 keeps the time lags.
    @prop = param("prop", ~0.0, ~0.0, ~1.0) > ~0.5
    # flow 1: load -> swing -> (slot, whip, release, drive) -> follow is one
    # velocity-continuous motion (via chunks), and the load is timed at run
    # time to end when the swing is due, so it is still moving when the
    # swing begins. 0 keeps the ease-then-hold load and the per-chunk
    # easings (the practised params before 2026-09-26 set flow 0).
    @flow = param("flow", ~1.0, ~0.0, ~1.0) > ~0.5
    # flow's two ingredients, separable for comparison (both follow `flow`
    # unless set): via_swing chains load -> swing -> ... -> follow as via
    # chunks; timed_load gives the load its run-time duration (a via
    # TimedChunk). via_swing alone keeps the fixed 0.12 s load, which then
    # holds until the swing is due; timed_load alone flows the load into the
    # first swing chunk only, the rest on their own easings.
    both = ~0.0
    both = ~1.0 if @flow
    @via_swing = param("via_swing", both, ~0.0, ~1.0) > ~0.5
    @timed_load = param("timed_load", both, ~0.0, ~1.0) > ~0.5
    # flow: shortest and longest run-time load
    @load_min = ~0.04
    @load_max = ~0.6
    # The follow-through, three separable ingredients (they follow `flow`
    # unless set):
    # through 1: the follow passes the extension as a via keyframe and the
    #   let_go inherits its velocity and eases to rest at the finish, so the
    #   motion never stops between contact and the finish; the top hand
    #   lets go as an event when the bat comes round (else as the let_go
    #   starts), not by holding the follow until it does.
    # trunk_through 1: the trunk's swing keyframe is the contact posture and
    #   its follow keyframe runs past the extension by `over_follow` of
    #   contact -> extension, instead of a swing goal far past contact that
    #   the follow then comes back from.
    # gain_ease 1: the swing's reflex gains (and chunk gain) last through the
    #   follow and ease to the standing ones over the let_go, instead of
    #   switching back as the follow begins.
    @through = param("through", both, ~0.0, ~1.0) > ~0.5
    @trunk_through = param("trunk_through", both, ~0.0, ~1.0) > ~0.5
    @gain_ease = param("gain_ease", both, ~0.0, ~1.0) > ~0.5
    @over_follow = param("over_follow", ~0.5, ~0.0, ~1.5)
    @grip_sent = false
    @turn_torso = param("turn_torso", ~0.35, ~0.05, ~0.9)
    @turn_arms = param("turn_arms", ~0.35, ~0.05, ~1.0)
    # the rate test: fire once the proximal segment's turning rate is below
    # pk_* of its peak so far (<1: it is decelerating; >1: the turn alone)
    @pk_torso = param("pk_torso", ~0.95, ~0.6, ~1.3)
    @pk_arms = param("pk_arms", ~1.2, ~0.6, ~1.3)
    @hands_front = param("hands_front", ~0.05, ~-0.3, ~0.5)
    @wrist_delay = param("wrist_delay", ~0.0, ~0.0, ~0.06)
    @fallback = ~0.12
    @stiff = param("stiff", ~0.075, ~0.0, ~0.3)
    @arm_kp = param("arm_kp", ~8.4, ~3.0, ~16.0)
    @arm_kd = param("arm_kd", ~0.16, ~0.05, ~1.0)
    @wrist_kp = param("wrist_kp", ~4.8, ~1.0, ~16.0)
    @wrist_kd = param("wrist_kd", ~0.12, ~0.02, ~1.0)
    @trunk_kp = param("trunk_kp", ~6.3, ~3.0, ~16.0)
    @trunk_kd = param("trunk_kd", ~0.57, ~0.02, ~1.0)
    # legs: firm while standing, lifting and striding; soft from the swing
    # on so the hips can turn over the planted feet
    @leg_kp = param("leg_kp", ~7.0, ~1.0, ~16.0)
    @leg_kd = param("leg_kd", ~0.3, ~0.02, ~0.8)
    @leg_swing_kp = param("leg_swing_kp", ~2.2, ~0.5, ~10.0)
    @leg_swing_kd = param("leg_swing_kd", ~0.2, ~0.02, ~0.6)
    # the trunk's swing is ballistic: feed-forward bursts with the stretch
    # reflexes turned down (swing_kp, swing_kd replace the trunk's gains from
    # the swing to the follow-through). The arms stay connected (their own
    # swing gains) so the trunk's turn reaches the bat, and the wrists go
    # loose at the release so the barrel whips through.
    @swing_kp = param("swing_kp", ~2.5, ~1.0, ~16.0)
    @swing_kd = param("swing_kd", ~0.02, ~0.0, ~0.6)
    @arm_swing_kp = param("arm_swing_kp", ~8.0, ~1.0, ~16.0)
    @arm_swing_kd = param("arm_swing_kd", ~0.1, ~0.0, ~0.6)
    @wrist_rel_kp = param("wrist_rel_kp", ~2.0, ~0.2, ~10.0)
    @wrist_rel_kd = param("wrist_rel_kd", ~0.05, ~0.0, ~0.4)
    # stride timing on the pitcher's delivery (s into it; the release comes
    # at about 0.9 s), stride chunk durations, the stride's push
    @lift_at = param("lift_at", ~0.25, ~0.0, ~0.8)
    @stride_at = param("stride_at", ~0.5, ~0.3, ~1.0)
    # the whole step (lift, hang, stride, plant) this much later on the
    # delivery, its shape unchanged: lands the plant nearer the swing
    @step_delay = param("step_delay", ~0.0, ~0.0, ~0.2)
    @dur_leglift = param("dur_leglift", ~0.24, ~0.1, ~0.5)
    @dur_stride = param("dur_stride", ~0.3, ~0.1, ~0.45)
    @drv_stride = param("drv_stride", ~0.8, ~0.0, ~1.0)
    # timing: the hips fire when the pitch is t_trigger from the plate, the
    # torso and arms lag seconds later; inside pitches earlier by k_in s/m
    @t_trigger = param("t_trigger", ~0.27, ~0.15, ~0.45)
    @lag_torso = param("lag_torso", ~0.02, ~0.0, ~0.1)
    @lag_arms = param("lag_arms", ~0.03, ~0.0, ~0.15)
    @k_in = param("k_in", ~0.08, ~0.0, ~0.6)
    @t_load = param("t_load", ~0.19, ~0.12, ~0.4)
    # hip-shoulder separation: while the hips open before the torso fires,
    # spine rotation counters k_sep of the pelvis turn (up to sep_max rad)
    @k_sep = param("k_sep", ~0.8, ~0.0, ~1.2)
    @sep_max = param("sep_max", ~0.35, ~0.0, ~0.6)
    # the swing: trunk goal past contact by `over` of load -> contact, arms
    # through the waypoints then past contact by `over_arms`
    @dur_hips = param("dur_hips", ~0.29, ~0.1, ~0.4)
    @dur_torso = param("dur_torso", ~0.32, ~0.1, ~0.4)
    # (flow: the slot is a keyframe of one smooth motion; below ~50 ms the
    # spline through it spikes, so the search starts there)
    slot_lo = ~0.02
    slot_lo = ~0.05 if @via_swing
    @dur_slot = param("dur_slot", ~0.04, slot_lo, ~0.2)
    @dur_mid = param("dur_mid", ~0.035, ~0.015, ~0.15)
    @dur_whip = param("dur_whip", ~0.05, ~0.02, ~0.15)
    @dur_drive = param("dur_drive", ~0.067, ~0.02, ~0.2)
    @over = param("over", ~0.63, ~0.0, ~1.5)
    @over_arms = param("over_arms", ~1.0, ~0.0, ~1.5)
    @drv_hips = param("drv_hips", ~0.9, ~0.0, ~1.0)
    # the legs turning the pelvis over the planted feet (hip rotators and
    # abductors driven toward the swing's leg posture); 0 leaves them to the
    # reflexes as in the first versions
    @drv_legs = param("drv_legs", ~0.0, ~0.0, ~1.0)
    @drv_torso = param("drv_torso", ~0.9, ~0.0, ~1.0)
    @drv_arms = param("drv_arms", ~0.3, ~0.0, ~1.0)
    @drv_whip = param("drv_whip", ~0.8, ~0.0, ~1.0)
    @swing_gain = param("swing_gain", ~1.5, ~0.2, ~3.0)
    @arm_gain = param("arm_gain", ~1.5, ~0.2, ~3.0)
    # real-time correction (aim height, in/out, swing-plane tilt)
    @z_nom = param("z_nom", ~0.8, ~0.6, ~1.0)
    @x_nom = param("x_nom", ~0.72, ~0.55, ~1.0)
    @g_z = param("g_z", ~1.3, ~0.0, ~2.5)
    @g_x = param("g_x", ~0.4, ~0.0, ~1.5)
    @att_nom = param("att_nom", ~0.175, ~0.0, ~0.35)
    @att_bias = param("att_bias", ~0.05, ~-0.1, ~0.25)
    @g_att = param("g_att", ~1.0, ~0.0, ~3.0)
    @t_lock = param("t_lock", ~0.154, ~0.0, ~0.25)
    @spring = param("spring", ~0.031, ~0.02, ~0.15)
    # flow: the spring the aim eases in on before the swing (from the
    # release); the swing's chunks retime it to `spring`
    @spring_pre = param("spring_pre", ~0.1, ~0.03, ~0.3)
    # follow-through and release of the top hand
    @dur_follow = param("dur_follow", ~0.15, ~0.05, ~0.3)
    @dur_release = param("dur_release", ~0.35, ~0.15, ~0.6)
    # regrip servo (integral and proportional gains, closing distance)
    @rg_i = param("rg_i", ~4.0, ~0.0, ~12.0)
    @rg_p = param("rg_p", ~0.5, ~0.0, ~2.0)
    @grip_close = ~0.03
    # v5 (see the header), each off by default
    @lift_via = param("lift_via", ~0.0, ~0.0, ~1.0) > ~0.5
    @stride_load = param("stride_load", ~0.0, ~0.0, ~1.0) > ~0.5
    # (stride_load: how far toward q_gather the stride loads, from q_coil)
    @gather = param("gather", ~1.0, ~0.1, ~1.0)
    @plant_via = param("plant_via", ~0.0, ~0.0, ~1.0) > ~0.5
    @dur_plant = param("dur_plant", ~0.15, ~0.06, ~0.3)
    @plant_swing = param("plant_swing", ~0.0, ~0.0, ~1.0) > ~0.5
    @hips_end = param("hips_end", ~0.06, ~-0.05, ~0.2)
    # hip_open: the hips' load (from the plant, latched on the front foot's
    # contact, until the hips' swing is due) opens this fraction of the load
    # -> swing hip turn (pelvis and legs together): the hips begin to turn
    # as the front foot lands and are moving when they fire, while the
    # torso's separation keeps the shoulders closed; 0 holds the hips
    @hip_open = param("hip_open", ~0.0, ~0.0, ~0.5)
    @knot_on = param("knot", ~0.0, ~0.0, ~1.0) > ~0.5
    @con_speed = param("con_speed", ~12.0, ~4.0, ~30.0)
    @con_lead = param("con_lead", ~-0.03, ~-0.12, ~0.1)
    # the trunk's share of the contact velocity (u_contact bends the spine
    # hard through contact; the trunk may carry less of it)
    @con_trunk = param("con_trunk", ~1.0, ~0.0, ~1.5)
    # and the wrists' share (the plane's rotation uncocks them hard through
    # contact; past it the bottom wrist would run into its ulnar limit)
    @con_wrist = param("con_wrist", ~1.0, ~0.0, ~1.5)
    # limit_brake: in the follow-through an upper-body joint heading into the
    # end of its range faster than it can stop is braked by its antagonist
    # (feed-forward, up to limit_brake, rising as the time to the limit at
    # its current speed falls below brake_t): the eccentric braking of a
    # batter's wrists and hips after contact, instead of a stop on the limit
    # (the bottom wrist's ulnar deviation hit its limit ~0.15 s after contact)
    @limit_brake = param("limit_brake", ~0.0, ~0.0, ~1.0)
    @brake_t = param("brake_t", ~0.08, ~0.02, ~0.2)
    @hips_lead = param("hips_lead", ~0.03, ~0.0, ~0.12)
    @arc = param("arc", ~0.0, ~0.0, ~1.0) > ~0.5
    @dur_arc = param("dur_arc", ~0.45, ~0.2, ~0.9)
    @rel_frac = param("rel_frac", ~0.5, ~0.1, ~1.0)
    # arc: the legs' finish continues past the swing stance by `leg_follow`
    # of landed -> swing (the back foot pivots on, the hips keep turning),
    # instead of the swing stance the hips' swing has been heading past
    @leg_follow = param("leg_follow", ~0.0, ~0.0, ~1.0)

  # ---- reflex gains -------------------------------------------------------------

  # Leg muscles: the joint pairs plus, on the human-calibrated body, the
  # toes and the biarticulars (rectus femoris, hamstrings, gastrocnemius).
  -> leg_prefixes
    ["l_hip", "r_hip", "l_knee", "r_knee", "l_ankle", "r_ankle", "l_toe", "r_toe", "l_rf", "r_rf", "l_ham", "r_ham", "l_gas", "r_gas"]

  -> leg_mask
    body.mask(leg_prefixes)

  -> normal_gains
    restore_gains(:hips)
    restore_gains(:torso)
    restore_gains(:arms)

  # A track's standing reflex gains.
  -> restore_gains(which)
    r = @ctl.reflex
    if which == :arms
      r.set_gains(body.mask(["l_shoulder", "r_shoulder", "l_elbow", "r_elbow"]), @arm_kp, @arm_kd)
      r.set_gains(body.mask(["l_wrist", "r_wrist"]), @wrist_kp, @wrist_kd)
    elsif which == :torso
      r.set_gains(body.mask(["spine_"]), @trunk_kp, @trunk_kd)
    else
      r.set_gains(body.mask(["pelvis_"]), @trunk_kp, @trunk_kd)
      r.set_gains(leg_mask, @leg_kp, @leg_kd)
    nil

  # Ballistic swing: stretch reflexes turned down on a track's rotating
  # muscles (the legs and the pelvis shift keep theirs: they hold the stance).
  -> swing_gains(which)
    r = @ctl.reflex
    if which == :arms
      r.set_gains(track_mask(:arms), @arm_swing_kp, @arm_swing_kd)
    elsif which == :torso
      r.set_gains(body.mask(["spine_"]), @swing_kp, @swing_kd)
    else
      r.set_gains(body.mask(["pelvis_yaw"]), @swing_kp, @swing_kd)
      r.set_gains(leg_mask, @leg_swing_kp, @leg_swing_kd)
    nil

  # ---- postures ---------------------------------------------------------------

  -> posture(upper, legs, stiff)
    p = Pose.new
    names = BatPostures.joints
    i = 0
    while i < names.size
      p.set(names[i], upper[i], stiff)
      i += 1
    names = BatPostures.leg_joints
    i = 0
    while i < names.size
      p.set(names[i], legs[i], stiff)
      i += 1
    p

  # b + over * (b - a) per upper-body joint, clamped inside each joint's
  # range: a goal past posture b along a -> b, so the muscles are still
  # driving when the bat reaches b.
  -> beyond(a, b, over)
    names = BatPostures.joints
    out = []
    i = 0
    while i < names.size
      m = body.muscle(body.pos_index(names[i]))
      q = b[i] + over * (b[i] - a[i])
      out.push(clamp(q, m.qmin + ~0.02, m.qmax - ~0.02))
      i += 1
    out

  # The same over the leg joints (a -> b of the leg tables).
  -> beyond_legs(a, b, over)
    return b if over <= ~0.0
    names = BatPostures.leg_joints
    out = []
    i = 0
    while i < names.size
      m = body.muscle(body.pos_index(names[i]))
      q = b[i] + over * (b[i] - a[i])
      out.push(clamp(q, m.qmin + ~0.02, m.qmax - ~0.02))
      i += 1
    out

  # Feed-forward burst for a move from a to b (tables over `names`): on each
  # of the mask's joints, the muscle the move shortens gets `level`, scaled
  # down for joints that barely move (full at `full` of travel).
  -> burst(names, a, b, mask, level, full)
    inside = {}
    mask.each ->(k) inside[k] = true
    drv = zeros
    i = 0
    while i < names.size
      p = body.pos_index(names[i])
      if inside.key?(p)
        dq = b[i] - a[i]
        k = p
        k = body.neg_index(names[i]) if dq < ~0.0
        drv[k] = level * clamp(dq.abs / full, ~0.0, ~1.0)
      i += 1
    drv

  # ---- the movement -------------------------------------------------------------

  -> movement(which)
    mask = track_mask(which)
    uj = BatPostures.joints
    lj = BatPostures.leg_joints
    q_set = BatPostures.q_set
    q_load = BatPostures.q_load
    q_con = BatPostures.q_contact
    q_ext = BatPostures.q_extend
    legs_load = BatPostures.legs_stance
    legs_swing = BatPostures.legs_swing0
    if @stride
      q_load = BatPostures.q_coil
      legs_load = BatPostures.legs_landed
      legs_swing = BatPostures.legs_swing
    # (stride_load: the leg lift coils to q_coil, the stride loads on to q_gather)
    q_lift = q_load
    q_load = gathered if @stride && @stride_load
    if @uppercut
      q_con = BatPostures.q_contact_u
      q_ext = BatPostures.q_extend_u
    stance = BatPostures.legs_stance
    p_set = posture(q_set, stance, @stiff)
    p_ready = posture(q_set, stance, @stiff * ~1.5)
    p_load = posture(q_load, legs_load, @stiff)
    p_extend = posture(q_ext, legs_swing, ~0.0)
    p_finish = posture(BatPostures.q_finish, legs_swing, @stiff)
    p_finish = posture(BatPostures.q_wrap, beyond_legs(legs_load, legs_swing, @leg_follow), @stiff) if @arc
    p_recover = posture(BatPostures.q_recover, stance, @stiff)
    idle = ->(f, c) nil
    aim_mid = ->(f, c) aim_offsets(:release)
    aim_con = ->(f, c) aim_offsets(:contact)
    aim_ext = ->(f, c) aim_offsets(:extend)
    pitched = Latch.test("pitched", ->(f, e, c) f.at("ball_vel", 1) > ~5.0)
    lag = ~0.0
    lag = @lag_torso if which == :torso
    lag = @lag_arms if which == :arms
    due = Latch.test("due", ->(f, e, c) swing_due?(f, lag, which))
    if @prop && which != :hips
      seg = :pelvis
      seg = :torso if which == :arms
      late = lag + @fallback
      due = Latch.any([Latch.test("turned", ->(f, e, c) proximal_ready?(f, seg)), Latch.test("late", ->(f, e, c) swing_due?(f, late, which))])
    gripped = Latch.above("grip_l", 0, ~0.5)
    # the correction before the swing (the torso's adds hip-shoulder
    # separation) and its spring
    # TODO: `pre_aim = ->(f, c) ...` inside an `if` block is silently dropped
    # (a lambda literal assigned to a local in an if-body; both engines), so
    # the lambda is bound outside the if. Inline it once that is fixed.
    sep = ->(f, c) separation(f, c)
    pre_aim = aim_mid
    if which == :torso
      pre_aim = sep
    pre_spring = @spring
    pre_spring = @spring_pre if @flow

    mv = Movement.new("bat")
    # Every chunk states the same spring time. (This first-chunk declaration
    # was the workaround for controller.w building the spring from the first
    # correcting chunk only; the SDK now retimes it per chunk. Kept so the
    # practised runs stay bit-identical.)
    mv.add(Chunk.new("lift", ~1.0).pose(p_set).hold_until(Latch.after(~1.3)).correct(idle, @spring))
    mv.add(Chunk.new("set", ~0.6).pose(p_set).hold_until(Latch.after(~0.7)))
    if @stride
      rd = mv.add(Chunk.new("ready", ~0.2).pose(p_ready).hold_until(delivery(@lift_at + @step_delay)))
      p_lift = posture(q_lift, BatPostures.legs_lift, @stiff)
      lift_due = Latch.any([delivery(@stride_at + @step_delay), pitched])
      if @lift_via
        # (retimed until it starts to end when the stride is due: retime_lifts)
        ll = mv.add(TimedChunk.new("leglift", @dur_leglift).pose(p_lift).hold_until(lift_due, ~1.5).via)
        @lifts.push(ll)
      else
        mv.add(Chunk.new("leglift", @dur_leglift).pose(p_lift).hold_until(lift_due, ~1.5))
      p_stride = posture(q_load, BatPostures.legs_stride, @stiff)
      push = burst(lj, BatPostures.legs_lift, BatPostures.legs_stride, mask, @drv_stride, ~0.15)
      st = mv.add(Chunk.new("stride", @dur_stride).pose(p_stride).drive(push))
      planted = Latch.contact("r_foot", ~0.02)
      pl = nil
      if @plant_via
        # a via keyframe: ends on the foot's contact or on time, either way
        # handing its velocity on (no slam, no stop)
        st.via
        pl = mv.add(Chunk.new("plant", @dur_plant).pose(p_load).hold_until(planted, @dur_plant).via)
      else
        pl = mv.add(Chunk.new("plant", ~0.08).pose(p_load).hold_until(planted, ~0.4))
      # (plant_swing: the hips go from the plant straight into the swing)
      ld = nil
      p_ld = p_load
      p_ld = posture(lerp_list(q_load, q_con, @hip_open), lerp_list(legs_load, legs_swing, @hip_open), @stiff) if which == :hips && @hip_open > ~0.0
      ld = mv.add(load_chunk(which, ~0.12, p_ld, due, lag)) if !(@plant_swing && which == :hips)
      if @flow && which != :hips
        # flow: the upper body starts aiming as soon as the pitch is seen
        # (it is released during the stride), on the slower pre-swing
        # spring, rather than all at once when the load begins
        st.correct(pre_aim, @spring_pre)
        pl.correct(pre_aim, @spring_pre)
    else
      rd = mv.add(Chunk.new("ready", ~0.2).pose(p_ready).hold_until(pitched))
      ld = mv.add(load_chunk(which, @t_load, p_load, due, lag))
    rd.on_enter(->(f, c) c.emit("ready")) if which == :arms
    ld.correct(pre_aim, pre_spring) if ld != nil
    # (a subclass may build the swing itself: swing_train; nil = this one)
    sw = swing_train(which, mv, mask, legs_load, legs_swing)
    if sw == nil && which == :arms
      q_rel = BatPostures.q_release
      q_rel = BatPostures.q_release_u if @uppercut
      sw = mv.add(flowing(Chunk.new("swing", @dur_slot).pose(posture(BatPostures.q_slot, legs_swing, ~0.0)).ease(:linear).drive(burst(uj, q_load, BatPostures.q_slot, mask, @drv_arms, ~0.5)).gain(@arm_gain).correct(aim_mid, @spring)))
      q_prev = BatPostures.q_slot
      last = sw
      if @uppercut
        q_mid = BatPostures.q_mid_u
        last = mv.add(flowing(Chunk.new("whip", @dur_mid).pose(posture(q_mid, legs_swing, ~0.0)).ease(:linear).drive(burst(uj, q_prev, q_mid, mask, @drv_whip, ~0.5)).gain(@arm_gain).correct(aim_mid, @spring)))
        q_prev = q_mid
      if @prop
        # the wrists uncock when the hands are in front of the lead hip
        front = Latch.test("hands_front", ->(f, e, c) hands_front?(f))
        # (flow: the latch may cut the chunk short but never holds it, so
        # the via velocity carries on)
        wait = ~0.12
        wait = ~0.0 if @via_swing
        last.hold_until(front, last.duration + wait)
      rel = mv.add(flowing(Chunk.new("release", @dur_whip).pose(posture(q_rel, legs_swing, ~0.0)).ease(:linear).drive(burst(uj, q_prev, q_rel, mask, @drv_whip, ~0.5)).gain(@arm_gain).correct(aim_mid, @spring)))
      rel.on_enter(->(f, c) c.reflex.set_gains(body.mask(["l_wrist", "r_wrist"]), @wrist_rel_kp, @wrist_rel_kd))
      # (flow: no stagger; a staggered chunk runs on its easing, not the via spline)
      rel.stagger(body.mask(["l_wrist", "r_wrist"]), @wrist_delay) if @prop && @wrist_delay > ~0.0 && !@via_swing
      if @knot_on
        # the contact knot: AT the contact posture with the planned velocity
        # (min-jerk position basis, as a knot needs), passing its keyframe
        # on time (via)
        mv.add(Chunk.new("drive", @dur_drive).pose(posture(q_con, legs_swing, ~0.0)).drive(burst(uj, q_rel, q_con, mask, @drv_whip, ~0.5)).gain(@arm_gain).correct(aim_con, @spring).knot(contact_velocity, nil).via)
      else
        mv.add(flowing(Chunk.new("drive", @dur_drive).pose(posture(beyond(q_rel, q_con, @over_arms), legs_swing, ~0.0)).ease(:linear).drive(burst(uj, q_rel, q_con, mask, @drv_whip, ~0.5)).gain(@arm_gain).correct(aim_con, @spring)))
    elsif sw == nil
      dur = @dur_hips
      level = @drv_hips
      if which == :torso
        dur = @dur_torso
        level = @drv_torso
      drv = burst(uj, q_load, q_con, mask, level, ~0.5)
      if which == :hips && @drv_legs > ~0.0
        legs = burst(lj, legs_load, legs_swing, mask, @drv_legs, ~0.4)
        drv = (0...drv.size).map ->(i) drv[i] + legs[i]
      # (trunk_through: the contact posture is the swing's keyframe)
      q_goal = beyond(q_load, q_con, @over)
      q_goal = q_con if @trunk_through
      if @knot_on && which == :torso
        # the trunk's contact knot (as the arms')
        vt = contact_velocity.map ->(x) x * @con_trunk
        sw = mv.add(Chunk.new("swing", dur).pose(posture(q_con, legs_swing, ~0.0)).drive(drv).gain(@swing_gain).correct(aim_mid, @spring).knot(vt, nil).via)
      elsif @plant_swing && which == :hips
        # from the plant until hips_end before the plate (retime_hips)
        sw = mv.add(flowing(TimedChunk.new("swing", dur).pose(posture(q_goal, legs_swing, ~0.0)).ease(:cubic_out).drive(drv).gain(@swing_gain).correct(aim_mid, @spring)))
        @hip_swings.push(sw)
      else
        sw = mv.add(flowing(Chunk.new("swing", dur).pose(posture(q_goal, legs_swing, ~0.0)).ease(:cubic_out).drive(drv).gain(@swing_gain).correct(aim_mid, @spring)))
    sw.on_enter(->(f, c) swing_start(which, c))
    p_follow = p_extend
    p_follow = posture(beyond(q_con, q_ext, @over_follow), legs_swing, ~0.0) if @trunk_through && which != :arms
    fl = nil
    if @arc
      # one arc from the contact knot to the finish, ending at rest; the
      # gains ease back over it (ease_gains) and the top hand lets go on the
      # way (release_on_around)
      fl = mv.add(Chunk.new("follow", @dur_arc).pose(p_finish).correct(aim_ext, @spring).knot(nil))
    else
      fl = mv.add(Chunk.new("follow", @dur_follow).pose(p_follow).correct(aim_ext, @spring))
    fl.via if @through && !@arc
    # (arc: the gains ease back over the arc itself, ease_gains)
    if @gain_ease && !@arc
      g_swing = @swing_gain
      g_swing = @arm_gain if which == :arms
      fl.gain(g_swing)
    elsif !@arc
      fl.on_enter(->(f, c) restore_gains(which))
    # the top hand lets go when the bat has come round to point back at the
    # pitcher (felt through the hands: the bat's knob -> tip direction);
    # through: as an event while the follow moves on (release_on_around)
    around = Latch.test("bat_around", ->(f, e, c) bat_heading(f) < ~-0.9).after_min(~0.06)
    fl.hold_until(around, @dur_follow + ~0.2) if which == :arms && !@through && !@arc
    if !@arc
      rl = mv.add(Chunk.new("let_go", @dur_release).pose(p_finish))
      rl.on_enter(->(f, c) c.emit("grip:l:0")) if which == :arms
    fin = mv.add(Chunk.new("finish", ~0.2).pose(p_finish).hold_until(Latch.after(~0.5)))
    if @arc
      fin.on_enter(->(f, c) finish_arc(which, c))
    elsif @gain_ease
      fin.on_enter(->(f, c) restore_gains(which))
    if which == :arms
      mv.add(Chunk.new("recover", ~0.8).pose(p_recover).hold_until(Latch.after(~0.95)))
      servo = ->(f, c) regrip_offsets(f)
      near = Latch.test("near", ->(f, e, c) grip_distance(f) < @grip_close)
      rg = mv.add(Chunk.new("regrip", ~0.1).pose(p_recover).hold_until(near, ~2.5).correct(servo, @spring))
      rg.on_enter(->(f, c) reset_regrip)
      cl = mv.add(Chunk.new("close", ~0.05).pose(p_recover).hold_until(gripped, ~0.3).correct(servo, @spring))
      cl.on_enter(->(f, c) c.emit("grip:l:1"))
    else
      mv.add(Chunk.new("recover", ~0.8).pose(p_recover).hold_until(gripped.after_min(~0.9), ~5.0))
    mv.loop_from(1)
    mv

  # A subclass's own swing chunks for a track (added to mv; returns the first,
  # which gets the swing's on_enter), or nil for the swing built here.
  -> swing_train(which, mv, mask, legs_load, legs_swing)
    nil

  # flow: a keyframe the command passes through on its way to the next one
  # (a via chunk) instead of arriving and stopping.
  -> flowing(ch)
    return ch if !@via_swing
    ch.via

  # The load. Without flow: ease into the load posture and hold until the
  # swing is due. With flow: a via chunk through the load posture whose
  # duration is kept, until it starts, at the predicted time until the
  # track's swing is due (retime_loads), so the command is still moving
  # when the swing begins: a small counter-movement (the Catmull-Rom
  # tangent at its end points at the swing's goal), then on into the swing.
  -> load_chunk(which, dur, p_load, due, lag)
    return Chunk.new("load", dur).pose(p_load).hold_until(due, ~1.5).via if @via_swing && !@timed_load
    return Chunk.new("load", dur).pose(p_load).hold_until(due, ~1.5) if !@timed_load
    ld = TimedChunk.new("load", dur).pose(p_load).hold_until(due, ~1.5).via
    name = "hips"
    name = "torso" if which == :torso
    name = "arms" if which == :arms
    @timed.push([ld, name, lag, which])
    ld

  # flow: every tick until a track's load starts, set the load's duration to
  # the time until that track's swing is due (the hips' trigger plus the
  # track's lag, from the pitch's predicted time to the plate; t_load while
  # no pitch is coming). In `prop` mode the torso and arms may still fire
  # earlier on proprioception (the latch cuts the via chunk short, and the
  # swing inherits its velocity); their lag is then the latest they fire.
  -> retime_loads(f, ctl)
    p = predict(f)
    @timed.each ->(e)
      if ctl.track(e[1]).chunk_name != "load"
        left = @t_load
        left = p[0] - (trigger(e[2], e[3]) + @k_in * (@x_nom - p[1])) if p[0] < ~8.0
        e[0].retime(clamp(left, @load_min, @load_max))
    nil

  # lift_via: until the leg lift starts, its duration is the time left until
  # the stride is due on the delivery clock (the whole lift, before the
  # delivery starts), so it ends as the stride begins.
  -> retime_lifts(f, ctl)
    w = ~0.0
    w = f.at("pitch_windup", 1) if f.at("pitch_windup", 0) > ~0.5
    w = @lift_at + @step_delay if w < @lift_at + @step_delay
    left = clamp(@stride_at - @lift_at - (w - @lift_at - @step_delay), ~0.1, ~0.7)
    @lifts.each ->(ch)
      ch.retime(left) if ctl.track("hips").chunk_name != "leglift"
    nil

  # plant_swing: until the hips fire, their swing lasts until hips_end s
  # before the pitch reaches the plate (dur_hips while no pitch is coming).
  -> retime_hips(f, ctl)
    return nil if @hips_fired
    p = predict(f)
    left = @dur_hips
    left = p[0] - @hips_end if p[0] < ~8.0
    @hip_swings.each ->(ch) ch.retime(clamp(left, ~0.12, ~0.45))
    nil

  # When (time to the plate, s) a track's swing is due, before the in/out
  # shift. Without knot: the hips' t_trigger, the torso and arms `lag` later.
  # knot: planned backward from contact: the arms and the torso when the
  # time left equals their swing's planned duration plus con_lead (so their
  # contact knots fall con_lead before the plate), the hips hips_lead before
  # the first of them.
  -> trigger(lag, which)
    return @t_trigger - lag if !@knot_on
    arms = @dur_slot + @dur_whip + @dur_drive + @con_lead
    arms = arms + @dur_mid if @uppercut
    torso = @dur_torso + @con_lead
    return arms if which == :arms
    return torso if which == :torso
    first = arms
    first = torso if torso > arms
    first + @hips_lead

  # stride_load: the stride's load posture, `gather` of the way from q_coil
  # to q_gather.
  -> gathered
    return BatPostures.q_gather if @gather >= ~1.0
    a = BatPostures.q_coil
    b = BatPostures.q_gather
    (0...a.size).map ->(i) a[i] + @gather * (b[i] - a[i])

  # knot: the contact knot's velocity as contractions (1/s): the sweet spot
  # moving along the swing plane at con_speed m/s (u_contact per m).
  -> contact_velocity
    u = BatPostures.u_contact
    names = BatPostures.joints
    out = zeros
    i = 0
    while i < names.size
      k = @con_speed
      k = k * @con_wrist if names[i].include?("wrist")
      joint_offset(out, names[i], k * u[i])
      i += 1
    out

  # arc: at the finish the gains are the standing ones and the top hand has
  # let go (if the bat never came round on the arc).
  -> finish_arc(which, c)
    restore_gains(which)
    if which == :arms && !@grip_sent
      c.emit("grip:l:0")
      @grip_sent = true
    nil

  # through: the top hand lets go as soon as the bat has come round (0.06 s
  # into the follow at the earliest) while the follow moves on; the let_go
  # still sends it as it starts if the bat never came round.
  -> release_on_around(f, ctl)
    return nil if @grip_sent
    tr = ctl.track("arms")
    if tr.chunk_name == "follow" && tr.elapsed(f) >= ~0.06 && bat_heading(f) < ~-0.9
      ctl.emit("grip:l:0")
      @grip_sent = true
    elsif @arc && tr.chunk_name == "follow" && tr.elapsed(f) >= @rel_frac * @dur_arc
      ctl.emit("grip:l:0")
      @grip_sent = true
    nil

  # gain_ease: over each track's let_go, its reflex gains ease from the
  # swing's to the standing ones (restore_gains sets them exactly at the
  # finish).
  -> ease_gains(f, ctl)
    [[:hips, "hips"], [:torso, "torso"], [:arms, "arms"]].each ->(w)
      tr = ctl.track(w[1])
      if tr.chunk_name == "let_go"
        blend_gains(w[0], clamp(tr.elapsed(f) / @dur_release, ~0.0, ~1.0))
      elsif @arc && tr.chunk_name == "follow"
        blend_gains(w[0], clamp(tr.elapsed(f) / @dur_arc, ~0.0, ~1.0))
    nil

  # limit_brake (see read_params), each tick of the arms' follow
  -> brake_limits(f, ctl)
    return nil if ctl.track("arms").chunk_name != "follow"
    BatPostures.joints.each ->(j)
      qd = f.joint_rate(body, j)
      p = body.pos_index(j)
      m = body.muscle(p)
      q = f.joint_angle(body, j)
      gap = q - m.qmin
      anta = p
      if qd > ~0.0
        gap = m.qmax - q
        anta = body.neg_index(j)
      sp = qd.abs
      if sp > ~0.01
        ttl = gap / sp
        ctl.add_drive(anta, @limit_brake * clamp(~1.0 - ttl / @brake_t, ~0.0, ~1.0)) if ttl < @brake_t
    nil

  -> lerp(a, b, u)
    a + (b - a) * u

  -> lerp_list(a, b, u)
    (0...a.size).map ->(i) a[i] + (b[i] - a[i]) * u

  # Reflex gains a fraction u of the way from the swing's to the standing
  # ones. The swing's chunk gain is folded in, since the let_go runs at 1.
  -> blend_gains(which, u)
    r = @ctl.reflex
    if which == :arms
      g = @arm_gain
      r.set_gains(body.mask(["l_shoulder", "r_shoulder", "l_elbow", "r_elbow"]), lerp(@arm_swing_kp * g, @arm_kp, u), lerp(@arm_swing_kd * g, @arm_kd, u))
      r.set_gains(body.mask(["l_wrist", "r_wrist"]), lerp(@wrist_rel_kp * g, @wrist_kp, u), lerp(@wrist_rel_kd * g, @wrist_kd, u))
    elsif which == :torso
      g = @swing_gain
      r.set_gains(body.mask(["spine_"]), lerp(@swing_kp * g, @trunk_kp, u), lerp(@swing_kd * g, @trunk_kd, u))
    else
      g = @swing_gain
      r.set_gains(body.mask(["pelvis_yaw"]), lerp(@swing_kp * g, @trunk_kp, u), lerp(@swing_kd * g, @trunk_kd, u))
      r.set_gains(body.mask(["pelvis_shift"]), lerp(@trunk_kp * g, @trunk_kp, u), lerp(@trunk_kd * g, @trunk_kd, u))
      r.set_gains(leg_mask, lerp(@leg_swing_kp * g, @leg_kp, u), lerp(@leg_swing_kd * g, @leg_kd, u))
    nil

  -> swing_start(which, c)
    swing_gains(which)
    if which == :hips
      c.emit("swing")
      @grip_sent = false
      @hips_fired = true
      @p_max = ~0.0
      @t_max = ~0.0
      @yaw_ref_pelvis = @pelvis_now
      @yaw_ref_torso = @torso_now
    nil

  # ---- proprioception for the chain's handoffs ----------------------------------

  -> torso_yaw(f)
    Math.atan2(f.at("torso_fwd", 1), f.at("torso_fwd", 0))

  -> wrap(a)
    return a - ~6.283185307179586 if a > ~3.141592653589793
    return a + ~6.283185307179586 if a < ~-3.141592653589793
    a

  # The segment below has turned toward the pitcher by the handoff angle
  # since the hips fired, and has stopped speeding up (its turning rate is
  # below peak_frac of its peak so far).
  -> proximal_ready?(f, seg)
    return false if !@hips_fired
    turned = @yaw_ref_pelvis - f.joint_angle(body, "pelvis_yaw")
    rate = ~0.0 - f.joint_rate(body, "pelvis_yaw")
    mx = @p_max
    need = @turn_torso
    frac = @pk_torso
    if seg == :torso
      turned = wrap(@yaw_ref_torso - torso_yaw(f))
      rate = ~0.0 - f.at("torso_angvel", 2)
      mx = @t_max
      need = @turn_arms
      frac = @pk_arms
    turned >= need && rate < frac * mx

  # The hands (bottom grip) have passed hands_front m in front of the pelvis
  # toward the mound.
  -> hands_front?(f)
    f.at("pelvis_pos", 1) - f.at("r_hand_pos", 1) >= @hands_front

  -> track_chain(f)
    @pelvis_now = f.joint_angle(body, "pelvis_yaw")
    @torso_now = torso_yaw(f)
    return nil if !@hips_fired
    pr = ~0.0 - f.joint_rate(body, "pelvis_yaw")
    tr = ~0.0 - f.at("torso_angvel", 2)
    @p_max = pr if pr > @p_max
    @t_max = tr if tr > @t_max
    nil

  # The pitcher's delivery has run `t` seconds (the pitch_windup sensor).
  -> delivery(t)
    Latch.test("delivery", ->(f, e, c) f.at("pitch_windup", 0) > ~0.5 && f.at("pitch_windup", 1) >= t)

  -> track_mask(which)
    return body.mask(["pelvis_"] + leg_prefixes) if which == :hips
    return body.mask(["spine_"]) if which == :torso
    body.mask(["l_shoulder", "r_shoulder", "l_elbow", "r_elbow", "l_wrist", "r_wrist"])

  # Hip-shoulder separation (the torso's load chunk): as the pelvis opens
  # past its load angle, spine rotation turns the other way so the shoulders
  # stay closed, up to sep_max; plus the aim correction's spine share.
  -> separation(f, c)
    off = aim_offsets(:release)
    off = zeros if off == nil
    q_load = BatPostures.q_load
    q_load = BatPostures.q_coil if @stride
    q_load = gathered if @stride && @stride_load
    opened = q_load[0] - f.joint_angle(body, "pelvis_yaw")
    dq = clamp(@k_sep * opened, ~0.0, @sep_max)
    joint_offset(off, "spine_rot", dq)

  # ---- seeing the pitch ------------------------------------------------------------

  # [time to the front of the plate, crossing x, crossing z, vertical approach
  # angle there] from the ball's position and velocity: quadratic drag along
  # the path (closed form for the time), straight-line direction, gravity
  # drop over that time. 9.0 s means no pitch is coming.
  -> predict(f)
    vx = f.at("ball_vel", 0)
    vy = f.at("ball_vel", 1)
    vz = f.at("ball_vel", 2)
    return [~9.0, @x_nom, @z_nom, ~0.0] if vy < ~1.0
    dy = @plate_y - f.at("ball_pos", 1)
    sp = Math.sqrt(vx * vx + vy * vy + vz * vz)
    k = ~0.0062
    path = dy * sp / vy
    tau = (Math.exp(k * path) - ~1.0) / (k * sp)
    s = dy / vy
    x = f.at("ball_pos", 0) + vx * s
    z = f.at("ball_pos", 2) + vz * s - ~4.905 * tau * tau
    # at the plate: drag has slowed the ball by exp(-k path); gravity has
    # added -g tau to the vertical speed
    slow = Math.exp(~0.0 - k * path)
    vh = Math.sqrt(vx * vx + vy * vy) * slow
    vzp = vz * slow - ~9.81 * tau
    [tau, x, z, Math.atan2(vzp, vh)]

  -> swing_due?(f, lag, which)
    p = predict(f)
    return false if p[0] > ~8.0
    p[0] <= trigger(lag, which) + @k_in * (@x_nom - p[1])

  -> before(f, ctl)
    track_chain(f)
    retime_lifts(f, ctl) if @lift_via
    retime_loads(f, ctl) if @timed_load
    retime_hips(f, ctl) if @plant_swing
    release_on_around(f, ctl) if @through || @arc
    ease_gains(f, ctl) if @gain_ease || @arc
    brake_limits(f, ctl) if @limit_brake > ~0.0
    p = predict(f)
    coming = p[0] < ~8.0 && p[0] > ~-0.05
    if !coming
      @aiming = false
      @locked = false
      @hips_fired = false
      return nil
    tau = p[0]
    px = p[1]
    pz = p[2]
    if tau > @t_lock
      @lock_z = pz
      @lock_x = px
      @lock_att = @att_bias - p[3]
    if !@aiming
      @aiming = true
      @aim_ticks = 0
    # report the aim point (for the display) every 20 ms until it locks
    if !@locked && @aim_ticks % 4 == 0
      at = @lock_att
      ctl.emit("aim:[tau]:[px]:[pz]:[at]")
    @aim_ticks = @aim_ticks + 1
    if !@locked && tau <= @t_lock
      @locked = true
      lx = @lock_x
      lz = @lock_z
      la = @lock_att
      ctl.emit("aim_lock:[tau]:[lx]:[lz]:[la]")
    nil

  # Contraction offsets that bend the swing toward the predicted crossing
  # (height and in/out) and tilt its plane to the pitch's approach, the
  # tilt through the waypoint's own vector (:release, :contact, :extend).
  -> aim_offsets(wp)
    return nil if !@aiming
    dz = clamp(@lock_z - @z_nom, ~-0.4, ~0.4)
    dx = clamp(@lock_x - @x_nom, ~-0.3, ~0.3)
    names = BatPostures.k_joints
    kz = BatPostures.k_z
    kx = BatPostures.k_x
    if @uppercut
      kz = BatPostures.k_z_u
      kx = BatPostures.k_x_u
    off = zeros
    i = 0
    while i < names.size
      joint_offset(off, names[i], @g_z * kz[i] * dz + @g_x * kx[i] * dx)
      i += 1
    return off if !@uppercut
    da = clamp(@lock_att - @att_nom, ~-0.2, ~0.2) * @g_att
    ka = BatPostures.k_att_release
    ka = BatPostures.k_att_contact if wp == :contact
    ka = BatPostures.k_att_extend if wp == :extend
    names = BatPostures.joints
    i = 0
    while i < names.size
      joint_offset(off, names[i], ka[i] * da)
      i += 1
    off

  # ---- the top hand -------------------------------------------------------------

  # The bat's knob -> tip direction, y component (-1: pointing at the pitcher).
  -> bat_heading(f)
    dx = f.at("bat_tip_pos", 0) - f.at("bat_knob_pos", 0)
    dy = f.at("bat_tip_pos", 1) - f.at("bat_knob_pos", 1)
    dz = f.at("bat_tip_pos", 2) - f.at("bat_knob_pos", 2)
    dy / Math.sqrt(dx * dx + dy * dy + dz * dz)

  -> grip_distance(f)
    x = f.at("grip_err", 0)
    y = f.at("grip_err", 1)
    z = f.at("grip_err", 2)
    Math.sqrt(x * x + y * y + z * z)

  -> reset_regrip
    i = 0
    while i < 6
      @rg[i] = ~0.0
      i += 1
    nil

  # PI servo in hand space: the grip_err vector (hand -> handle) through the
  # arm's pseudo-inverse Jacobian gives joint moves; the integral carries
  # the hand the rest of the way against gravity sag.
  -> regrip_offsets(f)
    e = [f.at("grip_err", 0), f.at("grip_err", 1), f.at("grip_err", 2)]
    jp = BatPostures.regrip_pinv
    names = BatPostures.regrip_joints
    off = zeros
    i = 0
    while i < 6
      dq = jp[3 * i] * e[0] + jp[3 * i + 1] * e[1] + jp[3 * i + 2] * e[2]
      @rg[i] = clamp(@rg[i] + @rg_i * @dt * dq, ~-0.6, ~0.6)
      joint_offset(off, names[i], @rg[i] + @rg_p * dq)
      i += 1
    off
