# -*- ruby -*-

require 'rubygems'
require 'bundler/setup'
require 'rjack-tarpit'

RJack::TarPit.new( 'human-ql' ).define_tasks

desc "Upload RDOC to Amazon S3 (rdoc.gravitext.com/human-ql, Oregon)"
task :publish_rdoc => [ :clean, :rerdoc ] do
  sh <<-SH
    aws s3 sync --acl public-read doc/ s3://rdoc.gravitext.com/human-ql/
  SH
end
