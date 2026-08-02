# Journal profile — neutral two-column article defaults for later adaptation.

+ LatexJournalProfile
  -> .build
    LatexProfile.new(
      :journal,
      "article",
      ["twocolumn"],
      ["amsmath", "amssymb", "booktabs", "graphicx", "microtype", "natbib"],
      "abbrvnat",
      :standard)
