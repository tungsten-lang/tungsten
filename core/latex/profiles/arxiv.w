# arXiv profile — portable article defaults suitable for a preprint baseline.

+ LatexArxivProfile
  -> .build
    LatexProfile.new(
      :arxiv,
      "article",
      ["11pt"],
      [
        "amsmath", "amssymb", "booktabs",
        ["geometry", "margin=1in"],
        "hyperref"
      ],
      "plain",
      :standard)
