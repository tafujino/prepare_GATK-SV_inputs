# frozen_string_literal: true

require 'optparse'
require 'pathname'
require 'fileutils'
require 'yaml'
require_relative 'workflow_input_parser'
require_relative 'table_parser'

# @param src_primary_uri        [String]
# @param data_dir               [Pathname]
# @param inspect_secondary_file [Boolean]
# @param no_clobber             [Boolean]
# @return                       [Pathname] path of the destination primary file
def download_gcp_file(src_primary_uri, data_dir, inspect_secondary_file: false, no_clobber: false)
  src_uris = [src_primary_uri]
  if inspect_secondary_file
    case src_primary_uri
    when /\.bed\.gz$/, /\.vcf\.gz$/
      src_uris << "#{src_primary_uri}.tbi"
    when /\.bed$/, /\.vcf$/
      src_uris << "#{src_primary_uri}.idx"
    when /\.fa$/, /\.fa\.gz$/, /\.fasta$/, /\.fasta\.gz$/
      src_uris << "#{src_primary_uri}.fai"
    when /\.bam$/
      src_uris << "#{src_primary_uri}.bai"
    when /\.cram$/
      src_uris << "#{src_primary_uri}.crai"
    end
  end
  path_mappings = src_uris.map do |src_uri|
    src_uri =~ %r{^gs://(.+)$}
    dst_path = data_dir / Regexp.last_match(1)
    FileUtils.mkpath dst_path.dirname
    unless no_clobber && dst_path.exist?
      warn "Downloading #{src_uri}"
      download_cmd = [
        'gsutil',
        '-q',
        '-m',
        'cp',
        '-r',
        no_clobber ? '-n' : nil,
        src_uri,
        dst_path.dirname
      ].compact.join(' ')
      system download_cmd
    end
    dst_path
  end
  path_mappings.first
end

# @param params     [Hash{ String => Object }]
# @param data_dir   [Pathname]
# @param key        [String]
# @param no_clobber [Boolean]
def rewrite_file_list(params, data_dir, key, no_clobber: false)
  file_list_path = params[key]
  file_list = File.readlines(file_list_path, chomp: true)
  file_list.map! do |src_uri|
    download_gcp_file(src_uri, data_dir, inspect_secondary_file: true, no_clobber:)
  end
  File.open(file_list_path, 'w') do |f|
    file_list.each { |path| f.puts path }
  end
end

opt = OptionParser.new
no_clobber = false
opt.on('-n') { no_clobber = true }
opt.parse!(ARGV)

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
data_dir = base_dir / 'data'
params = WorkflowInputParser.run(workflow_inputs_json_path)
workspace_data = TableParser.run(workspace_data_tsv_path)
sample = { 'sample_id' => sample_name,
           'bam_or_cram_file' => sample_cram_path,
           'requester_pays_cram' => false }

src_uris = []
params.transform_values! do |v|
  next v unless v.is_a?(DataPointer)

  case v.table_name
  when 'workspace'
    v0 = workspace_data[v.key]
    next v0 unless v0.is_a?(String)
    next v0 unless v0 =~ %r{^gs://(.+)$}

    src_path = Regexp.last_match(1)
    dst_path = data_dir / src_path
    src_uri = v0
    src_uris << src_uri
    dst_path
  when 'this'
    sample[v.key]
  else
    warn "Invalid table: #{v.table_name}"
    exit 1
  end
end
params.compact!

src_uris.each do |src_uri|
  download_gcp_file(src_uri, data_dir, inspect_secondary_file: true, no_clobber:)
end

%w[
  gcnv_model_tars_list
  ref_pesr_disc_files_list
  ref_pesr_sd_files_list
  ref_pesr_split_files_list
].each do |key|
  rewrite_file_list(params, data_dir, "GATKSVPipelineSingleSample.#{key}", no_clobber:)
end

File.write(out_path, JSON.generate(params))
