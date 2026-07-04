require "support/to_node"

module Tungsten::AST
  RSpec.describe "on guard (platform guard)" do
    def parse(code)
      Tungsten::Parser.parse(code)
    end

    def first_expr(code)
      parse(code).list.first
    end

    # -- Parser tests --

    describe "parsing" do
      it "parses a simple 'on macos' block" do
        node = first_expr("on macos\n  -> clock_ms\n    42")
        expect(node).to be_a(OnGuard)
        expect(node.predicate).to eq(TargetDesignator.new("macos"))
        expect(node.capabilities).to eq([])
        expect(node.body.list.length).to eq(1)
      end

      it "parses 'on linux && x86_64'" do
        node = first_expr("on linux && x86_64\n  -> clock_ms\n    42")
        expect(node.predicate).to eq(
          TargetAnd.new(TargetDesignator.new("linux"), TargetDesignator.new("x86_64"))
        )
      end

      it "parses 'on linux || macos'" do
        node = first_expr("on linux || macos\n  -> clock_ms\n    42")
        expect(node.predicate).to eq(
          TargetOr.new(TargetDesignator.new("linux"), TargetDesignator.new("macos"))
        )
      end

      it "parses 'on linux with io_uring'" do
        node = first_expr("on linux with io_uring\n  -> submit\n    42")
        expect(node.predicate).to eq(TargetDesignator.new("linux"))
        expect(node.capabilities).to eq(["io_uring"])
      end

      it "parses 'on linux && x86_64 with io_uring'" do
        node = first_expr("on linux && x86_64 with io_uring\n  -> submit\n    42")
        expect(node.predicate).to eq(
          TargetAnd.new(TargetDesignator.new("linux"), TargetDesignator.new("x86_64"))
        )
        expect(node.capabilities).to eq(["io_uring"])
      end

      it "parses 'on !(linux || macos)'" do
        node = first_expr("on !(linux || macos)\n  -> clock_ms\n    42")
        expect(node.predicate).to eq(
          TargetNot.new(TargetOr.new(TargetDesignator.new("linux"), TargetDesignator.new("macos")))
        )
      end

      it "parses 'on !(linux || macos) with fallback_clock'" do
        node = first_expr("on !(linux || macos) with fallback_clock\n  -> clock_ms\n    42")
        expect(node.predicate).to eq(
          TargetNot.new(TargetOr.new(TargetDesignator.new("linux"), TargetDesignator.new("macos")))
        )
        expect(node.capabilities).to eq(["fallback_clock"])
      end

      it "parses grouped expression 'on linux && (x86_64 || arm64)'" do
        node = first_expr("on linux && (x86_64 || arm64)\n  -> clock_ms\n    42")
        expect(node.predicate).to eq(
          TargetAnd.new(
            TargetDesignator.new("linux"),
            TargetOr.new(TargetDesignator.new("x86_64"), TargetDesignator.new("arm64"))
          )
        )
      end

      it "gives 'with' the lowest precedence" do
        # on linux || macos with kqueue → (linux || macos) with kqueue
        node = first_expr("on linux || macos with kqueue\n  -> poll\n    42")
        expect(node.predicate).to eq(
          TargetOr.new(TargetDesignator.new("linux"), TargetDesignator.new("macos"))
        )
        expect(node.capabilities).to eq(["kqueue"])
      end

      it "supports chained 'with' clauses" do
        node = first_expr("on linux with io_uring with fast_clock\n  -> submit\n    42")
        expect(node.predicate).to eq(TargetDesignator.new("linux"))
        expect(node.capabilities).to eq(["io_uring", "fast_clock"])
      end

      it "parses alias designators (amd64, intel)" do
        node = first_expr("on amd64\n  -> foo\n    1")
        expect(node.predicate).to eq(TargetDesignator.new("amd64"))

        node2 = first_expr("on intel\n  -> foo\n    1")
        expect(node2.predicate).to eq(TargetDesignator.new("intel"))
      end

      it "produces correct to_sexp" do
        node = first_expr("on linux && x86_64 with io_uring\n  -> submit\n    42")
        sexp = node.to_sexp
        expect(sexp[0]).to eq(:on_guard)
        expect(sexp[1]).to eq([:target_and, [:target_designator, "linux"], [:target_designator, "x86_64"]])
        expect(sexp[2]).to eq(["io_uring"])
      end

      it "parses multiple definitions inside an on block" do
        code = <<~W
          on macos
            -> clock_ms
              42
            -> monotonic_ns
              99
        W
        node = first_expr(code)
        expect(node.body.list.length).to eq(2)
      end
    end

    # -- Target matching tests --

    describe Tungsten::Target do
      let(:macos_x86) { { os: "macos", arch: "x86_64", features: [] } }
      let(:linux_x86) { { os: "linux", arch: "x86_64", features: [] } }
      let(:linux_arm) { { os: "linux", arch: "arm64", features: [] } }
      let(:linux_x86_uring) { { os: "linux", arch: "x86_64", features: ["io_uring"] } }

      it "matches simple os designator" do
        pred = TargetDesignator.new("macos")
        expect(Tungsten::Target.matches?(pred, [], macos_x86)).to be true
        expect(Tungsten::Target.matches?(pred, [], linux_x86)).to be false
      end

      it "matches simple arch designator" do
        pred = TargetDesignator.new("x86_64")
        expect(Tungsten::Target.matches?(pred, [], macos_x86)).to be true
        expect(Tungsten::Target.matches?(pred, [], linux_arm)).to be false
      end

      it "normalizes amd64 alias to x86_64" do
        pred = TargetDesignator.new("amd64")
        expect(Tungsten::Target.matches?(pred, [], macos_x86)).to be true
      end

      it "normalizes intel alias to x86_64" do
        pred = TargetDesignator.new("intel")
        expect(Tungsten::Target.matches?(pred, [], linux_x86)).to be true
      end

      it "evaluates AND predicates" do
        pred = TargetAnd.new(TargetDesignator.new("linux"), TargetDesignator.new("x86_64"))
        expect(Tungsten::Target.matches?(pred, [], linux_x86)).to be true
        expect(Tungsten::Target.matches?(pred, [], linux_arm)).to be false
        expect(Tungsten::Target.matches?(pred, [], macos_x86)).to be false
      end

      it "evaluates OR predicates" do
        pred = TargetOr.new(TargetDesignator.new("linux"), TargetDesignator.new("macos"))
        expect(Tungsten::Target.matches?(pred, [], linux_x86)).to be true
        expect(Tungsten::Target.matches?(pred, [], macos_x86)).to be true
      end

      it "evaluates NOT predicates" do
        pred = TargetNot.new(TargetDesignator.new("linux"))
        expect(Tungsten::Target.matches?(pred, [], macos_x86)).to be true
        expect(Tungsten::Target.matches?(pred, [], linux_x86)).to be false
      end

      it "checks capability requirements" do
        pred = TargetDesignator.new("linux")
        expect(Tungsten::Target.matches?(pred, ["io_uring"], linux_x86_uring)).to be true
        expect(Tungsten::Target.matches?(pred, ["io_uring"], linux_x86)).to be false
      end

      it "handles complex predicates: !(linux || macos)" do
        pred = TargetNot.new(TargetOr.new(TargetDesignator.new("linux"), TargetDesignator.new("macos")))
        expect(Tungsten::Target.matches?(pred, [], linux_x86)).to be false
        expect(Tungsten::Target.matches?(pred, [], macos_x86)).to be false
      end
    end

    # -- Interpreter tests --

    describe "interpreter integration" do
      def run(code, target: nil)
        saved = Tungsten::Target.current
        Tungsten::Target.current = target if target
        Tungsten::Interpreter.new.run(code)
      ensure
        Tungsten::Target.current = saved
      end

      it "selects the matching guarded method at top level" do
        code = <<~W
          on macos
            -> clock_ms
              42

          on linux
            -> clock_ms
              99

          clock_ms
        W
        result = run(code, target: { os: "macos", arch: "x86_64", features: [] })
        expect(result).to eq(42)
      end

      it "selects matching guard inside a class definition" do
        code = <<~W
          + Clock
            on macos
              -> tick
                "mac"

            on linux
              -> tick
                "lin"
        W

        result = run(code + "\nClock.new.tick", target: { os: "macos", arch: "x86_64", features: [] })
        expect(result).to eq("mac")
      end

      it "non-matching guard is not visible" do
        code = <<~W
          + Clock
            on linux
              -> tick
                "lin"

            -> tock
              "always"
        W

        result = run(code + "\nClock.new.tock", target: { os: "macos", arch: "x86_64", features: [] })
        expect(result).to eq("always")

        expect {
          run(code + "\nClock.new.tick", target: { os: "macos", arch: "x86_64", features: [] })
        }.to raise_error(Tungsten::Error, /undefined method 'tick'/)
      end

      it "raises on duplicate guarded methods for the same target" do
        code = <<~W
          + Clock
            on macos
              -> tick
                "first"

            on macos
              -> tick
                "second"
        W

        expect {
          run(code, target: { os: "macos", arch: "x86_64", features: [] })
        }.to raise_error(Tungsten::Error, /ambiguous platform guard.*tick/)
      end

      it "fallback to unguarded method when no guard matches" do
        code = <<~W
          + Clock
            -> tick
              "fallback"

            on linux
              -> tick
                "lin"
        W

        result = run(code + "\nClock.new.tick", target: { os: "macos", arch: "x86_64", features: [] })
        expect(result).to eq("fallback")
      end

      it "guarded method overrides unguarded when guard matches" do
        code = <<~W
          + Clock
            -> tick
              "fallback"

            on macos
              -> tick
                "mac"
        W

        result = run(code + "\nClock.new.tick", target: { os: "macos", arch: "x86_64", features: [] })
        expect(result).to eq("mac")
      end

      it "supports capability filtering with 'with'" do
        code = <<~W
          + IO
            on linux with io_uring
              -> submit
                "uring"

            -> submit
              "fallback"
        W

        result_with = run(code + "\nIO.new.submit", target: { os: "linux", arch: "x86_64", features: ["io_uring"] })
        expect(result_with).to eq("uring")

        result_without = run(code + "\nIO.new.submit", target: { os: "linux", arch: "x86_64", features: [] })
        expect(result_without).to eq("fallback")
      end
    end
  end
end
