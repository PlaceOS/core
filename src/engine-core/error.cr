module ACAEngine::Core
  class Error < Exception
    getter message

    def initialize(@message : String = "")
      super(@message)
    end
  end

  class ModuleError < Error
  end
end
