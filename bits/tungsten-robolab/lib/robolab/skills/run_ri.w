# RunRI: the RunSkill sprint (run.w, unchanged) with reciprocal inhibition.
#
# Erik: "make sure you're using full power in the large muscles in the
# stride." Measured on the P95 top-speed champion, the prime movers reach 1.0
# but the soleus and gastrocnemius are at >= 0.9 for only 11-15 % of the time
# while their antagonists co-contract (mono knee flexors mean 0.73,
# dorsiflexors 0.58). This skill is RunSkill with one addition: with `ri`
# (a params-file switch, k > 0) Controller#set_reciprocal scales each
# antagonist's activation by 1 - k x the drive on its agonist, per leg for
# hip flexors / extensors, knee flexors / vasti, soleus / dorsiflexors,
# rectus femoris / hamstrings and gastrocnemius / dorsiflexors. Full drive on
# the prime movers is RunSkill's own drive tunables at 1.0 (drv_knee,
# drv_ankle, drv_gas, drv_hip, drv_ham in the push; drv_swh, drv_rf in the
# swing), set in the params file. Without `ri` it is RunSkill exactly.
#
# Phase gating (opt-in params-file switches, for the push-through stance of
# the ideal-control analysis, sprint_limits.py):
#   gate_push 1   a push chunk ends on its foot's release only (timeout
#                 t_gate_max, default 0.3 s), not on RunSkill's t_push_max:
#                 the stance pushes until the foot leaves
#   gate_swing 1  the flight chunk's swing drives on the leg that just pushed
#                 (hip flexor drv_swh, knee flexor drv_swk, rectus femoris
#                 drv_rf) are held back while its foot is still loaded, so
#                 they start at the sensed toe-off
#   push_through 1  RunSkill's push chunk times out (t_push_max) before the
#                 foot leaves, so the flight chunk's follow-through pose (a
#                 tucked knee) and swing drives act on a leg still pushing: in
#                 the P95 champion's last ~30 ms of stance the knee flexors
#                 reach 0.6-0.9 and the dorsiflexors 0.4-0.8 while the vasti
#                 fall to ~0.5 (the ideal-control stance keeps the vasti and
#                 soleus near full to lift-off). With push_through the pushing
#                 leg's command waits pt_delay into the flight chunk
#                 (Chunk#stagger) and, while its foot is loaded, it keeps full
#                 drive (pt_drv) on vasti, soleus, gastrocnemius and hip
#                 extensors; combine with gate_swing
#   tcn 1         a residual causal TCN (ConvPolicy, tcn.w, as P6 / P7) adds
#                 joint offsets (hips, knees, ankles, spine; clamped to
#                 +-tcn_max) to the command every tick from ~0.2 s of
#                 proprioception. The hidden layers' weights and the input
#                 normalisation come from the params file (fixed); the head's
#                 weights are declared as tunables (tcn_w<k>, zero = the
#                 controller without the TCN) so search.py trains the head

+ RunRISkill < RunSkill
  -> start(frame, ctl)
    @gate_push = @params.key?("gate_push") && @params["gate_push"] > ~0.5
    @gate_swing = @params.key?("gate_swing") && @params["gate_swing"] > ~0.5
    @t_gate_max = ~0.3
    @t_gate_max = @params["t_gate_max"] if @params.key?("t_gate_max")
    @push_through = @params.key?("push_through") && @params["push_through"] > ~0.5
    super(frame, ctl)
    k = ~0.0
    k = @params["ri"] if @params.key?("ri")
    setup_reciprocal(ctl, k) if k > ~0.0
    self

  -> read_params
    super
    @tcn = nil
    if @params.key?("tcn") && @params["tcn"] > ~0.5
      @tcn_joints = ["l_hip_flex", "l_knee", "l_ankle", "r_hip_flex", "r_knee", "r_ankle", "spine_flex"]
      @tcn = ConvPolicy.new(body, @params, @tcn_joints)
      declare_tcn_head
    @push_through = @params.key?("push_through") && @params["push_through"] > ~0.5
    return self if !@push_through
    @pt_delay = param("pt_delay", ~0.03, ~0.0, ~0.12)
    @pt_drv = param("pt_drv", ~1.0, ~0.0, ~1.0)
    self

  # The TCN head's weights as tunables (the flat vector's tail: W[out][hidden]
  # then b[out]; ConvPolicy's layout).
  -> declare_tcn_head
    hid = ~8.0
    hid = @params["tcn_hidden"] if @params.key?("tcn_hidden")
    h = hid.to_i
    kern = ~3.0
    kern = @params["tcn_kernel"] if @params.key?("tcn_kernel")
    k = kern.to_i
    nl = ~3.0
    nl = @params["tcn_layers"] if @params.key?("tcn_layers")
    nin = 2 * body.joints.size + 7
    start = h * nin * k + h + (nl.to_i - 1) * (h * h * k + h)
    nout = @tcn_joints.size
    lim = ~1.0
    lim = @params["tcn_wlim"] if @params.key?("tcn_wlim")
    i = 0
    while i < nout * h + nout
      param("tcn_w" + (start + i).to_s, ~0.0, ~0.0 - lim, lim)
      i += 1
    self

  -> apply_tcn(frame, ctl)
    x = @tcn.features(frame)
    ctl.emit("tcnx:" + x.join(",")) if @params.key?("tcn_xtrace")
    y = @tcn.step(x)
    off = zeros
    i = 0
    while i < @tcn_joints.size
      joint_offset(off, @tcn_joints[i], y[i])
      i += 1
    m = 0
    while m < off.size
      ctl.add_offset(m, off[m])
      m += 1
    self

  -> flight_chunk(st, sw, pose)
    ch = super(st, sw, pose)
    return ch if !@push_through || @pt_delay < ~0.002
    ch.stagger(body.mask([st + "hip", st + "knee", st + "ankle", st + "toe", st + "rf", st + "ham", st + "gas"]), @pt_delay)
    ch

  -> push_chunk(st, sw, first)
    ch = super(st, sw, first)
    ch.hold_until(Latch.release(st + "foot").after_min(~0.03), @t_gate_max) if @gate_push && !first
    ch

  -> after(frame, ctl)
    super(frame, ctl)
    apply_tcn(frame, ctl) if @tcn != nil && @phase != nil
    if @push_through && @phase == :flight && frame.contact?(@st + "foot", ~0.05)
      ["knee_neg", "ankle_pos", "gas", "hip_flex_neg"].each ->(m)
        ctl.add_drive(body.index(@st + m), @pt_drv) if body.has?(@st + m)
    return self if !@gate_swing || @phase != :flight || !frame.contact?(@st + "foot", ~0.05)
    hold(ctl, @st + "hip_flex_pos", @drv_swh)
    hold(ctl, @st + "knee_pos", @drv_swk)
    hold(ctl, @st + "rf", @drv_rf)
    self

  # Take back a drive the current chunk added.
  -> hold(ctl, name, v)
    ctl.add_drive(body.index(name), ~0.0 - v) if body.has?(name) && v > ~0.0
    self

  -> setup_reciprocal(ctl, k)
    pairs = []
    ["l_", "r_"].each ->(side)
      [["hip_flex_pos", "hip_flex_neg"], ["knee_pos", "knee_neg"], ["ankle_pos", "ankle_neg"], ["rf", "ham"],
       ["gas", "ankle_neg"]].each ->(pr)
        a = index_or(side + pr[0])
        b = index_or(side + pr[1])
        pairs.push([a, b]) if a >= 0 && b >= 0
    ctl.set_reciprocal(pairs, k)
    self
