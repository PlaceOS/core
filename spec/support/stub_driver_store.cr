require "../helper"

module PlaceOS::Core
  # Exercises the fetch/build decision logic without a build service.
  #
  # The two calls out — `download_compiled` (is there already an artifact?) and
  # `request_build` (please make one) — are replaced with counters and a scripted
  # outcome, so specs can drive the exact combination that wedged production:
  # nothing on disk, nothing prebuilt, but buildable on request.
  class StubDriverStore < DriverStore
    property download_available : Bool = false
    property build_succeeds : Bool = false
    property download_delay : Time::Span = Time::Span.zero
    property download_error : String? = nil

    @download_calls : Atomic(Int32) = Atomic(Int32).new(0)
    @build_calls : Atomic(Int32) = Atomic(Int32).new(0)

    def download_calls : Int32
      @download_calls.get
    end

    def build_calls : Int32
      @build_calls.get
    end

    protected def download_compiled(file_name : String, commit : String, branch : String, uri : String) : Bool
      @download_calls.add(1)
      sleep download_delay
      raise Error.new(download_error.not_nil!) if download_error
      return false unless download_available
      write_stub_binary(driver_binary_path(file_name, commit))
      true
    end

    protected def request_build(path : Path, file_name : String, commit : String, branch : String, uri : String, username : String?, password : String?) : Bool
      @build_calls.add(1)
      return false unless build_succeeds
      write_stub_binary(path)
      true
    end

    # `validate_binary` probes a candidate by running it with `-h`, so the stand-in
    # for a compiled driver has to be something that actually executes.
    def write_stub_binary(path : Path) : Nil
      File.write(path, "#!/bin/sh\nexit 0\n")
      File.chmod(path, 0o755)
    end
  end

  # Each spec gets its own binary directory and driver identity so that the
  # process-wide fetch coordination in `DriverStore` can't leak between them.
  def self.stub_store : StubDriverStore
    StubDriverStore.new(File.tempname("driver-store-spec"))
  end
end
