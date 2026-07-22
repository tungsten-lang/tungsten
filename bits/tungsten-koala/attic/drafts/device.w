# Device — compute device detection, memory management, data transfer
# GPU-first: operations above a size threshold automatically dispatch to GPU.

in Tungsten:Koala

+ Device
  ro :kind       # :cpu, :cuda, :metal, :rocm
  ro :name       # "NVIDIA A100", "Apple M2 GPU", etc.
  ro :memory     # total device memory in bytes
  ro :index      # device index (for multi-GPU)

  # Size threshold (elements) below which CPU is faster due to transfer overhead.
  # Tuned per device family on first use.
  CPU_THRESHOLD = 4096

  @@devices     = nil
  @@default     = nil
  @@initialized = false

  -> new(@kind, @name, @memory, @index = 0)

  # --- Discovery ---

  # Detect all available compute devices. Called once on first use.
  -> .detect
    return @@devices if @@initialized

    @@devices = [self.new(:cpu, self.cpu_name, self.system_memory, 0)]

    case
    => self.cuda_available?
      self.cuda_devices.each_with_index -> (dev, i)
        @@devices.push(self.new(:cuda, dev.name, dev.memory, i))
    => self.metal_available?
      @@devices.push(self.new(:metal, self.metal_name, self.metal_memory, 0))
    => self.rocm_available?
      self.rocm_devices.each_with_index -> (dev, i)
        @@devices.push(self.new(:rocm, dev.name, dev.memory, i))

    @@initialized = true
    @@devices

  # List all available devices.
  -> .all
    self.detect

  # The default device — GPU if available, CPU otherwise.
  -> .default
    @@default ||= begin
      self.detect
      gpu = @@devices.find(-> (d) d.kind != :cpu)
      gpu || @@devices.first

  # Override the default device.
  -> .default=(device)
    @@default = case device
    => Device  -> device
    => Symbol  -> self.find(device)

  # Find a device by kind.
  -> .find(kind)
    self.detect
    @@devices.find(-> (d) d.kind == kind) || <! DeviceError, "No [kind] device available"

  # The CPU device.
  -> .cpu
    self.detect
    @@devices.first

  # The best GPU device, or nil.
  -> .gpu
    self.detect
    @@devices.find(-> (d) d.kind != :cpu)

  # Whether any GPU is available.
  -> .gpu?
    self.gpu != nil

  # Resolve a device option. nil means auto-select based on size.
  #
  #     Device.resolve(nil, elements: 50_000)   # => GPU if available and above threshold
  #     Device.resolve(:cpu, elements: 50_000)  # => CPU (forced)
  #     Device.resolve(:gpu, elements: 10)       # => GPU (forced, even if small)
  -> .resolve(option, elements: 0)
    case option
    => nil
      if self.gpu? && elements > CPU_THRESHOLD
        self.gpu
      else
        self.cpu
    => :cpu    -> self.cpu
    => :gpu    -> self.gpu || <! DeviceError, "No GPU available"
    => :cuda   -> self.find(:cuda)
    => :metal  -> self.find(:metal)
    => :rocm   -> self.find(:rocm)
    => Device  -> option

  # --- Properties ---

  -> gpu?     @kind != :cpu
  -> cpu?     @kind == :cpu
  -> cuda?    @kind == :cuda
  -> metal?   @kind == :metal
  -> rocm?    @kind == :rocm

  -> to_s "[kind]:[index] ([name], [Memory.format(@memory)])"

  # --- Backend detection ---

  [private]

  -> .cuda_available?
    FFI.available?("libcuda")

  -> .metal_available?
    System.os == :macos && FFI.available?("Metal")

  -> .rocm_available?
    FFI.available?("libamdhip64")

  -> .cuda_devices
    CUDA:Runtime.device_list

  -> .rocm_devices
    ROCm:Runtime.device_list

  -> .cpu_name
    System.cpu_name

  -> .system_memory
    System.total_memory

  -> .metal_name
    Metal:Device.default.name

  -> .metal_memory
    Metal:Device.default.recommended_max_working_set_size


# --- Memory transfer ---

+ DeviceMemory
  ro :device
  ro :pointer
  ro :size

  -> new(@device, @pointer, @size)

  # Allocate memory on a device.
  -> .alloc(device, size)
    ptr = case device.kind
    => :cpu   -> System.alloc(size)
    => :cuda  -> CUDA:Runtime.malloc(size)
    => :metal -> Metal:Buffer.new(size)
    => :rocm  -> ROCm:Runtime.malloc(size)
    self.new(device, ptr, size)

  # Transfer data between devices.
  -> .transfer(src_mem, dst_device)
    dst = self.alloc(dst_device, src_mem.size)
    case [src_mem.device.kind, dst_device.kind]
    => [:cpu, :cuda]   -> CUDA:Runtime.memcpy_h2d(dst.pointer, src_mem.pointer, src_mem.size)
    => [:cuda, :cpu]   -> CUDA:Runtime.memcpy_d2h(dst.pointer, src_mem.pointer, src_mem.size)
    => [:cpu, :metal]  -> Metal:Buffer.upload(dst.pointer, src_mem.pointer, src_mem.size)
    => [:metal, :cpu]  -> Metal:Buffer.download(dst.pointer, src_mem.pointer, src_mem.size)
    => [:cpu, :rocm]   -> ROCm:Runtime.memcpy_h2d(dst.pointer, src_mem.pointer, src_mem.size)
    => [:rocm, :cpu]   -> ROCm:Runtime.memcpy_d2h(dst.pointer, src_mem.pointer, src_mem.size)
    => _               -> <! DeviceError, "Unsupported transfer: [src_mem.device.kind] -> [dst_device.kind]"
    dst

  -> free
    case @device.kind
    => :cpu   -> System.free(@pointer)
    => :cuda  -> CUDA:Runtime.free(@pointer)
    => :metal -> Metal:Buffer.release(@pointer)
    => :rocm  -> ROCm:Runtime.free(@pointer)


+ DeviceError < Error
