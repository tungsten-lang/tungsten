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
# database.  That is the near-linear path.
#
# Unhinted DRAT is checked with two-watched-literal propagation over the
# live database.  Watches are chosen among non-false literals, so undoing
# an assignment never invalidates a watch: between proof steps the checker
# clears the trail and the watch structure carries over untouched.  Each
# step therefore costs work proportional to the clauses actually visited,
# not to the size of the database — the previous full-fixpoint reference
# loop made large plain-DRAT proofs quadratic and unusable in practice.
# Deletions are indexed by sorted literal content, replacing the previous
# full-database scan per delete line.

use dimacs
use proof

+ WratChecker
  -> new(@nvars)
    @assign = []      # index by variable: 0 unassigned, 1 true, -1 false
    @trail = []
    @qhead = 0
    i = 0
    while i <= @nvars
      @assign.push(0)
      i += 1

    # Clause storage, one slot per added clause (live or dead).
    @clits = []       # slot -> Array of literals
    @alive = []       # slot -> 1 live, 0 dead
    @cid = []         # slot -> proof id
    @wa = []          # slot -> first watched literal (0 if unit/empty)
    @wb = []          # slot -> second watched literal (0 if unit/empty)

    @slot_of = {}     # proof id -> slot
    @ids = []         # insertion order of ids (live filter via @slot_of/@alive)
    @next_id = 1

    @units = []       # slots of clauses stored as single-literal
    @empty_live = 0   # count of live empty clauses in the database

    # watch lists: literal l -> bucket at index l + @nvars
    @watch = []
    i = 0
    while i <= 2 * @nvars
      @watch.push([])
      i += 1

    # sorted-content key -> slots in insertion order (for DRAT deletes)
    @key_slots = {}

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
    @qhead = 0

  # ---- clause database ----------------------------------------------------

  -> content_key(lits)
    lits.sort.join(",")

  -> add_clause(lits, id)
    cid = id > 0 ? id : @next_id
    @next_id = cid + 1 if cid >= @next_id
    slot = @clits.size
    @clits.push(lits)
    @alive.push(1)
    @cid.push(cid)
    @wa.push(0)
    @wb.push(0)
    @slot_of[cid] = slot
    @ids.push(cid)

    key = self.content_key(lits)
    @key_slots[key] = [] unless @key_slots.has_key?(key)
    @key_slots[key].push(slot)

    if lits.empty?
      @empty_live += 1
    else
      # Pick two watches with distinct literal values; duplicated literals
      # degrade to the unit case, which keeps the watch invariant honest.
      first = lits[0]
      second = 0
      j = 1
      while j < lits.size && second == 0
        second = lits[j] if lits[j] != first
        j += 1
      if second == 0
        @units.push(slot)
      else
        @wa[slot] = first
        @wb[slot] = second
        @watch[first + @nvars].push(slot)
        @watch[second + @nvars].push(slot)
    cid

  -> kill_slot(slot)
    @alive[slot] = 0
    @empty_live -= 1 if @clits[slot].empty?
    # Watch lists and @units drop dead slots lazily during traversal.

  -> delete_id(cid)
    if @slot_of.has_key?(cid)
      slot = @slot_of[cid]
      if @alive[slot] == 1
        self.kill_slot(slot)
        true
      else
        false
    else
      false

  # DRAT deletes by literal content; drop the first structural match in
  # insertion order.  Array `==` is identity in Tungsten, so clauses are
  # keyed by their sorted join -- comparing arrays directly would never
  # match.
  -> delete_lits(lits)
    key = self.content_key(lits)
    hit = -1
    if @key_slots.has_key?(key)
      bucket = @key_slots[key]
      j = 0
      while j < bucket.size && hit < 0
        hit = bucket[j] if @alive[bucket[j]] == 1
        j += 1
    if hit < 0
      false
    else
      self.kill_slot(hit)
      true

  -> live_ids
    out = []
    @ids.each -> (cid)
      slot = @slot_of[cid]
      out.push(cid) if @alive[slot] == 1
    out

  # Look up a live clause by proof id (hinted path); [] when absent.
  -> lits_for_id(cid)
    if @slot_of.has_key?(cid)
      slot = @slot_of[cid]
      @alive[slot] == 1 ? @clits[slot] : []
    else
      []

  # ---- propagation --------------------------------------------------------

  # Evaluate a clause under the current assignment (hinted/RAT paths).
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

  # Two-watched-literal propagation to fixpoint from the current trail.
  # Returns true on conflict.
  -> propagate
    conflict = @empty_live > 0

    # Live unit clauses fire first: nothing watches them.
    ui = 0
    while ui < @units.size && !conflict
      slot = @units[ui]
      if @alive[slot] == 1
        l = @clits[slot][0]
        v = self.value(l)
        if v < 0
          conflict = true
        elsif v == 0
          self.assign_lit(l)
      ui += 1

    while @qhead < @trail.size && !conflict
      lit = @trail[@qhead]
      @qhead += 1
      bucket = @watch[(0 - lit) + @nvars]
      i = 0
      while i < bucket.size && !conflict
        slot = bucket[i]
        if @alive[slot] == 0
          bucket[i] = bucket[bucket.size - 1]
          bucket.pop
        else
          # Normalise: @wb[slot] is the watch being falsified.
          if @wa[slot] == 0 - lit
            @wa[slot] = @wb[slot]
            @wb[slot] = 0 - lit
          other = @wa[slot]
          if self.value(other) > 0
            i += 1
          else
            lits = @clits[slot]
            found = 0
            j = 0
            while j < lits.size && found == 0
              cand = lits[j]
              found = cand if cand != other && cand != (0 - lit) && self.value(cand) >= 0
              j += 1
            if found != 0
              @wb[slot] = found
              @watch[found + @nvars].push(slot)
              bucket[i] = bucket[bucket.size - 1]
              bucket.pop
            elsif self.value(other) == 0
              self.assign_lit(other)
              i += 1
            else
              conflict = true
    conflict

  # Replay a hint chain. Returns true if it ends in a conflict.
  -> propagate_hints(hints)
    conflict = false
    ok = true
    hints.each -> (cid)
      if ok && !conflict
        lits = self.lits_for_id(cid)
        if lits.empty? && !(@slot_of.has_key?(cid) && @alive[@slot_of[cid]] == 1)
          ok = false
        else
          info = self.classify(lits)
          if info["unassigned"] == 0 && !info["sat"]
            conflict = true
          elsif info["unassigned"] == 1 && !info["sat"]
            self.assign_lit(info["unit"])
          else
            # A hint that is satisfied or still ambiguous is not a valid
            # step in a propagation chain.
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
      result = self.propagate
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
          other = @clits[@slot_of[cid]]
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
