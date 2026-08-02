# Thesis profile — generic report/title-page defaults, institution-neutral.

+ LatexThesisProfile
  -> .build
    LatexProfile.new(
      :thesis,
      "report",
      ["12pt", "oneside"],
      [
        "amsmath", "amssymb", "booktabs",
        ["geometry", "margin=1in"],
        "hyperref", "natbib"
      ],
      "plainnat",
      :thesis)
