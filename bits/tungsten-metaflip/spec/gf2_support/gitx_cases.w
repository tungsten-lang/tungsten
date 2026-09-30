# Cases for lib/metaflip/gf2/procx.w and gitx.w, run by spec/gf2_support_test.w.
#
#  * Procx: hostile arguments, byte-exact stdout, exit codes, stderr modes, cwd/env, stdout_to.
#  * Gitx on a hermetic repository built here with fixed identities and dates (so its commit
#    ids are constants); a blob-less clone of it proves that nothing is ever fetched unless
#    lazy_fetch: true says so.
#  * Gitx on the pinned upstream clones of the record hunt against answers Python's subprocess
#    gave (spec/fixtures/gf2_support/gitx/*.tsv, made by gen_gitx_goldens.py). They are skipped
#    when the campaign work directory is not on this machine; it is found through
#    GF2_RECORD_HUNT_WORK or the default below. They only read, always with GIT_NO_LAZY_FETCH=1.
use ../../lib/metaflip/gf2/gitx
use ../../lib/metaflip/gf2/fsx
use core/crypto/sha256

-> gitx_case_fixture_dir
  configured = env("GF2_SUPPORT_FIXTURES")
  return configured + "/gitx" if configured != nil && configured != ""
  candidates = [__DIR__ + "/../fixtures/gf2_support/gitx", __DIR__ + "/fixtures/gf2_support/gitx"]
  found = candidates.select -> (dir)
    File.exist?(dir + "/real_log.tsv")
  found.size > 0 ? found[0] : candidates[0]

-> gitx_case_work_dir
  configured = env("GF2_RECORD_HUNT_WORK")
  return configured if configured != nil && configured != ""
  "/Users/erik/.tungsten/metaflip/experiments/record-hunt-20260926/work"

-> gitx_case_rows(dir, name)
  text = read_file(dir + "/" + name)
  raise "missing fixture " + dir + "/" + name if text == nil
  rows = []
  text.split("\n").each -> (line)
    rows.push(line.split("\t")) unless line == ""
  rows

# Checks that the block raises an error of class `expected` ("ProcError", "GitError", ...).
-> gitx_case_raises(t, label, expected, &)
  seen = "none"
  begin
    yield
  rescue e: ProcError
    seen = "ProcError"
  rescue e: GitError
    seen = "GitError"
  rescue e
    seen = "other: " + e.to_s
  t.eq(label, seen, expected)

-> gitx_case_digest(text)
  Crypto:SHA256.hexdigest(text)

# ---- Procx --------------------------------------------------------------------------------

-> gitx_case_procx(t)
  t.eq("quote of nothing", Procx.quote(""), "''")
  t.eq("quote of a word", Procx.quote("abc"), "'abc'")
  t.eq("quote of an apostrophe", Procx.quote("it's"), "'it'\\''s'")
  t.eq("quote turns numbers into text", Procx.quote(42), "'42'")
  gitx_case_raises(t, "quote rejects a NUL byte", "ProcError") ->
    Procx.quote("a\0b")
  t.eq("command", Procx.command(["a b", "it's", ""], cwd: "/x y", env: {"K" => "v w"}), "cd '/x y' && K='v w' 'a b' 'it'\\''s' ''")
  gitx_case_raises(t, "command rejects an empty argv", "ProcError") ->
    Procx.command([])
  gitx_case_raises(t, "command rejects a bad variable name", "ProcError") ->
    Procx.command(["true"], env: {"A B" => "x"})
  gitx_case_raises(t, "command rejects a variable name with an equals sign", "ProcError") ->
    Procx.command(["true"], env: {"A=B" => "x"})
  ["A", "a_1", "_x", "PATH2"].each -> (name)
    t.eq("identifier? " + name, Procx.identifier?(name), true)
  ["", "1a", "a-b", "a b", "é"].each -> (name)
    t.eq("identifier? \"" + name + "\"", Procx.identifier?(name), false)
  # Hostile arguments must arrive untouched.
  hostile = ["", " ", "a b", "it's", "\"dq\"", "$HOME", "`echo pwned`", "$(echo pwned)", "a\nb", "\n", "\n\n", "*", "?", "\\", "\\n",
             "; echo pwned", "&& echo pwned", "| cat", "> gf2-must-not-exist", "-n", "-e", "--", "é", "日本語", "tab\there", "a  b", "'", "''", "'\\''",
             "%s", "%d\n", "x" * 20000]
  hostile.each -> (arg)
    answer = Procx.run(["printf", "%s", arg])
    t.eq("hostile argument (" + arg.size.to_s + " bytes) round trip", answer.out, arg)
    t.eq("hostile argument status", answer.status, 0)
  t.ok("no stray file came from the hostile arguments", !File.exist?("gf2-must-not-exist"))
  many = Procx.run(["printf", "%s|", "a b", "c'd", ""])
  t.eq("several arguments", many.out, "a b|c'd||")
  # stdout is exact
  t.eq("stdout without a trailing newline", Procx.run(["printf", "no newline"]).out, "no newline")
  t.eq("stdout that is only newlines", Procx.run(["printf", "\n\n\n"]).out, "\n\n\n")
  t.eq("empty stdout", Procx.run(["true"]).out, "")
  t.eq("unicode stdout", Procx.run(["printf", "%s", "héllo 日本語"]).out, "héllo 日本語")
  megabyte = Procx.run(["sh", "-c", "yes x | head -c 1000000"])
  t.eq("a megabyte of stdout", megabyte.out.size, 1000000)
  t.eq("a megabyte of stdout, last bytes", megabyte.out.slice(999998, 2), "x\n")
  # A NUL byte in stdout cuts the captured text (a C string) before the exit status arrives.
  cut = Procx.run(["sh", "-c", "printf 'ab\\0cd'"])
  t.eq("a NUL in stdout: truncated?", cut.truncated?, true)
  t.eq("a NUL in stdout: no status", cut.status, nil)
  t.eq("a NUL in stdout: ok? is false", cut.ok?, false)
  t.eq("a NUL in stdout: the text before it", cut.out, "ab")
  gitx_case_raises(t, "check_output refuses output with a NUL", "ProcError") ->
    Procx.check_output(["sh", "-c", "printf 'ab\\0cd'"])
  t.eq("a normal result is not truncated", Procx.run(["true"]).truncated?, false)
  # a child that prints the status marker itself cannot fool the parser: the real one comes last
  forged = "x\n" + 1.chr + "procx:9"
  echoed = Procx.run(["printf", "%s", forged])
  t.eq("a forged marker stays in stdout", echoed.out, forged)
  t.eq("a forged marker does not change the status", echoed.status, 0)
  ["0", "7", "255", "007"].each -> (text)
    t.eq("digits? " + text, Procx.digits?(text), true)
  ["", "x", "1x", "-1", " 1", "1234"].each -> (text)
    t.eq("digits? \"" + text + "\"", Procx.digits?(text), false)
  # exit statuses
  t.eq("status 0", Procx.run(["true"]).status, 0)
  t.eq("status 1", Procx.run(["false"]).status, 1)
  t.eq("status 7", Procx.run(["sh", "-c", "exit 7"]).status, 7)
  t.eq("status 255", Procx.run(["sh", "-c", "exit 255"]).status, 255)
  t.eq("a killed child reports 128 + signal", Procx.run(["sh", "-c", "kill -9 $$"]).status, 137)
  missing = Procx.run(["gf2-definitely-not-a-command"])
  t.eq("command not found is status 127", missing.status, 127)
  t.ok("command not found says so on stderr", missing.err.include?("not found"))
  t.eq("ok? is true for 0", Procx.run(["true"]).ok?, true)
  t.eq("ok? is false otherwise", Procx.run(["false"]).ok?, false)
  # stderr
  both = Procx.run(["sh", "-c", "echo out; echo err 1>&2"])
  t.eq("stdout stays apart from stderr", both.out, "out\n")
  t.eq("stderr is captured", both.err, "err\n")
  hushed = Procx.run(["sh", "-c", "echo out; echo err 1>&2"], stderr: :null)
  t.eq("stderr: :null keeps stdout", hushed.out, "out\n")
  t.eq("stderr: :null drops stderr", hushed.err, "")
  inherited = Procx.run(["sh", "-c", "echo out; true"], stderr: :inherit)
  t.eq("stderr: :inherit keeps stdout", inherited.out, "out\n")
  t.eq("stderr: :inherit captures nothing", inherited.err, "")
  gitx_case_raises(t, "an unknown stderr mode", "ProcError") ->
    Procx.run(["true"], stderr: :everywhere)
  # stdin is /dev/null, so a filter finishes at once
  t.eq("stdin is empty", Procx.run(["cat"]).out, "")
  # cwd and env
  t.eq("cwd", Procx.run(["pwd"], cwd: "/").out, "/\n")
  Fsx.with_tempdir(prefix: "gf2 procx 'q' ") -> (dir)
    t.eq("cwd with awkward characters", Procx.run(["sh", "-c", "pwd -P"], cwd: dir).out.strip, Fsx.resolve(dir))
    gone = Procx.run(["true"], cwd: Fsx.join(dir, "missing"))
    t.ok("a missing cwd fails", !gone.ok?)
    target = Fsx.join(dir, "raw.bin")
    binary = Procx.run(["sh", "-c", "printf 'a\\0b\\0c'"], stdout_to: target)
    t.eq("stdout_to leaves nothing in out", binary.out, "")
    t.eq("stdout_to status", binary.status, 0)
    t.eq("stdout_to is NUL-safe", read_file(target), "a\0b\0c")
    t.eq("stdout_to size", File.size(target), 5)
    elsewhere = Procx.run(["sh", "-c", "echo x; echo y 1>&2"], stdout_to: Fsx.join(dir, "with space.txt"))
    t.eq("stdout_to keeps stderr separate", elsewhere.err, "y\n")
    t.eq("stdout_to to a path with a space", read_file(Fsx.join(dir, "with space.txt")), "x\n")
    unwritable = Procx.run(["true"], stdout_to: Fsx.join(dir, "no/such/dir/out"))
    t.ok("stdout_to into a missing directory fails", !unwritable.ok?)
    t.ok("and says why on stderr", unwritable.err.size > 0)
  t.eq("env", Procx.run(["sh", "-c", "printf %s \"$GF2_X\""], env: {"GF2_X" => "it's \"v\" $HOME `x`\nline2"}).out, "it's \"v\" $HOME `x`\nline2")
  t.eq("env with two variables", Procx.run(["sh", "-c", "printf %s-%s \"$GF2_A\" \"$GF2_B\""], env: {"GF2_A" => "1", "GF2_B" => ""}).out, "1-")
  t.eq("env does not leak into the parent", env("GF2_A"), nil)
  # check_output / succeeds?
  t.eq("check_output returns stdout", Procx.check_output(["printf", "%s", "fine"]), "fine")
  failed = nil
  begin
    Procx.check_output(["sh", "-c", "echo oops 1>&2; exit 3"])
  rescue e: ProcError
    failed = e
  t.ok("check_output raises ProcError on failure", failed != nil)
  if failed != nil
    t.eq("ProcError status", failed.status, 3)
    t.eq("ProcError stderr", failed.stderr, "oops\n")
    t.ok("ProcError message names the status", failed.message.include?("status 3"))
    t.ok("ProcError message carries stderr", failed.message.include?("oops"))
    t.ok("ProcError command is the quoted command", failed.command.starts_with?("'sh' '-c'"))
  wordy = nil
  begin
    Procx.check_output(["sh", "-c", "yes err | head -c 2000 1>&2; exit 1"])
  rescue e: ProcError
    wordy = e
  t.ok("a long stderr is clipped in the message", wordy != nil && wordy.message.size < 700)
  t.ok("but kept whole on the error", wordy != nil && wordy.stderr.size == 2000)
  t.eq("succeeds? true", Procx.succeeds?(["true"]), true)
  t.eq("succeeds? false", Procx.succeeds?(["false"]), false)
  t.eq("succeeds? for a missing command", Procx.succeeds?(["gf2-definitely-not-a-command"]), false)

# ---- Procx.run_all -------------------------------------------------------------------------

-> gitx_case_run_all(t)
  jobs = [["sh", "-c", "sleep 0.2; printf a"], ["printf", "b"], ["sh", "-c", "echo e 1>&2; exit 4"], ["sh", "-c", "printf 'x\\0y'"],
          ["pwd"], ["sh", "-c", "kill -9 $$"], ["gf2-definitely-not-a-command"], ["sh", "-c", "printf %s \"$GF2_X\""]]
  results = Procx.run_all(jobs, limit: 3, cwd: "/", env: {"GF2_X" => "it's"})
  outs = results.map -> (result)
    result.out
  statuses = results.map -> (result)
    result.status
  t.eq("run_all: one result per job", results.size, 8)
  t.eq("run_all: results in job order", outs, ["a", "b", "", "x\0y", "/\n", "", "", "it's"])
  t.eq("run_all: statuses", statuses, [0, 0, 4, 0, 0, 137, 127, 0])
  t.eq("run_all: stderr per job", results[2].err, "e\n")
  t.ok("run_all: a missing command says so", results[6].err.include?("not found"))
  t.eq("run_all: NUL bytes survive", results[3].out.size, 3)
  t.eq("run_all of nothing", Procx.run_all([]), [])
  gitx_case_raises(t, "run_all needs a positive limit", "ProcError") ->
    Procx.run_all([["true"]], limit: 0)
  slow = [["sleep", "0.3"], ["sleep", "0.3"], ["sleep", "0.3"], ["sleep", "0.3"]]
  started = clock()
  Procx.run_all(slow, limit: 4)
  together = clock() - started
  started = clock()
  Procx.run_all(slow, limit: 1)
  one_by_one = clock() - started
  t.ok("run_all with limit 1 runs the jobs one after the other", one_by_one >= 1.15)
  t.ok("run_all really runs jobs at the same time", one_by_one > together * 1.5)

# ---- Gitx on a hermetic repository ---------------------------------------------------------

-> gitx_case_env(date)
  {"GIT_CONFIG_GLOBAL" => "/dev/null", "GIT_CONFIG_SYSTEM" => "/dev/null", "GIT_CONFIG_NOSYSTEM" => "1",
   "GIT_AUTHOR_NAME" => "Ada Tester", "GIT_AUTHOR_EMAIL" => "ada@example.org",
   "GIT_COMMITTER_NAME" => "Ada Tester", "GIT_COMMITTER_EMAIL" => "ada@example.org",
   "GIT_AUTHOR_DATE" => date, "GIT_COMMITTER_DATE" => date}

-> gitx_case_git(repo, date, args)
  Procx.check_output(["git", "-C", repo] + args, env: gitx_case_env(date))

# Two commits ("first" tagged v1, "second" = HEAD). The ids below are what plain git computes
# for exactly these bytes, names and dates.
-> gitx_case_make_repo(root)
  repo = Fsx.join(root, "src repo")
  Fsx.mkdir_p(repo)
  early = "2001-02-03T04:05:06+00:00"
  gitx_case_git(repo, early, ["init", "-q", "-b", "main", "."])
  Fsx.mkdir_p(Fsx.join(repo, "dir/sub"))
  files = [["a.txt", "one\n"], ["dir/b.txt", "bee\n"], ["dir/sub/c.txt", "sea\n"], ["empty.txt", ""], ["sp ace.txt", "spaced\n"],
           ["q'uote.txt", "q\n"], ["dq\"uote.txt", "d\n"], ["é.txt", "e\n"], ["nl\nname.txt", "n\n"]]
  files.each -> (file)
    Fsx.write(Fsx.join(repo, file[0]), file[1])
  Procx.check_output(["sh", "-c", "printf 'x\\0y\\0z\\n' > bin.dat"], cwd: repo)
  gitx_case_git(repo, early, ["add", "-A"])
  gitx_case_git(repo, early, ["commit", "-q", "-m", "first: it's \"quoted\" é"])
  gitx_case_git(repo, early, ["tag", "v1"])
  late = "2002-03-04T05:06:07+00:00"
  Fsx.write(Fsx.join(repo, "a.txt"), "one\ntwo\n")
  Fsx.write(Fsx.join(repo, "c.txt"), "cee\n")
  gitx_case_git(repo, late, ["add", "-A"])
  gitx_case_git(repo, late, ["commit", "-q", "-m", "second"])
  repo

-> gitx_case_head
  "704499b14ea824b064eb376e51150f23289c1c00"

-> gitx_case_first
  "9af07d4da42fc75091bcfa2419df572fbb80d365"

-> gitx_case_names
  ["a.txt", "bin.dat", "c.txt", "dir/b.txt", "dir/sub/c.txt", "dq\"uote.txt", "empty.txt", "nl\nname.txt", "q'uote.txt", "sp ace.txt", "é.txt"]

-> gitx_case_repo(t, repo)
  git = Gitx.new(repo)
  t.eq("repo accessor", git.repo, repo)
  gitx_case_raises(t, "a repository directory that does not exist", "GitError") ->
    Gitx.new(repo + "/nope")
  t.eq("no lazy fetch by default", git.env["GIT_NO_LAZY_FETCH"], "1")
  t.eq("no prompts", git.env["GIT_TERMINAL_PROMPT"], "0")
  t.eq("lazy_fetch: true switches it off", Gitx.new(repo, lazy_fetch: true).env["GIT_NO_LAZY_FETCH"], "0")
  # rev_parse
  t.eq("rev_parse HEAD", git.rev_parse("HEAD"), gitx_case_head)
  t.eq("rev_parse a tag", git.rev_parse("v1"), gitx_case_first)
  t.eq("rev_parse HEAD~1", git.rev_parse("HEAD~1"), gitx_case_first)
  t.eq("rev_parse HEAD^", git.rev_parse("HEAD^"), gitx_case_first)
  t.eq("rev_parse an abbreviation", git.rev_parse("704499b"), gitx_case_head)
  t.eq("rev_parse a tree", git.rev_parse("v1^{tree}"), "8fa613c85dffc2be8fecb60d86b3163cf594f4bf")
  t.eq("rev_parse a path in a revision", git.rev_parse("HEAD:dir"), "0ded10800637a0e1167dc3373fba0154a1f05905")
  gitx_case_raises(t, "rev_parse of an unknown name", "GitError") ->
    git.rev_parse("no-such-rev")
  gitx_case_raises(t, "rev_parse of nothing", "GitError") ->
    git.rev_parse("")
  gitx_case_raises(t, "rev_parse refuses option lookalikes", "GitError") ->
    git.rev_parse("--upload-pack=evil")
  gitx_case_raises(t, "rev_parse of a range", "GitError") ->
    git.rev_parse("v1..HEAD")
  failure = nil
  begin
    git.rev_parse("no-such-rev")
  rescue e: GitError
    failure = e
  t.ok("GitError carries git's status and stderr", failure != nil && failure.status == 128 && failure.stderr.include?("fatal"))
  # ls_tree
  t.eq("ls_tree of HEAD", git.ls_tree("HEAD"), gitx_case_names)
  t.eq("ls_tree by full id", git.ls_tree(gitx_case_head), gitx_case_names)
  t.eq("ls_tree of the tag", git.ls_tree("v1"), gitx_case_names.select -> (name)
    name != "c.txt")
  t.eq("ls_tree below a directory", git.ls_tree("HEAD", "dir"), ["dir/b.txt", "dir/sub/c.txt"])
  t.eq("ls_tree below a nested directory", git.ls_tree("HEAD", "dir/sub"), ["dir/sub/c.txt"])
  t.eq("ls_tree of a single file", git.ls_tree("HEAD", "a.txt"), ["a.txt"])
  t.eq("ls_tree of a path that is not there", git.ls_tree("HEAD", "nowhere"), [])
  t.eq("ls_tree keeps names raw (space, quotes, newline, unicode)", git.ls_tree("HEAD", "nl\nname.txt"), ["nl\nname.txt"])
  t.eq("ls_tree of a space in a path", git.ls_tree("HEAD", "sp ace.txt"), ["sp ace.txt"])
  t.eq("ls_tree of a unicode path", git.ls_tree("HEAD", "é.txt"), ["é.txt"])
  t.eq("ls_tree path starting with a dash is a path", git.ls_tree("HEAD", "-x"), [])
  gitx_case_raises(t, "ls_tree of an unknown revision", "GitError") ->
    git.ls_tree("no-such-rev")
  gitx_case_raises(t, "ls_tree refuses option lookalikes", "GitError") ->
    git.ls_tree("--name-only")
  # show
  t.eq("show a.txt at HEAD", git.show("HEAD", "a.txt"), "one\ntwo\n")
  t.eq("show a.txt at the tag", git.show("v1", "a.txt"), "one\n")
  t.eq("show a nested file", git.show("HEAD", "dir/sub/c.txt"), "sea\n")
  t.eq("show an empty file is empty text, not nil", git.show("HEAD", "empty.txt"), "")
  t.eq("show keeps NUL bytes", git.show("HEAD", "bin.dat"), "x\0y\0z\n")
  t.eq("show a name with a space", git.show("HEAD", "sp ace.txt"), "spaced\n")
  t.eq("show a name with an apostrophe", git.show("HEAD", "q'uote.txt"), "q\n")
  t.eq("show a name with a double quote", git.show("HEAD", "dq\"uote.txt"), "d\n")
  t.eq("show a unicode name", git.show("HEAD", "é.txt"), "e\n")
  t.eq("show a name with a newline", git.show("HEAD", "nl\nname.txt"), "n\n")
  t.eq("show a file the old commit did not have", git.show("v1", "c.txt"), nil)
  t.eq("show a path that is not there", git.show("HEAD", "no/such/path"), nil)
  t.eq("show at an unknown revision", git.show("no-such-rev", "a.txt"), nil)
  t.eq("show! returns the same text", git.show!("HEAD", "dir/b.txt"), "bee\n")
  gitx_case_raises(t, "show! of a missing path", "GitError") ->
    git.show!("HEAD", "no/such/path")
  gitx_case_raises(t, "show refuses option lookalikes", "GitError") ->
    git.show("--help", "a.txt")
  # cat-file family
  t.eq("exists? a blob", git.exists?("HEAD:a.txt"), true)
  t.eq("exists? a tree", git.exists?("HEAD:dir"), true)
  t.eq("exists? a commit", git.exists?(gitx_case_head), true)
  t.eq("exists? a missing path", git.exists?("HEAD:nothing"), false)
  t.eq("exists? a missing id", git.exists?("0123456789012345678901234567890123456789"), false)
  t.eq("cat_file of a blob", git.cat_file("HEAD:a.txt"), "one\ntwo\n")
  t.eq("cat_file keeps NUL bytes", git.cat_file("HEAD:bin.dat"), "x\0y\0z\n")
  t.eq("cat_file of a tree lists it", git.cat_file("HEAD:dir"), "100644 blob af9c6fd168ea28cf99aa2c2dd9057a8b720e2262\tb.txt\n040000 tree 24b75148452cffd637bd82a4e35b48f22efb8c66\tsub\n")
  t.eq("cat_file of a missing object", git.cat_file("HEAD:nothing"), nil)
  t.eq("cat_file_size of a blob", git.cat_file_size("HEAD:a.txt"), 8)
  t.eq("cat_file_size of the empty blob", git.cat_file_size("HEAD:empty.txt"), 0)
  t.eq("cat_file_size of the NUL blob", git.cat_file_size("HEAD:bin.dat"), 6)
  t.eq("cat_file_size of a missing object", git.cat_file_size("HEAD:nothing"), nil)
  t.eq("cat_file_type blob", git.cat_file_type("HEAD:a.txt"), "blob")
  t.eq("cat_file_type tree", git.cat_file_type("HEAD:dir"), "tree")
  t.eq("cat_file_type commit", git.cat_file_type("HEAD"), "commit")
  t.eq("cat_file_type of a missing object", git.cat_file_type("HEAD:nothing"), nil)
  gitx_case_raises(t, "cat_file refuses option lookalikes", "GitError") ->
    git.cat_file("--batch")
  # log1
  t.eq("log1 %H", git.log1("HEAD", "%H"), gitx_case_head)
  t.eq("log1 %h %ci", git.log1("HEAD", "%h %ci"), "704499b 2002-03-04 05:06:07 +0000")
  t.eq("log1 %aI", git.log1("HEAD", "%aI"), "2002-03-04T05:06:07Z")
  t.eq("log1 %s", git.log1("HEAD", "%s"), "second")
  t.eq("log1 of the tag", git.log1("v1", "%h %ci"), "9af07d4 2001-02-03 04:05:06 +0000")
  t.eq("log1 with quotes and unicode in the subject", git.log1("v1", "%s"), "first: it's \"quoted\" é")
  t.eq("log1 is stripped", git.log1("HEAD", "%s%n"), "second")
  gitx_case_raises(t, "log1 of an unknown revision", "GitError") ->
    git.log1("no-such-rev", "%H")

# The c-style unquoting of ls-tree names, on its own.
-> gitx_case_unquote(t)
  t.eq("unquote a plain name", Gitx.unquote("\"plain.txt\""), "plain.txt")
  t.eq("unquote a tab", Gitx.unquote("\"a\\tb\""), "a\tb")
  t.eq("unquote a newline", Gitx.unquote("\"a\\nb\""), "a\nb")
  t.eq("unquote every one-letter escape", Gitx.unquote("\"\\a\\b\\t\\n\\v\\f\\r\\\"\\\\\""), 7.chr + 8.chr + "\t\n" + 11.chr + 12.chr + "\r\"\\")
  t.eq("unquote an octal escape", Gitx.unquote("\"x\\033y\""), "x" + 27.chr + "y")
  t.eq("unquote octal DEL", Gitx.unquote("\"\\177\""), 127.chr)
  t.eq("unquote leaves unicode alone", Gitx.unquote("\"é/ü 日本語\""), "é/ü 日本語")
  t.eq("unquote a backslash followed by digits", Gitx.unquote("\"oct\\\\101\""), "oct\\101")
  t.eq("unquote the empty name", Gitx.unquote("\"\""), "")
  gitx_case_raises(t, "unquote refuses escaped non-ASCII bytes", "GitError") ->
    Gitx.unquote("\"\\303\\251\"")

# Names git c-quotes in ls-tree output survive a round trip through a real repository.
-> gitx_case_quoting(t, root)
  repo = Fsx.join(root, "quoting repo")
  Fsx.mkdir_p(repo)
  date = "2003-04-05T06:07:08+00:00"
  gitx_case_git(repo, date, ["init", "-q", "-b", "main", "."])
  names = ["plain.txt", "tab\there.txt", "back\\slash.txt", "quo\"te.txt", "new\nline.txt", "bell" + 7.chr + ".txt", "del" + 127.chr + ".txt",
           "esc" + 27.chr + "\[0m.txt", "\"leading-quote.txt", "-dash.txt", "sp ace.txt", "é/ü ñ.txt", "日本語.txt", "oct\\101.txt", "cr\rname.txt"]
  names.each_with_index -> (name, at)
    path = Fsx.join(repo, name)
    Fsx.mkdir_p(Fsx.dirname(path))
    Fsx.write(path, "content " + at.to_s + "\n")
  gitx_case_git(repo, date, ["add", "-A"])
  gitx_case_git(repo, date, ["commit", "-q", "-m", "odd names"])
  git = Gitx.new(repo)
  t.eq("ls_tree returns every odd name exactly", git.ls_tree("HEAD").sort, names.sort)
  t.eq("ls_tree below a directory with odd names", git.ls_tree("HEAD", "é"), ["é/ü ñ.txt"])
  names.each_with_index -> (name, at)
    t.eq("show of an odd name (" + at.to_s + ")", git.show("HEAD", name), "content " + at.to_s + "\n")

# A blob-less clone of the hermetic repository: nothing may be fetched, unless asked.
-> gitx_case_partial(t, root, repo)
  gitx_case_git(repo, "2001-02-03T04:05:06+00:00", ["config", "uploadpack.allowFilter", "true"])
  gitx_case_git(repo, "2001-02-03T04:05:06+00:00", ["config", "uploadpack.allowAnySHA1InWant", "true"])
  clone = Fsx.join(root, "partial clone")
  Procx.check_output(["git", "clone", "-q", "--no-local", "--filter=blob:none", "--no-checkout", repo, clone], env: gitx_case_env("2001-02-03T04:05:06+00:00"))
  before = Fsx.walk(Fsx.join(clone, ".git")).map -> (path)
    path + ":" + Fsx.size(path).to_s
  git = Gitx.new(clone)
  t.eq("the partial clone knows the tree", git.ls_tree("HEAD"), gitx_case_names)
  t.eq("the partial clone knows the commit", git.rev_parse("HEAD"), gitx_case_head)
  t.eq("a missing blob is nil, not a download", git.show("HEAD", "a.txt"), nil)
  t.eq("exists? is false for a blob that was not fetched", git.exists?("HEAD:a.txt"), false)
  t.eq("cat_file of an unfetched blob", git.cat_file("HEAD:a.txt"), nil)
  t.eq("cat_file_size of an unfetched blob", git.cat_file_size("HEAD:a.txt"), nil)
  gitx_case_raises(t, "show! of an unfetched blob", "GitError") ->
    git.show!("HEAD", "a.txt")
  after = Fsx.walk(Fsx.join(clone, ".git")).map -> (path)
    path + ":" + Fsx.size(path).to_s
  t.eq("nothing was written to the clone's .git", after, before)
  # now allow it
  eager = Gitx.new(clone, lazy_fetch: true)
  t.eq("lazy_fetch: true downloads the blob", eager.show("HEAD", "a.txt"), "one\ntwo\n")
  t.eq("and the blob is now local for the strict reader too", git.show("HEAD", "a.txt"), "one\ntwo\n")

# ---- Gitx on the pinned upstream clones ----------------------------------------------------

# The pinned clones are blob-less: one lazy fetch adds packs to them for good. So the cases
# refuse to touch a clone through a Gitx that could fetch, export GIT_NO_LAZY_FETCH=1 for the
# whole block as a second line of defence, and check that no pack file appeared.
-> gitx_case_open(t, work, name)
  git = Gitx.new(work + "/upstream/" + name)
  strict = git.env["GIT_NO_LAZY_FETCH"] == "1"
  t.ok("pinned clone " + name + " is read without lazy fetch", strict)
  strict ? git : nil

-> gitx_case_packs(work, name)
  Fsx.entries(work + "/upstream/" + name + "/.git/objects/pack").size

-> gitx_case_real(t, dir)
  work = gitx_case_work_dir
  unless File.directory?(work + "/upstream/fmm/.git")
    << "SKIP gitx real clones: no record-hunt work directory at " + work
    return nil
  outer = env("GIT_NO_LAZY_FETCH")
  Env.set("GIT_NO_LAZY_FETCH", "1")
  names = ["fmm", "mmc", "merlijn", "fmm_digest"]
  packs = names.map -> (name)
    gitx_case_packs(work, name)
  gitx_case_real_rows(t, dir, work)
  again = names.map -> (name)
    gitx_case_packs(work, name)
  t.eq("no pack file appeared in any pinned clone", again, packs)
  if outer == nil
    Env.delete("GIT_NO_LAZY_FETCH")
  else
    Env.set("GIT_NO_LAZY_FETCH", outer)
  nil

-> gitx_case_real_rows(t, dir, work)
  gitx_case_rows(dir, "real_log.tsv").each -> (row)
    git = gitx_case_open(t, work, row[0])
    if git != nil
      t.eq("rev_parse " + row[0] + " " + row[1], git.rev_parse(row[1]), row[2])
      t.eq("log1 %H " + row[0] + " " + row[1], git.log1(row[1], "%H"), row[2])
      t.eq("log1 %h %ci " + row[0] + " " + row[1], git.log1(row[1], "%h %ci"), row[3])
      t.eq("log1 %aI " + row[0] + " " + row[1], git.log1(row[1], "%aI"), row[4])
      t.eq("log1 %s " + row[0] + " " + row[1], git.log1(row[1], "%s"), row[5])
  gitx_case_rows(dir, "real_ls_tree.tsv").each -> (row)
    git = gitx_case_open(t, work, row[0])
    if git != nil
      listed = git.ls_tree(row[1], row[2] == "-" ? nil : row[2])
      t.eq("ls_tree count " + row[0] + " " + row[1] + " " + row[2], listed.size, row[3].to_i)
      t.eq("ls_tree names " + row[0] + " " + row[1] + " " + row[2], gitx_case_digest(listed.join("\n") + "\n"), row[4])
  gitx_case_rows(dir, "real_probe.tsv").each -> (row)
    git = gitx_case_open(t, work, row[0])
    if git != nil
      blob = git.show(row[1], row[2])
      if row[3] == "ok"
        t.eq("show size " + row[0] + " " + row[2], blob == nil ? -1 : blob.size, row[4].to_i)
        t.eq("show digest " + row[0] + " " + row[2], blob == nil ? "" : gitx_case_digest(blob), row[5])
        t.eq("cat_file_size " + row[0] + " " + row[2], git.cat_file_size(row[1] + ":" + row[2]), row[4].to_i)
      else
        t.eq("show of an unavailable blob is nil " + row[0] + " " + row[2], blob, nil)
  nil

# Procx and Gitx clean up their temporary files, successes and failures alike. TMPDIR points at
# a private directory for the duration, so a concurrent test run cannot disturb the count.
-> gitx_case_litter(t, repo)
  Fsx.with_tempdir(prefix: "gf2-litter-") -> (scratch)
    previous = env("TMPDIR")
    Env.set("TMPDIR", scratch)
    begin
      Procx.run(["true"])
      Procx.run(["sh", "-c", "echo e 1>&2; exit 2"])
      Procx.run(["true"], stderr: :null)
      Procx.run(["printf", "x"], stdout_to: Fsx.join(scratch, "kept.txt"))
      Procx.succeeds?(["false"])
      Procx.run_all([["true"], ["sh", "-c", "echo e 1>&2; exit 2"]], limit: 2)
      begin
        Procx.check_output(["sh", "-c", "exit 3"])
      rescue e: ProcError
        nil
      git = Gitx.new(repo)
      git.rev_parse("HEAD")
      git.ls_tree("HEAD")
      git.show("HEAD", "a.txt")
      git.show("HEAD", "nope")
      git.cat_file("HEAD:a.txt")
      git.exists?("HEAD:nope")
      git.log1("HEAD", "%H")
      begin
        git.rev_parse("nope")
      rescue e: GitError
        nil
    ensure
      if previous == nil
        Env.delete("TMPDIR")
      else
        Env.set("TMPDIR", previous)
    t.eq("no temporary file is left behind", Fsx.entries(scratch), ["kept.txt"])

-> gf2_gitx_cases(t)
  gitx_case_procx(t)
  gitx_case_run_all(t)
  gitx_case_unquote(t)
  Fsx.with_tempdir(prefix: "gf2 gitx ") -> (root)
    repo = gitx_case_make_repo(root)
    gitx_case_repo(t, repo)
    gitx_case_quoting(t, root)
    gitx_case_partial(t, root, repo)
    gitx_case_litter(t, repo)
  gitx_case_real(t, gitx_case_fixture_dir)
