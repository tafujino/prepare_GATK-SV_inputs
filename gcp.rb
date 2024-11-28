# frozen_string_literal: true

require 'fileutils'
require 'pathname'

# @param src_primary_uri        [String]
# @param data_dir               [Pathname]
# @param inspect_secondary_file [Boolean]
# @param no_clobber             [Boolean]
# @return                       [Pathname] path of the destination primary file
def download_gcp_file(src_primary_uri, data_dir, inspect_secondary_file: false, no_clobber: false)
  src_uris = [src_primary_uri]
  if inspect_secondary_file
    case src_primary_uri
    when /\.bed\.gz$/, /\.vcf\.gz$/, /\.txt\.gz$/
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
