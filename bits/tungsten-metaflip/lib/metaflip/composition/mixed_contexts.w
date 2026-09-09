# Each immutable parent ticket still owns 27 cursor positions. Versions 1..3
# retain {2,3,4}^3; versions 4..6 use exactly one unit coordinate. Within each
# family the three versions select pairs, groups, then groups plus grids.
-> ffmd_version(label, prefix) (String String) i64
  version = 1 ## i64
  while version <= 6
    if label == prefix + version.to_s()
      return version
    version += 1
  0

-> ffmd_scale(version, context, dimension) (i64 i64 i64) i64
  if version < 1 || version > 6 || context < 0 || context >= 27 || dimension < 0 || dimension > 2
    return 0
  if version <= 3
    if dimension == 0
      return 2+context/9
    if dimension == 1
      return 2+(context/3)%3
    return 2+context%3
  fixed = context/9 ## i64
  if dimension == fixed
    return 1
  variable = dimension ## i64
  if dimension > fixed
    variable -= 1
  if variable == 0
    return 2+(context%9)/3
  2+context%3
