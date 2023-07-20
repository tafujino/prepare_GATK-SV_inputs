# frozen_string_litaral: true

require 'csv'
require_relative 'data_pointer'
require_relative 'primitive_value_parser'

module TableParser
  class << self
    # @param tsv_path [String]
    # @return         [Hash{ String => Object }]
    def run(tsv_path)
      row = CSV.read(tsv_path, headers: true, col_sep: "\t", quote_char: "\x00").first.to_a
      remove_table_prefix_from_key!(row)
      kvs = row.to_h
      kvs.transform_values { |v| PrimitiveValueParser.run(v) }
    end

    private

    # The first key contains a prefix /^\w+:/ and this function removes it
    # @param row [Array<Array<String>>] Array of key-value
    def remove_table_prefix_from_key!(row)
      first_kv = row.shift
      k, v = first_kv
      k = k.sub(/^\w+:(\w+)$/, '\1')
      row.unshift([k, v])
    end
  end
end
