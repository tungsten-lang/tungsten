# The proof checker.
#
# Every step of a refutation must be redundant with respect to the clauses
# already accepted.  Two redundancy tests are implemented:
#
#   RUP  (reverse unit propagation) -- assume the negation of the clause and
#        unit-propagate; the clause is redundant if that yields a conflict.
#   RAT  (resolution asymmetric tautology) -- if RUP fails, every resolvent
#        on the pivot literal must itself be RUP.
#
# With hints (WRAT/LRAT) the checker never searches: it replays exactly the
# clauses the solver names, in order, which makes a check cost the total
# length of the hinted clauses rather than a fixpoint over the whole
# database.  That is the near-linear path.  Unhinted DRAT falls back to
# propagating the entire database to a fixpoint, which is correct but is a
# reference implementation, not a fast one.


use dimacs
use proof

+ WratChecker
  -> new(@nvars)
    @db = {}          # live clauses: id -> Array of literals
    @ids = []         # insertion order of live ids
    @next_id = 1
    @assign = []      # index by variable: 0 unassigned, 1 true, -1 false
    @trail = []
    i = 0
    while i <= @nvars
      @assign.push(0)
      i += 1

  # ---- assignment helpers -------------------------------------------------

  -> value(lit)
    v = @assign[lit.abs]
    lit > 0 ? v : 0 - v

  -> assign_lit(lit)
    @assign[lit.abs] = lit > 0 ? 1 : -1
    @trail.push(lit)

  -> undo_all
    @trail.each -> (lit)
      @assign[lit.abs] = 0
    @trail = []

  # ---- clause database ----------------------------------------------------

  -> add_clause(lits, id)
    cid = id > 0 ? id : @next_id
    @next_id = cid + 1 if cid >= @next_id
    @db[cid] = lits
    @ids.push(cid)
    cid

  -> delete_id(cid)
    if @db.has_key?(cid)
      @db.delete(cid)
      true
    else
      false

  # DRAT deletes by literal content; drop the first structural match.
  # Array `==` is identity in Tungsten, so clauses are compared by their
  # sorted join -- comparing the arrays directly would never match.
  -> delete_lits(lits)
    want = lits.sort.join(",")
    hit = 0
    @ids.each -> (cid)
      if hit == 0 && @db.has_key?(cid)
        hit = cid if @db[cid].sort.join(",") == want
    hit == 0 ? false : self.delete_id(hit)

  -> live_ids
    out = []
    @ids.each -> (cid)
      out.push(cid) if @db.has_key?(cid)
    out

  # ---- propagation --------------------------------------------------------

  # Evaluate a clause under the current assignment.
  # Returns {"sat", "unassigned", "unit"} where "unit" is the sole
  # unassigned literal when exactly one remains.
  -> classify(lits)
    sat = false
    unassigned = 0
    unit = 0
    lits.each -> (l)
      v = self.value(l)
      if v > 0
        sat = true
      elsif v == 0
        unassigned += 1
        unit = l
    { "sat": sat, "unassigned": unassigned, "unit": unit }

  # Propagate the whole database to a fixpoint. Returns true on conflict.
  -> propagate_all
    conflict = false
    changed = true
    while changed && !conflict
      changed = false
      self.live_ids.each -> (cid)
        unless conflict
          info = self.classify(@db[cid])
          unless info["sat"]
            if info["unassigned"] == 0
              conflict = true
            elsif info["unassigned"] == 1
              self.assign_lit(info["unit"])
              changed = true
    conflict

  # Replay a hint chain. Returns true if it ends in a conflict.
  -> propagate_hints(hints)
    conflict = false
    ok = true
    hints.each -> (cid)
      if ok && !conflict
        if @db.has_key?(cid)
          info = self.classify(@db[cid])
          if info["unassigned"] == 0 && !info["sat"]
            conflict = true
          elsif info["unassigned"] == 1 && !info["sat"]
            self.assign_lit(info["unit"])
          else
            # A hint that is satisfied or still ambiguous is not a valid
            # step in a propagation chain.
            ok = false
        else
          ok = false
    conflict

  # ---- redundancy tests ---------------------------------------------------

  # Assume the negation of `lits`; returns false if that is already
  # contradictory at assumption time (which counts as a conflict).
  -> assume_negation(lits)
    conflict = false
    lits.each -> (l)
      v = self.value(l)
      if v > 0
        conflict = true      # clause is already satisfied by an assumption
      elsif v == 0
        self.assign_lit(0 - l)
    conflict

  -> rup?(lits, hints)
    self.undo_all
    immediate = self.assume_negation(lits)
    result = false
    if immediate
      result = true
    elsif hints.empty?
      result = self.propagate_all
    else
      result = self.propagate_hints(hints)
    self.undo_all
    result

  # RAT on the first literal: every resolvent on the pivot must be RUP.
  -> rat?(lits)
    ok = false
    unless lits.empty?
      pivot = lits[0]
      ok = true
      self.live_ids.each -> (cid)
        if ok
          other = @db[cid]
          if other.include?(0 - pivot)
            resolvent = []
            lits.each -> (l)
              resolvent.push(l)
            other.each -> (l)
              resolvent.push(l) unless l == (0 - pivot) || resolvent.include?(l)
            ok = false unless self.rup?(resolvent, [])
    ok

  # ---- driver -------------------------------------------------------------

  # Check a parsed proof against the loaded formula.
  # Returns {"verified", "reason", "steps", "empty_clause"}.
  -> check(steps)
    verified = false
    reason = "proof ended without deriving the empty clause"
    done = false
    count = 0

    steps.each -> (st)
      unless done
        if st["kind"] == "d"
          if st["hints"].empty?
            self.delete_lits(st["lits"])
          else
            st["hints"].each -> (cid)
              self.delete_id(cid)
        else
          lits = st["lits"]
          count += 1
          if self.rup?(lits, st["hints"])
            self.add_clause(lits, st["id"])
            if lits.empty?
              verified = true
              reason = "empty clause derived"
              done = true
          elsif st["hints"].empty? && self.rat?(lits)
            self.add_clause(lits, st["id"])
          else
            reason = "step [count] is not redundant: [lits.join(" ")]"
            done = true

    { "verified": verified, "reason": reason, "steps": count }

# Build a checker preloaded with a formula.
-> wrat_checker_for(formula)
  ck = WratChecker.new(formula["nvars"])
  formula["clauses"].each -> (c)
    ck.add_clause(c, 0)
  ck

# Check proof text against CNF text. Returns the checker's result record.
-> wrat_verify(cnf_text, proof_text)
  formula = wrat_parse_cnf(cnf_text)
  parsed = wrat_parse_proof(proof_text)
  ck = wrat_checker_for(formula)
  result = ck.check(parsed["steps"])
  result["format"] = parsed["format"]
  result
