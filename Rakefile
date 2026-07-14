# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:test)

task :default => :test

desc "Run end-to-end self-test specs"
task :e2e do
  sh "bundle exec rspec spec/e2e/"
end
