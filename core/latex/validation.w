# Structured LaTeX cross-reference provenance and source-level validation.
#
# Validation covers commands created through Core helpers. `LaTeX.raw` is an
# intentional provenance-erasing boundary and arbitrary TeX is never scanned.

+ LaTeX
  -> .validated_citation_key(value)
    text = value.to_s
    raise "unsafe LaTeX citation key: " + text if !safe_label?(text)
    text

  -> .citation_keys(value)
    values = value.class_name == "Array" ? value : [value]
    raise "LaTeX.cite needs at least one key" if values.empty?
    keys = []
    values.each -> (key)
      keys.push(validated_citation_key(key))
    keys

  -> .cite(value)
    keys = citation_keys(value)
    events = []
    keys.each -> (key)
      events.push(LatexReferenceEvent.new(:cite, key))
    LatexFragment.new("\\cite{" + keys.join(",") + "}", events)

  -> .validate(fragment, bibliography_keys = nil)
    if fragment.class_name != "LatexFragment"
      raise "LaTeX.validate needs a LatexFragment"
    LatexValidationReport.new(fragment, bibliography_keys)


# One label, ref, eqref, or cite key recorded by a structured LaTeX helper.
+ LatexReferenceEvent
  ro :kind, :key

  -> new(kind, key)
    if ![:label, :ref, :eqref, :cite].include?(kind)
      raise "unknown LaTeX reference event kind: " + kind.to_s
    @kind = kind
    if kind == :cite
      @key = LaTeX.validated_citation_key(key)
    else
      @key = LaTeX.validated_label(key)

  -> to_s
    @kind.to_s + ":" + @key

  -> inspect
    to_s


# Immutable tree of reference events shared by composed fragments.
+ LatexEventChain
  -> new(events = nil, children = nil)
    @events = []
    @children = []
    if events != nil
      raise "LaTeX event chain events must be an Array" if events.class_name != "Array"
      events.each -> (event)
        if event.class_name != "LatexReferenceEvent"
          raise "LaTeX event chain contains an invalid event"
        @events.push(event)
    if children != nil
      raise "LaTeX event chain children must be an Array" if children.class_name != "Array"
      children.each -> (child)
        if child.class_name != "LatexEventChain"
          raise "LaTeX event chain contains an invalid child"
        @children.push(child)
    if !@events.empty? && !@children.empty?
      raise "LaTeX event chain cannot mix events and children"

  -> .leaf(events)
    LatexEventChain.new(events, nil)

  -> .combine(chains)
    raise "LaTeX event chains must be an Array" if chains.class_name != "Array"
    chains.each -> (chain)
      if chain.class_name != "LatexEventChain"
        raise "LaTeX event chains contain an invalid value"
    return LatexEventChain.leaf([]) if chains.empty?
    return chains[0] if chains.size == 1
    LatexEventChain.new(nil, chains)

  -> leaf?
    @children.empty?

  -> child_count
    @children.size

  -> child_at(index)
    @children[index]

  -> event_count
    @events.size

  -> event_at(index)
    @events[index]

  -> flatten
    out = []
    stack = [self]
    while !stack.empty?
      node = stack.pop
      if node.leaf?
        i = 0
        while i < node.event_count
          out.push(node.event_at(i))
          i += 1
      else
        i = node.child_count - 1
        while i >= 0
          stack.push(node.child_at(i))
          i -= 1
    out


# Tracked-only label, reference, and citation diagnostics for one fragment.
+ LatexValidationReport
  -> new(fragment, bibliography_keys = nil)
    @events = fragment.reference_events
    @bibliography_supplied = bibliography_keys != nil
    @bibliography_keys = []
    @bibliography_index = {}
    if bibliography_keys != nil
      if bibliography_keys.class_name != "Array"
        raise "LaTeX bibliography keys must be an Array or nil"
      bibliography_keys.each -> (key)
        safe = LaTeX.validated_citation_key(key)
        if !@bibliography_index.has_key?(safe)
          @bibliography_keys.push(safe)
          @bibliography_index[safe] = true
    analyze

  -> copy(values)
    out = []
    values.each -> (value)
      out.push(value)
    out

  -> analyze
    @labels = []
    @references = []
    @citations = []
    @duplicate_labels = []
    @unresolved_references = []
    @unresolved_citations = @bibliography_supplied ? [] : nil
    label_index = {}
    duplicate_index = {}

    @events.each -> (event)
      if event.kind == :label
        if label_index.has_key?(event.key)
          if !duplicate_index.has_key?(event.key)
            @duplicate_labels.push(event.key)
            duplicate_index[event.key] = true
        else
          @labels.push(event.key)
          label_index[event.key] = true
      elsif event.kind == :ref || event.kind == :eqref
        @references.push(event)
      elsif event.kind == :cite
        @citations.push(event.key)

    unresolved_seen = {}
    @references.each -> (reference)
      if !label_index.has_key?(reference.key)
        identity = reference.kind.to_s + ":" + reference.key
        if !unresolved_seen.has_key?(identity)
          @unresolved_references.push(reference)
          unresolved_seen[identity] = true

    if @bibliography_supplied
      unresolved_citation_index = {}
      @citations.each -> (citation)
        if !@bibliography_index.has_key?(citation)
          if !unresolved_citation_index.has_key?(citation)
            @unresolved_citations.push(citation)
            unresolved_citation_index[citation] = true
    self

  -> labels
    copy(@labels)

  -> references
    copy(@references)

  -> citations
    copy(@citations)

  -> duplicate_labels
    copy(@duplicate_labels)

  -> unresolved_references
    copy(@unresolved_references)

  -> unresolved_citations
    return nil if @unresolved_citations == nil
    copy(@unresolved_citations)

  -> scope
    :structured_helpers

  -> tracked_only?
    true

  -> citation_check_complete?
    @bibliography_supplied || @citations.empty?

  -> complete?
    citation_check_complete?

  -> valid?
    return false if !complete?
    return false if !@duplicate_labels.empty?
    return false if !@unresolved_references.empty?
    return true if @unresolved_citations == nil
    @unresolved_citations.empty?

  -> tracked_valid?
    valid?

  -> issues
    out = []
    @duplicate_labels.each -> (label)
      out.push("duplicate label " + label)
    @unresolved_references.each -> (reference)
      out.push("unresolved " + reference.kind.to_s + " " + reference.key)
    if !@bibliography_supplied && !@citations.empty?
      out.push("citation validation needs bibliography keys")
    elsif @bibliography_supplied
      @unresolved_citations.each -> (citation)
        out.push("unresolved citation " + citation)
    out

  -> raise_if_invalid
    raise "LaTeX validation failed: " + issues.join("; ") if !valid?
    self

  -> to_s
    if valid?
      return "valid tracked structured LaTeX references"
    "tracked structured LaTeX issues: " + issues.join("; ")

  -> inspect
    "LatexValidationReport(" + to_s + ")"
