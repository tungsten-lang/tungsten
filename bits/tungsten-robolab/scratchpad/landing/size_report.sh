#!/bin/bash
# Sizes behind "land it all on main, or in a separate repo?" (30 Sep 2026). Read-only: git plumbing, du, stat.
# Output goes to scratchpad/landing/SIZES_0930.txt. The slow history count is last.
R=/Users/erik/tungsten
P=bits/tungsten-robolab
B=$R/$P
exec > "$B/scratchpad/landing/SIZES_0930.txt" 2>&1
cd "$R" || exit 1
cand() { git diff-tree -r --no-commit-id --diff-filter=AM --name-only main robolab-land-tmp; }
BY_DIR='{split($5,a,"/"); d=a[3]; if (d=="scratchpad") d=d"/"a[4]; if (a[4]=="") d="(top-level files)"; s[d]+=$4; n[d]++} END{for(k in s) printf "%9.2f MB %5d files  %s\n", s[k]/1048576, n[k], k}'
echo "== $(date)   main $(git rev-parse --short main)   candidate 1 $(git rev-parse --short robolab-land-tmp)"

echo
echo "== 1. the robolab tree already on main (tracked blobs, uncompressed)"
git ls-tree -r -l main -- $P | awk '{n++; s+=$4} END{printf "%d files, %.1f MB\n", n, s/1048576}'
echo "-- by directory"
git ls-tree -r -l main -- $P | awk "$BY_DIR" | sort -rn | head -14
echo "-- 12 largest tracked files"
git ls-tree -r -l main -- $P | sort -k4 -n -r | head -12 | awk '{printf "%8.2f MB  %s\n", $4/1048576, $5}'

echo
echo "== 2. candidate 1 (the verified commit on robolab-land-tmp) over main"
cand | xargs git ls-tree -r -l robolab-land-tmp -- | awk '{s+=$4; c++} END{printf "%d added or changed files, %.2f MB of blobs (uncompressed)\n", c, s/1048576}'
printf 'robolab-land-tmp\n^main\n' | git pack-objects --revs --stdout 2>/dev/null | wc -c | awk '{printf "packed size of what main would gain (what a fetch adds): %.2f MB\n", $1/1048576}'
echo "-- added size by directory"
cand | xargs git ls-tree -r -l robolab-land-tmp -- | awk "$BY_DIR" | sort -rn | head -12
echo "-- largest added files"
cand | xargs git ls-tree -r -l robolab-land-tmp -- | sort -k4 -n -r | head -10 | awk '{printf "%8.2f MB  %s\n", $4/1048576, $5}'

echo
echo "== 3. candidate 2 additions on top of candidate 1 (the anatomy study, the subset audits, the landing records; du, upper bound)"
cd "$B"
comm -13 <(sort scratchpad/landing_only.txt) <(sort scratchpad/landing_only_v2.txt) | while read -r p; do [ -e "$p" ] && printf '%s\0' "$p"; done | xargs -0 du -ck 2>/dev/null | tail -1 | awk '{printf "%.2f MB\n", $1/1024}'

echo
echo "== 4. what stays out of git (local only; the .gitignore keeps it out)"
du -sh bin/champions bin/challengers out playground/cache playground/refs 2>/dev/null
du -sch bin/robolab_* 2>/dev/null | tail -1 | awk '{print $1, "bin/robolab_* (built entries)"}'
du -sh .venv* 2>/dev/null

echo
echo "== 5. the repo around it"
cd "$R"
git count-objects -vH
du -sh .git 2>/dev/null
echo "commits on main: $(git rev-list --count main)"

echo
echo "== 6. robolab's share of main's history (every object reachable from commits that touch $P; slow)"
git rev-list --objects main -- $P | git cat-file --batch-check='%(objectsize:disk)' | awk '{s+=$1; n++} END{printf "%d objects, %.1f MB on disk\n", n, s/1048576}'
echo "== done $(date)"
