module PlaceOS::Core
  class Error < ::Exception
    getter message

    def initialize(@message : String = "", @cause : Exception? = nil)
      super
    end
  end

  class ModuleError < Error
  end
end
