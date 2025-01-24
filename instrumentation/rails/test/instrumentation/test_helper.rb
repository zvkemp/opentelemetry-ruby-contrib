# frozen_string_literal: true

# Copyright The OpenTelemetry Authors
#
# SPDX-License-Identifier: Apache-2.0

require 'logger'

require 'simplecov'
SimpleCov.command_name(:instrumentation_tests) # custom name required to merge with the 'railtie' tests
SimpleCov.start

require 'bundler/setup'
Bundler.require(:default, :development, :test)

require 'minitest/autorun'
require 'rack/test'
require 'test_helpers/app_config'

require 'opentelemetry-instrumentation-rails'

# Global opentelemetry-sdk setup
EXPORTER = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
span_processor = OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(EXPORTER)

OpenTelemetry::SDK.configure do |c|
  c.error_handler = ->(exception:, message:) { raise(exception || message) }
  c.logger = Logger.new($stderr, level: ENV.fetch('OTEL_LOG_LEVEL', 'fatal').to_sym)
  c.use_all
  c.add_span_processor span_processor
end
