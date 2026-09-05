# Setter calls remain potentially raising even when the RHS is a literal.
+ BoundedSetting
  -> new
    @value = ~1.0
  -> value
    @value
  -> value=(value)
    raise "positive setting required" if value <= ~0.0
    @value = value

setting = BoundedSetting.new
assignment_caught = false
begin
  setting.value = ~0.0
rescue error
  assignment_caught = true
  << "assignment: " + error.to_s
raise "FAIL assignment rescue" if !assignment_caught
compound_caught = false
begin
  setting.value -= ~2.0
rescue error
  compound_caught = true
  << "compound: " + error.to_s
raise "FAIL compound assignment rescue" if !compound_caught
raise "FAIL failed setter changed state" if setting.value != ~1.0
<< "unchanged: [setting.value]"
