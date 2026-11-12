# Gitx: read-only git access to one repository, without ever fetching.
#
# The pinned upstream clones of the record hunt (FastMatrixMultiplication, matmulcatalog, ...)
# are blob-less partial clones: every tree is local, most blobs are not. A plain `git show` of
# a missing blob silently downloads it, which changes the clone under our feet. Every call made
# here therefore runs `git -C REPO ...` with GIT_NO_LAZY_FETCH=1 (and GIT_TERMINAL_PROMPT=0),
# so a missing object is an ordinary failure (`show` answers nil) instead of a network fetch.
# `Gitx.new(repo, lazy_fetch: true)` opts back in for a scratch clone that is meant to fill up.
#
# The calls are exactly the ones the Python/Ruby originals make:
#   ls_tree   gf2_record_board.py public_tables, screen_public_ternary_gf2.py integer_files,
#             mmc_gf2_replay.py Source.__init__   ['git', '-C', clone, 'ls-tree', '-r', '--name-only', rev, path]
#   show      verify_gf2_lineage.py upstream_file, mmc_gf2_replay.py Source.raw,
#             screen_public_ternary_gf2.py seeds   ['git', '-C', clone, 'show', f'{rev}:{path}']
#   rev_parse screen_public_ternary_gf2.py seeds, mmc_gf2_replay.py Source.__init__,
#             collect_chains.py (`47ad44dc5^`)      ['git', '-C', clone, 'rev-parse', rev]
#   log1      setup_restore.sh / comparators.json   git log -1 --format='%h %ci' (%H %h %ci %aI %s)
#   exists? / cat_file / cat_file_size / cat_file_type   git cat-file -e / -p / -s / -t
#
# Speed: a call is one shell plus git and touches no file (stderr is dropped). When a call fails
# and the caller needs the reason (rev_parse, log1, show!) the same read-only command is run
# again with stderr captured. Text with a NUL byte in it (a binary blob) cannot travel through
# `capture`; that case, and only that one, is read again through a temporary file.
use procx

# Raised for a failed git call; `status` and `stderr` are those of the git process.
+ GitError < Error
  -> new(@message, @status, @stderr)
  ro :status, :stderr

+ Gitx
  # `repo` is the working tree (or git directory) handed to `git -C`; it must exist.
  -> new(@repo, lazy_fetch: false)
    raise GitError.new("no such repository directory: " + @repo.to_s, nil, "") unless File.directory?(@repo)
    @env = {"GIT_NO_LAZY_FETCH" => lazy_fetch ? "0" : "1", "GIT_TERMINAL_PROMPT" => "0"}

  ro :repo, :env

  # `git ls-tree -r --name-only REV [-- PATH]`: the file names below PATH (all files when PATH
  # is nil) in the order git lists them, relative to the repository root. Names come back as
  # their raw bytes: git's c-style quoting of a name with a quote, backslash or control
  # character (a newline included) is undone. GitError when git fails (unknown revision).
  -> ls_tree(rev, path = nil)
    check_spec(rev)
    args = ["-c", "core.quotepath=off", "ls-tree", "-r", "--name-only", rev]
    args = args + ["--", path] if path != nil
    names = []
    answer!(args).split("\n").each -> (line)
      names.push(line.starts_with?("\"") ? Gitx.unquote(line) : line) unless line == ""
    names

  # `git show REV:PATH`: the blob's bytes as a String, or nil when git cannot deliver it (no
  # such path, or the blob is not in this clone and fetching is off).
  -> show(rev, path)
    check_spec(rev)
    answer(["show", rev + ":" + path])

  # Like show, but a missing object raises GitError with git's message.
  -> show!(rev, path)
    check_spec(rev)
    answer!(["show", rev + ":" + path])

  # `git rev-parse --verify REV`: the full object name REV stands for. Raises GitError when it
  # names nothing (or more than one object).
  -> rev_parse(rev)
    check_spec(rev)
    answer!(["rev-parse", "--verify", rev]).strip

  # `git cat-file -e SPEC`: true when the object is available in this clone.
  -> exists?(spec)
    check_spec(spec)
    query(["cat-file", "-e", spec]).ok?

  # `git cat-file -p SPEC`: the object's content as a String, or nil when unavailable.
  -> cat_file(spec)
    check_spec(spec)
    answer(["cat-file", "-p", spec])

  # `git cat-file -s SPEC`: the object's size in bytes (Integer), or nil when unavailable.
  -> cat_file_size(spec)
    check_spec(spec)
    size = answer(["cat-file", "-s", spec])
    size == nil ? nil : size.strip.to_i

  # `git cat-file -t SPEC`: "blob", "tree", "commit" or "tag", or nil when unavailable.
  -> cat_file_type(spec)
    check_spec(spec)
    type = answer(["cat-file", "-t", spec])
    type == nil ? nil : type.strip

  # `git log -1 --format=FORMAT REV`, stripped: one commit field such as %H, %h, %ci, %aI or %s.
  -> log1(rev, format)
    check_spec(rev)
    answer!(["log", "-1", "--format=" + format, rev]).strip

  # ---- internals ------------------------------------------------------------------------

  # A revision or object name must not look like an option.
  -> check_spec(spec)
    if spec.to_s == "" || spec.to_s.starts_with?("-")
      raise GitError.new("invalid revision or object name: " + spec.to_s, nil, "")

  # Runs git quietly and returns a ProcResult whose #out is git's exact stdout. A NUL byte in
  # the output cuts `capture` short; then the command is run again with stdout in a file.
  -> query(args)
    command = ["git", "-C", @repo] + args
    result = Procx.run(command, env: @env, stderr: :null)
    return result unless result.truncated?
    path = tempfile_create("gitx-", nil)
    raise GitError.new("cannot create a temporary file", nil, "") if path == nil
    begin
      result = Procx.run(command, env: @env, stderr: :null, stdout_to: path)
      text = result.ok? ? read_file(path) : nil
      result = ProcResult.new(result.status, text == nil ? "" : text, "")
    ensure
      file_unlink(path)
    result

  # git's stdout, or nil when the command failed.
  -> answer(args)
    result = query(args)
    result.ok? ? result.out : nil

  # git's stdout; GitError (with git's own message, gathered by running it once more with
  # stderr captured) when the command failed.
  -> answer!(args)
    result = query(args)
    return result.out if result.ok?
    again = Procx.run(["git", "-C", @repo] + args, env: @env)
    detail = again.err.strip
    detail = detail.slice(0, 400) if detail.size > 400
    raise GitError.new("git " + args.join(" ") + " failed with status " + result.status.to_s + ": " + detail, result.status, again.err)

  # The name inside one c-quoted ls-tree line ("...") with its escapes resolved. With
  # core.quotepath=off git only escapes ASCII: \a \b \t \n \v \f \r \" \\ and \ooo for the rest.
  -> .unquote(line)
    body = line.slice(1, line.size - 2)
    bytes = body.bytes
    out = StringBuffer(body.size)
    run = 0
    at = 0
    while at < bytes.size
      if bytes[at] != 92
        at += 1
      else
        out << body.slice(run, at - run)
        at += 1
        lead = bytes[at]
        code = Gitx.escape_code(lead)
        if code == nil
          code = (lead - 48) * 64 + (bytes[at + 1] - 48) * 8 + (bytes[at + 2] - 48)
          at += 2
        raise GitError.new("unexpected escape in a ls-tree name: " + line, nil, "") if code < 0 || code > 127
        out << code.chr
        at += 1
        run = at
    out << body.slice(run, bytes.size - run)
    out.to_s

  # The byte a one-letter C escape stands for (a \ b \ t \ n \ v \ f \ r " \), nil for an octal digit.
  -> .escape_code(letter)
    return 7 if letter == 97
    return 8 if letter == 98
    return 9 if letter == 116
    return 10 if letter == 110
    return 11 if letter == 118
    return 12 if letter == 102
    return 13 if letter == 114
    return 34 if letter == 34
    return 92 if letter == 92
    nil
