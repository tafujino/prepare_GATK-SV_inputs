# frozen_string_literal: true

WORKFLOW_INPUT_JSON_PATH = 'inputs.json'
SAMPLE_TSV_PATH = 'sample.tsv'
WORKSPACE_DATA_TSV_PATH = 'GATK-Structural-Variants-Single-Sample-workspace-attributes.tsv'

require 'csv'
require_relative 'workflow_input_parser'

task 'parse' do
  pp WorkflowInputParser.run(WORKFLOW_INPUT_JSON_PATH)
end
