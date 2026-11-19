#!/usr/bin/env ruby
# examples/memory/00_run_all_demos.rb
# frozen_string_literal: true
#
# Runs every example in this directory through the shared runner.

exec(RbConfig.ruby, File.expand_path('../run_all.rb', __dir__), 'memory')
