require "tmpdir"
require "fileutils"
require "open3"
require "timeout"
require "json"
ROOT = File.realpath(File.join(__dir__, "../../.."))
WORKER = File.join(ROOT, "bits/tungsten-av/tests/crash_worker.w")
def wait_file(path, pid)
  Timeout.timeout(180) do
    until File.exist?(path)
      raise "worker exited before barrier" if Process.waitpid(pid, Process::WNOHANG)
      sleep 0.02
    end
  end
end
Dir.mktmpdir("av-native-crash-") do |root|
  binary = File.join(root, "worker")
  out, err, built = Open3.capture3({"BASH_ENV" => nil}, File.join(ROOT, "bin/tungsten"), "-o", binary, WORKER, chdir: ROOT)
  raise "crash worker compile failed: #{out}\n#{err}" unless built.success?
  %w[master.mov share.mp4].each { |name| File.write(File.join(root, name), "old #{name}") }
  run = lambda do
    out, err, status = Open3.capture3({"BASH_ENV" => nil}, binary, "publish", root, chdir: ROOT)
    raise "publisher failed: #{out}\n#{err}" unless status.success?
  end
  run.call
  %w[before after].each do |boundary|
    old = %w[master.mov share.mp4].map { |n| File.binread(File.join(root, "published", n)) }
    %w[master.mov share.mp4].each { |name| File.write(File.join(root, name), "#{boundary} #{name}") }
    marker = File.join(root, "barrier")
    env = {"BASH_ENV" => nil, "TUNGSTEN_AV_TEST_BARRIER" => "#{boundary}-activation", "TUNGSTEN_AV_TEST_MARKER" => marker}
    pid = Process.spawn(env, binary, "publish", root, chdir: ROOT, out: File.join(root, "log"), err: [:child, :out], pgroup: true)
    begin
      wait_file(marker, pid)
      target = JSON.parse(File.read(marker))["pid"]
      raise "barrier PID mismatch: #{target} != #{pid}" unless target == pid
      Process.kill("KILL", target)
      Process.wait(pid)
      actual = %w[master.mov share.mp4].map { |n| File.binread(File.join(root, "published", n)) }
      wanted = boundary == "before" ? old : %w[master.mov share.mp4].map { |n| File.binread(File.join(root, n)) }
      raise "mixed release after #{boundary} activation" unless actual == wanted
    ensure
      Process.kill("KILL", target) rescue Errno::ESRCH
      Process.wait(pid) rescue Errno::ECHILD
      FileUtils.rm_f(marker)
    end
    run.call
    puts "PASS coherent bundle after SIGKILL #{boundary} activation"
  end
  pid = Process.spawn({"BASH_ENV" => nil}, binary, "supervise", root, chdir: ROOT, out: File.join(root, "log"), err: [:child, :out], pgroup: true)
  begin
    marker = File.join(root, "child.pid")
    wait_file(marker, pid)
    child = Integer(File.read(marker))
    Process.kill("TERM", Integer(File.read(File.join(root, "parent.pid"))))
    Timeout.timeout(10) { Process.wait(pid) }
    sleep 0.2
    alive = begin Process.kill(0, child); true; rescue Errno::ESRCH; false; end
    raise "cancelled stage left a descendant" if alive
    puts "PASS cancellation terminates descendant process group"
  ensure
    Process.kill("KILL", pid) rescue Errno::ESRCH
    Process.wait(pid) rescue Errno::ECHILD
  end
end
