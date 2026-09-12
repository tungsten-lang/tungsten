use ../lib/metaflip/wide/tui

lanes = i64[18]
lanes[0]=2209
lanes[1]=2210
lanes[2]=10000000
lanes[3]=5000000
lanes[4]=1000
lanes[5]=1900
lanes[9]=2210
lanes[10]=2211
lanes[11]=12000000
lanes[12]=6000000
lanes[13]=1500
lanes[14]=1900
levels = i64[3]
levels[0]=2211
levels[1]=2210
levels[2]=2209
ticks = i64[3]
ticks[0]=1
ticks[1]=10
ticks[2]=100
bits = i64[2]
bits[0]=30000
bits[1]=29000
times = i64[3]
times[0]=0
times[1]=1
times[2]=2
width = 40 ## i64
while width <= 160
  rows=ffws_frame_rows(16,2209,29000,22000000,2,4,2,1,0,3,1950,2000,2,1,40,100,4,lanes,levels,ticks,3,bits,ticks,2,times,levels,3," | cycle 2/43 rank-search (60s)",width,2209,2)
  body=rows.join("\n")
  if !body.include?("metaflip") || !body.include?("GF(2)") || !body.include?("CPU islands") || !body.include?("Diversity") || !body.include?("Effectiveness") || !body.include?("Rank timeline")
    << "FAIL wide dashboard structure"
    exit(1)
  if body.include?("WR ") || body.include?("world record") || body.include?("space=reset") || body.include?("w=reseed")
    << "FAIL wide unsupported capabilities"
    exit(1)
  if width >= 80
    if !body.include?("\e[1;33mmetaflip\e[0m") || !body.include?("⟨16,16,16⟩") || !body.include?("r2210/r2209") || !body.include?("r2211/r2210") || !body.include?("5.0M/s") || !body.include?("6.0M/s") || !body.include?("snapshot age 100ms")
      << "FAIL wide dashboard telemetry"
      exit(1)
  if width == 120
    if !body.include?("density: archive only") || body.include?("density-slack") || !body.include?("no pair") || !body.include?("blocked")
      << "FAIL density policy and separated attempt labels"
      exit(1)
    << body
  width += 40
<< "PASS wide TUI layout, large ranks, rates, history and honest capabilities"
Tungsten.PROTECT_THE_CORE!
Tungsten.LOCK_THE_DOORS!
