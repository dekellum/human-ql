# -*- ruby -*- encoding: utf-8 -*-

require 'rjack-tarpit/spec' if gem 'rjack-tarpit', '~> 2.1'

RJack::TarPit.specify do |s|
  require 'human-ql/base'
  s.version = HumanQL::VERSION
  s.add_developer( 'David Kellum', 'dek-oss@gravitext.com' )

  s.depend 'minitest', '~> 5.9.1', :dev
  s.depend 'rdoc',     '~> 4.3.0', :dev

  unless RUBY_PLATFORM =~ /java/
    # Testing
    s.depend 'sequel',    '~> 4.36',   :dev
    s.depend 'pg',        '~> 0.18.1', :dev
    s.depend 'sequel_pg', '~> 1.6.11', :dev
  end

  s.required_ruby_version = '>= 1.9.1'
  s.extra_rdoc_files |= %w[ README.rdoc History.rdoc ]
end
