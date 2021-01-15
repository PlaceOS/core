require "json"

module Initializer
  def initialize(__pull_for_json_serializable : JSON::PullParser)
    super(__pull_for_json_serializable)
  end

  def initialize(**args)
    {% begin %}
      if args.has_key? :__pull_for_json_serializable
        super
      else
      {% for var in @type.instance_vars %}
        {% if var.type.nilable? || var.has_default_value? %}
        @{{ var.id }} = args.has_key?({{var.symbolize}}) ? args[{{var.symbolize}}]? : {% if var.has_default_value? %} {{ var.default_value }} {% else %} nil {% end %}
        {% else %}
        @{{ var.id }} = args[{{var.symbolize}}]
        {% end %}
      {% end %}
      end
   {% end %}
  end
end

abstract struct Record
  include JSON::Serializable
end
