# ACM profile — concise acmart sigconf defaults, not a compliance claim.

+ LatexACMProfile
  -> .build
    LatexProfile.new(
      :acm,
      "acmart",
      ["sigconf"],
      ["amsmath", "booktabs"],
      "ACM-Reference-Format",
      :acm)
