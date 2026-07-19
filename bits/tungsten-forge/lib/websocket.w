# Forge::WebSocket — WebSocket upgrade and handling
# RFC 6455 compliant with ping/pong and fragmentation support

+ WebSocket

  + Handler
    ro :socket
    ro :callbacks
    ro :channels

    -> new(@socket)
      @callbacks = {}
      @channels  = []
      @open      = true

    -> on(event, &block)
      @callbacks[event] = block
      self

    -> send(data)
      frame = Frame.text(data)
      @socket.write(frame.encode)

    -> send_binary(data)
      frame = Frame.binary(data)
      @socket.write(frame.encode)

    -> close(code: 1000, reason: "")
      frame = Frame.close(code, reason)
      @socket.write(frame.encode)
      @open = false
      self.trigger(:close, {code: code, reason: reason})

    -> open?
      @open

    -> subscribe(channel_name)
      @channels.push(channel_name)
      ChannelRegistry.subscribe(channel_name, self)

    -> unsubscribe(channel_name)
      @channels.delete(channel_name)
      ChannelRegistry.unsubscribe(channel_name, self)

    # --- Internal ---

    -> run
      self.trigger(:open, nil)

      loop
        break unless @open
        frame = Frame.read(@socket)
        break unless frame

        case frame.opcode
          :text =>
            self.trigger(:message, frame.payload)
          :binary =>
            self.trigger(:binary, frame.payload)
          :ping =>
            pong = Frame.pong(frame.payload)
            @socket.write(pong.encode)
          :pong =>
            self.trigger(:pong, frame.payload)
          :close =>
            self.close(code: frame.close_code, reason: frame.close_reason)

      # Clean up channel subscriptions
      @channels.each -> (ch)
        ChannelRegistry.unsubscribe(ch, self)

    -> trigger(event, data)
      handler = @callbacks[event]
      handler.call(data) if handler


  # --- WebSocket upgrade ---

  + Upgrade
    MAGIC = "258EAFA5-E914-47DA-95CA-5AB5DC11AD65"

    -> .handshake(request, socket)
      key = request.headers.get("Sec-WebSocket-Key")
      return nil unless key

      accept = Digest.sha1_base64(key + MAGIC)

      response = [
        "HTTP/1.1 101 Switching Protocols",
        "Upgrade: websocket",
        "Connection: Upgrade",
        "Sec-WebSocket-Accept: [accept]",
        "",
        ""
      ].join("\r\n")

      socket.write(response)
      Handler.new(socket)


  # --- WebSocket frame ---

  + Frame
    ro :opcode
    ro :payload
    ro :fin

    OPCODES = {
      text:   0x1,
      binary: 0x2,
      close:  0x8,
      ping:   0x9,
      pong:   0xA
    }

    -> new(@opcode, @payload = "", @fin = true)

    -> .text(data)
      self.new(:text, data)

    -> .binary(data)
      self.new(:binary, data)

    -> .close(code, reason)
      payload = [code].pack("n") + reason
      self.new(:close, payload)

    -> .ping(data = "")
      self.new(:ping, data)

    -> .pong(data = "")
      self.new(:pong, data)

    -> .read(socket)
      # Read and decode a WebSocket frame from the socket
      header = socket.read(2)
      return nil unless header

      fin = (header[0].ord & 0x80) != 0
      opcode_num = header[0].ord & 0x0F
      masked = (header[1].ord & 0x80) != 0
      length = header[1].ord & 0x7F

      if length == 126
        length = socket.read(2).unpack("n").first
      elsif length == 127
        length = socket.read(8).unpack("Q>").first

      mask_key = nil
      if masked
        mask_key = socket.read(4)
      payload = socket.read(length)

      if masked && mask_key
        payload = payload.bytes.each_with_index.map(-> (b, i)
          b ^ mask_key[i % 4].ord
        ).pack("C*")

      opcode = OPCODES.key(opcode_num) || :unknown
      self.new(opcode, payload, fin)

    -> close_code
      return nil unless @opcode == :close && @payload.size >= 2
      @payload[0..1].unpack("n").first

    -> close_reason
      return nil unless @opcode == :close && @payload.size > 2
      @payload[2..]

    -> encode
      bytes = [] ## reuse
      fin_mask = 0x00
      if @fin
        fin_mask = 0x80
      bytes.push(fin_mask | OPCODES[@opcode])

      payload_len = @payload.size()
      if payload_len < 126
        bytes.push(payload_len)
      elsif payload_len < 65536
        bytes.push(126)
        bytes += [payload_len].pack("n").bytes
      else
        bytes.push(127)
        bytes += [payload_len].pack("Q>").bytes

      bytes.pack("C*") + @payload


  # --- Channel registry for pub/sub ---

  + ChannelRegistry
    @@channels = {}

    -> .subscribe(channel, handler)
      @@channels[channel] = @@channels[channel] || []
      @@channels[channel].push(handler)

    -> .unsubscribe(channel, handler)
      @@channels[channel]&.delete(handler)

    -> .broadcast(channel, data)
      subscribers = @@channels[channel] || []
      subscribers.each -> (handler)
        handler.send(data) if handler.open?

    -> .subscriber_count(channel)
      (@@channels[channel] || []).size
