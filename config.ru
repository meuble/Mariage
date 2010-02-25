require 'rubygems'
require 'vendor/sinatra/lib/sinatra.rb'
require 'vendor/sequel/lib/sequel.rb'

Sinatra::Application.default_options.merge!(
  :run => false,
  :env => :production
)

require 'mariage_claire_et_michel.rb'
run Sinatra.application