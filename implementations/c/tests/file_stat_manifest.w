metadata = file_stat_data("tests/file_stat_manifest.w", true)
<< metadata != nil
<< metadata[14] == "file"
<< metadata[7] > 0
<< metadata[11] > 0
<< digest_file64("tests/file_stat_manifest.w") != nil
<< digest_file64("tests/does-not-exist.w") == nil
