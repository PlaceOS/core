# NOTE: This was used in a bunch of places, and didn't make sense to put in `DriverStore`.
module PlaceOS::Core::ExecutablesFor
  def executables_for(driver : Model::Driver) : Array(Model::Executable)
    binary_store.query(
      entrypoint: driver.file_name,
      commit: driver.commit,
    ).sort_by do |executable|
      File.info(binary_store.path(executable)).modification_time
    end.reverse!
  end
end
