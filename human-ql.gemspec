# -*- ruby -*- encoding: utf-8 -*-

require File.expand_path("../lib/human-ql/base", __FILE__)

Gem::Specification.new do |s|
  s.name = 'human-ql'
  s.version = HumanQL::VERSION
  s.author = 'David Kellum'
  s.email  = 'dek-oss@gravitext.com'

  s.summary = "Human Query Language for full text search engines."
  s.description = <<-TEXT
  Human Query Language for full text search engines. Provides a lenient parser
  and associated tools for a self-contained and search-engine agnostic query
  language suitable for use by end users. Lenient in that is will produce a
  parse tree for any input, given a default operator and by generally ignoring
  any unparsable syntax. Suitable for use by end users in that it supports
  potentially several operator variants and a query language not unlike some
  major web search and other commercial search engines.
  TEXT

  s.files = File.readlines(File.expand_path('../Manifest.txt', __FILE__)).
              map(&:strip)

  s.add_development_dependency 'minitest', '~> 5.14.1'

  unless RUBY_PLATFORM =~ /java/
    # Testing
    s.add_development_dependency 'sequel',    '~> 5.41'
    s.add_development_dependency 'pg',        '~> 1.2.1'
    s.add_development_dependency 'sequel_pg', '~> 1.14'
  end

  s.required_ruby_version = '>= 1.9.1'

  s.extra_rdoc_files |= %w[ README.rdoc History.rdoc ]
  s.rdoc_options = ["--main", "README.rdoc"]
end
