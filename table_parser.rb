# frozen_string_litaral: true

require 'csv'
require_relative 'data_pointer'
require_relative 'string_inference'

module TableParser
  class << self
    # @param tsv_path [String]
    # @return         [Hash{ String => Object }]
    def run(tsv_path)
      rows = CSV.read(tsv_path, col_sep: "\t")
      remove_table_prefix_from_key!(rows).to_h
    end

    private

    # The first key contains a prefix /^\w+:/ and this function removes it
    # @param row [Array<Array<String>>] Array of key-value
    def remove_table_prefix_from_key!(rows)
      k, v = rows.shift
      k.gsub!(/^\w+:(\w+)$/, '\1')
      rows.unshift([k, v])
    end
  end
end
