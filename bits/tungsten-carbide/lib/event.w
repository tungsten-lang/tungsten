# Carbide::Event — domain events with pub/sub
# Publish events from anywhere; subscribers react asynchronously or synchronously.

in Tungsten:Carbide

+ Event
  ro :data
  ro :occurred_at
  ro :id

  @@subscribers = {}  # event_class => [handler, ...]

  -> new(**data)
    @data        = data
    @occurred_at = Time.now
    @id          = Random.uuid

  # --- Publishing ---

  -> .publish(event)
    handlers = @@subscribers[event.class] || []
    handlers.each -> (handler)
      case handler
        {async: true, block: block} =>
          Thread.new -> block.call(event)
        {block: block} =>
          block.call(event)
    event

  # --- Subscribing ---

  -> .on(event_class, async: false, &block)
    @@subscribers[event_class] ||= []
    @@subscribers[event_class].push({block: block, async: async})

  -> .subscribe(subscriber)
    # A subscriber object with `handle(event)` method
    event_class = subscriber.class.handles
    @@subscribers[event_class] ||= []
    @@subscribers[event_class].push({block: -> (e) subscriber.handle(e)})

  -> .subscribers_for(event_class)
    @@subscribers[event_class] || []

  -> .clear_subscribers(event_class = nil)
    if event_class
      @@subscribers.delete(event_class)
    else
      @@subscribers = {}

  # --- Subscriber base class ---

  + Subscriber
    @@handles_event = nil

    -> .handles(event_class = nil)
      if event_class
        @@handles_event = event_class
      else
        @@handles_event

    -> handle(event)
      <! "Subscriber#handle must be implemented"


  # --- Event store (optional persistence) ---

  + Store
    @@events = []

    -> .record(event)
      @@events.push(event)

    -> .replay(event_class = nil, since: nil)
      events = @@events
      events = events.select(-> (e) e.is_a?(event_class)) if event_class
      events = events.select(-> (e) e.occurred_at >= since) if since
      events

    -> .clear
      @@events = []
