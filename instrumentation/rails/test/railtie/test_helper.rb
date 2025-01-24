# frozen_string_literal: true

# Copyright The OpenTelemetry Authors
#
# SPDX-License-Identifier: Apache-2.0

# Configure Rails Environment
ENV['RACK_ENV'] = 'test'
ENV['RAILS_ENV'] = 'test'

require 'logger'

require 'simplecov'
SimpleCov.command_name(:railtie_tests) # custom name required to merge with the 'instrumentation' tests
SimpleCov.start

require 'bundler/setup'
Bundler.require(:default, :development, :test)

require_relative '../../test/railtie/dummy/config/environment'
require 'rails/test_help'
