in Jobs

+ %class_name%Job[Job]
  queue_as :default
  retry_policy count: 3, backoff: :exponential

  -> perform(*args)
    # TODO: implement job logic
