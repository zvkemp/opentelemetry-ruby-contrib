# frozen_string_literal: true

# Copyright The OpenTelemetry Authors
#
# SPDX-License-Identifier: Apache-2.0

module OpenTelemetry
  module Instrumentation
    module System
      class Instrumentation < Base
        CPU_MODE = %i[
          idle
          interrupt
          iowait
          kernel
          nice
          steal
          system
          user
        ]

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
            instance.data_source.fetch_current.cpu_time_user
            instance.data_source.fetch_current.cpu_time_system
            # FIXME: attr { "cpu.mode": ['user', 'system', ...] }
            # FIXME: impl
            # ps: utime (user)
            # ps: time (user + system)
            # FIXME: need to emit multiple values here, and set attributes on them.
            0
            obs.observe(
              instance.data_source.fetch_current.cpu_time_user,
              'cpu.mode' => 'user'
            )
            obs.observe(
              instance.data_source.fetch_current.cpu_time_system,
              'cpu.mode' => 'system'
            )
          end

          # https://opentelemetry.io/docs/specs/semconv/system/process-metrics/#metric-processcpuutilization
          # FIXME: what's up with this unit
          observable_gauge('process.cpu.utilization', unit: '1') do
            # FIXME: attr { "cpu.mode": ['user', 'system', ...] }
            # FIXME: impl
            0
          end

          # https://opentelemetry.io/docs/specs/semconv/system/process-metrics/#metric-processmemoryusage
          observable_up_down_counter('process.memory.usage', unit: 'By') do
            # FIXME: impl
            0
          end

          # https://opentelemetry.io/docs/specs/semconv/system/process-metrics/#metric-processmemoryvirtual
          observable_up_down_counter('process.memory.virtual', unit: 'By') do
            # FIXME: implement me
            0
          end

          # https://opentelemetry.io/docs/specs/semconv/system/process-metrics/#metric-processdiskio
          observable_counter('process.disk.io', unit: 'By') do
            # FIXME: implement me
            0
          end

          # https://opentelemetry.io/docs/specs/semconv/system/process-metrics/#metric-processnetworkio
          observable_counter('process.network.io', unit: 'By') do
            # FIXME: implement me
            0
          end

          # https://opentelemetry.io/docs/specs/semconv/system/process-metrics/#metric-processthreadcount
          observable_up_down_counter('process.thread.count') { |obs| obs.observe(Thread.list.size) }

          # https://opentelemetry.io/docs/specs/semconv/system/process-metrics/#metric-processcontext_switches
          observable_counter('process.context_switches') do
            # FIXME: attribute process.context_switch_type
            0 # FIXME: implement me
          end

          # https://opentelemetry.io/docs/specs/semconv/system/process-metrics/#metric-processopen_file_descriptorcount
          observable_up_down_counter('process.open_file_descriptor.count') do |obs|
            # FIXME: this probably isn't the most efficient way, but it should be correct
            obs.observe(ObjectSpace.each_object(IO).count { |x| !x.closed? })
          end

          # https://opentelemetry.io/docs/specs/semconv/system/process-metrics/#metric-processpagingfaults
          observable_counter('process.paging.faults') do
            # FIXME: attribute process.paging.fault_type
            # FIXME: implement me
            0
          end

          # https://opentelemetry.io/docs/specs/semconv/system/process-metrics/#metric-processuptime
          observable_gauge('process.uptime', unit: 's') do
            # FIXME: implement
            0
          end

          # FIXME: upstream to semconv
          observable_counter('process.runtime.gc_count') { |obs| obs.observe(GC.count) }
        end

        install do |config|
          load_platform_data_source
          start_asynchronous_instruments(config)
        end

        present do
          defined?(OpenTelemetry::Metrics) && platform_supported?
        end

        attr_reader :data_source

        private

        # FIXME: it would be _nice_ to create an instrument group that pings `ps` or something once
        # and then reports collects all of the data from one output.
        # - can cache the output on the instance here with a TTL?

        def start_asynchronous_instruments(config)
          return unless config[:metrics]

          start_process_metrics_instruments if config[:process_metrics]
          start_system_metrics_instruments if config[:system_metrics]
        end

        def start_process_metrics_instruments
          # FIXME: allow configuration
          @instrument_configs.each_key do |type, name|
            next unless configured?(name)

            public_send(type, name) if name.start_with?('process.')
          end
        end

        def start_system_metrics_instruments
        end

        def configured?(metric_name)
          # FIXME: implement config-based switches for these
          true
        end

        def load_platform_data_source
          @data_source = platform_data_source_impl&.new
        end

        def platform_supported?
          !platform_data_source_impl.nil?
        end

        def platform_data_source_impl
          case RbConfig::CONFIG['host_os']
          when /darwin/
            DarwinPS
          when /linux/
            LinuxPS
          end
        end

        class PSData
          def self.parse(raw)
            output = raw.lines
            header = output.shift.strip.split(/\s+/)
            new(header.zip(output.first.strip.split(/\s+/)).to_h)
          end

          def initialize(parsed)
            @parsed = parsed
          end
        end

        class GenericPS
          TTL = 15 # FIXME: sensible default?

          attr_reader :cache

          def initialize(ttl: TTL)
            @ttl = ttl
            @cache = {}
            @mutex = Mutex.new
          end

          def fetch(pid)
            @mutex.synchronize do
              last_fetched_at, data = cache.fetch(pid) do
                return refresh(pid)
              end

              return data if last_fetched_at + @ttl > Time.now.to_i

              refresh(pid)
            end
          end

          def fetch_current
            fetch(Process.pid)
          end

          private

          def refresh(pid)
            data = parse_ps(pid)
            cache[pid] = [Time.now.to_i, data]
            data
          end

          def parse_ps(pid)
            data_class.parse(exec_shell_ps(pid))
          end

          def data_class
            PSData
          end

          def exec_shell_ps(_pid)
            raise 'not implemented'
          end
        end

        class DarwinPS < GenericPS
          private

          class Data < PSData
            def cpu_time_user
              parse_cpu_time(@parsed['UTIME'])
            end

            def cpu_time_system
              parse_cpu_time(@parsed['TIME']) - cpu_time_user
            end

            private

            def parse_cpu_time(str)
              components = str.split(':', 3)

              # FIXME: make this better
              if components.length == 2
                hours = 0
                minutes, seconds = components
              elsif components.length == 3
                hours, minutes, seconds = components
              end

              ((Integer(hours) * 60 * 60) + (Integer(minutes) * 60) + Float(seconds)).to_i
            end
          end

          def data_class
            Data
          end

          def exec_shell_ps(pid)
            `ps -p #{pid} -O utime,time`
          end
        end

        class LinuxPS < GenericPS
          # FIXME: impl
        end
      end
    end
  end
end
