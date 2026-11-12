# ippeveprinter passes one spool file and its IPP attributes in the environment.
-> notify_failure(message)
  Process.spawn(["/usr/bin/osascript", "-e", "display notification \"" + message + "\" with title \"Amazon Return Label Printer\""]).wait

-> fail_job(message, notification)
  ccall("w_eputs", "ERROR: " + message)
  notify_failure(notification)
  exit(1)

args = argv()
if env("CONTENT_TYPE") != "application/pdf" || args.size != 1
  fail_job("This label bridge supports PDF jobs only.", "This label needs PDF output; the phone sent an unsupported format.")
copies = env("IPP_COPIES")
if copies != nil && copies != "" && copies != "1"
  fail_job("Please print one copy at a time.", "Please print one copy at a time.")
root = ccall("w_executable_dir")
if root == nil || root == ""
  fail_job("Cannot locate the executable directory.", "Could not locate the label program.")
result = Process.spawn([root + "/print-label", args[0]]).wait
if result != 0
  ccall("w_eputs", "ERROR: Label extraction or submission failed; see the bridge log.")
  notify_failure("Could not extract or submit the label. Check the bridge log.")
  exit(result)
ccall("w_eputs", "INFO: Label submitted to the Rollo queue.")
exit(0)
