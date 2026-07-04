# Carbide::Channel — WebSocket/real-time channels
# Connection lifecycle, subscribe/broadcast to named channels.
# Integrates with Forge::WebSocket for transport.

in Tungsten:Carbide

+ Channel
  ro :name
  ro :connection
  ro :params

  @@channels = {}

  # --- Class-level DSL ---

  -> .channel_name(name = nil)
    if name
      @@channels[name] = self
      @_channel_name = name
    else
      @_channel_name || self.name.underscore

  -> .find(name)
    @@channels[name]

  # --- Instance lifecycle ---

  -> new(@connection, **params)
    @name   = self.class.channel_name
    @params = params
    @subscriptions = []

  # Called when a client subscribes to this channel
  -> subscribed
    # Override in subclasses

  # Called when a client unsubscribes
  -> unsubscribed
    # Override in subclasses

  # Called when a message is received from the client
  -> received(data)
    # Override in subclasses

  # --- Broadcasting ---

  -> .broadcast(channel_name, data)
    Forge:WebSocket:ChannelRegistry.broadcast(
      channel_name,
      JSON.encode({channel: channel_name, data: data})
    )

  -> broadcast(data)
    self.class.broadcast(@name, data)

  # --- Streaming ---

  -> stream_from(source)
    @subscriptions.push(source)
    @connection.subscribe(source)

  -> stop_stream(source)
    @subscriptions.delete(source)
    @connection.unsubscribe(source)

  -> stop_all_streams
    @subscriptions.each -> (source)
      @connection.unsubscribe(source)
    @subscriptions = []

  # --- Connection wrapper ---

  + Connection
    ro :socket
    ro :account
    ro :channels

    -> new(@socket, account: nil)
      @account  = account
      @channels = {}

    -> subscribe(channel_name, **params)
      channel_class = Channel.find(channel_name)
      << nil unless channel_class

      channel = channel_class.new(self, **params)
      @channels[channel_name] = channel
      channel.subscribed
      channel

    -> unsubscribe(channel_name)
      channel = @channels.delete(channel_name)
      channel&.unsubscribed
      channel&.stop_all_streams

    -> disconnect
      @channels.each -> (name, channel)
        channel.unsubscribed
        channel.stop_all_streams
      @channels = {}
      @socket.close
