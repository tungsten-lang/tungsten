state = ccall_rawargs("w_content_temp_map_new", 4, 2)
ccall_nobox("w_content_temp_map_seed", state, "%left", 0)
ccall_nobox("w_content_temp_map_seed", state, "%t3", 1)

<< ccall("w_content_temp_norm", "%left", state)
<< ccall("w_content_temp_norm", "%t3", state)
<< ccall("w_content_temp_norm", "%t1", state)
<< ccall("w_content_temp_norm", "%named", state)
<< ccall("w_content_temp_norm", "%named", state)
