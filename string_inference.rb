# frozen_string_literal: true

module StringInference
  class << self
    # @param v [String]
    # @return  [String, Integer, Float, Boolean, Array]
    def run(v)
      unless v.is_a?(String)
        warn "Non-string value is given: #{v}"
        exit 1
      end

      ret = try_array(v) || try_primitive_value(v)
      return ret unless ret.nil? # just `if ret` is a not valid since ret may be `false`

      v
    end

    private

    # @param v [String]
    # @param   [Integer, nil]
    def try_integer(v)
      Integer(v)
    rescue
      nil
    end

    # @param v [String]
    # @param   [Float, nil]
    def try_float(v)
      Float(v)
    rescue
      nil
    end

    # @param v [String]
    # @param   [Boolean, nil]
    def try_boolean(v)
      case v.downcase
      when 'true'
        true
      when 'false'
        false
      end
    end

    # Does not support a nested array
    def try_array(v)
      return nil unless v =~ /^\[(.*)\]$/

      Regexp.last_match(1).split(',').map do |e|
        next Regexp.last_match(1) if e =~ /"(.*)"/

        ret = try_primitive_value(e)
        next ret unless ret.nil? # just `if ret` is a not valid since ret may be `false`

        warn "Failed to parse: #{e}"
        exit 1
      end
    end

    # @param v [String]
    # @param   [Object, nil] Be careful to the return value!!
    #                        `nil` means inference failure and `false` means just boolean `false` value
    def try_primitive_value(v)
      try_integer(v) || try_float(v) || try_boolean(v)
    end
  end
end
