# -*- ruby -*-

require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList['test/**/test_*.rb']
end

task :default => :test

task(:tag).clear

desc "Tag for release"
task :tag do
  t = Time.now.utc.strftime('%Y%m%dT%H%M%SZ')
  tag = "human-ql-#{t}"
  sh "git tag -s #{tag} -m 'release #{tag} to rubygems.org'"
end

desc "Upload RDOC to Amazon S3 (rdoc.gravitext.com/human-ql, Oregon)"
task :publish_rdoc => [:clean, :rdoc] do
  sh <<-SH
    aws s3 sync --acl public-read doc/ s3://rdoc.gravitext.com/human-ql/
  SH
end

require 'rdoc/task'

RDoc::Task.new :rdoc do |rdoc|
  rdoc.main = "README.doc"
  rdoc.rdoc_files.include("README.rdoc", "lib/*.rb")
end

task :rdoc do
  sh <<-SH
    rm -rf doc/fonts
    cp rdoc_css/*.css doc/css/
  SH
end
