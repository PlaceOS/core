require "../helper"

module PlaceOS::Core
  describe DriverStore, tags: "driver_store" do
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
