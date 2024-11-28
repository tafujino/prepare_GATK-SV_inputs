# frozen_string_literal: true

require 'csv'
require 'fileutils'
require 'optparse'
require 'pathname'

require_relative 'gcp'

REPO_DIR = Pathname.new('gatk-sv-cohort')
TERRA_TABLE_DIR = REPO_DIR / 'inputs/build/ref_panel_1kg/terra'

# @param version [String, nil]
def clone_repo_and_switch(version = nil)
  if File.exist?(REPO_DIR)
    warn "Directory '#{REPO_DIR}' already exists. Skip downloading."
  else
    ret = system "git clone https://github.com/broadinstitute/gatk-sv.git #{REPO_DIR}"
    unless ret
      warn 'Failed to clone gatk-sv repository'
      exit 1
    end
  end

  return unless version

  warn "Switch to '#{version}'"
  Dir.chdir(REPO_DIR) do
    ret = system "git switch --detach #{version}"
    unless ret
      warn "Failed to checkout the specified version: #{version}"
      exit 1
    end
  end
end

# @param in_path [Pathname]
# @param out_path [Pathname]
# @param download_dir [Pathname]
# @param no_clobber [Boolean]
def rewrite_workspace_tsv_and_download_files(in_path, out_path, download_dir, no_clobber:)
  rows = CSV.read(in_path, col_sep: "\t")
  unless rows.length == 2
    warn '# of rows should be two'
    exit 1
  end
  header_row, value_row = rows
  value_row.map! do |v|
    next v unless v =~ %r{^gs://}

    download_gcp_file(v, download_dir, inspect_secondary_file: true, no_clobber:)
  end
  CSV.open(out_path, 'w', col_sep: "\t") do |tsv|
    tsv << header_row
    tsv << value_row
  end
end

opt = OptionParser.new
no_clobber = false
opt.on('-n', '--no-clobbber') { no_clobber = true }
opt.parse!(ARGV)
opt.banner = "Usage: #{$PROGRAM_NAME} TABLE_DIR DOWNLOAD_DIR [VERSION] [options]"

if ARGV.length < 2
  puts opt.banner
  exit 1
end

table_dir = Pathname.new(ARGV.shift)
download_dir = Pathname.new(ARGV.shift)
version = ARGV.shift unless ARGV.empty?

clone_repo_and_switch(version)

warn 'Building Terra cohort mode workspace inputs'
Dir.chdir(REPO_DIR) do
  values_dir = Pathname.pwd / 'inputs/values'
  template_path = Pathname.pwd / 'inputs/templates/terra_workspaces/cohort_mode'
  out_dir = Pathname.pwd / 'inputs/build/ref_panel_1kg/terra'
  system <<~CMD
    scripts/inputs/build_inputs.py #{values_dir} #{template_path} #{out_dir} -a '{ "test_batch" : "ref_panel_1kg" }'
  CMD
end

warn 'Copying Terra tables and download the files on the Workspace Data table from the cloud'
FileUtils.mkpath(download_dir)
FileUtils.mkpath(table_dir)
Dir.glob(TERRA_TABLE_DIR / '*.tsv').each do |in_path|
  in_path = Pathname.new(in_path)
  out_path = table_dir / in_path.basename
  warn "Processing #{in_path.basename} ..."
  if in_path.basename.to_s == 'workspace.tsv'
    rewrite_workspace_tsv_and_download_files(in_path, out_path, download_dir, no_clobber:)
  else
    FileUtils.cp(in_path, out_path)
  end
end

warn 'Copying the workflow configuration JSONs'
FileUtils.mkpath(table_dir / 'workflow_configurations')
Dir.glob(TERRA_TABLE_DIR / 'workflow_configurations/*.json') do |json_path|
  FileUtils.cp(json_path, table_dir / 'workflow_configurations')
end
