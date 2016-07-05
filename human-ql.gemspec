# -*- ruby -*- encoding: utf-8 -*-

require 'rjack-tarpit/spec' if gem 'rjack-tarpit', '~> 2.1'

RJack::TarPit.specify do |s|
  require 'human-ql/base'
  s.version = HumanQL::VERSION
  s.add_developer( 'David Kellum', 'dek-oss@gravitext.com' )

  s.depend 'minitest', '~> 5.8.4', :dev
end
