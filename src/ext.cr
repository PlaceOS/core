# TODO: remove when URI serialises to json
class URI
  def to_json(json)
    json.string(to_s)
  end
end
