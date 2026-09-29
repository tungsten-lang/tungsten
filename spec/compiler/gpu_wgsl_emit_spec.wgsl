// Tungsten @gpu kernel output (WGSL dialect) — do not edit by hand

var<workgroup> tungsten_internal_wg_wgsl_control_tile : array<f32, 256>;
@group(0) @binding(0) var<storage, read_write> tungsten_internal_bind_wgsl_control_counters : array<atomic<i32>>;
@group(0) @binding(1) var<storage, read_write> tungsten_internal_bind_wgsl_control_values : array<f32>;
@group(0) @binding(2) var<uniform> tungsten_internal_bind_wgsl_control_n : i32;
@compute @workgroup_size(256)
fn wgsl_control(@builtin(global_invocation_id) tungsten_internal_tid : vec3<u32>,
   @builtin(local_invocation_id) tungsten_internal_tid_local : vec3<u32>,
   @builtin(workgroup_id) tungsten_internal_group_id : vec3<u32>) {
  var i = i32(tungsten_internal_tid.x);
  var lane = i32(tungsten_internal_tid_local.x);
  var group = i32(tungsten_internal_group_id.x);
  if ((tungsten_internal_bind_wgsl_control_n < 0)) {
    return;
  }
  loop {
    if (!((i < tungsten_internal_bind_wgsl_control_n))) { break; }
    if ((lane == 0)) {
      var old_add = atomicAdd(&tungsten_internal_bind_wgsl_control_counters[group], 1);
    } else {
      var old_load = atomicLoad(&tungsten_internal_bind_wgsl_control_counters[group]);
    }
    var old_exchange = atomicExchange(&tungsten_internal_bind_wgsl_control_counters[group], lane);
    var old_min = atomicMin(&tungsten_internal_bind_wgsl_control_counters[group], old_exchange);
    atomicStore(&tungsten_internal_bind_wgsl_control_counters[group], old_min);
    tungsten_internal_wg_wgsl_control_tile[lane] = tungsten_internal_bind_wgsl_control_values[i];
    workgroupBarrier();
    i += 256;
  }
}

@group(0) @binding(3) var<storage, read_write> tungsten_internal_bind_wgsl_secondary_output : array<f32>;
@compute @workgroup_size(256)
fn wgsl_secondary(@builtin(global_invocation_id) tungsten_internal_tid : vec3<u32>,
   @builtin(local_invocation_id) tungsten_internal_tid_local : vec3<u32>,
   @builtin(workgroup_id) tungsten_internal_group_id : vec3<u32>) {
  var i = i32(tungsten_internal_tid.x);
  var unsigned_i = u32(i);
  tungsten_internal_bind_wgsl_secondary_output[i] = 1.0;
}

