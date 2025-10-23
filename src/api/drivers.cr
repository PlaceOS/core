require "redis"
require "placeos-models"
require "./application"

module PlaceOS::Core::Api
  class Drivers < Application
    base "/api/core/v1/drivers/"

    protected getter store = DriverStore.new

    # Boolean check whether driver is compiled
    @[AC::Route::GET("/:file_name/compiled")]
    def compiled(
      @[AC::Param::Info(name: "file_name", description: "the name of the file in the repository", example: "drivers/place/meet.cr")]
      driver_file : String,
      @[AC::Param::Info(description: "the commit hash of the driver to check is compiled", example: "e901494")]
      commit : String,
      @[AC::Param::Info(description: "the driver database id", example: "driver-GFEaAlJB5")]
      tag : String,
    ) : Bool
      driver = Model::Driver.find!(tag)
      repository = driver.repository!
      store.compiled?(driver_file, commit, repository.branch, repository.uri)
    end

    # Force re-compile driver
    @[AC::Route::POST("/:file_name/recompile")]
    def recompile(
      @[AC::Param::Info(name: "file_name", description: "the name of the file in the repository", example: "drivers/place/meet.cr")]
      driver_file : String,
      @[AC::Param::Info(description: "the commit hash of the driver to check is compiled", example: "e901494")]
      commit : String,
      @[AC::Param::Info(description: "the driver database id", example: "driver-GFEaAlJB5")]
      tag : String,
    ) : String
      driver = Model::Driver.find!(tag)
      repository = driver.repository!
      result = store.compile(driver_file, repository.uri, commit, repository.branch, true, repository.username, repository.decrypt_password, false)
      if result.success
        render text: "OK"
      else
        render :internal_server_error, text: result.output
      end
    end

    # Fetch and reload compiled driver
    @[AC::Route::POST("/:driver_id/reload")]
    def reload(
      @[AC::Param::Info(description: "the driver database id", example: "driver-GFEaAlJB5")]
      driver_id : String,
    ) : String
      result = store.reload_driver(driver_id)
      render status: result[:status], text: result[:message]
    end

    # Returns the details of a driver
    @[AC::Route::GET("/:file_name/details")]
    def details(
      @[AC::Param::Info(description: "the id of the repository", example: "repo-xxxx")]
      repository : String,
      @[AC::Param::Info(name: "file_name", description: "the name of the file in the repository", example: "drivers/place/meet.cr")]
      driver_file : String,
      @[AC::Param::Info(description: "the commit hash of the driver to be built", example: "e901494")]
      commit : String,
      @[AC::Param::Info(description: "the branch of the repository", example: "main")]
      branch : String = "master",
    ) : Nil
      Log.context.set(driver: driver_file, repository: repository, commit: commit, branch: branch)
      repo = Model::Repository.find!(repository)
      defaults = store.defaults(driver_file, commit, branch, repo.uri)
      if defaults.success
        response.headers["Content-Type"] = "application/json"
        render text: defaults.output
      end
      password = repo.decrypt_password if repo.password.presence
      result = store.compile(driver_file, repo.uri, commit, branch, false, repo.username, password)
      if result.success
        defaults = store.defaults(driver_file, commit, branch, repo.uri)
        if defaults.success
          response.headers["Content-Type"] = "application/json"
          render text: defaults.output
        end
      end
      render :internal_server_error, text: result.output
    end
  end
end
