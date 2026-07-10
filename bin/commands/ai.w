# tungsten ai — generate Tungsten code via Anthropic API
#
# Usage: tungsten ai describe what you want
# Requires ANTHROPIC_API_KEY.

args = argv()
prompt = args.join(" ")

if prompt == "-h"
  << "Usage: tungsten ai 'describe what you want'"
  exit(0)
if prompt == "--help"
  << "Usage: tungsten ai 'describe what you want'"
  exit(0)
if prompt == nil
  << "Usage: tungsten ai 'describe what you want'"
  exit(1)
if prompt.strip() == ""
  << "Usage: tungsten ai 'describe what you want'"
  exit(1)

api_key = env("ANTHROPIC_API_KEY")
if api_key == nil
  << "Missing ANTHROPIC_API_KEY"
  exit(1)
if api_key == ""
  << "Missing ANTHROPIC_API_KEY"
  exit(1)

system_prompt = "You are a Tungsten programming language expert. Write valid Tungsten code only: << for print, -> methods, + classes, indent blocks, no markdown fences."

-> json_escape(s)
  out = s
  out = out.replace("\\", "\\\\")
  out = out.replace("\"", "\\\"")
  out = out.replace("\n", "\\n")
  out = out.replace("\r", "\\r")
  out = out.replace("\t", "\\t")
  out

# Build JSON without "[" inside double-quoted literals (that is string interpolation).
lb = "["
rb = "]"
lc = "{"
rc = "}"
body = lc
body = body + "\"model\":\"claude-sonnet-4-20250514\","
body = body + "\"max_tokens\":2048,"
body = body + "\"system\":\"" + json_escape(system_prompt) + "\","
body = body + "\"messages\":" + lb + lc
body = body + "\"role\":\"user\",\"content\":\"" + json_escape(prompt) + "\""
body = body + rc + rb
body = body + rc

tmp = "/tmp/tungsten-ai-body.json"
write_file(tmp, body)

<< "Forging..."

cmd = "curl -sS -X POST https://api.anthropic.com/v1/messages"
cmd = cmd + " -H 'Content-Type: application/json'"
cmd = cmd + " -H 'x-api-key: " + api_key + "'"
cmd = cmd + " -H 'anthropic-version: 2023-06-01'"
cmd = cmd + " --data-binary @" + tmp

resp = capture(cmd)
system("rm -f " + tmp)

if resp == nil
  << "Empty response from API"
  exit(1)
if resp.strip() == ""
  << "Empty response from API"
  exit(1)

parsed = JSON.parse(resp)
if parsed["error"] != nil
  << "API error: " + parsed["error"].to_s()
  exit(1)

content = parsed["content"]
if content == nil
  << "Unexpected API response"
  exit(1)
if content.size() == 0
  << "Unexpected API response"
  exit(1)

code = content[0]["text"]
if code == nil
  << "No text in API response"
  exit(1)
code = code.strip()

<< "---"
<< code
<< "---"
<< ""
<< "Run this? (y/n)"
answer = gets()
if answer != nil
  a = answer.strip()
  if a == "y"
    << ""
    run_tmp = "/tmp/tungsten-ai-run.w"
    write_file(run_tmp, code + "\n")
    root = env("TUNGSTEN_ROOT")
    if root == nil
      root = "."
    compiler = root + "/bin/tungsten-compiler"
    system("'" + compiler + "' run '" + run_tmp + "'")
