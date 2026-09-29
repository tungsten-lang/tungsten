"""post a message to ~/.tungsten/chats/robolab.txt as 'Claude sprint agent' (the file's own format: --- separators)."""
import sys, datetime, os
msg = sys.stdin.read().strip()
t = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%MZ")
path = os.path.expanduser("~/.tungsten/chats/robolab.txt")
with open(path, "a") as f:
    f.write(f"\n---\nFrom: Claude sprint agent\nTime: {t}\n{msg}\n")
print("posted", t)
