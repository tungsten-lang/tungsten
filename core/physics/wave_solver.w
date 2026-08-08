# Lax–Friedrichs (local, two-wave) approximate Riemann solver and minmod
# reconstruction, in fluctuation form.
#
# The local Lax-Friedrichs wave family splits the state jump into two waves
#     w1 = ½(ΔU − ΔF/a_max),   w2 = ½(ΔU + ΔF/a_max)
# travelling at speeds ∓a_max, where a_max is the largest absolute
# characteristic speed of either side. The fluctuations
#     A⁻ΔU = Σ wᵢ·min(sᵢ,0),   A⁺ΔU = Σ wᵢ·max(sᵢ,0)
# satisfy the flux-jump identity A⁻ΔU + A⁺ΔU = F(U_R) − F(U_L).
# `fluctuations_valid?` checks it with a scale-aware numerical tolerance.
#
# Minmod reconstruction produces one-sided cell-edge states
#     U∓ = U ∓ ½·minmod(U − U_L, U_R − U)
# with minmod(a,b) = max(0, min(a,b)) + min(0, max(a,b)).

+ LaxFriedrichs
  -> .within_tolerance?(left, right, tolerance)
    return false if !EulerSystem.finite_number?(tolerance)
    return false if tolerance < ~0.0
    return false if !EulerSystem.finite_number?(left)
    return false if !EulerSystem.finite_number?(right)
    scale = left.abs
    scale = right.abs if right.abs > scale
    scale = ~1.0 if scale < ~1.0
    (left - right).abs <= tolerance * scale

  -> .valid_inputs?(sys, ul, ur, dir, tolerance)
    return false if !EulerSystem.finite_number?(tolerance)
    return false if tolerance < ~0.0
    return false if !sys.direction_valid?(dir)
    sys.state_valid?(ul) && sys.state_valid?(ur)

  # Largest absolute wavespeed of either state — the LF viscosity.
  -> .amax(sys, ul, ur, dir)
    sys.validate_direction(dir)
    sys.validate_state(ul)
    sys.validate_state(ur)
    a = sys.max_wavespeed(ul, dir)
    b = sys.max_wavespeed(ur, dir)
    result = a > b ? a : b
    if !EulerSystem.finite_number?(result) || result <= ~0.0
      raise "LaxFriedrichs: maximum wavespeed must be positive and finite"
    result

  # Two-wave decomposition of the jump ur − ul. Returns [wave1, wave2].
  -> .wave_family(sys, ul, ur, dir)
    a = LaxFriedrichs.amax(sys, ul, ur, dir)
    fl = sys.flux(ul, dir)
    fr = sys.flux(ur, dir)
    wave1 = []
    wave2 = []
    k = 0
    while k < sys.nstate
      du = ur[k] - ul[k]
      df = (fr[k] - fl[k]) / a
      wave1.push(~0.5 * (du - df))
      wave2.push(~0.5 * (du + df))
      k = k + 1
    [wave1, wave2]

  # Wave speeds [−a_max, +a_max].
  -> .speed_family(sys, ul, ur, dir)
    a = LaxFriedrichs.amax(sys, ul, ur, dir)
    [~0.0 - a, a]

  # A⁻ΔU: the left-going part of the flux jump.
  -> .left_fluctuation(sys, ul, ur, dir)
    waves = LaxFriedrichs.wave_family(sys, ul, ur, dir)
    speeds = LaxFriedrichs.speed_family(sys, ul, ur, dir)
    s1 = speeds[0] < ~0.0 ? speeds[0] : ~0.0
    s2 = speeds[1] < ~0.0 ? speeds[1] : ~0.0
    out = []
    k = 0
    while k < sys.nstate
      out.push(waves[0][k] * s1 + waves[1][k] * s2)
      k = k + 1
    out

  # A⁺ΔU: the right-going part of the flux jump.
  -> .right_fluctuation(sys, ul, ur, dir)
    waves = LaxFriedrichs.wave_family(sys, ul, ur, dir)
    speeds = LaxFriedrichs.speed_family(sys, ul, ur, dir)
    s1 = speeds[0] > ~0.0 ? speeds[0] : ~0.0
    s2 = speeds[1] > ~0.0 ? speeds[1] : ~0.0
    out = []
    k = 0
    while k < sys.nstate
      out.push(waves[0][k] * s1 + waves[1][k] * s2)
      k = k + 1
    out

  # -- numerical identity predicates --------------------------------------

  # Zero jump must produce (numerically) zero waves.
  -> .waves_consistent?(sys, u, dir, tolerance = ~1.0e-8)
    return false if !LaxFriedrichs.valid_inputs?(sys, u, u, dir, tolerance)
    waves = LaxFriedrichs.wave_family(sys, u, u, dir)
    k = 0
    while k < sys.nstate
      return false if !LaxFriedrichs.within_tolerance?(
        waves[0][k], ~0.0, tolerance)
      return false if !LaxFriedrichs.within_tolerance?(
        waves[1][k], ~0.0, tolerance)
      k = k + 1
    true

  # The waves must sum to the state jump.
  -> .waves_valid?(sys, ul, ur, dir, tolerance = ~1.0e-8)
    return false if !LaxFriedrichs.valid_inputs?(
      sys, ul, ur, dir, tolerance)
    waves = LaxFriedrichs.wave_family(sys, ul, ur, dir)
    k = 0
    while k < sys.nstate
      jump = ur[k] - ul[k]
      total = waves[0][k] + waves[1][k]
      return false if !LaxFriedrichs.within_tolerance?(
        jump, total, tolerance)
      k = k + 1
    true

  # Zero jump must produce zero fluctuations.
  -> .fluctuations_consistent?(sys, u, dir, tolerance = ~1.0e-8)
    return false if !LaxFriedrichs.valid_inputs?(sys, u, u, dir, tolerance)
    left = LaxFriedrichs.left_fluctuation(sys, u, u, dir)
    right = LaxFriedrichs.right_fluctuation(sys, u, u, dir)
    k = 0
    while k < sys.nstate
      return false if !LaxFriedrichs.within_tolerance?(
        left[k], ~0.0, tolerance)
      return false if !LaxFriedrichs.within_tolerance?(
        right[k], ~0.0, tolerance)
      k = k + 1
    true

  # Flux-jump identity: A⁻ΔU + A⁺ΔU = F(U_R) − F(U_L).
  -> .fluctuations_valid?(sys, ul, ur, dir, tolerance = ~1.0e-8)
    return false if !LaxFriedrichs.valid_inputs?(
      sys, ul, ur, dir, tolerance)
    fl = sys.flux(ul, dir)
    fr = sys.flux(ur, dir)
    left = LaxFriedrichs.left_fluctuation(sys, ul, ur, dir)
    right = LaxFriedrichs.right_fluctuation(sys, ul, ur, dir)
    k = 0
    while k < sys.nstate
      flux_jump = fr[k] - fl[k]
      total = left[k] + right[k]
      return false if !LaxFriedrichs.within_tolerance?(
        flux_jump, total, tolerance)
      k = k + 1
    true

+ Minmod
  -> .validate_states(ul, u, ur)
    if (ul.class_name != "Array" || u.class_name != "Array" ||
        ur.class_name != "Array" || u.size == 0 ||
        ul.size != u.size || ur.size != u.size)
      raise "Minmod: states must be equal nonempty Arrays"
    i = 0
    while i < u.size
      if (!EulerSystem.finite_number?(ul[i]) ||
          !EulerSystem.finite_number?(u[i]) ||
          !EulerSystem.finite_number?(ur[i]))
        raise "Minmod: state entries must be finite numbers"
      i += 1
    true

  # minmod(a, b) = max(0, min(a, b)) + min(0, max(a, b)) — picks the
  # smaller-magnitude slope when signs agree, zero when they disagree.
  -> .slope(a, b)
    if (!EulerSystem.finite_number?(a) || !EulerSystem.finite_number?(b))
      raise "Minmod: slope inputs must be finite numbers"
    small = a < b ? a : b
    large = a > b ? a : b
    positive = small > ~0.0 ? small : ~0.0
    negative = large < ~0.0 ? large : ~0.0
    positive + negative

  # Left cell-edge state: U − ½·minmod(U − U_L, U_R − U), per component.
  -> .left(ul, u, ur)
    Minmod.validate_states(ul, u, ur)
    out = []
    k = 0
    while k < u.size
      out.push(u[k] - ~0.5 * Minmod.slope(u[k] - ul[k], ur[k] - u[k]))
      k = k + 1
    out

  # Right cell-edge state: U + ½·minmod(U − U_L, U_R − U), per component.
  -> .right(ul, u, ur)
    Minmod.validate_states(ul, u, ur)
    out = []
    k = 0
    while k < u.size
      out.push(u[k] + ~0.5 * Minmod.slope(u[k] - ul[k], ur[k] - u[k]))
      k = k + 1
    out

  # Flat data must reconstruct to itself.
  -> .left_consistent?(u, tolerance = ~1.0e-8)
    return false if !EulerSystem.finite_number?(tolerance)
    return false if tolerance < ~0.0
    rec = Minmod.left(u, u, u)
    k = 0
    while k < u.size
      return false if !LaxFriedrichs.within_tolerance?(
        rec[k], u[k], tolerance)
      k = k + 1
    true

  -> .right_consistent?(u, tolerance = ~1.0e-8)
    return false if !EulerSystem.finite_number?(tolerance)
    return false if tolerance < ~0.0
    rec = Minmod.right(u, u, u)
    k = 0
    while k < u.size
      return false if !LaxFriedrichs.within_tolerance?(
        rec[k], u[k], tolerance)
      k = k + 1
    true
