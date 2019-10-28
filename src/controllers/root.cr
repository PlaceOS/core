require "./application"

# TODO: Remove root controller once radix routing bug fixed
module ACAEngine::Core::Api
  class Root < Application
    base "/"

    def index
      head :not_found
    end
  end
end
