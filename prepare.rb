# frozen_string_literal: true

require 'pathname'
require 'fileutils'
require 'yaml'
require_relative 'workflow_input_parser'
require_relative 'table_parser'

# @param params        [Hash{ String => Object }]
# @param path_mappings [Hash{ String => Pathname }]
def rewrite_gcnv_model_tars_list(params, path_mappings)
  key = 'GATKSVPipelineSingleSample.gcnv_model_tars_list'
  gcnv_model_tars_list_path = params[key]
  gcnv_model_tars_list = File.readlines(gcnv_model_tars_list_path, chomp: true)
  gcnv_model_tars_list.each do |tar_uri|
    is_success = false
    path_mappings.each do |src_dir_uri, dst_dir|
      uri_prefix_regexp = Regexp.compile("^#{Regexp.escape(src_dir_uri)}")
      next unless tar_uri =~ uri_prefix_regexp

      is_success = true
      tar_uri.gsub!(uri_prefix_regexp, dst_dir.to_s)
      break
    end
    unless is_success
      warn "Cannot find URI rewrite rule for #{tar_uri}"
      exit 1
    end
  end
end

config_path = Pathname.new(ARGV.shift)
base_dir = Pathname.new(ARGV.shift)

config = YAML.load_file(config_path)
workflow_inputs_json_path = Pathname.new(config['terra_workflow_inputs'])
workspace_data_tsv_path = Pathname.new(config['terra_workspace_data'])
sample_name = config['sample_name']
sample_cram_path = Pathname.new(config['sample_cram'])
out_path = Pathname.new(config['wdl_params'])
out_path = base_dir / out_path if out_path.relative?

base_dir = Pathname.new(base_dir).expand_path
params = WorkflowInputParser.run(workflow_inputs_json_path)
workspace_data = TableParser.run(workspace_data_tsv_path)
sample = { 'sample_id' => sample_name,
           'bam_or_cram_file' => sample_cram_path,
           'requester_pays_cram' => false }

path_mappings = {}
params.transform_values! do |v|
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

  src_path = Pathname.new(Regexp.last_match(1))
  src_dir = src_path.dirname
  dst_path = download_dir / src_path
  dst_dir = dst_path.dirname
  FileUtils.mkpath(dst_dir)
  path_mappings["gs://#{src_dir}"] = dst_dir

  dst_path.to_s
end
params.compact!

path_mappings.each do |src_dir_uri, dst_dir|
  warn "Downloading #{src_dir_uri}"
  warn("gsutil -q -m cp -r #{src_dir_uri} #{dst_dir.dirname}")
end

rewrite_gcnv_model_tars_list(params, path_mappings)

File.write(out_path, JSON.generate(params))
