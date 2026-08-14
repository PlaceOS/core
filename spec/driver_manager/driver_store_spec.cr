require "../helper"
require "../support/stub_driver_store"

module PlaceOS::Core
  describe DriverStore, tags: "driver_store" do
    # Regression: a driver whose binary is absent locally *and* has no prebuilt
    # artifact on the build service was unrecoverable. `compiled?` only ever asks
    # whether an artifact exists; when the answer is "no" nothing in that path
    # makes one appear, so on-demand loads failed identically forever and only a
    # restart (whose startup pass does fall back to compiling) fixed it.
    describe "#fetch_or_build?" do
      file_name = "drivers/place/spec_helper.cr"
      branch = "master"
      uri = "https://github.com/placeos/private-drivers"

      it "asks the build service to compile when no prebuilt artifact exists" do
        store = Core.stub_store
        store.download_available = false
        store.build_succeeds = true

        path = store.fetch_or_build?(file_name, "aaaaaa1", branch, uri)

        path.should_not be_nil
        File.exists?(path.not_nil!).should be_true
        store.download_calls.should eq 1
        store.build_calls.should eq 1
      end

      it "does not request a build when a prebuilt artifact is available" do
        store = Core.stub_store
        store.download_available = true
        store.build_succeeds = true

        store.fetch_or_build?(file_name, "aaaaaa2", branch, uri).should_not be_nil

        store.download_calls.should eq 1
        store.build_calls.should eq 0
      end

      it "returns nil when the driver can neither be downloaded nor built" do
        store = Core.stub_store
        store.download_available = false
        store.build_succeeds = false

        store.fetch_or_build?(file_name, "aaaaaa3", branch, uri).should be_nil

        store.download_calls.should eq 1
        store.build_calls.should eq 1
      end

      # The failure that made this un-self-healing in production: if a failed
      # attempt were remembered, the driver would stay unlaunchable until the
      # process restarted. Every call must go back out to the build service.
      it "retries the build service on the call after a failure" do
        store = Core.stub_store
        store.download_available = false
        store.build_succeeds = false

        store.fetch_or_build?(file_name, "aaaaaa4", branch, uri).should be_nil
        store.download_calls.should eq 1

        store.fetch_or_build?(file_name, "aaaaaa4", branch, uri).should be_nil
        store.download_calls.should eq 2
        store.build_calls.should eq 2

        # ...and it recovers the moment the build service can serve the driver.
        store.download_available = true
        store.fetch_or_build?(file_name, "aaaaaa4", branch, uri).should_not be_nil
      end

      it "coalesces concurrent callers into a single build" do
        store = Core.stub_store
        store.download_available = false
        store.build_succeeds = true
        # Hold the first caller inside the fetch long enough for the rest to pile up
        store.download_delay = 50.milliseconds

        concurrency = 5
        results = Channel(String?).new(concurrency)
        concurrency.times do
          spawn { results.send store.fetch_or_build?(file_name, "aaaaaa5", branch, uri) }
        end
        concurrency.times { results.receive.should_not be_nil }

        store.download_calls.should eq 1
        store.build_calls.should eq 1
      end

      it "skips the build service entirely when a usable binary is on disk" do
        store = Core.stub_store
        store.write_stub_binary(store.driver_binary_path(file_name, "aaaaaa6"))

        store.fetch_or_build?(file_name, "aaaaaa6", branch, uri).should_not be_nil

        store.download_calls.should eq 0
        store.build_calls.should eq 0
      end

      # A loader that raises must release its coordination slot. If it doesn't,
      # every later caller for that binary blocks on the abandoned promise
      # forever — the "wedged until restart" failure mode, reached via a hung
      # build service request rather than a negative answer.
      it "releases the fetch slot when the build service raises" do
        store = Core.stub_store
        store.download_error = "build service unreachable"

        expect_raises(Exception, "build service unreachable") do
          store.fetch_or_build?(file_name, "aaaaaa7", branch, uri)
        end

        store.download_error = nil
        store.download_available = true

        completed = Channel(String?).new(1)
        spawn { completed.send(store.fetch_or_build?(file_name, "aaaaaa7", branch, uri)) }

        select
        when path = completed.receive
          path.should_not be_nil
        when timeout 5.seconds
          raise "second fetch blocked: the failed fetch leaked its coordination slot"
        end
      end
    end

    describe ".compiled?" do
      # Regression: previously, multiple modules sharing the same driver
      # (`file_name + commit`) would each take their own `compiled?` path,
      # all see `File.exists?` as false, and each call the build service and
      # `fetch_binary` to the same on-disk path — racing the write and hammering
      # the build service for the same binary. `compiled?` now coordinates
      # in-flight fetches keyed by binary path: one fiber fetches, the rest wait
      # on a channel and observe the binary once it's on disk.
      it "dedupes concurrent fetches of the same binary" do
        _, driver, _ = setup

        store = DriverStore.new
        path = store.driver_binary_path(driver.file_name, driver.commit)

        # Force a first-time fetch by removing any binary left on disk from a
        # prior spec, and zero out the slow-path counter.
        File.delete(path.to_s) rescue nil
        DriverStore.reset_compiled_attempts

        repo = driver.repository!
        concurrency = 5
        results = Channel(Bool).new(concurrency)

        concurrency.times do
          spawn do
            results.send store.compiled?(driver.file_name, driver.commit, repo.branch, repo.uri)
          end
        end

        concurrency.times { results.receive.should be_true }

        # All `concurrency` callers should resolve through a single fetch:
        # one fiber became the loader, the rest waited on the channel and then
        # found the binary already on disk.
        DriverStore.compiled_attempts.should eq 1
        File.exists?(path.to_s).should be_true
      end

      it "shares a single failed fetch across concurrent callers" do
        _, driver, _ = setup

        store = DriverStore.new
        repo = driver.repository!

        # A commit that the build service does not (and cannot) produce — every
        # `compiled?` against it must come back `false`. With dedup, all
        # concurrent callers observe the *same* failed fetch (one round-trip);
        # without it, each caller would pay its own round-trip to the build
        # service.
        bogus_commit = "deadbee"
        path = store.driver_binary_path(driver.file_name, bogus_commit).to_s
        File.delete(path) rescue nil
        DriverStore.reset_compiled_attempts

        concurrency = 5
        results = Channel(Bool).new(concurrency)
        concurrency.times do
          spawn do
            results.send store.compiled?(driver.file_name, bogus_commit, repo.branch, repo.uri)
          end
        end

        concurrency.times { results.receive.should be_false }

        DriverStore.compiled_attempts.should eq 1
        File.exists?(path).should be_false
      end

      it "lets a later call short-circuit without a fetch when the binary is already present" do
        _, driver, _ = setup

        store = DriverStore.new
        repo = driver.repository!
        path = store.driver_binary_path(driver.file_name, driver.commit).to_s

        # Force the warming call to go through the slow path.
        File.delete(path) rescue nil
        DriverStore.reset_compiled_attempts
        store.compiled?(driver.file_name, driver.commit, repo.branch, repo.uri).should be_true
        DriverStore.compiled_attempts.should eq 1

        # A subsequent call should hit the fast path — no new fetch.
        DriverStore.reset_compiled_attempts
        store.compiled?(driver.file_name, driver.commit, repo.branch, repo.uri).should be_true
        DriverStore.compiled_attempts.should eq 0
      end
    end
  end
end
