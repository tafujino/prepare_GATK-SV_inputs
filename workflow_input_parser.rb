# frozen_string_litaral: true

require 'json'
require_relative 'data_pointer'
require_relative 'string_inference'

module WorkflowInputParser
  class << self
    # @param json_path [String]
    # @return          [Hash{ String => Object }]
    def run(json_path)
      kvs = JSON.parse(File.read(json_path))
      kvs.transform_values { |v| infer(v) }
    end

    private

    # @param v [Object]
    # @return  [Object]
    def infer(v)
      return v unless v.is_a?(String)

      if v =~ /\$\{.+\}/
        unless v =~ /^\$\{(.+)\}$/
          warn 'Failed to parse. The value contains a placeholder but it does not span the entire string'
          exit 1
        end

        v0 = Regexp.last_match(1)
        try_data_pointer(v0) ||StringInference.run(v0)
      else
        StringInference.run(v)
      end
    end

    # @param v [String]
    # @return  [DataPointer, nil] if it is interpretable as a data pointer, returns DataPointer object
    #                             Otherwise, returns nil
    def try_data_pointer(v)
      DataPointer.new(Regexp.last_match(1), Regexp.last_match(2)) if v =~ /^([a-zA-Z_]\w*)\.([a-zA-Z_]\w*)$/
    end
  end
end
