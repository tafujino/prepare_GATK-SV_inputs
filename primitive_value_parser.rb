# frozen_string_literal: true

module PrimitiveValueParser
  class << self
    # @param v [String]
    # @return  [String, Integer, Float, Boolean, Array]
    def run(v)
      unless v.is_a?(String)
        warn "Non-string value is given: #{v}"
        exit 1
      end

      ret = try_array(v)
      return ret unless ret.nil?

      ret = try_integer(v)
      return ret unless ret.nil?

      ret = try_float(v)
      return ret unless ret.nil?

      # The following is invalid because try_boolean may return `false`
      # try_boolean(v) || v
      ret = try_boolean(v)
      return ret unless ret.nil?

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

        ret = try_integer(v)
        next ret unless ret.nil?

        ret = try_float(v)
        next ret unless ret.nil?

        ret = try_boolean(v)
        next ret unless ret.nil?

        warn "Failed to parse: #{e}"
        exit 1
      end
    end
  end
end
