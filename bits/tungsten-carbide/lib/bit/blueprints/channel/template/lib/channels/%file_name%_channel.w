in Channels

+ %class_name%Channel[Channel]
  channel_name "%file_name%"

  -> subscribed
    stream_from "%file_name%"

  -> unsubscribed
    stop_all_streams

  -> received(data)
    # Handle incoming messages
    broadcast(data)
