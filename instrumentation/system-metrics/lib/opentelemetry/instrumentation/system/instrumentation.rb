# frozen_string_literal: true

# Copyright The OpenTelemetry Authors
#
# SPDX-License-Identifier: Apache-2.0

module OpenTelemetry
  module Instrumentation
    module System
      class Instrumentation < Base
        option :process_metrics, default: true, validate: :boolean
        option :system_metrics, default: false, validate: :boolean
        # an option called `metrics` must be set in order to use the SDK meter
        option :metrics, default: true, validate: :boolean

        compatible do
          # FIXME: implement this
          true
        end

        if defined?(OpenTelemetry::Metrics)
          # https://opentelemetry.io/docs/specs/semconv/system/process-metrics/#metric-processcputime
          observable_counter('process.cpu.time', unit: 's') do |obs|
            instance.maybe_observe(obs, 'cpu.mode' => 'user', &:cpu_time_user)
            instance.maybe_observe(obs, 'cpu.mode' => 'system', &:cpu_time_system)
          end

          # https://opentelemetry.io/docs/specs/semconv/system/process-metrics/#metric-processcpuutilization
          # FIXME: what's up with this unit
          observable_gauge('process.cpu.utilization', unit: '1', disabled: true) do
            # FIXME: attr { "cpu.mode": ['user', 'system', ...] }
            # FIXME: impl
          end

          # https://opentelemetry.io/docs/specs/semconv/system/process-metrics/#metric-processmemoryusage
          observable_up_down_counter('process.memory.usage', unit: 'By') do |obs|
            instance.maybe_observe(obs, &:process_memory_usage)
          end

          # https://opentelemetry.io/docs/specs/semconv/system/process-metrics/#metric-processmemoryvirtual
          observable_up_down_counter('process.memory.virtual', unit: 'By') do |obs|
            instance.maybe_observe(obs, &:process_memory_virtual)
          end

          # https://opentelemetry.io/docs/specs/semconv/system/process-metrics/#metric-processdiskio
          observable_counter('process.disk.io', unit: 'By', disabled: true) do
            # FIXME: implement me - unclear how to proceed on this one.
            # System-level metric would make more sense
          end

          # https://opentelemetry.io/docs/specs/semconv/system/process-metrics/#metric-processnetworkio
          observable_counter('process.network.io', unit: 'By', disabled: true) do
            # FIXME: implement me - unclear how to proceed on this one.
            # System-level metric would make more sense
          end

          # https://opentelemetry.io/docs/specs/semconv/system/process-metrics/#metric-processthreadcount
          observable_up_down_counter('process.thread.count') do |obs|
            # FIXME: should these be green threads or OS threads?
            obs.observe(Thread.list.size)
          end

          # https://opentelemetry.io/docs/specs/semconv/system/process-metrics/#metric-processcontext_switches
          observable_counter('process.context_switches') do |obs|
            instance.maybe_observe(obs, 'process.context_switch_type' => 'voluntary', &:voluntary_context_switches)
            instance.maybe_observe(obs, 'process.context_switch_type' => 'involuntary', &:involuntary_context_switches)
          end

          # https://opentelemetry.io/docs/specs/semconv/system/process-metrics/#metric-processopen_file_descriptorcount
          observable_up_down_counter('process.open_file_descriptor.count') do |obs|
            # TODO: may not be the most efficient way, but it should be correct
            obs.observe(ObjectSpace.each_object(IO).count { |x| !x.closed? })
          end

          # https://opentelemetry.io/docs/specs/semconv/system/process-metrics/#metric-processpagingfaults
          observable_counter('process.paging.faults') do |obs|
            instance.maybe_observe(obs, 'process.paging.fault_type' => 'major', &:page_faults_major)
            instance.maybe_observe(obs, 'process.paging.fault_type' => 'minor', &:page_faults_minor)
          end

          # https://opentelemetry.io/docs/specs/semconv/system/process-metrics/#metric-processuptime
          observable_gauge('process.uptime', unit: 's') do |obs|
            instance.maybe_observe(obs, &:process_uptime)
          end

          # FIXME: upstream to semconv
          observable_counter('process.runtime.gc_count') { |obs| obs.observe(GC.count) }
        end

        install do |config|
          load_platform
          start_asynchronous_instruments(config)
        end

        present do
          defined?(OpenTelemetry::Metrics) && platform_supported?
        end

        attr_reader :platform

        def maybe_observe(observations, attributes = {})
          if (value = yield(self))
            observations.observe(value, attributes)
          end
        end

        def cpu_time_system
          current_data.cpu_time_system
        end

        def cpu_time_user
          current_data.cpu_time_user
        end

        def process_memory_usage
          current_data.process_memory_usage
        end

        def process_memory_virtual
          current_data.process_memory_virtual
        end

        def voluntary_context_switches
          current_data.voluntary_context_switches
        end

        def involuntary_context_switches
          current_data.involuntary_context_switches
        end

        def page_faults_minor
          current_data.page_faults_minor
        end

        def page_faults_major
          current_data.page_faults_major
        end

        def process_uptime
          current_data.process_uptime
        end

        private

        def current_data
          platform.fetch_current
        end

        def start_asynchronous_instruments(config)
          return unless config[:metrics]

          start_namespaced_instruments('process.') if config[:process_metrics]
          start_namespaced_instruments('system.') if config[:system_metrics]
        end

        def start_namespaced_instruments(namespace)
          @instrument_configs.each do |(type, name), instrument_config|
            next unless name.start_with?(namespace)

            # NOTE: this key exists on the config to allow for semconv-defined
            # instruments that are unimplemented here.
            next if instrument_config[:disabled]
            next unless configured?(name)

            # instantiate the async instrument
            public_send(type, name)
          end
        end

        def configured?(metric_name)
          true
        end

        def load_platform
          @platform = Platform.impl&.new
        end

        def platform_supported?
          !Platform.impl.nil?
        end
      end
    end
  end
end
