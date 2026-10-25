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
use stream

+ WratChecker
  ro :nvars, :track_content_keys, :assign, :trail, :qhead
  ro :clits, :alive, :cid, :wa, :wb, :watch_ready
  ro :slot_by_id, :slot_of, :ids, :next_id, :units, :empty_live, :watch, :key_slots
  ro :live_clauses, :live_literals, :peak_live_clauses, :peak_live_literals
  ro :check_verified, :check_reason, :check_done, :check_count

  -> new(@nvars, @track_content_keys = true)
    @assign = Array.new(@nvars + 1, 0) # index by variable: 0 unassigned, 1 true, -1 false
    @trail = []
    @qhead = 0

    # Clause storage, one slot per added clause (live or dead).
    @clits = []       # slot -> Array of literals
    @alive = []       # slot -> 1 live, 0 dead
    @cid = []         # slot -> proof id
    @wa = []          # slot -> first watched literal (0 if unit/empty)
    @wb = []          # slot -> second watched literal (0 if unit/empty)
    @watch_ready = false

    @slot_by_id = [-1] # dense proof id -> slot (-1 when unused)
    @slot_of = {}      # sparse proof id -> slot fallback
    @ids = []          # insertion order of ids (live filter via slot/@alive)
    @next_id = 1

    @units = []       # slots of clauses stored as single-literal
    @empty_live = 0   # count of live empty clauses in the database

    # Watch lists are built lazily.  A hinted proof normally never performs
    # database-wide propagation, so eagerly duplicating every clause slot into
    # watches is pure memory overhead on the common WRAT/LRAT path.
    @watch = []

    # Sorted-content keys are needed only for DRAT's delete-by-literals form.
    # WRAT/LRAT delete by id and must not pay for a sorted copy plus a String
    # key for every formula and learned clause.
    @key_slots = {}

    # Logical storage counters are reported by --stats.  Tungsten Flame
    # remains the source of allocator-level measurements; these counters make
    # database growth and the effect of deletions visible without profiling.
    @live_clauses = 0
    @live_literals = 0
    @peak_live_clauses = 0
    @peak_live_literals = 0

  # ---- assignment helpers -------------------------------------------------

  -> value(lit)
    v = @assign[lit > 0 ? lit : 0 - lit]
    lit > 0 ? v : 0 - v

  -> assign_lit(lit)
    if lit > 0
      @assign[lit] = 1
    else
      @assign[0 - lit] = -1
    @trail.push(lit)

  -> undo_all
    trail = @trail
    assign = @assign
    i = 0
    n = trail.size
    while i < n
      lit = trail[i]
      assign[lit > 0 ? lit : 0 - lit] = 0
      i += 1
    # Tungsten intentionally has no tracing collector in this runtime.  A new
    # trail Array per proof step therefore remains resident until exit; reuse
    # the buffer across the complete replay.
    trail.pop while trail.size > 0
    @qhead = 0

  # ---- clause database ----------------------------------------------------

  -> content_key(lits)
    lits.sort.join(",")

  -> index_watches(slot, lits)
    if lits.empty?
      # @empty_live is maintained independent of watch construction.
      nil
    else
      first = lits[0]
      second = 0
      j = 1
      n = lits.size
      while j < n && second == 0
        lj = lits[j]
        second = lj if lj != first
        j += 1
      if second == 0
        @units.push(slot)
      else
        @wa[slot] = first
        @wb[slot] = second
        nvars = @nvars
        @watch[first + nvars].push(slot)
        @watch[second + nvars].push(slot)

  -> prepare_watches
    return nil if @watch_ready
    @watch = []
    i = 0
    limit = 2 * @nvars
    while i <= limit
      @watch.push([])
      i += 1
    nslots = @clits.size
    @wa = Array.new(nslots, 0)
    @wb = Array.new(nslots, 0)
    @units = []
    slot = 0
    while slot < nslots
      self.index_watches(slot, @clits[slot]) if @alive[slot] == 1
      slot += 1
    @watch_ready = true

  -> slot_for_id(cid)
    if cid > 0 && cid < @slot_by_id.size
      @slot_by_id[cid]
    elsif @slot_of.has_key?(cid)
      @slot_of[cid]
    else
      -1

  -> add_clause(lits, id)
    cid = id > 0 ? id : @next_id
    @next_id = cid + 1 if cid >= @next_id
    slot = @clits.size
    @clits.push(lits)
    @alive.push(1)
    @cid.push(cid)
    sby = @slot_by_id
    if cid == sby.size
      sby.push(slot)
    elsif cid > 0 && cid < sby.size
      sby[cid] = slot
    elsif cid > 0 && cid <= sby.size + 1024
      while sby.size < cid
        sby.push(-1)
      sby.push(slot)
    else
      @slot_of[cid] = slot
    @ids.push(cid)

    @live_clauses += 1
    @live_literals += lits.size
    @peak_live_clauses = @live_clauses if @live_clauses > @peak_live_clauses
    @peak_live_literals = @live_literals if @live_literals > @peak_live_literals

    if @track_content_keys
      key = self.content_key(lits)
      @key_slots[key] = [] unless @key_slots.has_key?(key)
      @key_slots[key].push(slot)

    if lits.empty?
      @empty_live += 1
    if @watch_ready
      @wa.push(0)
      @wb.push(0)
      self.index_watches(slot, lits)
    cid

  -> kill_slot(slot)
    lits = @clits[slot]
    @alive[slot] = 0
    @empty_live -= 1 if lits.empty?
    @live_clauses -= 1
    @live_literals -= lits.size
    # Dead literal arrays are never consulted again.  Releasing them here
    # bounds resident clause storage when a proof contains deletion records;
    # slot/id/watch tables retain the stable identity needed by lazy cleanup.
    @clits[slot] = []
    # Watch lists and @units drop dead slots lazily during traversal.

  -> delete_id(cid)
    slot = self.slot_for_id(cid)
    if slot >= 0 && @alive[slot] == 1
      self.kill_slot(slot)
      true
    else
      false

  # DRAT deletes by literal content; drop the first structural match in
  # insertion order.  Array `==` is identity in Tungsten, so clauses are
  # keyed by their sorted join -- comparing arrays directly would never
  # match.
  -> delete_lits(lits)
    return false unless @track_content_keys
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
      slot = self.slot_for_id(cid)
      out.push(cid) if slot >= 0 && @alive[slot] == 1
    out

  # Look up a live clause by proof id (hinted path); nil when absent.  Empty
  # live clauses remain distinguishable as [] without a second Hash lookup.
  -> lits_for_id(cid)
    slot = self.slot_for_id(cid)
    slot >= 0 && @alive[slot] == 1 ? @clits[slot] : nil

  # ---- propagation --------------------------------------------------------

  # Two-watched-literal propagation to fixpoint from the current trail.
  # Returns true on conflict.
  -> propagate
    self.prepare_watches
    conflict = @empty_live > 0
    assign = @assign
    trail = @trail
    alive = @alive
    clits = @clits
    wa = @wa
    wb = @wb
    watch = @watch
    nvars = @nvars
    units = @units

    # Live unit clauses fire first: nothing watches them.
    ui = 0
    usize = units.size
    while ui < usize && !conflict
      slot = units[ui]
      if alive[slot] == 1
        l = clits[slot][0]
        v = l > 0 ? assign[l] : 0 - assign[0 - l]
        if v < 0
          conflict = true
        elsif v == 0
          if l > 0
            assign[l] = 1
          else
            assign[0 - l] = -1
          trail.push(l)
      ui += 1

    while @qhead < trail.size && !conflict
      lit = trail[@qhead]
      @qhead += 1
      neg_lit = 0 - lit
      bucket = watch[neg_lit + nvars]
      i = 0
      while i < bucket.size && !conflict
        slot = bucket[i]
        if alive[slot] == 0
          bucket[i] = bucket[bucket.size - 1]
          bucket.pop
        else
          # Normalise: wb[slot] is the watch being falsified.
          if wa[slot] == neg_lit
            wa[slot] = wb[slot]
            wb[slot] = neg_lit
          other = wa[slot]
          other_v = other > 0 ? assign[other] : 0 - assign[0 - other]
          if other_v > 0
            i += 1
          else
            lits = clits[slot]
            found = 0
            j = 0
            lsize = lits.size
            while j < lsize && found == 0
              cand = lits[j]
              if cand != other && cand != neg_lit
                cand_v = cand > 0 ? assign[cand] : 0 - assign[0 - cand]
                found = cand if cand_v >= 0
              j += 1
            if found != 0
              wb[slot] = found
              watch[found + nvars].push(slot)
              bucket[i] = bucket[bucket.size - 1]
              bucket.pop
            elsif other_v == 0
              if other > 0
                assign[other] = 1
              else
                assign[0 - other] = -1
              trail.push(other)
              i += 1
            else
              conflict = true
    conflict

  # Replay a hint chain. Returns true if it ends in a conflict.
  -> propagate_hints(hints)
    conflict = false
    ok = true
    hi = 0
    hsize = hints.size
    assign = @assign
    trail = @trail
    sby = @slot_by_id
    sbysize = sby.size
    alive = @alive
    clits = @clits
    while hi < hsize
      cid = hints[hi]
      if ok && !conflict
        slot = (cid > 0 && cid < sbysize) ? sby[cid] : self.slot_for_id(cid)
        lits = (slot >= 0 && alive[slot] == 1) ? clits[slot] : nil
        if lits == nil
          ok = false
        else
          # Keep classification scalar.  The former Hash result allocated one
          # object (plus keys/slots) for every replayed hint; on a large proof
          # with millions of citations those temporaries dominated RSS.
          sat = false
          unassigned = 0
          unit = 0
          li = 0
          lsize = lits.size
          while li < lsize
            l = lits[li]
            if l > 0
              v = assign[l]
            else
              v = 0 - assign[0 - l]
            if v > 0
              sat = true
            elsif v == 0
              unassigned += 1
              unit = l
            li += 1
          if unassigned == 0 && !sat
            conflict = true
          elsif unassigned == 1 && !sat
            if unit > 0
              assign[unit] = 1
            else
              assign[0 - unit] = -1
            trail.push(unit)
          else
            # A hint that is satisfied or still ambiguous is not a valid
            # step in a propagation chain.
            ok = false
      hi += 1
    conflict

  # ---- redundancy tests ---------------------------------------------------

  # Assume the negation of `lits`; returns false if that is already
  # contradictory at assumption time (which counts as a conflict).
  -> assume_negation(lits)
    conflict = false
    assign = @assign
    trail = @trail
    i = 0
    n = lits.size
    while i < n
      l = lits[i]
      if l > 0
        v = assign[l]
      else
        v = 0 - assign[0 - l]
      if v > 0
        conflict = true      # clause is already satisfied by an assumption
      elsif v == 0
        neg_l = 0 - l
        if neg_l > 0
          assign[neg_l] = 1
        else
          assign[0 - neg_l] = -1
        trail.push(neg_l)
      i += 1
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
          other = @clits[self.slot_for_id(cid)]
          if other.include?(0 - pivot)
            resolvent = []
            lits.each -> (l)
              resolvent.push(l)
            other.each -> (l)
              resolvent.push(l) unless l == (0 - pivot) || resolvent.include?(l)
            ok = false unless self.rup?(resolvent, [])
    ok

  # ---- driver -------------------------------------------------------------

  -> start_check
    @check_verified = false
    @check_reason = "proof ended without deriving the empty clause"
    @check_done = false
    @check_count = 0

  -> consume_step(kind, id, lits, hints)
    return nil if @check_done
    if kind == "d"
      if hints.empty?
        self.delete_lits(lits)
      else
        hints.each -> (cid)
          self.delete_id(cid)
    else
      @check_count += 1
      if self.rup?(lits, hints)
        self.add_clause(lits, id)
        if lits.empty?
          @check_verified = true
          @check_reason = "empty clause derived"
          @check_done = true
      elsif hints.empty? && self.rat?(lits)
        self.add_clause(lits, id)
      else
        @check_reason = "step [@check_count] is not redundant: [lits.join(" ")]"
        @check_done = true

  -> check_result
    {
      "verified": @check_verified,
      "reason": @check_reason,
      "steps": @check_count,
      "clauses_added": @clits.size,
      "live_clauses": @live_clauses,
      "live_literals": @live_literals,
      "peak_live_clauses": @peak_live_clauses,
      "peak_live_literals": @peak_live_literals,
    }

  # Compatibility path for callers that already hold parsed step records.
  -> check(steps)
    self.start_check
    steps.each -> (st)
      self.consume_step(st["kind"], st["id"], st["lits"], st["hints"])
    self.check_result

  # Allocation-bounded path: replay one record at a time.  Continue scanning
  # after the empty clause or a failed step so malformed trailing bytes cannot
  # hide behind an otherwise valid prefix.
  -> check_stream(scanner)
    self.start_check
    while scanner.advance
      self.consume_step(scanner.kind, scanner.id, scanner.lits, scanner.hints)
    result = self.check_result
    result["records"] = scanner.records
    result["literal_tokens"] = scanner.literal_tokens
    result["hint_tokens"] = scanner.hint_tokens
    result["peak_record_literals"] = scanner.peak_record_literals
    result["peak_record_hints"] = scanner.peak_record_hints
    result

# Build a checker preloaded with a formula.
-> wrat_checker_for(formula, format = "drat")
  drat = format == "drat"
  ck = WratChecker.new(formula["nvars"], drat)
  formula["clauses"].each -> (c)
    ck.add_clause(c, 0)
  ck.prepare_watches if drat
  ck

# Check proof text against CNF text. Returns the checker's result record.
-> wrat_verify(cnf_text, proof_text)
  formula = wrat_parse_cnf(cnf_text)
  scanner = wrat_scanner_for_text(proof_text)
  ck = wrat_checker_for(formula, scanner.format)
  result = ck.check_stream(scanner)
  result["format"] = scanner.format
  result["proof_version"] = scanner.version
  result["proof_bytes"] = scanner.bytesize
  result

# Check a borrowed mmap without copying or retaining the proof body.
-> wrat_verify_mmap(cnf_text, proof_mapping)
  formula = wrat_parse_cnf(cnf_text)
  scanner = wrat_scanner_for_mmap(proof_mapping)
  ck = wrat_checker_for(formula, scanner.format)
  result = ck.check_stream(scanner)
  result["format"] = scanner.format
  result["proof_version"] = scanner.version
  result["proof_bytes"] = scanner.bytesize
  result
