# Shared reporter for the GF(2) support-library cases run by
# spec/gf2_support_test.w. A case file defines `-> gf2_<module>_cases(t)` and
# reports through the Check instance it is handed; the driver prints the
# closing PASS line or exits 1 (build_cache_test.w convention).
+ Check
  # GF2_VERBOSE=1 also prints a line for every passing check and the seconds each
  # section took.
  -> new
    @checks = 0
    @failures = 0
    @verbose = env("GF2_VERBOSE") != nil && env("GF2_VERBOSE") != ""
    @section = nil
    @section_started = 0

  ro :checks, :failures

  # Start a named group of checks (closes the previous one).
  -> section(name)
    close_section
    @section = name
    @section_started = clock()

  -> close_section
    if @verbose && @section != nil
      << "time " + @section + ": " + (clock() - @section_started).to_s + " s"

  # Record one boolean check; failures print immediately as `FAIL label`.
  -> ok(label, condition)
    @checks += 1
    if !condition
      @failures += 1
      << "FAIL " + label
    elsif @verbose
      << "ok   " + label
    condition

  # Compare values with ==; on mismatch show both sides (clipped).
  -> eq(label, actual, expected)
    @checks += 1
    if actual == expected
      << "ok   " + label if @verbose
      return true
    @failures += 1
    << "FAIL " + label
    << "  expected: " + Check.clip(expected)
    << "  actual:   " + Check.clip(actual)
    false

  # The block must raise. (Instance methods cannot combine an optional
  # parameter with `&`: an omitted optional would swallow the block, see
  # PORT-BLOCKERS.md, so the two variants are separate methods.)
  -> raises_any(label, &)
    raises(label, "") ->
      yield

  # The block must raise an error whose message contains `fragment`.
  -> raises(label, fragment, &)
    @checks += 1
    message = nil
    begin
      yield
    rescue e
      message = e.to_s
    if message == nil
      @failures += 1
      << "FAIL " + label + " (nothing raised)"
      return false
    if !message.include?(fragment)
      @failures += 1
      << "FAIL " + label
      << "  expected an error containing: " + fragment
      << "  actual error:                 " + Check.clip(message)
      return false
    << "ok   " + label if @verbose
    true

  # The record-hunt campaign's work directory (GF2_RECORD_HUNT_WORK, else the default
  # under $HOME), or nil when it is not on this machine: cases on real data skip then.
  -> .work_dir
    configured = env("GF2_RECORD_HUNT_WORK")
    configured = env("HOME").to_s + "/.tungsten/metaflip/experiments/record-hunt-20260926/work" if configured == nil || configured == ""
    File.directory?(configured) ? configured : nil

  -> .clip(value)
    text = value.to_s
    text.size > 300 ? text.slice(0, 300) + "..." : text

  # Print the verdict for the whole run; exit status 1 when anything failed.
  -> finish(name)
    close_section
    if @failures > 0
      << name + ": " + @failures.to_s + " of " + @checks.to_s + " checks failed"
      exit(1)
    << "PASS " + name + ": " + @checks.to_s + " checks"
