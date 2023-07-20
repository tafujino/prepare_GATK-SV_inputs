# frozen_string_literal: true

require 'pathname'
require 'fileutils'
require 'open3'
require_relative 'workflow_input_parser'
require_relative 'table_parser'

base_dir = ARGV.shift
workflow_input_json_path = ARGV.shift
workspace_data_tsv_path = ARGV.shift
sample_tsv_path = ARGV.shift
sample_name = ARGV.shift

base_dir = Pathname.new(base_dir).expand_path
input = WorkflowInputParser.run(workflow_input_json_path)
workspace_data = TableParser.run(workspace_data_tsv_path)
sample = TableParser.run(sample_tsv_path)

input.transform_values! do |v|
  next v unless v.is_a?(DataPointer)

  case v.table_name
  when 'workspace'
    download_dir = base_dir / 'workspace_data'
    v0 = workspace_data[v.key]
  when 'this'
    download_dir = base_dir / sample_name
    v0 = sample[v.key]
  else
    warn "Invalid table: #{v.table_name}"
    exit 1
  end

  next v0 unless v0.is_a?(String)
  next v0 unless v0 =~ %r{^gs://(.+)$}

  dst_path = download_dir / Regexp.last_match(1)
  FileUtils.mkpath(dst_path.dirname)

  warn "Downloading #{v0}"
  Open3.popen3("gsutil cp #{v0} #{dst_path.dirname}") do |_, o, e, _|
    o.each { |line| warn line }
    e.each { |line| warn line }
  end
  dst_path.to_s
end

puts JSON.generate(input)
