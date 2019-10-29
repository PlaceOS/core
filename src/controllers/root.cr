require "./application"

# TODO: Remove root controller once radix routing bug fixed
module ACAEngine::Core::Api
  class Root < Application
    base "/api/core/v1/"

    def index
      head :ok
    end
  end
end
