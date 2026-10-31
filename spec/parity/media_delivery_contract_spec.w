# Pure validation helpers remain consistent on all engines.
raise "HEVC pinning" if !Transcode.level_pinnable?(:hevc10)
raise "H264 pinning" if !Transcode.level_pinnable?(:h264)
raise "retry classification" if Transcode.retryable?("missing input") || !Transcode.retryable?("VideoToolbox dropped a frame")
raise "HEVC dotted level alias" if Transcode.level_row(:hevc10, "4.0")[1] != 120
raise "H264 integer level alias" if Transcode.level_row(:h264, "4")[1] != 40
<< "PASS media delivery validation helpers"
