# frozen_string_literal: true

require 'optparse'
require 'pathname'

REPO_DIR = 'gatk-sv-cohort'

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

opt = OptionParser.new
no_clobber = false
opt.on('-n') { no_clobber = true }
opt.parse!(ARGV)
# data_dir = Pathname.new(ARGV.shift || '.')
version = ARGV.shift

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
