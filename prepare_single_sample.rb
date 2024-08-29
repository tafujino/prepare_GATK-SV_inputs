# frozen_string_literal: true

require 'json'
require 'optparse'
require 'pathname'

INPUT_PARAM_FILES = {
  'dockers' => 'dockers.json',
  'ref_panel' => 'ref_panel_1kg.json',
  'reference_resources' => 'resources_hg38.json'
}.freeze

# @param version [String, nil]
# @return [String]
def clone_repo_and_switch(version = nil)
  repo_name = "gatk-sv-#{version || 'latest'}-local"

  if File.exist?(repo_name)
    warn "Directory '#{repo_name}' already exists. Skip downloading."
  else
    ret = system "git clone https://github.com/broadinstitute/gatk-sv.git #{repo_name}"
    unless ret
      warn 'Failed to clone gatk-sv repository'
      exit 1
    end
  end

  if version
    warn "Switch to '#{version}'"
    Dir.chdir(repo_name) do
      ret = system "git switch --detach #{version}"
      unless ret
        warn "Failed to checkout the specified version: #{version}"
        exit 1
      end
    end
  end
  repo_name
end

# @param str [String]
# @param dict [Hash{ String => Hash{ String => String }}] namespace -> varname -> value
# @return [String, nil]
def substitute_variable(str, dict)
  if str =~ /^([^.\s]+)\.([^.\s]+)$/
    namespace = Regexp.last_match(1)
    varname = Regexp.last_match(2)
    unless dict.key?(namespace)
      warn "Failed to find namespace '#{namespace}'"
      return nil
    end
    unless dict[namespace].key?(varname)
      warn "Failed to find variable '#{varname}' in namespace '#{namespace}'"
      return nil
    end
    dict[namespace][varname]
  else
    warn "Failed to parse key '#{str}'"
    exit 1
  end
end

# Imitates Jinja engine in a very crude manner
# @param str [String]
# @param dict [Hash{ String => Hash{ String => String }}] namespace -> varname -> value
def eval_jinja_placeholders(str, dict)
  # substitute {{ ... }} or {{ ... | tojson }}
  str.gsub(/{{\s*(\S+)\s*(\|\s*tojson\s*)?}}/) do
    substitute_variable(Regexp.last_match(1), dict)
  end
end

# @param str [String]
# @param dict [Hash{ String => Hash{ String => String }}] namespace -> varname -> value
def eval_one_wdl_placeholder(str, dict)
  # substitute "${ ... }$"
  if str =~ /\${\s*(\S+)\s*}/
    substitute_variable(Regexp.last_match(1), dict)
  else
    str
  end
end

# @param path [String]
# @param dict [Hash{ String => Hash{ String => String }}] namespace -> varname -> value
# @return [Hash{ String => String }]
def build_workspace_table(path, dict)
  template = File.read(path)
  evaluated = eval_jinja_placeholders(template, dict)
  rows = CSV.parse(evaluated, col_sep: "\t")
  # The first key contains a table name and removes it
  k, v = rows.shift
  k.gsub!(/^\w+:(\w+)$/, '\1')
  rows.unshift([k, v])
  rows.to_h
end

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
        'gcloud',
        'storage',
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
  file_list.map! do |path|
    next path unless path =~ %r{^gs://}

    download_gcp_file(path, data_dir, inspect_secondary_file: true, no_clobber: no_clobber)
  end
  File.open(file_list_path, 'w') do |f|
    file_list.each { |path| f.puts path }
  end
end

opt = OptionParser.new
no_clobber = false
opt.on('-n') { no_clobber = true }
opt.parse!(ARGV)
data_dir = Pathname.new(ARGV.shift || '.')
version = ARGV.shift

repo_name = clone_repo_and_switch(version)

input_params = INPUT_PARAM_FILES.transform_values do |filename|
  JSON.parse(File.read("#{repo_name}/inputs/values/#{filename}"))
end

workspace = build_workspace_table(
  "#{repo_name}/inputs/templates/terra_workspaces/single_sample/workspace.tsv.tmpl",
  input_params
)

single_sample_template = File.read("#{repo_name}/inputs/templates/terra_workspaces/single_sample/GATKSVPipelineSingleSample.no_melt.json.tmpl", chomp: true)
inputs_str = eval_jinja_placeholders(single_sample_template, input_params)

input_params['workspace'] = workspace
inputs = JSON.parse(inputs_str)
inputs = inputs.map.to_h do |k, v|
  v = eval_one_wdl_placeholder(v, input_params) if v.is_a?(String)
  [k, v]
end
inputs.compact!

inputs.transform_values! do |v|
  if v.is_a?(String) && v =~ %r{^gs://}
    download_gcp_file(v, data_dir, inspect_secondary_file: true, no_clobber: no_clobber)
  else
    v
  end
end

%w[
  gcnv_model_tars_list
  ref_pesr_disc_files_list
  ref_pesr_sd_files_list
  ref_pesr_split_files_list
].each do |key|
  rewrite_file_list(inputs, data_dir, "GATKSVPipelineSingleSample.#{key}", no_clobber: no_clobber)
end

File.write('inputs.template.json', JSON.pretty_generate(inputs))
