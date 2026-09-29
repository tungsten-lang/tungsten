# MyoBaodingV3: the baoding skill with a rotating field in place of the timed
# gait. The round-2 gait states (a0..a3, b0..b3) were postures held for
# searched durations, blind to where the balls were: open-loop timing that
# search never got to turn the pair (0.05-0.12 turns in 5 s). Here the
# fingers' posture is a function of the pair's *measured* angle phi, so the
# hand pushes the pair onward from wherever it is:
#
#   dq(phi) = u * (A_s + B_s cos(phi) + C_s sin(phi))       per joint group
#
# over the 14 joint groups (wrist deviation and flexion, the four thumb
# joints, each finger's knuckle and middle joints), with one field per
# turning direction s (`pf<s>_<group>_{a,c,s}`, s = p for counter-clockwise,
# n for clockwise). u in [-1, 1] is the command: the saturated angle error
# u = clamp(k_pf (phi* - phi)) toward the targets (HOLD targets included),
# plus `pf_lead` in the targets' own direction of travel for turning tasks.
# The field rides on the base skill's cup, posture map and synergy (tunable
# to zero), eased in by the chunks' correction spring. `pf_force` (+-1)
# pins u for searching one field on the spin task. With `pf` = 0 this is
# MyoBaodingSkill.

+ MyoBaodingV3Skill < MyoBaodingSkill
  -> start(frame, ctl)
    @pf = param("pf", ~0.0, ~0.0, ~1.0) > ~0.5
    @k_pf = param("k_pf", ~3.0, ~0.0, ~10.0)
    @pf_lead = param("pf_lead", ~0.5, ~0.0, ~1.0)
    # search aid: a fixed command (+1 counter-clockwise field, -1 clockwise)
    @pf_force = param("pf_force", ~0.0, ~-1.0, ~1.0)
    @pfp = []
    @pfn = []
    gnames = ["dev", "flex", "cabd", "cflex", "mp", "ip", "f2", "p2", "f3", "p3", "f4", "p4", "f5", "p5"]
    hs = ["a", "c", "s"]
    if @pf
      i = 0
      while i < 42
        @pfp.push(param("pfp_" + gnames[i / 3] + "_" + hs[i % 3], ~0.0, ~-0.6, ~0.6))
        i += 1
      i = 0
      while i < 42
        @pfn.push(param("pfn_" + gnames[i / 3] + "_" + hs[i % 3], ~0.0, ~-0.6, ~0.6))
        i += 1
    @u_pf = ~0.0
    super(frame, ctl)

  -> synergy_offsets(f)
    off = super(f)
    return off if !@pf || off == nil
    p = phi(f)
    u = clamp(@k_pf * wrap(phi_goal(f) - p), ~-1.0, ~1.0)
    u = clamp(u + @pf_lead * @dir, ~-1.0, ~1.0) if @dir != 0
    u = @pf_force if @pf_force != ~0.0
    @u_pf = u
    field = @pfp
    mag = u
    if u < ~0.0
      field = @pfn
      mag = ~0.0 - u
    cp = Math.cos(p)
    sp = Math.sin(p)
    names = ["deviation", "flexion", "cmc_abduction", "cmc_flexion", "mp_flexion", "ip_flexion"]
    digits = ["2", "2", "3", "3", "4", "4", "5", "5"]
    i = 0
    while i < 14
      dq = mag * (field[3 * i] + field[3 * i + 1] * cp + field[3 * i + 2] * sp)
      if i < 6
        joint_offset(off, names[i], dq)
      else
        d = digits[i - 6]
        if (i - 6) % 2 == 0
          joint_offset(off, "mcp" + d + "_flexion", dq)
        else
          joint_offset(off, "pm" + d + "_flexion", dq)
          joint_offset(off, "md" + d + "_flexion", dq * ~0.7)
      i += 1
    off
