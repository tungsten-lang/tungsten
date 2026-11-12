# Ancient Egyptian, Chinese shizhi, palm, and slope/seked units.
#
# Cross-engine parity spec (scripts/parity.sh): verifies exact rational
# conversions, Rhind Papyrus granary & pyramid identities, and `ro` unit
# disambiguation alongside `ro` accessor markers and shadowed locals.

-> check(label, got, want)
  if got != want
    << "FAIL [label]: got=[got] want=[want]"
    exit(1)
  << "PASS [label]: [got]"

+ Granary
  -> new(@capacity) ro

+ Vessel
  -> new(@volume)
    ro

  -> in_ro @volume | ro

# Ancient Egyptian length & area
check("khet.to.royal_cubit", (1 khet | royal_cubit).to_s(), "100 royal_cubit")
check("egyptian_cubit.to.palm", (1 egyptian cubit | egypt_palm).to_s(), "7 egypt_palm")
check("short_cubit.to.egypt_palm", (1 short cubit | egypt_palm).to_s(), "6 egypt_palm")
check("short_cubit.eq.sheseps", 1 short_cubit == 6 sheseps, true)
check("shesep.to.digit", (1 shesep | digit).to_s(), "4 digit")
check("khet_sq.to.aroura", ((1 khet * 1 khet) | aroura).to_s(), "1 aroura")

# Ancient Egyptian volume & Rhind Mathematical Papyrus Problem 41
check("hekat.to.ro", (1 hekat | ro).to_s(), "320 ro")
check("heqat.eq.hekat", 1 heqat == 1 hekat && 2 heqats == 640 ros, true)
check("hekat.plus.ro", (1 hekat + 160 ro).to_s(), "1.5 hekat")
check("khar.to.hekat", (1 khar | hekat).to_s(), "20 hekat")
check("khar.to.ro", (1 khar | ro).to_s(), "6400 ro")
check("attach.ro", (5 | ro).to_s(), "5 ro")
check("vessel.in_ro", Vessel.new(2 hekat).in_ro().to_s(), "640 ro")

silo_d = 9 egyptian cubits
silo_h = 10 egyptian cubits
silo = Granary.new((silo_d - silo_d / 9) * (silo_d - silo_d / 9) * silo_h)
check("rmp41.khar", (silo.capacity | khar).to_s(), "960 khar")
check("rmp41.hekat", (silo.capacity | hekat).to_s(), "19200 hekat")

-> shadowed_ro_bitor
  ro = 6
  1 | ro

check("shadowed.ro.bitor", shadowed_ro_bitor(), 7)

# Ancient Egyptian decan (10-day civil week)
check("decan.to.d", (1 decan | d).to_s(), "10 d")
check("36.decans.to.d", (36 decans | d).to_s(), "360 d")

# English palm / handbreadth
check("ft.to.handbreadth", (1 ft | handbreadth).to_s(), "4 handbreadth")
check("palm.eq.handbreadth", 1 palm == 1 handbreadth && 4 palms == 1 ft, true)

# Slope (rise/run) and batter / seked (run/rise)
check("slope.to.percent_grade", (0.06 slope | percent_grade).to_s(), "6 percent_grade")
check("rise_run.percent_grade", (((15 m / 250 m) | slope) | percent_grade).to_s(), "6 percent_grade")
check("seked.to.batter", (7 seked | batter).to_s(), "1 batter")
rmp56_batter = ((360 royal_cubit / 2) / 250 royal_cubit) | batter
check("rmp56.seked", (rmp56_batter | seked).to_s(), "5.04 seked")

# Chinese shizhi length, area, mass, and volume
check("li.to.m", (1 li | m).to_s(), "500 m")
check("m.to.li", (1000 m | li).to_s(), "2 li")
check("li.to.yin", (1 li | yin).to_s(), "15 yin")
check("yin.to.zhang", (1 yin | zhang).to_s(), "10 zhang")
check("li.to.bu_cn", (1 li | bu_cn).to_s(), "300 bu_cn")
check("chinese_pace.to.chi", (1 chinese pace | chi).to_s(), "5 chi")
check("fen.to.hao", (1 fen | hao).to_s(), "100 hao")
check("bu_sq.to.mu", ((24 bu_cn * 30 bu_cn) | mu).to_s(), "3 mu")
check("qing.to.mu", (1 qing | mu).to_s(), "100 mu")
check("dan.to.jin", (1 dan | jin).to_s(), "100 jin")
check("jin.to.dan", (200 jin | dan).to_s(), "2 dan")
check("dans.eq.kg", 2 dans == 100 kg, true)
check("liang.to.qian", (1 liang | qian).to_s(), "10 qian")
check("mace.to.g", (2 maces | g).to_s(), "10 g")
check("mace.eq.qian", 1 mace == 1 qian, true)
check("dou.to.sheng", (1 dou | sheng).to_s(), "10 sheng")
check("sheng.to.L", (1 sheng | L).to_s(), "1 L")
