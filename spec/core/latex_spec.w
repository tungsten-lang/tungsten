# Focused cross-engine checks for safe LaTeX fragments and publication profiles.
#
# Run compiled:
#   bin/tungsten spec/core/latex_spec.w
# Run interpreted:
#   bin/tungsten run --interpret spec/core/latex_spec.w

-> latex_check(name, got, want)
  if got != want
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

-> latex_contains(name, source, expected)
  if !source.include?(expected)
    raise "FAIL " + name + ": missing " + expected + " in " + source
  << "PASS " + name

escaped = LaTeX.escape("\\{}$&#_%~^")
latex_check(
  "escape.reserved",
  escaped,
  "\\textbackslash{}\\{\\}\\$\\&\\#\\_\\%\\textasciitilde{}\\textasciicircum{}")
latex_check("escape.text_fragment", LaTeX.text("A&B_1").to_s, "A\\&B\\_1")
latex_check("escape.math_text", LaTeX.math_text("A&B_1").to_s, "\\text{A\\&B\\_1}")
latex_check("raw.explicit", LaTeX.raw("\\alpha").to_s, "\\alpha")

nested = LaTeX.fraction(
  LaTeX.symbol(:alpha_1),
  LaTeX.superscript(LaTeX.symbol(:x), 2))
latex_check("compose.nested", nested.to_s, "\\frac{\\alpha_{1}}{x^{2}}")
latex_check(
  "compose.safe_string",
  LaTeX.raw("x=").append("A&B").to_s,
  "x=\\text{A\\&B}")

builder = LaTeX.builder
builder.text("Result & proof: ")
builder.math(Rational.new(1, 3))
builder.line(LaTeX.ref("sec:proof"))
latex_check(
  "builder.nested",
  builder.to_s,
  "Result \\& proof: \\(\\frac{1}{3}\\)\\ref{sec:proof}\n")

latex_check("render.rational", LaTeX.render(Rational.new(-3, 4)).to_s, "-\\frac{3}{4}")
latex_check("render.scientific", LaTeX.number_string("6.6743e-11").to_s, "6.6743\\times 10^{-11}")
latex_check("render.array", LaTeX.render([1, Rational.new(1, 2)]).to_s, "\\left\[1, \\frac{1}{2}\\right]")
latex_check(
  "render.matrix",
  LaTeX.matrix([[1, 2], [3, 4]]).to_s,
  "\\begin{bmatrix}1 & 2 \\\\\n3 & 4\\end{bmatrix}")
latex_check(
  "render.sparse_matrix",
  LaTeX.render(SparseMatrix.from_dense([[1, 0], [0, 2]])).to_s,
  "\\begin{bmatrix}1 & 0 \\\\\n0 & 2\\end{bmatrix}")

latex_check("render.quantity", LaTeX.render(9.80665 m/s²).to_s, "9.80665\\,\\mathrm{m/s^{2}}")
latex_check("render.percentage", LaTeX.render(7.65%).to_s, "7.65\\%")
latex_check("render.currency", LaTeX.render($12.50).to_s, "\\text{\\$}12.50")

equation = LaTeX.equation(
  LaTeX.raw("E = mc^{2}"), "eq:mass_energy")
latex_contains("paper.equation", equation.to_s, "\\begin{equation}")
latex_contains("paper.label", equation.to_s, "\\label{eq:mass_energy}")
latex_check("paper.eqref", LaTeX.eqref("eq:mass_energy").to_s, "\\eqref{eq:mass_energy}")

unsafe_label_rejected = false
begin
  LaTeX.label("eq:bad}\\input{secrets}")
rescue error
  unsafe_label_rejected = true
latex_check("paper.unsafe_label_rejected", unsafe_label_rejected, true)

table = LaTeX.table(
  ["Name", "Value & unit"],
  [["alpha_1", 3], ["beta", Rational.new(1, 2)]],
  "Results & checks",
  "tab:results",
  "lc")
latex_contains("paper.table_environment", table.to_s, "\\begin{tabular}{lc}")
latex_contains("paper.table_header_escape", table.to_s, "Value \\& unit")
latex_contains("paper.table_cell_escape", table.to_s, "alpha\\_1")
latex_contains("paper.table_caption_escape", table.to_s, "\\caption{Results \\& checks}")
latex_contains("paper.table_label", table.to_s, "\\label{tab:results}")

profile_name_parts = []
LaTeX.profile_names.each -> (profile_name)
  profile_name_parts.push(profile_name.to_s)
latex_check("profiles.names", profile_name_parts.join(","), "ieee,acm,arxiv,thesis,journal")

ieee = LaTeX.profile(:ieee)
acm = LaTeX.profile(:acm)
arxiv = LaTeX.profile(:arxiv)
thesis = LaTeX.profile(:thesis)
journal = LaTeX.profile(:journal)
latex_check("profiles.ieee.class", ieee.document_class, "IEEEtran")
latex_check("profiles.ieee.bibliography", ieee.bibliography_style, "IEEEtran")
latex_check("profiles.acm.class", acm.document_class, "acmart")
latex_check("profiles.string_selection", LaTeX.profile("ACM").name, :acm)
latex_check("profiles.acm.bibliography", acm.bibliography_style, "ACM-Reference-Format")
latex_check("profiles.arxiv.class", arxiv.document_class, "article")
latex_check("profiles.thesis.class", thesis.document_class, "report")
latex_check("profiles.journal.bibliography", journal.bibliography_style, "abbrvnat")

metadata = {
  :title => "A&B",
  :authors => ["Ada_1", "Emmy"],
  :abstract => "Safe & exact.",
  :keywords => ["symbolic_math", "proof"],
  :bibliography => "refs/main",
  :institution => "Example U",
  :degree => "PhD"
}
ieee_document = ieee.document(LaTeX.section("Results", "Body & text"), metadata).to_s
latex_contains("profiles.ieee.document_class", ieee_document, "\\documentclass\[conference]{IEEEtran}")
latex_contains("profiles.ieee.keywords", ieee_document, "\\begin{IEEEkeywords}")
latex_contains("profiles.ieee.metadata_escape", ieee_document, "\\title{A\\&B}")
latex_contains("profiles.ieee.bibliography_output", ieee_document, "\\bibliographystyle{IEEEtran}")

acm_document = acm.document(LaTeX.raw("Body"), metadata).to_s
latex_contains("profiles.acm.first_author", acm_document, "\\author{Ada\\_1}")
latex_contains("profiles.acm.second_author", acm_document, "\\author{Emmy}")
latex_contains("profiles.acm.keywords", acm_document, "\\keywords{symbolic\\_math, proof}")

arxiv_document = arxiv.document(LaTeX.raw("Body"), metadata).to_s
latex_contains("profiles.arxiv.geometry", arxiv_document, "\\usepackage\[margin=1in]{geometry}")
latex_contains("profiles.arxiv.bibliography", arxiv_document, "\\bibliographystyle{plain}")

thesis_document = thesis.document(LaTeX.raw("Body"), metadata).to_s
latex_contains("profiles.thesis.title_page", thesis_document, "\\begin{titlepage}")
latex_contains("profiles.thesis.institution", thesis_document, "Example U\\par")

journal_document = journal.document(LaTeX.raw("Body"), metadata).to_s
latex_contains("profiles.journal.class", journal_document, "\\documentclass\[twocolumn]{article}")
latex_contains("profiles.journal.bibliography", journal_document, "\\bibliographystyle{abbrvnat}")

unknown_profile_rejected = false
begin
  LaTeX.profile(:unknown)
rescue error
  unknown_profile_rejected = true
latex_check("profiles.unknown_rejected", unknown_profile_rejected, true)

<< "latex_spec: all checks passed"
