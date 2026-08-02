# LaTeXProfiles — publication-profile registry for LaTeX document fragments.

use core/latex/profiles/base
use core/latex/profiles/ieee
use core/latex/profiles/acm
use core/latex/profiles/arxiv
use core/latex/profiles/thesis
use core/latex/profiles/journal

+ LaTeXProfiles
  -> .names
    [:ieee, :acm, :arxiv, :thesis, :journal]

  -> .fetch(name)
    key = name.to_s.downcase
    return LatexIEEEProfile.build if key == "ieee"
    return LatexACMProfile.build if key == "acm"
    return LatexArxivProfile.build if key == "arxiv"
    return LatexThesisProfile.build if key == "thesis"
    return LatexJournalProfile.build if key == "journal"
    raise "unknown LaTeX profile: " + name.to_s

  -> .document(name, body, metadata = nil)
    metadata = {} if metadata == nil
    fetch(name).document(body, metadata)
