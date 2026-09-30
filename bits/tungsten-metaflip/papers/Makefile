# Build the two drafts with tectonic (https://tectonic-typesetting.github.io) and pack arXiv sources.
#   make            -> methods/main.pdf and results/main.pdf
#   make arxiv      -> dist/{methods,results}-arxiv.tar.gz, each verified by a standalone build
#   make final      -> the same, refusing while any \todo remains
#   make clean
TECTONIC ?= tectonic
PAPERS = methods results
PY ?= python3

all: $(PAPERS:%=%/main.pdf)

.PHONY: all arxiv final clean FORCE
FORCE:

# the sections, tables and data are prerequisites through the wildcard rule below
%/main.pdf: FORCE
	$(PY) scripts/mkbib.py $*
	cd $* && $(TECTONIC) -X compile main.tex --keep-intermediates --keep-logs

arxiv:
	for p in $(PAPERS); do $(PY) scripts/pack_arxiv.py $$p || exit 1; done

final:
	for p in $(PAPERS); do $(PY) scripts/pack_arxiv.py $$p --final || exit 1; done

clean:
	for p in $(PAPERS); do rm -f $$p/main.pdf $$p/main.aux $$p/main.bbl $$p/main.blg $$p/main.out $$p/main.log $$p/main.toc; done
	rm -rf dist
