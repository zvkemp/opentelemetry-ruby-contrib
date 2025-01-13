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
    with_metrics_sdk do
      reset_meter_provider
      METRICS_EXPORTER.reset
    end

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
        snapshots = METRICS_EXPORTER.metric_snapshots.group_by(&:name)

        gc_count = snapshots.delete('process.runtime.gc_count')
        _(gc_count.length).must_equal(1)
        _(gc_count[0].data_points.length).must_equal(1)
        _(gc_count[0].data_points[0].value).must_be :>, 0

        thread_count = snapshots.delete('process.thread.count')
        _(thread_count.length).must_equal(1)
        _(thread_count[0].data_points.length).must_equal(1)
        _(thread_count[0].data_points[0].value).must_be :>, 0

        fd_count = snapshots.delete('process.open_file_descriptor.count')
        _(fd_count.length).must_equal(1)
        _(fd_count[0].data_points.length).must_equal(1)
        _(fd_count[0].data_points[0].value).must_be :>, 0

        cpu_time = snapshots.delete('process.cpu.time')
        _(cpu_time.length).must_equal(1)
        _(cpu_time[0].data_points.length).must_equal(2)
        _(cpu_time[0].data_points[0].value).must_be :>=, 0
        _(cpu_time[0].data_points[1].value).must_be :>=, 0
        _(cpu_time[0].data_points.map { |d| d.attributes['cpu.mode'] }.sort).must_equal(%w[system user])

        memory_usage = snapshots.delete('process.memory.usage')
        _(memory_usage.length).must_equal(1)
        _(memory_usage[0].data_points.length).must_equal(1)
        _(memory_usage[0].data_points[0].value).must_be :>, 0

        memory_virtual = snapshots.delete('process.memory.virtual')
        _(memory_virtual.length).must_equal(1)
        _(memory_virtual[0].data_points.length).must_equal(1)
        _(memory_virtual[0].data_points[0].value).must_be :>, 0

        context_switches = snapshots.delete('process.context_switches')
        _(context_switches.length).must_equal(1)

        if linux?
          _(context_switches[0].data_points.length).must_equal(2)
          # _(context_switches[0].data_points[0].value).must_be :>, 0
        end

        paging_faults = snapshots.delete('process.paging.faults')
        _(paging_faults.length).must_equal(1)

        if linux?
          _(paging_faults[0].data_points.length).must_equal(2)
          # _(paging_faults[0].data_points[0].value).must_be :>, 0
        end

        process_uptime = snapshots.delete('process.uptime')
        _(process_uptime.length).must_equal(1)
        _(process_uptime[0].data_points.length).must_equal(1)
        _(process_uptime[0].data_points[0].value).must_be :>, 0

        _(snapshots.keys).must_be_empty # exhaustive
      end
    end
  end
end
