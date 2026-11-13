use ../lib/cli

args = argv()
if args.size == 0
  << JSON.encode({"ok": false, "error": "missing AV command"})
  exit(2)
Av:Commands:Dispatch.run(args[0], args.slice(1, args.size))
