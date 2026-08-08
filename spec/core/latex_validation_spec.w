# Focused interpreted/native checks for structured LaTeX reference validation.
#
# Run interpreted:
#   bin/tungsten run spec/core/latex_validation_spec.w
# Run compiled:
#   bin/tungsten compile spec/core/latex_validation_spec.w --out /tmp/latex-validation-spec
#   /tmp/latex-validation-spec

-> latex_validation_check(name, got, want)
  if got != want
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

forward = LaTeX.builder
forward.text("See ")
forward.append(LaTeX.eqref("eq:energy"))
forward.line(LaTeX.equation(LaTeX.raw("E=mc^{2}"), "eq:energy"))
forward_body = forward.to_fragment
forward_document = LaTeX.profile(:ieee).document(forward_body, {:title => "A&B"})
forward_source = forward_document.to_s
forward_report = LaTeX.validate(forward_document, [])
latex_validation_check("forward.valid", forward_report.valid?, true)
latex_validation_check("forward.tracked_valid", forward_report.tracked_valid?, true)
latex_validation_check("forward.complete", forward_report.complete?, true)
latex_validation_check(
  "forward.citation_check_complete",
  forward_report.citation_check_complete?,
  true)
latex_validation_check("forward.scope", forward_report.scope, :structured_helpers)
latex_validation_check("forward.tracked_only", forward_report.tracked_only?, true)
latex_validation_check("forward.label", forward_report.labels.join(","), "eq:energy")
latex_validation_check("forward.reference_kind", forward_report.references[0].kind, :eqref)
latex_validation_check("forward.source_unchanged", forward_document.to_s, forward_source)
latex_validation_check("forward.metadata_escaped", forward_source.include?("\\title{A\\&B}"), true)

duplicate = LaTeX.concat([
  LaTeX.section("First", "Body", "dup"),
  LaTeX.raw("\n"),
  LaTeX.equation(1, "dup")
])
duplicate_report = LaTeX.validate(duplicate)
latex_validation_check("duplicate.labels", duplicate_report.duplicate_labels.join(","), "dup")
latex_validation_check("duplicate.invalid", duplicate_report.valid?, false)

unresolved = LaTeX.concat([LaTeX.ref("sec:missing"), LaTeX.eqref("eq:missing")])
unresolved_report = LaTeX.validate(unresolved)
latex_validation_check("unresolved.count", unresolved_report.unresolved_references.size, 2)
latex_validation_check(
  "unresolved.first_kind", unresolved_report.unresolved_references[0].kind, :ref)
latex_validation_check(
  "unresolved.first_key", unresolved_report.unresolved_references[0].key, "sec:missing")
latex_validation_check(
  "unresolved.second_kind", unresolved_report.unresolved_references[1].kind, :eqref)

multi_cite = LaTeX.cite(["carlisle2024", "tan2024"])
latex_validation_check(
  "citation.source", multi_cite.to_s, "\\cite{carlisle2024,tan2024}")
partial_catalog = LaTeX.validate(multi_cite, ["carlisle2024"])
latex_validation_check(
  "citation.partial", partial_catalog.unresolved_citations.join(","), "tan2024")

unchecked = LaTeX.validate(multi_cite)
latex_validation_check("citation.unchecked_complete", unchecked.complete?, false)
latex_validation_check("citation.unchecked_valid", unchecked.valid?, false)
latex_validation_check("citation.unchecked_unresolved", unchecked.unresolved_citations, nil)

empty_catalog = LaTeX.validate(multi_cite, [])
latex_validation_check("citation.empty_catalog_complete", empty_catalog.complete?, true)
latex_validation_check(
  "citation.empty_catalog_unresolved",
  empty_catalog.unresolved_citations.join(","),
  "carlisle2024,tan2024")

repeated = LaTeX.concat([
  LaTeX.label("sec:x"), LaTeX.ref("sec:x"), LaTeX.ref("sec:x"),
  LaTeX.cite("source1"), LaTeX.cite("source1")
])
repeated_report = LaTeX.validate(repeated, ["source1"])
latex_validation_check("repeated.uses_valid", repeated_report.valid?, true)
latex_validation_check(
  "repeated.no_duplicate_definition", repeated_report.duplicate_labels.empty?, true)

nested_cell = LaTeX.ref("sec:results") + LaTeX.raw("; ") + LaTeX.cite("paper1")
nested_table = LaTeX.table(["Evidence"], [[nested_cell]], "Results", "tab:nested")
nested_section = LaTeX.section("Results", nested_table, "sec:results")
nested_document = LaTeX.profile(:arxiv).document(nested_section)
nested_report = LaTeX.validate(nested_document, ["paper1"])
latex_validation_check("nested.profile_valid", nested_report.valid?, true)
latex_validation_check("nested.labels", nested_report.labels.join(","), "sec:results,tab:nested")

metadata_body = LaTeX.section("Metadata", "Body", "sec:metadata")
metadata_title = LaTeX.text("See ") + LaTeX.ref("sec:metadata")
metadata_abstract = LaTeX.text("Evidence ") + LaTeX.cite("metadata1")
metadata_document = LaTeX.profile(:arxiv).document(metadata_body, {
  :title => metadata_title,
  :abstract => metadata_abstract
})
metadata_report = LaTeX.validate(metadata_document, ["metadata1"])
latex_validation_check("metadata.standard_valid", metadata_report.valid?, true)
latex_validation_check(
  "metadata.standard_reference", metadata_report.references[0].key, "sec:metadata")
latex_validation_check("metadata.standard_citation", metadata_report.citations[0], "metadata1")

thesis_author = LaTeX.text("Author; see ") + LaTeX.ref("sec:thesis")
thesis_abstract = LaTeX.text("Evidence ") + LaTeX.cite("thesis1")
thesis_document = LaTeX.profile(:thesis).document(
  LaTeX.section("Thesis", "Body", "sec:thesis"),
  {:title => "Thesis", :authors => [thesis_author], :abstract => thesis_abstract})
thesis_report = LaTeX.validate(thesis_document, ["thesis1"])
latex_validation_check("metadata.thesis_valid", thesis_report.valid?, true)
latex_validation_check("metadata.thesis_reference", thesis_report.references[0].key, "sec:thesis")
latex_validation_check("metadata.thesis_citation", thesis_report.citations[0], "thesis1")

append_fragment = LaTeX.label("sec:append").append(LaTeX.ref("sec:append"))
latex_validation_check("composition.append", LaTeX.validate(append_fragment).valid?, true)
join_separator = LaTeX.label("dup:separator")
joined = LaTeX.join([LaTeX.text("a"), LaTeX.text("b"), LaTeX.text("c")], join_separator)
latex_validation_check(
  "composition.separator_repeated",
  LaTeX.validate(joined).duplicate_labels.join(","),
  "dup:separator")

unsafe_citation_rejected = false
begin
  LaTeX.cite("bad}\\input{secrets}")
rescue error
  unsafe_citation_rejected = true
latex_validation_check("citation.unsafe_key", unsafe_citation_rejected, true)

fragment_required_rejected = false
begin
  LaTeX.validate("\\label{x}")
rescue error
  fragment_required_rejected = true
latex_validation_check("validation.fragment_required", fragment_required_rejected, true)

invalid_report_rejected = false
begin
  unresolved_report.raise_if_invalid
rescue error
  invalid_report_rejected = true
latex_validation_check("validation.raise", invalid_report_rejected, true)

raw_commands = LaTeX.raw("\\label{raw}\\ref{raw}\\cite{raw}")
raw_report = LaTeX.validate(raw_commands)
latex_validation_check("raw.scope_explicit", raw_report.scope, :structured_helpers)
latex_validation_check("raw.untracked_labels", raw_report.labels.empty?, true)
latex_validation_check("raw.untracked_references", raw_report.references.empty?, true)
latex_validation_check("raw.untracked_citations", raw_report.citations.empty?, true)
latex_validation_check("raw.untracked_valid", raw_report.valid?, true)

string_preamble_rejected = false
begin
  LatexProfile.new(
    :custom, "article", [], [], "plain", :standard,
    ["\\input{unsafe}"])
rescue error
  string_preamble_rejected = true
latex_validation_check(
  "profile.string_preamble_rejected", string_preamble_rejected, true)
trusted_profile = LatexProfile.new(
  :custom, "article", [], [], "plain", :standard,
  [LaTeX.raw("\\newcommand{\\R}{\\mathbb{R}}")])
latex_validation_check(
  "profile.trusted_preamble",
  trusted_profile.preamble_fragment.to_s.include?("\\newcommand"),
  true)

options = ["draft"]
packages = [["geometry", "margin=1in"]]
copied_profile = LatexProfile.new(
  :copy, "article", options, packages, "plain", :standard)
options.push("twocolumn")
packages[0].push("unsafe")
returned_options = copied_profile.class_options
returned_packages = copied_profile.packages
returned_options.push("oneside")
returned_packages[0].push("unsafe")
latex_validation_check("profile.options_defensive", copied_profile.class_options.size, 1)
latex_validation_check("profile.packages_defensive", copied_profile.packages[0].size, 2)

scale_parts = []
1_000.times -> (i)
  scale_parts.push(LaTeX.label("scale:" + i.to_s))
scale_fragment = LaTeX.concat(scale_parts)
scale_report = LaTeX.validate(scale_fragment)
latex_validation_check("scale.labels", scale_report.labels.size, 1_000)
latex_validation_check("scale.valid", scale_report.valid?, true)

append_chain = LaTeX.raw("")
128.times -> (i)
  append_chain = append_chain + LaTeX.label("append:" + i.to_s)
latex_validation_check(
  "scale.append_chain", LaTeX.validate(append_chain).labels.size, 128)

<< "latex_validation_spec: all checks passed"
