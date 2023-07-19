# frozen_string_litaral: true

require 'json'
require_relative 'data_pointer'

module WorkflowInputParser
  class << self
    # @param json_path [String]
    # @return          [Hash{ String => Object }]
    def run(json_path)
      kvs = JSON.parse(File.read(json_path))
      kvs.transform_values { |v| infer(v) }
    end

    private

    # @param v [String]
    # @return  [Object]
    def infer(v)
      if v =~ /\$\{.+\}/
        unless v =~ /^\$\{(.+)\}$/
          warn 'The value contains placeholder but the range is not the entire string. Failed to parse.'
          exit 1
        end

        v0 = Regexp.last_match(1)
        parse_as_a_data_pointer(v0) || parse_as_a_raw_value(v0)
      else
        parse_as_a_raw_value(v)
      end
    end

    # @param v [String]
    # @return  [DataPointer, nil] if it is interpretable as a data pointer, returns DataPointer object
    #                             Otherwise, returns nil
    def parse_as_a_data_pointer(v)
      DataPointer.new(Regexp.last_match(1), Regexp.last_match(2)) if v =~ /^(\w+)\.(\w+)$/
    end

    # @param v [String]
    # @return  [String, Integer, Float]
    def parse_as_a_raw_value(v)
      unless v.is_a?(String)
        warn "Non-string value is given: #{v}"
        exit 1
      end

      begin
        Integer(v)
      rescue
        begin
          Float(v)
        rescue
          v
        end
      end
    end
  end
end
