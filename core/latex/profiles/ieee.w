# IEEE profile — concise IEEEtran conference defaults, not a compliance claim.

+ LatexIEEEProfile
  -> .build
    LatexProfile.new(
      :ieee,
      "IEEEtran",
      ["conference"],
      ["amsmath", "amssymb", "booktabs", "cite"],
      "IEEEtran",
      :ieee)
