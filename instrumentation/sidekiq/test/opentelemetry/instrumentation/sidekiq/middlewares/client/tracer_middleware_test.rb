# frozen_string_literal: true

# Copyright The OpenTelemetry Authors
#
# SPDX-License-Identifier: Apache-2.0

require 'test_helper'
require_relative '../../../../../../lib/opentelemetry/instrumentation/sidekiq'
require_relative '../../../../../../lib/opentelemetry/instrumentation/sidekiq/middlewares/client/tracer_middleware'

describe OpenTelemetry::Instrumentation::Sidekiq::Middlewares::Client::TracerMiddleware do
  let(:instrumentation) { OpenTelemetry::Instrumentation::Sidekiq::Instrumentation.instance }
  let(:exporter) { EXPORTER }
  let(:spans) { exporter.finished_spans }
  let(:enqueue_span) { spans.first }
  let(:config) { {} }

  with_metrics_sdk do
    let(:metric_snapshots) do
      metrics_exporter.tap(&:pull)
                      .metric_snapshots.select { |snapshot| snapshot.data_points.any? }
                      .group_by(&:name)
    end
  end

  before do
    instrumentation.install(config)
    exporter.reset
  end

  after do
    instrumentation.instance_variable_set(:@installed, false)
    Sidekiq::Worker.drain_all
  end

  describe 'process spans' do
    it 'before performing any jobs' do
      _(exporter.finished_spans.size).must_equal 0
    end

    it 'traces enqueing' do
      job_id = SimpleJob.perform_async

      _(exporter.finished_spans.size).must_equal 1

      _(enqueue_span.name).must_equal 'default publish'
      _(enqueue_span.kind).must_equal :producer
      _(enqueue_span.parent_span_id).must_equal OpenTelemetry::Trace::INVALID_SPAN_ID
      _(enqueue_span.attributes['messaging.system']).must_equal 'sidekiq'
      _(enqueue_span.attributes['messaging.sidekiq.job_class']).must_equal 'SimpleJob'
      _(enqueue_span.attributes['messaging.message_id']).must_equal job_id
      _(enqueue_span.attributes['messaging.destination']).must_equal 'default'
      _(enqueue_span.attributes['messaging.destination_kind']).must_equal 'queue'
      _(enqueue_span.events.size).must_equal(1)
      _(enqueue_span.events[0].name).must_equal('created_at')
    end

    it 'traces when enqueued with Active Job' do
      SimpleJobWithActiveJob.perform_later(1, 2)
      _(enqueue_span.name).must_equal('default publish')
      _(enqueue_span.attributes['messaging.system']).must_equal('sidekiq')
      _(enqueue_span.attributes['messaging.sidekiq.job_class']).must_equal('SimpleJobWithActiveJob')
      _(enqueue_span.attributes['messaging.destination']).must_equal('default')
      _(enqueue_span.attributes['messaging.destination_kind']).must_equal('queue')
    end

    describe 'when span_naming is job_class' do
      let(:config) { { span_naming: :job_class } }

      it 'uses the job class name for the span name' do
        SimpleJob.perform_async

        _(enqueue_span.name).must_equal('SimpleJob publish')
      end

      it 'uses the job class name when enqueued with Active Job' do
        SimpleJobWithActiveJob.perform_later(1, 2)
        _(enqueue_span.name).must_equal('SimpleJobWithActiveJob publish')
      end
    end

    describe 'when peer_service config is set' do
      let(:config) { { peer_service: 'MySidekiqService' } }

      it 'after performing a simple job' do
        SimpleJob.perform_async
        SimpleJob.drain

        _(enqueue_span.attributes['peer.service']).must_equal 'MySidekiqService'
      end
    end

    with_metrics_sdk do
      it 'yields no metrics if config is not set' do
        _(instrumentation.metrics_enabled?).must_equal false
        SimpleJob.perform_async
        SimpleJob.drain

        _(metric_snapshots).must_be_empty
      end

      describe 'with metrics enabled' do
        let(:config) { { metrics: true } }

        it 'metrics processing' do
          _(instrumentation.metrics_enabled?).must_equal true
          SimpleJob.perform_async
          SimpleJob.drain

          sent_messages = metric_snapshots['messaging.client.sent.messages']
          _(sent_messages.count).must_equal 1
          _(sent_messages.first.data_points.count).must_equal 1
          _(sent_messages.first.data_points.first.value).must_equal 1
          sent_messages_attributes = sent_messages.first.data_points.first.attributes
          _(sent_messages_attributes['messaging.system']).must_equal 'sidekiq'
          _(sent_messages_attributes['messaging.destination.name']).must_equal 'default' # FIXME: newer semconv specifies this key
          _(sent_messages_attributes['messaging.operation.name']).must_equal 'create'
        end
      end
    end
  end
end
