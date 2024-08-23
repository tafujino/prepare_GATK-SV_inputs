# frozen_string_literal: true

require 'json'
require_relative 'table_parser'

version = ARGV.shift

INPUT_PARAM_FILES = {
  'dockers' => 'dockers.json',
  'ref_panel' => 'ref_panel_1kg.json',
  'reference_resources' => 'resources_hg38.json'
}.freeze

# @param version [String, nil]
# @return [String]
def clone_repo_and_switch(version)
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

pp inputs
