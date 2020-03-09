require "./application"

# TODO: Remove root controller once radix routing bug fixed
module PlaceOS::Core::Api
  class Root < Application
    base "/api/core/v1/"

    def index
      head :ok
    end
  end
end
