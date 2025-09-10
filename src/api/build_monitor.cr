require "./application"

module PlaceOS::Core::Api
  class BuildMonitor < Application
    base "/api/core/v1/build/"

    protected getter store = DriverStore.new

    @[AC::Route::GET("/monitor")]
    def monitor(
      @[AC::Param::Info(name: "state", description: "state of job to return. One of [pending,running,cancelled error,done]. Defaults to 'pending'", example: "pending")]
      state : DriverStore::State = DriverStore::State::Pending,
    ) : Array(DriverStore::TaskStatus) | String
      result = store.monitor_jobs(state)
      if result[:success]
        render json: result[:output]
      else
        render status: result[:code], text: result[:output]
      end
    end

    @[AC::Route::DELETE("/cancel/:job")]
    def cancel(
      @[AC::Param::Info(name: "job", description: "ID of previously submitted compilation job")]
      job : String,
    ) : DriverStore::CancelStatus
      result = store.cancel_job(job)
      render status: result[:code], json: result[:output]
    end
  end
end
