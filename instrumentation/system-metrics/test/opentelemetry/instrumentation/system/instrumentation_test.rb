# frozen_string_literal: true

# Copyright The OpenTelemetry Authors
#
# SPDX-License-Identifier: Apache-2.0

require 'test_helper'
require_relative '../../../../lib/opentelemetry/instrumentation/system'

describe OpenTelemetry::Instrumentation::System::Instrumentation do
  let(:instrumentation) { OpenTelemetry::Instrumentation::System::Instrumentation.instance }
  let(:config) { {} }

  it 'has #name' do
    _(instrumentation.name).must_equal 'OpenTelemetry::Instrumentation::System'
  end

  before do
    with_metrics_sdk { METRICS_EXPORTER.reset }
    instrumentation.install(config)
  end

  after do
    instrumentation.instance_variable_set(:@installed, false)
  end

  without_metrics_api do
    describe 'without metrics api' do
      it 'works' do
        _(true).must_equal true
      end
    end
  end

  without_metrics_sdk do
    describe 'without metrics sdk' do
      it 'works' do
        _(true).must_equal true
      end
    end
  end

  with_metrics_sdk do
    describe 'with metrics sdk' do
      it 'works' do
        GC.start

        METRICS_EXPORTER.pull
        snapshots1 = METRICS_EXPORTER.metric_snapshots

        METRICS_EXPORTER.reset
        METRICS_EXPORTER.pull
        snapshots2 = METRICS_EXPORTER.metric_snapshots

        gc_count = snapshots.fetch('process.runtime.gc_count')

        _(gc_count.length).must_equal(1)
        _(gc_count[0].data_points.length).must_equal(1)
        _(gc_count[0].data_points[0].value).must_be :>, 0

        thread_count = snapshots.fetch('process.thread.count')

        _(thread_count.length).must_equal(1)
        _(thread_count[0].data_points.length).must_equal(1)
        _(thread_count[0].data_points[0].value).must_be :>, 0

        fd_count = snapshots.fetch('process.open_file_descriptor.count')
        _(fd_count.length).must_equal(1)
        _(fd_count[0].data_points.length).must_equal(1)
        _(fd_count[0].data_points[0].value).must_be :>, 0

        0
      end
    end
  end
end
