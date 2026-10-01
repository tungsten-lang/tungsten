# The LaTeX scanners of the paper tools (lib/metaflip/papers/tex.w) against the regular expressions of the Python originals
# (scripts/pack_arxiv.py, scripts/make_arxiv_md.py): comments, the files a source names, the lines that use \todo, the abstract.
# The expectations are the results of the originals' code on the same snippets. Prints FAIL lines and exits 1 on a mismatch.
use core/system
use ../lib/metaflip/papers/tex

failures = 0 ## i64
checks = 0 ## i64

-> expect(label, got, want)
  if got != want
    << "FAIL " + label + ": got " + got.to_s.slice(0, 300) + " want " + want.to_s.slice(0, 300)
    return 1
  0

checks += 1
failures += expect("comments", Tex.strip_comments("a % b\nc \\% d % e\n%x\nfoo"), "a \nc \\% d \n\nfoo")

source = "\\input{sections/a} % \\input{hidden}\n\\input{b,c}\\include{d}\\includegraphics\[width=3cm\]{fig}\\includegraphics{g}\n\\addplot table\[x=t,y=s\]{data/f.dat}\\addplot table {data/g.dat}\n\\bibliography{refs, extra}\n\\begin{table}\[tbp\]\\input{tables/t}\n\\begin{tabular}{ll}table x{notfile}\n\\input{}\\includegraphics{a}{b}"
images = ["", ".pdf", ".png", ".jpg"]
want = [["sections/a", [".tex"]], ["b", [".tex"]], ["c", [".tex"]], ["tables/t", [".tex"]], ["d", [".tex"]], ["fig", images], ["g", images], ["a", images], ["data/f.dat", [""]], ["data/g.dat", [""]], ["refs", [".bib"]], ["extra", [".bib"]]]
checks += 1
failures += expect("references", Tex.references(source), want)

todos = "x\n\\newcommand{\\todo}\[1\]{{\\color{red}#1}}\n  % \\todo{commented}\ntext \\todo{real}\n\\todo{second} % tail\n"
checks += 1
failures += expect("todo lines", Tex.todo_lines(todos), [4, 5])

checks += 1
failures += expect("abstract", Tex.abstract("\\begin{document}\n\\begin{abstract}\n  Upper bounds. \n\\end{abstract}\nbody"), "Upper bounds.")
checks += 1
failures += expect("no abstract", Tex.abstract("body"), nil)

checks += 1
failures += expect("cited keys", Tex.cited_keys("see \\cite{a, b} and \\citep\[p. 2\]{c}, \\citet*{a}"), ["a", "b", "c"])

if failures > 0
  << "FAIL " + failures.to_s + " of " + checks.to_s + " papers tex checks"
  exit(1)
<< "PASS papers tex: " + checks.to_s + " checks"
