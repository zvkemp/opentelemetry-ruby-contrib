# frozen_string_literal: true

# Copyright The OpenTelemetry Authors
#
# SPDX-License-Identifier: Apache-2.0

require 'bundler/setup'
Bundler.require(:default, :development, :test)

require 'minitest/autorun'
require 'minitest/reporters'
require 'rspec/mocks/minitest_integration'

Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new

EXPORTER = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
span_processor = OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(EXPORTER)

OpenTelemetry::SDK.configure do |c|
  c.error_handler = ->(exception:, message:) { raise(exception || message) }
  c.add_span_processor span_processor
end

module LoadedMetricsFeatures
  OTEL_METRICS_API_LOADED = !Gem.loaded_specs['opentelemetry-metrics-api'].nil?
  OTEL_METRICS_SDK_LOADED = !Gem.loaded_specs['opentelemetry-metrics-sdk'].nil?

  extend self

  def api_loaded?
    OTEL_METRICS_API_LOADED
  end

  def sdk_loaded?
    OTEL_METRICS_SDK_LOADED
  end
end

# NOTE: this isn't currently used, but it may be useful to fully reset state between tests
def reset_meter_provider
  return unless LoadedMetricsFeatures.sdk_loaded?

  resource = OpenTelemetry.meter_provider.resource
  OpenTelemetry.meter_provider = OpenTelemetry::SDK::Metrics::MeterProvider.new(resource: resource)
  OpenTelemetry.meter_provider.add_metric_reader(METRICS_EXPORTER)
end

def reset_metrics_exporter
  return unless LoadedMetricsFeatures.sdk_loaded?

  METRICS_EXPORTER.pull
  METRICS_EXPORTER.reset
end

if LoadedMetricsFeatures.sdk_loaded?
  METRICS_EXPORTER = OpenTelemetry::SDK::Metrics::Export::InMemoryMetricPullExporter.new
  OpenTelemetry.meter_provider.add_metric_reader(METRICS_EXPORTER)
end

module ConditionalEvaluation
  def self.included(base)
    base.extend(self)
  end

  def self.prepended(base)
    base.extend(self)
  end

  def with_metrics_sdk
    yield if LoadedMetricsFeatures.sdk_loaded?
  end

  def without_metrics_sdk
    yield unless LoadedMetricsFeatures.sdk_loaded?
  end

  def without_metrics_api
    yield unless LoadedMetricsFeatures.api_loaded?
  end

  def it(desc = 'anonymous', with_metrics_sdk: false, without_metrics_sdk: false, &block)
    return super(desc, &block) unless with_metrics_sdk || without_metrics_sdk

    raise ArgumentError, 'without_metrics_sdk and with_metrics_sdk must be mutually exclusive' if without_metrics_sdk && with_metrics_sdk

    return if with_metrics_sdk && !LoadedMetricsFeatures.sdk_loaded?
    return if without_metrics_sdk && LoadedMetricsFeatures.sdk_loaded?

    super(desc, &block)
  end
end

Minitest::Spec.prepend(ConditionalEvaluation)
