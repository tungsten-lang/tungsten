# Conditional recovery from the lowest pelvis height seen during landing.
# Retain the longer-distance policy on shallow landings. For a deep landing,
# wait until the selected recovery time, then use the existing crouch with
# bounded reflex gain. No launch, keyframe, neural-weight or activation edits.
+ GptSupportJumpSkill < GptJumpSkill
  -> start(f, ctl)
    super(f, ctl)
    @support_enabled = param("gpt_support", ~0.0, ~0.0, ~1.0) > ~0.5
    @support_time = param("gpt_support_time", ~0.18, ~0.08, ~0.32)
    @support_height = param("gpt_support_height", ~0.6, ~0.45, ~0.75)
    @support_gain = param("gpt_support_gain", ~1.0, ~0.4, ~1.4)
    @landing_low = ~100.0
    @support_fired = false
    @recovery_chunks = []
    if @support_enabled && @fb_stand
      @group_names.each ->(name)
        movement = ctl.track(name).movement
        @recovery_chunks.push(movement[5])
        sensed = Latch.test("gpt_support", ->(frame, elapsed, controller) support_now?(frame, elapsed, controller))
        movement[4].hold_until(Latch.any([Latch.after(@stand_after), sensed.after_min(@support_time)]))

  -> before(f, ctl)
    super(f, ctl)
    if @support_enabled && @fb_stand && ctl.track("body").chunk_name == "land"
      height = f.pelvis_height
      @landing_low = height if height < @landing_low

  -> support_now?(f, elapsed, ctl)
    return true if @support_fired
    return false if @landing_low >= @support_height
    @support_fired = true
    @recovery_chunks.each ->(chunk) chunk.gain(@support_gain)
    time = f.t
    lowest = @landing_low
    height = f.pelvis_height
    gain = @support_gain
    ctl.emit("gptcatch:[time]:[elapsed]:[lowest]:[height]:[gain]")
    true
