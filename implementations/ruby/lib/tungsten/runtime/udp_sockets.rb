# frozen_string_literal: true

require "io/wait"
require "socket"

module Tungsten
  module Runtime
    # The w_udp_* ccalls behind core/udp_socket.w, on Ruby's UDPSocket. The
    # handle the Tungsten object keeps is the Ruby socket itself (the compiled
    # runtime's is an fd). Semantics follow runtime/runtime_udp.c: one
    # datagram per recv, nil when the timeout passes, byte-exact payloads.
    module UdpSockets
      UDP_CCALLS = %w[
        w_udp_open w_udp_bind w_udp_connect w_udp_send w_udp_send_to
        w_udp_recv w_udp_recv_from w_udp_local_port w_udp_close
      ].freeze

      UDP_CCALL_ARITY = {
        "w_udp_open" => 1, "w_udp_bind" => 3, "w_udp_connect" => 3,
        "w_udp_send" => 2, "w_udp_send_to" => 4, "w_udp_recv" => 4,
        "w_udp_recv_from" => 4, "w_udp_local_port" => 1, "w_udp_close" => 1
      }.freeze

      def dispatch_udp_ccall(cname, args, node)
        argc = args.size - 1
        unless argc == UDP_CCALL_ARITY.fetch(cname)
          runtime_error("#{cname} expects #{UDP_CCALL_ARITY.fetch(cname)} arguments, got #{argc}", node: node)
        end
        udp_ccall(cname, args, node)
      rescue SocketError => e
        host = cname == "w_udp_send_to" ? args[3] : args[2]
        runtime_error("udp: cannot resolve #{host} (#{e.message.delete_prefix("getaddrinfo: ")})", node: node)
      rescue Errno::ECONNREFUSED
        what = cname.start_with?("w_udp_recv") ? "recv" : "send"
        runtime_error("udp: #{what} failed (connection refused)", node: node)
      rescue SystemCallError, IOError => e
        runtime_error("udp: #{cname.delete_prefix("w_udp_")} failed (#{e.message})", node: node)
      end

      private

      def udp_ccall(cname, args, node)
        case cname
        when "w_udp_open"
          family = { 4 => ::Socket::AF_INET, 6 => ::Socket::AF_INET6 }[args[1]]
          runtime_error("udp: family must be :ipv4 or :ipv6", node: node) unless family
          sock = ::UDPSocket.new(family)
          udp_grow_buffers(sock)
          sock
        when "w_udp_bind"
          sock = udp_handle(args[1], node)
          sock.bind(udp_bind_host(sock, args[2]), args[3].to_i)
          nil
        when "w_udp_connect"
          udp_handle(args[1], node).connect(args[2].to_s, args[3].to_i)
          nil
        when "w_udp_send"
          udp_handle(args[1], node).send(udp_payload(args[2], node), 0)
        when "w_udp_send_to"
          udp_handle(args[1], node).send(udp_payload(args[2], node), 0, args[3].to_s, args[4].to_i)
        when "w_udp_recv"
          udp_receive(udp_handle(args[1], node), args, from: false)
        when "w_udp_recv_from"
          udp_receive(udp_handle(args[1], node), args, from: true)
        when "w_udp_local_port"
          udp_handle(args[1], node).local_address.ip_port
        when "w_udp_close"
          args[1].close if args[1].is_a?(::UDPSocket) && !args[1].closed?
          nil
        end
      end

      UDP_BUFFER_BYTES = 256 * 1024

      # As runtime_udp.c does: room for full 64 KiB datagrams (macOS starts a
      # UDP send buffer at 9216 bytes), never shrinking a larger default.
      def udp_grow_buffers(sock)
        [ ::Socket::SO_SNDBUF, ::Socket::SO_RCVBUF ].each do |option|
          next if sock.getsockopt(::Socket::SOL_SOCKET, option).int >= UDP_BUFFER_BYTES

          sock.setsockopt(::Socket::SOL_SOCKET, option, UDP_BUFFER_BYTES)
        end
      end

      def udp_handle(handle, node)
        runtime_error("udp: socket is closed", node: node) unless handle.is_a?(::UDPSocket) && !handle.closed?
        handle
      end

      def udp_bind_host(sock, host)
        return host.to_s unless host.nil? || host.to_s.empty?

        sock.local_address.ipv6? ? "::" : "0.0.0.0"
      end

      def udp_payload(data, node)
        case data
        when Tungsten::ByteArray then data.bytes.pack("C*")
        when ::String then data.b
        else runtime_error("udp: send expects a String or ByteArray", node: node)
        end
      end

      # args: [cname, handle, max, timeout_ms, as_bytes]
      def udp_receive(sock, args, from:)
        max = args[2].to_i
        max = 65_536 if max <= 0
        timeout_ms = args[3].to_i
        deadline = timeout_ms.positive? ? Process.clock_gettime(Process::CLOCK_MONOTONIC) + (timeout_ms / 1000.0) : nil
        loop do
          data, addr = sock.recvfrom_nonblock(max)
          payload = args[4] ? Tungsten::ByteArray.new(data.bytes) : data.force_encoding(Encoding::UTF_8)
          return from ? [ payload, addr[3], addr[1] ] : payload
        rescue IO::WaitReadable
          remaining = deadline && (deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC))
          return nil if remaining && remaining <= 0

          sock.wait_readable(remaining)
        end
      end
    end
  end
end
