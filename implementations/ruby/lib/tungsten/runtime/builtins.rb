# frozen_string_literal: true

require "rbconfig"

module Tungsten
  module Runtime
    class FileHandle
      attr_reader :path, :mode

      def initialize(path, mode = "r")
        @path = Builtins.path_string(path)
        @mode = (mode || "r").to_s
        @io = ::File.open(@path, @mode)
      end

      def write(data)
        @io.write(data.to_s)
      end

      def <<(data)
        write(data)
        self
      end

      def puts(*items)
        @io.puts(*items.map { |item| item.nil? ? "nil" : item.to_s })
        self
      end

      def read(length = nil)
        length ? @io.read(length.to_i) : @io.read
      end

      def read_bytes(length = nil)
        read(length)
      end

      def gets
        @io.gets&.chomp
      end

      def each_line(&block)
        return @io.each_line unless block

        @io.each_line(&block)
        self
      end

      def flush
        @io.flush
        self
      end

      def close
        @io.close unless @io.closed?
        nil
      end

      def closed?
        @io.closed?
      end

      def rewind
        @io.rewind
        self
      end

      def seek(offset, whence = IO::SEEK_SET)
        @io.seek(offset.to_i, whence.to_i)
        self
      end

      def tell
        @io.tell
      end

      def eof?
        @io.eof?
      end

      def size
        flush unless closed?
        ::File.size?(@path) || 0
      end

      def mtime
        ::File.mtime(@path)
      rescue Errno::ENOENT, Errno::ENOTDIR, Errno::EACCES
        nil
      end

      def mtime_ns
        Builtins.mtime_ns(@path)
      end

      def type
        Builtins.file_type_value(@path)
      end

      def file_type
        type
      end

      def exist?
        ::File.exist?(@path)
      end
      alias exists? exist?

      def file?
        ::File.file?(@path)
      end

      def directory?
        ::File.directory?(@path)
      end

      def symlink?
        ::File.symlink?(@path)
      end

      def readlink
        ::File.readlink(@path)
      end

      def to_s
        @path
      end
    end

    module Builtins
      def self.path_string(value)
        case value
        when Tungsten::PathValue then value.expand
        else value.to_s
        end
      end

      def self.option_hash(args)
        args ||= []
        args.each_with_object({}) do |arg, opts|
          next unless arg.is_a?(Hash)

          arg.each { |key, value| opts[key.to_s] = value }
        end
      end

      def self.option_value(args, name, default = nil)
        opts = option_hash(args)
        opts.key?(name.to_s) ? opts[name.to_s] : default
      end

      def self.truthy_option(args, name, default = false)
        value = option_value(args, name, default)
        value != false && !value.nil?
      end

      def self.array_compare(left, right, comparator = nil)
        value = comparator ? comparator.call(left, right) : (left <=> right)
        raise Tungsten::Error.new("comparison failed for #{left.inspect} and #{right.inspect}") if value.nil?

        unless value.respond_to?(:to_i)
          raise Tungsten::Error.new("sort comparator must return an integer-compatible value")
        end

        value.to_i
      end

      def self.array_mergesort_copy(array, comparator = nil)
        n = array.length
        return array.dup if n < 2

        src = array.dup
        dst = Array.new(n)
        width = 1

        while width < n
          left = 0
          while left < n
            mid = [ left + width, n ].min
            right = [ left + (width * 2), n ].min
            i = left
            j = mid
            k = left

            while i < mid && j < right
              if array_compare(src[i], src[j], comparator) <= 0
                dst[k] = src[i]
                i += 1
              else
                dst[k] = src[j]
                j += 1
              end
              k += 1
            end

            while i < mid
              dst[k] = src[i]
              i += 1
              k += 1
            end

            while j < right
              dst[k] = src[j]
              j += 1
              k += 1
            end

            left += width * 2
          end

          src, dst = dst, src
          width *= 2
        end

        src
      end

      def self.array_mergesort_in_place!(array, comparator = nil)
        array.replace(array_mergesort_copy(array, comparator))
      end

      def self.array_random_index(limit, random = nil)
        limit = limit.to_i
        raise Tungsten::Error.new("shuffle bound must be positive") if limit <= 0

        value =
          if random
            if random.respond_to?(:random_number)
              random.random_number(limit)
            elsif random.respond_to?(:rand)
              random.rand(limit)
            else
              raise Tungsten::Error.new("shuffle random must respond to rand(limit)")
            end
          else
            require "securerandom"
            SecureRandom.random_number(limit)
          end

        unless value.is_a?(Integer) && value >= 0 && value < limit
          raise Tungsten::Error.new("shuffle random returned #{value.inspect}, expected 0...#{limit}")
        end

        value
      end

      def self.array_shuffle_in_place!(array, random = nil)
        i = array.length - 1
        while i > 0
          j = array_random_index(i + 1, random)
          array[i], array[j] = array[j], array[i] unless i == j
          i -= 1
        end
        array
      end

      def self.array_shuffle_copy(array, random = nil)
        array_shuffle_in_place!(array.dup, random)
      end

      def self.array_gather(array, indexes)
        indexes.map { |index| array[index] }
      end

      def self.array_rotate_copy(array, count = 1)
        array.rotate(count.to_i)
      end

      def self.array_rotate_in_place!(array, count = 1)
        array.replace(array_rotate_copy(array, count))
      end

      def self.file_type_value(path)
        stat = File.lstat(path_string(path))
        case stat.ftype
        when "link" then "symlink"
        when "characterSpecial" then "character"
        when "blockSpecial" then "block"
        else stat.ftype
        end
      rescue Errno::ENOENT, Errno::ENOTDIR, Errno::EACCES
        nil
      end

      def self.ruby_executable
        File.realpath(RbConfig.ruby)
      rescue Errno::ENOENT, Errno::EACCES
        RbConfig.ruby
      end

      def self.mtime_ns(path)
        stat = File.stat(path_string(path))
        (stat.mtime.to_i * 1_000_000_000) + stat.mtime.nsec
      rescue Errno::ENOENT, Errno::ENOTDIR, Errno::EACCES
        nil
      end

      def self.runtime_stamp
        path = ruby_executable
        flavor = path.include?("/src/patched/ruby/") ? "custom" : "system"
        stamp = mtime_ns(path)
        "#{flavor}@#{stamp ? stamp.to_s(36) : "unknown"}"
      end

      def self.runtime_identity
        "#{RUBY_DESCRIPTION} #{runtime_stamp}"
      end

      def self.runtime_version_label
        "ruby #{RUBY_VERSION}p#{RUBY_PATCHLEVEL} #{runtime_stamp}"
      end

      def self.stable_to_i(value)
        return value.to_i unless value.is_a?(Float) && value.finite?

        nearest = value.round
        tolerance = Float::EPSILON * [value.abs, nearest.abs, 1.0].max * 8
        (value - nearest).abs <= tolerance ? nearest : value.to_i
      end

      def self.setup(interpreter)
        register_free_functions(interpreter)
        register_method_builtins(interpreter)
      end

      def self.register_free_functions(interpreter)
        interpreter.define_builtin("puts") do |_recv, args, _block|
          args.each { |a| $stdout.puts(a.nil? ? "nil" : a.to_s) }
          nil
        end

        interpreter.define_builtin("print") do |_recv, args, _block|
          args.each { |a| $stdout.print(a.nil? ? "nil" : a.to_s) }
          nil
        end

        interpreter.define_builtin("exit") do |_recv, args, _block|
          Kernel.exit(args[0] || 0)
        end

        interpreter.define_builtin("read_file") do |_recv, args, _block|
          File.read(path_string(args[0]))
        end

        interpreter.define_builtin("read_file_bytes") do |_recv, args, _block|
          File.binread(path_string(args[0]))
        end

        interpreter.define_builtin("file?") do |_recv, args, _block|
          File.exist?(path_string(args[0]))
        end

        interpreter.define_builtin("file_exists?") do |_recv, args, _block|
          File.exist?(path_string(args[0]))
        end

        interpreter.define_builtin("file_file?") do |_recv, args, _block|
          File.file?(path_string(args[0]))
        end

        interpreter.define_builtin("file_directory?") do |_recv, args, _block|
          File.directory?(path_string(args[0]))
        end

        interpreter.define_builtin("file_symlink?") do |_recv, args, _block|
          File.symlink?(path_string(args[0]))
        end

        interpreter.define_builtin("file_type") do |_recv, args, _block|
          file_type_value(args[0])
        end

        interpreter.define_builtin("file_size") do |_recv, args, _block|
          File.size(path_string(args[0]))
        rescue Errno::ENOENT, Errno::ENOTDIR, Errno::EACCES
          nil
        end

        interpreter.define_builtin("file_mtime") do |_recv, args, _block|
          File.mtime(path_string(args[0]))
        rescue Errno::ENOENT, Errno::ENOTDIR, Errno::EACCES
          nil
        end

        interpreter.define_builtin("file_atime") do |_recv, args, _block|
          File.atime(path_string(args[0]))
        rescue Errno::ENOENT, Errno::ENOTDIR, Errno::EACCES
          nil
        end

        interpreter.define_builtin("file_ctime") do |_recv, args, _block|
          File.ctime(path_string(args[0]))
        rescue Errno::ENOENT, Errno::ENOTDIR, Errno::EACCES
          nil
        end

        interpreter.define_builtin("read_dir") do |_recv, args, _block|
          Dir.children(path_string(args[0] || "."))
        end

        interpreter.define_builtin("write_file") do |_recv, args, _block|
          File.write(path_string(args[0]), args[1])
        end

        interpreter.define_builtin("write_file_bytes") do |_recv, args, _block|
          File.binwrite(path_string(args[0]), args[1])
        end

        interpreter.define_builtin("file_open") do |_recv, args, block|
          handle = Runtime::FileHandle.new(args[0], args[1] || "r")
          if block
            begin
              block.call(handle)
            ensure
              handle.close
            end
          else
            handle
          end
        end

        interpreter.define_builtin("file_pwd") do |_recv, _args, _block|
          Dir.pwd
        end

        interpreter.define_builtin("file_chdir") do |_recv, args, _block|
          old_pwd = Dir.pwd
          Dir.chdir(path_string(args[0]))
          if _block
            begin
              _block.call
            ensure
              Dir.chdir(old_pwd)
            end
          else
            Dir.pwd
          end
        end

        interpreter.define_builtin("file_mkdir") do |_recv, args, _block|
          require "fileutils"

          path = path_string(args[0])
          recursive = truthy_option(args[1..], "recursive", false)
          recursive ? FileUtils.mkdir_p(path) : Dir.mkdir(path)
          true
        end

        interpreter.define_builtin("file_rmdir") do |_recv, args, _block|
          Dir.rmdir(path_string(args[0]))
          true
        end

        interpreter.define_builtin("file_rm") do |_recv, args, _block|
          require "fileutils"

          path = path_string(args[0])
          opts = args[1..]
          force = truthy_option(opts, "force", false)
          recursive = truthy_option(opts, "recursive", false)
          if recursive
            force ? FileUtils.rm_rf(path) : FileUtils.rm_r(path)
          else
            force ? FileUtils.rm_f(path) : File.delete(path)
          end
          true
        end

        interpreter.define_builtin("file_mv") do |_recv, args, _block|
          require "fileutils"

          force = truthy_option(args[2..], "force", false)
          FileUtils.mv(path_string(args[0]), path_string(args[1]), force:)
          true
        end

        interpreter.define_builtin("file_cp") do |_recv, args, _block|
          require "fileutils"

          source = path_string(args[0])
          dest = path_string(args[1])
          opts = args[2..]
          force = truthy_option(opts, "force", false)
          recursive = truthy_option(opts, "recursive", false)
          FileUtils.rm_rf(dest) if force && File.exist?(dest)
          recursive ? FileUtils.cp_r(source, dest) : FileUtils.cp(source, dest)
          true
        end

        interpreter.define_builtin("file_touch") do |_recv, args, _block|
          require "fileutils"

          FileUtils.touch(path_string(args[0]))
          true
        end

        interpreter.define_builtin("file_symlink") do |_recv, args, _block|
          File.symlink(path_string(args[0]), path_string(args[1]))
          true
        end

        interpreter.define_builtin("file_link") do |_recv, args, _block|
          File.link(path_string(args[0]), path_string(args[1]))
          true
        end

        interpreter.define_builtin("file_readlink") do |_recv, args, _block|
          File.readlink(path_string(args[0]))
        end

        interpreter.define_builtin("file_realpath") do |_recv, args, _block|
          File.realpath(path_string(args[0]))
        end

        interpreter.define_builtin("file_expand_path") do |_recv, args, _block|
          if args[1]
            File.expand_path(path_string(args[0]), path_string(args[1]))
          else
            File.expand_path(path_string(args[0]))
          end
        end

        interpreter.define_builtin("file_join") do |_recv, args, _block|
          File.join(*args.map { |arg| path_string(arg) })
        end

        interpreter.define_builtin("file_basename") do |_recv, args, _block|
          File.basename(path_string(args[0]))
        end

        interpreter.define_builtin("file_dirname") do |_recv, args, _block|
          File.dirname(path_string(args[0]))
        end

        interpreter.define_builtin("file_extname") do |_recv, args, _block|
          File.extname(path_string(args[0]))
        end

        interpreter.define_builtin("block_given?") do |_recv, _args, _block|
          !interpreter.instance_variable_get(:@current_block).nil?
        end

        interpreter.define_builtin("array_mergesort") do |_recv, args, block|
          array_mergesort_copy(args[0], block)
        end

        interpreter.define_builtin("array_mergesort!") do |_recv, args, block|
          array_mergesort_in_place!(args[0], block)
        end

        interpreter.define_builtin("array_shuffle") do |_recv, args, _block|
          array_shuffle_copy(args[0], option_value(args[1..], "random"))
        end

        interpreter.define_builtin("array_shuffle!") do |_recv, args, _block|
          array_shuffle_in_place!(args[0], option_value(args[1..], "random"))
        end

        interpreter.define_builtin("array_rotate") do |_recv, args, _block|
          array_rotate_copy(args[0], args[1] || 1)
        end

        interpreter.define_builtin("array_rotate!") do |_recv, args, _block|
          array_rotate_in_place!(args[0], args[1] || 1)
        end

        require "base64"

        interpreter.define_builtin("base64_encode") do |_recv, args, _block|
          ::Base64.strict_encode64(args[0].to_s)
        end

        interpreter.define_builtin("base64_decode") do |_recv, args, _block|
          ::Base64.strict_decode64(args[0].to_s)
        end

        interpreter.define_builtin("base64url_encode") do |_recv, args, _block|
          ::Base64.urlsafe_encode64(args[0].to_s, padding: false)
        end

        interpreter.define_builtin("base64url_decode") do |_recv, args, _block|
          ::Base64.urlsafe_decode64(args[0].to_s)
        end

        interpreter.define_builtin("file_mtime_ns") do |_recv, args, _block|
          mtime_ns(args[0])
        end

        interpreter.define_builtin("cache_read") do |_recv, args, _block|
          path = args[0].to_s
          next nil unless File.exist?(path)

          Marshal.load(File.binread(path))
        rescue StandardError
          nil
        end

        interpreter.define_builtin("cache_write") do |_recv, args, _block|
          require "fileutils"

          path = args[0].to_s
          tmp_path = "#{path}.tmp.#{$$}"
          FileUtils.mkdir_p(File.dirname(path))
          File.binwrite(tmp_path, Marshal.dump(args[1]))
          File.rename(tmp_path, path)
          true
        rescue StandardError
          File.delete(tmp_path) if defined?(tmp_path) && File.exist?(tmp_path)
          false
        end

        interpreter.define_builtin("system") do |_recv, args, _block|
          Kernel.system(args[0])
        end

        interpreter.define_builtin("argv") do |_recv, _args, _block|
          interpreter.argv
        end

        interpreter.define_builtin("gets") do |_recv, _args, _block|
          $stdin.gets&.chomp
        end

        interpreter.define_builtin("read_bytes") do |_recv, args, _block|
          n = args[0].to_i
          $stdin.read(n)
        end

        interpreter.define_builtin("log") do |_recv, args, _block|
          args.each { |a| $stderr.puts(a.nil? ? "nil" : a.to_s) }
          nil
        end

        interpreter.define_builtin("flush") do |_recv, _args, _block|
          $stdout.flush
          nil
        end

        interpreter.define_builtin("__project_root") do |_recv, _args, _block|
          dir = interpreter.instance_variable_get(:@current_file)
          dir = dir ? File.dirname(dir) : Dir.pwd
          interpreter.send(:find_project_root, dir) || Dir.pwd
        end

        interpreter.define_builtin("readline") do |_recv, args, _block|
          require "readline"
          prompt = args[0]&.to_s || ""
          line = Readline.readline(prompt, true)
          # Remove blank/duplicate entries from history
          if line && (line.strip.empty? || (Readline::HISTORY.length > 1 && Readline::HISTORY[-2] == line))
            Readline::HISTORY.pop
          end
          line
        end

        interpreter.define_builtin("eval") do |_recv, args, _block|
          # Run in the top-level scope so REPL variables persist across calls
          saved_env = interpreter.instance_variable_get(:@env)
          root_env = saved_env
          root_env = root_env.parent while root_env.parent
          interpreter.instance_variable_set(:@env, root_env)
          begin
            interpreter.run(args[0].to_s)
          ensure
            interpreter.instance_variable_set(:@env, saved_env)
          end
        end

        interpreter.define_builtin("capture") do |_recv, args, _block|
          require "open3"
          stdout, _stderr, _status = Open3.capture3(args[0])
          stdout
        end

        interpreter.define_builtin("popen") do |_recv, args, _block|
          require "open3"
          cmd = args[0]
          input = args[1] || ""
          stdout, _stderr, status = Open3.capture3(cmd, stdin_data: input)
          [stdout, status.success?]
        end

        interpreter.define_builtin("env") do |_recv, args, _block|
          ENV[args[0]]
        end

        interpreter.define_builtin("runtime_identity") do |_recv, _args, _block|
          runtime_identity
        end

        interpreter.define_builtin("clock") do |_recv, _args, _block|
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end

        interpreter.define_builtin("digest_sha256") do |_recv, args, _block|
          require "digest"
          ::Digest::SHA256.hexdigest(args[0].to_s)[0, 16]
        end

        interpreter.define_builtin("type") do |_recv, args, _block|
          value = args[0]
          case value
          when Runtime::WObject then value.w_class.name
          when Tungsten::ByteArray then "ByteArray"
          when Tungsten::CharValue then "Char"
          when Tungsten::StringBuffer then "StringBuffer"
          when Tungsten::PathValue then "Path"
          when Integer   then "Integer"
          when Float     then "Float"
          when String    then "String"
          when Array     then "Array"
          when Hash      then "Hash"
          when Symbol    then "Symbol"
          when TrueClass, FalseClass then "Boolean"
          when NilClass  then "Nil"
          when Range     then "Range"
          when BigDecimal then "Decimal"
          when Tungsten::Currency then "Currency"
          when Tungsten::Percentage then "Percentage"
          when Tungsten::Duration then "Duration"
          when Tungsten::Quantity then "Quantity"
          when Tungsten::Key then "Key"
          else value.class.name
          end
        end

        # ── 128-bit hash ──────────────────────────────────────────────────

        interpreter.define_builtin("wymix") do |_recv, args, _block|
          a = args[0].is_a?(Integer) ? args[0] : 0
          b = args[1].is_a?(Integer) ? args[1] : 0
          # 128-bit multiply, XOR high and low 64-bit halves, mask to i48
          product = a * b
          lo = product & 0xFFFFFFFFFFFFFFFF
          hi = (product >> 64) & 0xFFFFFFFFFFFFFFFF
          result = lo ^ hi
          # Sign-extend from 48 bits to Ruby integer (matching NaN-boxed i48)
          masked = result & 0x0000FFFFFFFFFFFF
          masked >= 0x800000000000 ? masked - 0x1000000000000 : masked
        end

        # ── Constructors ──────────────────────────────────────────────────

        interpreter.define_builtin("ByteArray") do |_recv, args, _block|
          if args[0].is_a?(::Array)
            Tungsten::ByteArray.new(args[0])
          elsif args[0].is_a?(Integer)
            Tungsten::ByteArray.new([0] * args[0])
          else
            Tungsten::ByteArray.new
          end
        end

        interpreter.define_builtin("StringBuffer") do |_recv, args, _block|
          Tungsten::StringBuffer.new(args[0]&.to_i || 0)
        end

        interpreter.define_builtin("Path") do |_recv, args, _block|
          Tungsten::PathValue.new(args[0].to_s)
        end

        interpreter.define_builtin("from_kitty") do |_recv, args, _block|
          Tungsten::Key.from_kitty(args[0])
        end

        # ── Logarithmic units (sketch) ────────────────────────────────────
        # First-pass support. Construct via lowercase functions because
        # the Tungsten lexer treats `dB` as `d` + `B` (two tokens). Use
        # `db`, `dbv`, `dbu`, `dbm`, `dbw`, `db_spl`, `np`.
        # Arithmetic in log space; .linear collapses to a physical Quantity.
        # Full lexer integration ("60 dB" as a literal) is a TODO.
        {
          "db"     => :dB,
          "dbv"    => :dBV,
          "dbu"    => :dBu,
          "dbm"    => :dBm,
          "dbw"    => :dBW,
          "np"     => :Np,
          "db_spl" => :dB_SPL,
        }.each do |fn_name, ctor|
          interpreter.define_builtin(fn_name) do |_recv, args, _block|
            Tungsten::LogQuantity.send(ctor, args[0])
          end
        end

        # ── Trig functions accepting angle quantities ────────────────────
        # `sin(45°)`, `cos(π/4 rad)`, `tan(0.5)` (Float = radians by convention).
        # Symbolic match on common angles for exact results: sin(π/6) = 1/2.

        # Convert any reasonable angle input to radians as a Float.
        # Float / Numeric: assumed already in radians.
        # Quantity with dimensionless dim (rad, deg, gon, turn): apply factor.
        # Quantity with custom dim "π" (symbolic-arithmetic carrier from `2π`):
        #   treat value as multiplier of π radians.
        # Quantity with custom dim "τ": multiplier of 2π.
        to_radians = lambda do |x|
          case x
          when Tungsten::Quantity
            dim = x.unit.dimension
            if dim.dimensionless?
              x.value.to_f * x.unit.factor
            elsif dim.custom? && dim.custom_name == "π"
              x.value.to_f * Math::PI
            elsif dim.custom? && dim.custom_name == "τ"
              x.value.to_f * 2 * Math::PI
            else
              raise Tungsten::Error.new("trig argument must be an angle, got #{Tungsten::Units.dimension_name(x.unit.dimension)}")
            end
          when Tungsten::Measurement
            x.value.to_f
          when Numeric
            x.to_f
          else
            raise Tungsten::Error.new("trig argument must be Numeric or Quantity, got #{x.class}")
          end
        end

        # Pattern-match common symbolic angles. Input is angle in radians (Float).
        # Returns a Rational/Integer for exact, nil to fall through to Float math.
        # Each entry: [normalized_radian_factor_of_pi, sin_exact, cos_exact, tan_exact_or_nil]
        # cos(0) = 1, sin(0) = 0, tan(0) = 0
        # sin(π/6) = 1/2, cos(π/6) = √3/2 (not Rational), tan(π/6) = √3/3 (not Rational)
        # sin(π/4) = √2/2, cos(π/4) = √2/2 (not Rational)
        # sin(π/3) = √3/2 (not Rational), cos(π/3) = 1/2
        # sin(π/2) = 1, cos(π/2) = 0
        # sin(π) = 0, cos(π) = -1
        symbolic_match = lambda do |radians, fn|
          # Normalize to [0, 2π)
          tau = Math::PI * 2
          r = radians % tau
          # Tolerance for "is this exactly π/6, π/4, etc.?"
          eps = 1e-12
          [
            [0.0,                0, 1, 0],
            [Math::PI / 6,       Rational(1, 2), nil, nil],
            [Math::PI / 4,       nil, nil, 1],
            [Math::PI / 3,       nil, Rational(1, 2), nil],
            [Math::PI / 2,       1, 0, nil],
            [Math::PI * 2 / 3,   nil, Rational(-1, 2), nil],
            [Math::PI * 3 / 4,   nil, nil, -1],
            [Math::PI * 5 / 6,   Rational(1, 2), nil, nil],
            [Math::PI,           0, -1, 0],
            [Math::PI * 7 / 6,   Rational(-1, 2), nil, nil],
            [Math::PI * 5 / 4,   nil, nil, 1],
            [Math::PI * 4 / 3,   nil, Rational(-1, 2), nil],
            [Math::PI * 3 / 2,   -1, 0, nil],
            [Math::PI * 5 / 3,   nil, Rational(1, 2), nil],
            [Math::PI * 7 / 4,   nil, nil, -1],
            [Math::PI * 11 / 6,  Rational(-1, 2), nil, nil],
          ].each do |angle, s, c, t|
            next unless (r - angle).abs < eps
            return s if fn == :sin && s
            return c if fn == :cos && c
            return t if fn == :tan && t
          end
          nil
        end

        interpreter.define_builtin("sin") do |_recv, args, _block|
          rad = to_radians.call(args[0])
          symbolic_match.call(rad, :sin) || Math.sin(rad)
        end

        interpreter.define_builtin("cos") do |_recv, args, _block|
          rad = to_radians.call(args[0])
          symbolic_match.call(rad, :cos) || Math.cos(rad)
        end

        interpreter.define_builtin("tan") do |_recv, args, _block|
          rad = to_radians.call(args[0])
          symbolic_match.call(rad, :tan) || Math.tan(rad)
        end

        interpreter.define_builtin("asin") do |_recv, args, _block|
          # Returns radians as Float (could later return a Quantity in deg).
          Math.asin(args[0].is_a?(Numeric) ? args[0].to_f : args[0].value.to_f)
        end

        interpreter.define_builtin("acos") do |_recv, args, _block|
          Math.acos(args[0].is_a?(Numeric) ? args[0].to_f : args[0].value.to_f)
        end

        interpreter.define_builtin("atan") do |_recv, args, _block|
          Math.atan(args[0].is_a?(Numeric) ? args[0].to_f : args[0].value.to_f)
        end

        interpreter.define_builtin("atan2") do |_recv, args, _block|
          y = args[0].is_a?(Numeric) ? args[0].to_f : args[0].value.to_f
          x = args[1].is_a?(Numeric) ? args[1].to_f : args[1].value.to_f
          Math.atan2(y, x)
        end

        interpreter.define_builtin("from_legacy") do |_recv, args, _block|
          Tungsten::Key.from_legacy(args[0])
        end
      end

      def self.register_method_builtins(interpreter)
        interpreter.define_method_builtin("type") do |recv, _args, _block|
          case recv
          when Runtime::FileHandle then recv.type
          when Runtime::WObject then recv.w_class.name
          when Tungsten::ByteArray then "ByteArray"
          when Tungsten::CharValue then "Char"
          when Tungsten::StringBuffer then "StringBuffer"
          when Tungsten::PathValue then "Path"
          when Integer   then "Integer"
          when Float     then "Float"
          when String    then "String"
          when Array     then "Array"
          when Hash      then "Hash"
          when Symbol    then "Symbol"
          when TrueClass, FalseClass then "Boolean"
          when NilClass  then "Nil"
          when Range     then "Range"
          when BigDecimal then "Decimal"
          when Tungsten::Currency then "Currency"
          when Tungsten::Percentage then "Percentage"
          when Tungsten::Duration then "Duration"
          when Tungsten::Quantity then "Quantity"
          when Tungsten::Key then "Key"
          else recv.class.name
          end
        end

        # ── Key builtins ──────────────────────────────────────────────────

        interpreter.define_method_builtin("kitty") do |recv, _args, _block|
          raise Tungsten::Error, "'kitty' is only available on Key" unless recv.is_a?(Tungsten::Key)
          recv.kitty
        end

        interpreter.define_method_builtin("legacy") do |recv, _args, _block|
          raise Tungsten::Error, "'legacy' is only available on Key" unless recv.is_a?(Tungsten::Key)
          recv.legacy
        end

        interpreter.define_method_builtin("bytes") do |recv, _args, _block|
          case recv
          when Tungsten::Key then recv.bytes
          when Tungsten::ByteArray then recv
          when Tungsten::CharValue then recv.bytes
          when Tungsten::IP6 then recv.bytes
          when Tungsten::MAC then recv.bytes
          when String then Tungsten::ByteArray.new(recv.bytes)
          when Symbol then Tungsten::ByteArray.new(recv.to_s.bytes)
          else raise Tungsten::Error, "'bytes' is not available on #{interpreter.send(:tungsten_class_name, recv)}"
          end
        end

        interpreter.define_method_builtin("name") do |recv, _args, _block|
          if recv.respond_to?(:name)
            recv.name
          else
            raise Tungsten::Error, "'name' is not available on #{interpreter.send(:tungsten_class_name, recv)}"
          end
        end

        interpreter.define_method_builtin("display") do |recv, _args, _block|
          raise Tungsten::Error, "'display' is only available on Key" unless recv.is_a?(Tungsten::Key)
          recv.display
        end

        interpreter.define_method_builtin("shift?") do |recv, _args, _block|
          raise Tungsten::Error, "'shift?' is only available on Key" unless recv.is_a?(Tungsten::Key)
          recv.shift?
        end

        interpreter.define_method_builtin("ctrl?") do |recv, _args, _block|
          raise Tungsten::Error, "'ctrl?' is only available on Key" unless recv.is_a?(Tungsten::Key)
          recv.ctrl?
        end

        interpreter.define_method_builtin("alt?") do |recv, _args, _block|
          raise Tungsten::Error, "'alt?' is only available on Key" unless recv.is_a?(Tungsten::Key)
          recv.alt?
        end

        interpreter.define_method_builtin("super?") do |recv, _args, _block|
          raise Tungsten::Error, "'super?' is only available on Key" unless recv.is_a?(Tungsten::Key)
          recv.super?
        end

        interpreter.define_method_builtin("printable?") do |recv, _args, _block|
          raise Tungsten::Error, "'printable?' is only available on Key" unless recv.is_a?(Tungsten::Key)
          recv.printable?
        end

        interpreter.define_method_builtin("functional?") do |recv, _args, _block|
          raise Tungsten::Error, "'functional?' is only available on Key" unless recv.is_a?(Tungsten::Key)
          recv.functional?
        end

        interpreter.define_method_builtin("modifier?") do |recv, _args, _block|
          raise Tungsten::Error, "'modifier?' is only available on Key" unless recv.is_a?(Tungsten::Key)
          recv.modifier?
        end

        interpreter.define_method_builtin("codepoint") do |recv, _args, _block|
          raise Tungsten::Error, "'codepoint' is only available on Key" unless recv.is_a?(Tungsten::Key)
          recv.codepoint
        end

        interpreter.define_method_builtin("modifiers") do |recv, _args, _block|
          raise Tungsten::Error, "'modifiers' is only available on Key" unless recv.is_a?(Tungsten::Key)
          recv.modifiers
        end

        interpreter.define_method_builtin("to") do |recv, args, _block|
          raise Tungsten::Error, "'to' is only available on Quantity" unless recv.is_a?(Tungsten::Quantity)
          recv.convert_to(args[0].to_s)
        end

        interpreter.define_method_builtin("value") do |recv, _args, _block|
          if recv.is_a?(Tungsten::Quantity)
            recv.value
          elsif recv.respond_to?(:value)
            recv.value
          else
            raise Tungsten::Error, "'value' is not available on #{interpreter.send(:tungsten_class_name, recv)}"
          end
        end

        interpreter.define_method_builtin("unit") do |recv, _args, _block|
          raise Tungsten::Error, "'unit' is only available on Quantity" unless recv.is_a?(Tungsten::Quantity)
          recv.unit.symbol
        end

        interpreter.define_method_builtin("dimension") do |recv, _args, _block|
          raise Tungsten::Error, "'dimension' is only available on Quantity" unless recv.is_a?(Tungsten::Quantity)
          Tungsten::Units.dimension_name(recv.unit.dimension)
        end

        interpreter.define_method_builtin("starts_with?") do |recv, args, _block|
          recv.start_with?(*args)
        end

        interpreter.define_method_builtin("ends_with?") do |recv, args, _block|
          recv.end_with?(*args)
        end

        interpreter.define_method_builtin("replace") do |recv, args, _block|
          recv.gsub(args[0], args[1])
        end

        interpreter.define_method_builtin("map_with_index") do |recv, args, block|
          recv.each_with_index.map do |item, idx|
            block.call(item, idx)
          end
        end

        # ── String builtins ──────────────────────────────────────────────

        interpreter.define_method_builtin("length") do |recv, _args, _block|
          recv.length
        end

        interpreter.define_method_builtin("size") do |recv, _args, _block|
          recv.size
        end

        interpreter.define_method_builtin("empty?") do |recv, _args, _block|
          recv.empty?
        end

        interpreter.define_method_builtin("chars") do |recv, _args, _block|
          recv.chars
        end

        interpreter.define_method_builtin("codes") do |recv, _args, _block|
          recv.to_s.codepoints
        end

        interpreter.define_method_builtin("lchs") do |recv, args, _block|
          # Mirror the compiled-runtime lchs path:
          #   "src".lchs                             # default flags, bits=64
          #   "src".lchs("c")                        # C lexer flags, bits=64
          #   "src".lchs("c", bits: 32)              # C lexer flags, bits=32
          #   "src".lchs("c", bits: 16)              # C lexer flags, bits=16
          #
          # The result is a plain Ruby Integer array; the interpreter never
          # exposes typed arrays, so callers compare counts and packed
          # values rather than typed-element width.
          str = recv.to_s
          lang = args[0].is_a?(String) ? args[0] : nil
          bits = 64
          # The Ruby interpreter doesn't pre-expand kwargs to positional, so
          # `lchs("c", bits: 64)` arrives here as ["c", {bits: 64}]. Accept
          # both the hash form and the (already-positional) integer form.
          if args.length >= 2
            tail = args[1]
            if tail.is_a?(Hash)
              bits = tail[:bits] || tail["bits"] || 64
            elsif tail.is_a?(Integer)
              bits = tail
            else
              raise "lchs: bits argument must be an integer (16, 32, or 64)"
            end
            unless [16, 32, 64].include?(bits)
              raise "lchs: bits must be 16, 32, or 64 (got #{bits})"
            end
          end

          lang_flags = nil
          if lang
            # Read the same c.lex64 binary the compiled runtime uses.
            # Cached on the interpreter so repeated calls don't re-read.
            interpreter.instance_variable_set(:@__lchs_lang_flags, {}) unless interpreter.instance_variable_get(:@__lchs_lang_flags)
            cache = interpreter.instance_variable_get(:@__lchs_lang_flags)
            lang_flags = cache[lang] ||= begin
              root = File.expand_path("../../../../..", __dir__)
              path = File.join(root, "languages", lang, "#{lang}.lex64")
              File.exist?(path) ? File.binread(path).bytes : nil
            end
          end

          # When no language file is loaded, fall back to the built-in
          # Tungsten flag layout — this is what `@source.lchs()` returns
          # when called with no arguments, e.g. from the compiler self-
          # host's own Lexer reading a `.w` file. The flag bits must
          # match the lexer.w constants:
          #   bit 6 = IS_ID_START, bit 5 = IS_ID_CONTINUE,
          #   bit 4 = IS_WHITESPACE, bit 3 = IS_HEX, bit 0 = IS_DIGIT
          default_flags = ->(cp) {
            f = 0
            f |= 0x40 if (cp >= 97 && cp <= 122) || (cp >= 65 && cp <= 90) || cp == 95  # IS_ID_START (a-z A-Z _)
            f |= 0x20 if (f & 0x40) != 0 || (cp >= 48 && cp <= 57)                      # IS_ID_CONTINUE
            f |= 0x10 if cp == 32 || cp == 9                                            # IS_WHITESPACE
            f |= 0x08 if (cp >= 48 && cp <= 57) || (cp >= 97 && cp <= 102) || (cp >= 65 && cp <= 70)  # IS_HEX
            f |= 0x01 if cp >= 48 && cp <= 57                                           # IS_DIGIT
            f
          }
          fetch_flag = ->(cp) { lang_flags ? (lang_flags[cp] || 0) : default_flags.call(cp) }

          # NaN-box tag pattern matching the C runtime's W_TAG_CHAR | (1 << 46).
          # Lex32 / Lex16 fit in their respective element widths and don't
          # carry the tag — only Lex64 needs it. Sign-extend to a signed
          # 64-bit value so Ruby's printed Integer matches the C side.
          lex64_tag = 0xFFFC000000000000 | (1 << 46)
          to_signed64 = ->(v) { v >= (1 << 63) ? v - (1 << 64) : v }

          str.codepoints.map do |cp|
            case bits
            when 64
              flags = fetch_flag.call(cp)
              raw =
                if lang_flags
                  lex64_tag | (cp << 18) | flags
                else
                  digit = (cp >= 48 && cp <= 57) ? cp - 48 : 0xF
                  lex64_tag | (cp << 18) | (digit << 7) | flags
                end
              to_signed64.call(raw)
            when 32
              flags = fetch_flag.call(cp)
              (cp << 11) | flags
            when 16
              if cp < 0x80
                (cp << 8) | fetch_flag.call(cp)
              else
                (0x80 << 8) | fetch_flag.call(cp)
              end
            end
          end
        end

        interpreter.define_method_builtin("split") do |recv, args, _block|
          args.empty? ? recv.split : recv.split(args[0])
        end

        interpreter.define_method_builtin("strip") do |recv, _args, _block|
          recv.strip
        end

        interpreter.define_method_builtin("upcase") do |recv, _args, _block|
          recv.upcase
        end

        interpreter.define_method_builtin("downcase") do |recv, _args, _block|
          recv.downcase
        end

        interpreter.define_method_builtin("includes?") do |recv, args, _block|
          recv.include?(args[0])
        end

        interpreter.define_method_builtin("index") do |recv, args, _block|
          recv.index(args[0])
        end

        interpreter.define_method_builtin("rindex") do |recv, args, _block|
          recv.rindex(args[0])
        end

        interpreter.define_method_builtin("reverse") do |recv, _args, _block|
          recv.reverse
        end

        interpreter.define_method_builtin("levenshtein") do |recv, args, _block|
          other = args[0].to_s
          s = recv.codepoints
          t = other.codepoints
          if s.empty?
            t.length
          elsif t.empty?
            s.length
          else
            n = t.length
            prev = (0..n).to_a
            curr = Array.new(n + 1, 0)
            s.each_with_index do |sc, i|
              curr[0] = i + 1
              t.each_with_index do |tc, j|
                cost = sc == tc ? 0 : 1
                ins = curr[j] + 1
                del = prev[j + 1] + 1
                sub = prev[j] + cost
                m = ins < del ? ins : del
                curr[j + 1] = sub < m ? sub : m
              end
              prev, curr = curr, prev
            end
            prev[n]
          end
        end

        interpreter.define_method_builtin("to_i") do |recv, _args, _block|
          Builtins.stable_to_i(recv)
        end

        interpreter.define_method_builtin("to_f") do |recv, _args, _block|
          recv.to_f
        end

        interpreter.define_method_builtin("to_s") do |recv, _args, _block|
          if recv.is_a?(Integer) && !_args.empty?
            recv.to_s(_args[0].to_i)
          else
            recv.to_s
          end
        end

        # ── Array builtins ───────────────────────────────────────────────

        interpreter.define_method_builtin("first") do |recv, _args, _block|
          recv.first
        end

        interpreter.define_method_builtin("last") do |recv, _args, _block|
          recv.last
        end

        interpreter.define_method_builtin("push") do |recv, args, _block|
          recv.push(*args)
          recv
        end

        interpreter.define_method_builtin("pop") do |recv, _args, _block|
          recv.pop
        end

        interpreter.define_method_builtin("shift") do |recv, _args, _block|
          recv.shift
        end

        interpreter.define_method_builtin("unshift") do |recv, args, _block|
          recv.unshift(*args)
          recv
        end

        interpreter.define_method_builtin("each") do |recv, _args, block|
          if block
            catch(Tungsten::BREAK_SIGNAL) do
              recv.each { |item| block.call(item) }
            end
            recv
          else
            recv.each
          end
        end

        interpreter.define_method_builtin("map") do |recv, _args, block|
          recv.map { |item| block.call(item) }
        end

        interpreter.define_method_builtin("select") do |recv, _args, block|
          recv.select { |item| block.call(item) }
        end

        interpreter.define_method_builtin("reject") do |recv, _args, block|
          recv.reject { |item| block.call(item) }
        end

        interpreter.define_method_builtin("reduce") do |recv, args, block|
          if args.empty?
            recv.reduce { |acc, item| block.call(acc, item) }
          else
            recv.reduce(args[0]) { |acc, item| block.call(acc, item) }
          end
        end

        interpreter.define_method_builtin("sort") do |recv, _args, block|
          if recv.is_a?(Array)
            array_mergesort_copy(recv, block)
          elsif block
            recv.sort { |a, b| block.call(a, b) }
          else
            recv.sort
          end
        end

        interpreter.define_method_builtin("sort!") do |recv, _args, block|
          if recv.is_a?(Array)
            array_mergesort_in_place!(recv, block)
          elsif block
            recv.sort! { |a, b| block.call(a, b) }
          else
            recv.sort!
          end
        end

        interpreter.define_method_builtin("mergesort!") do |recv, _args, block|
          array_mergesort_in_place!(recv, block)
        end

        interpreter.define_method_builtin("shuffle") do |recv, args, _block|
          if args.size == 1 && !args[0].is_a?(Hash)
            array_gather(recv, args[0])
          else
            array_shuffle_copy(recv, option_value(args, "random"))
          end
        end

        interpreter.define_method_builtin("shuffle!") do |recv, args, _block|
          array_shuffle_in_place!(recv, option_value(args, "random"))
        end

        interpreter.define_method_builtin("rotate") do |recv, args, _block|
          array_rotate_copy(recv, args[0] || 1)
        end

        interpreter.define_method_builtin("rotate!") do |recv, args, _block|
          array_rotate_in_place!(recv, args[0] || 1)
        end

        interpreter.define_method_builtin("flatten") do |recv, _args, _block|
          recv.flatten
        end

        interpreter.define_method_builtin("uniq") do |recv, _args, _block|
          recv.uniq
        end

        interpreter.define_method_builtin("join") do |recv, args, _block|
          if recv.is_a?(Tungsten::PathValue)
            recv.join(*args)
          else
            recv.join(args[0] || "")
          end
        end

        interpreter.define_method_builtin("any?") do |recv, _args, block|
          if block
            recv.any? { |item| block.call(item) }
          else
            recv.any?
          end
        end

        interpreter.define_method_builtin("all?") do |recv, _args, block|
          if block
            recv.all? { |item| block.call(item) }
          else
            recv.all?
          end
        end

        interpreter.define_method_builtin("none?") do |recv, _args, block|
          if block
            recv.none? { |item| block.call(item) }
          else
            recv.none?
          end
        end

        interpreter.define_method_builtin("min") do |recv, _args, _block|
          recv.min
        end

        interpreter.define_method_builtin("max") do |recv, _args, _block|
          recv.max
        end

        interpreter.define_method_builtin("sum") do |recv, args, _block|
          # Optional explicit initial value: `arr.sum(0 m)`. When omitted and
          # the array holds Quantities, start from the first element so the
          # default `0` initial doesn't trip `Integer + Quantity` errors.
          if !args.empty?
            recv.inject(args[0]) { |a, b| a + b }
          elsif recv.empty?
            0
          elsif recv.first.is_a?(Tungsten::Quantity)
            recv[1..].inject(recv.first) { |a, b| a + b }
          else
            recv.sum
          end
        end

        interpreter.define_method_builtin("mean") do |recv, _args, _block|
          if recv.empty?
            raise Tungsten::Error.new("mean of an empty array is undefined")
          end
          total = recv.first.is_a?(Tungsten::Quantity) ?
                    recv[1..].inject(recv.first) { |a, b| a + b } :
                    recv.sum
          total / recv.length
        end

        interpreter.define_method_builtin("stdev") do |recv, _args, _block|
          # Sample standard deviation (Bessel's correction: dividing by n-1).
          # For a Quantity array, propagates units correctly via Quantity arithmetic.
          n = recv.length
          raise Tungsten::Error.new("stdev requires at least 2 values") if n < 2
          first = recv.first
          mean = first.is_a?(Tungsten::Quantity) ?
                   recv[1..].inject(first) { |a, b| a + b } / n :
                   recv.sum.to_f / n
          variance_zero = first.is_a?(Tungsten::Quantity) ?
                            Tungsten::Quantity.new(0, first.unit * first.unit) :
                            0.0
          variance = recv.inject(variance_zero) do |acc, x|
            diff = x - mean
            acc + diff * diff
          end / (n - 1)
          # √variance — for Quantity, raise to 0.5 power semantics aren't supported,
          # so route through SI value.
          if variance.is_a?(Tungsten::Quantity)
            si = variance.value * variance.unit.factor
            sigma_si = Math.sqrt(si.to_f)
            # Result has dim √(unit²) = unit. Construct a Quantity in `first.unit`.
            Tungsten::Quantity.new(sigma_si / first.unit.factor, first.unit)
          else
            Math.sqrt(variance)
          end
        end

        interpreter.define_method_builtin("variance") do |recv, _args, _block|
          n = recv.length
          raise Tungsten::Error.new("variance requires at least 2 values") if n < 2
          first = recv.first
          mean = first.is_a?(Tungsten::Quantity) ?
                   recv[1..].inject(first) { |a, b| a + b } / n :
                   recv.sum.to_f / n
          init = first.is_a?(Tungsten::Quantity) ?
                   Tungsten::Quantity.new(0, first.unit * first.unit) : 0.0
          recv.inject(init) { |acc, x| diff = x - mean; acc + diff * diff } / (n - 1)
        end

        interpreter.define_method_builtin("median") do |recv, _args, _block|
          raise Tungsten::Error.new("median of an empty array is undefined") if recv.empty?
          sorted = recv.sort
          n = sorted.length
          n.odd? ? sorted[n / 2] : (sorted[n / 2 - 1] + sorted[n / 2]) / 2
        end

        # ── Hash builtins ────────────────────────────────────────────────

        interpreter.define_method_builtin("keys") do |recv, _args, _block|
          recv.keys
        end

        interpreter.define_method_builtin("values") do |recv, _args, _block|
          recv.values
        end

        interpreter.define_method_builtin("has_key?") do |recv, args, _block|
          recv.key?(args[0])
        end

        interpreter.define_method_builtin("key?") do |recv, args, _block|
          recv.key?(args[0])
        end

        interpreter.define_method_builtin("merge") do |recv, args, _block|
          recv.merge(args[0])
        end

        interpreter.define_method_builtin("fetch") do |recv, args, _block|
          if args.size > 1
            recv.fetch(args[0], args[1])
          else
            recv.fetch(args[0])
          end
        end

        interpreter.define_method_builtin("delete") do |recv, args, _block|
          recv.delete(args[0])
        end

        # ── Integer/Float builtins ───────────────────────────────────────

        interpreter.define_method_builtin("abs") do |recv, _args, _block|
          recv.abs
        end

        interpreter.define_method_builtin("zero?") do |recv, _args, _block|
          recv.zero?
        end

        interpreter.define_method_builtin("positive?") do |recv, _args, _block|
          recv.positive?
        end

        interpreter.define_method_builtin("negative?") do |recv, _args, _block|
          recv.negative?
        end

        interpreter.define_method_builtin("even?") do |recv, _args, _block|
          recv.even?
        end

        interpreter.define_method_builtin("odd?") do |recv, _args, _block|
          recv.odd?
        end

        interpreter.define_method_builtin("times") do |recv, _args, block|
          recv.times { |i| block.call(i) }
          recv
        end

        interpreter.define_method_builtin("clamp") do |recv, args, _block|
          recv.clamp(args[0], args[1])
        end

        interpreter.define_method_builtin("round") do |recv, args, _block|
          args.empty? ? recv.round : recv.round(args[0])
        end

        interpreter.define_method_builtin("ceil") do |recv, _args, _block|
          recv.ceil
        end

        interpreter.define_method_builtin("floor") do |recv, _args, _block|
          recv.floor
        end

        interpreter.define_method_builtin("sqrt") do |recv, _args, _block|
          Math.sqrt(recv)
        end

        interpreter.define_method_builtin("sq") do |recv, _args, _block|
          recv * recv
        end

        interpreter.define_method_builtin("add") do |recv, args, _block|
          recv + args[0]
        end

        # ── Collection utilities ─────────────────────────────────────────

        interpreter.define_method_builtin("count") do |recv, args, block|
          if block
            recv.count { |item| block.call(item) }
          elsif args.any?
            recv.count(args[0])
          else
            recv.count
          end
        end

        interpreter.define_method_builtin("flat_map") do |recv, _args, block|
          recv.flat_map { |item| block.call(item) }
        end

        interpreter.define_method_builtin("find") do |recv, _args, block|
          recv.find { |item| block.call(item) }
        end

        interpreter.define_method_builtin("each_with_index") do |recv, _args, block|
          recv.each_with_index { |item, i| block.call(item, i) }
          recv
        end

        interpreter.define_method_builtin("zip") do |recv, args, _block|
          recv.zip(*args)
        end

        interpreter.define_method_builtin("take") do |recv, args, _block|
          recv.take(args[0])
        end

        interpreter.define_method_builtin("drop") do |recv, args, _block|
          recv.drop(args[0])
        end

        interpreter.define_method_builtin("compact") do |recv, _args, _block|
          recv.compact
        end

        interpreter.define_method_builtin("freeze") do |recv, _args, _block|
          recv.freeze
        end

        interpreter.define_method_builtin("frozen?") do |recv, _args, _block|
          recv.frozen?
        end
      end
    end
  end
end
