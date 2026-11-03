# Private extension: preserve the distance policy, but enter its existing
# balanced-crouch recovery early when sensed landing posture predicts trouble.
# Disabled mode retains the inherited movement and latch exactly.
+ GptAdaptiveJumpSkill < GptJumpSkill
  -> start(f, ctl)
    super(f, ctl)
    enabled = param("gpt_capture", ~0.0, ~0.0, ~1.0)
    @capture_min = param("gpt_capture_min", ~0.18, ~0.04, ~0.28)
    @capture_pitch = param("gpt_capture_pitch", ~1.0, ~0.3, ~1.6)
    @capture_back = param("gpt_capture_back", ~0.3, ~0.1, ~0.8)
    @capture_look = param("gpt_capture_look", ~0.12, ~0.0, ~0.35)
    @capture_height = param("gpt_capture_height", ~0.56, ~0.4, ~0.75)
    if enabled > ~0.5 && @fb_stand
      @group_names.each ->(name)
        landing = ctl.track(name).movement[4]
        sensed = Latch.test("gpt_capture", ->(frame, elapsed, controller) capture_now?(frame, elapsed, controller))
        landing.hold_until(Latch.any([Latch.after(@stand_after), sensed.after_min(@capture_min)]))

  -> capture_now?(f, elapsed, ctl)
    pitch = f.torso_pitch
    rate = f.torso_pitch_rate
    predicted = pitch + @capture_look * rate
    height = f.pelvis_height
    fire = predicted > @capture_pitch || predicted < ~0.0 - @capture_back || height < @capture_height
    if fire
      time = f.t
      ctl.emit("gptcatch:[time]:[elapsed]:[pitch]:[rate]:[height]")
    fire
