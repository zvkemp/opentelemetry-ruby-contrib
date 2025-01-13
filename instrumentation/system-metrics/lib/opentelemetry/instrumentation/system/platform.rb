# frozen_string_literal: true

# Copyright The OpenTelemetry Authors
#
# SPDX-License-Identifier: Apache-2.0

module OpenTelemetry
  module Instrumentation
    module System
      module Platform
        def self.impl
          case RbConfig::CONFIG['host_os']
          when /darwin/
            Darwin::Platform
          when /linux/
            Linux::Platform
          end
        end

        class AbstractPlatform
          attr_reader :data_source

          def fetch_current
            data_source.fetch_current
          end
        end

        class AbstractDataSource
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
            data_class.parse(fetch_raw_data(pid))
          end

          def data_class
            PSData
          end

          def fetch_raw_data(_pid)
            ''
          end
        end

        class AbstractData
          def self.parse(_raw)
            new({})
          end

          def initialize(parsed)
            @data = parsed
          end

          attr_reader :data

          def cpu_time_user; end
          def cpu_time_system; end
          def process_memory_usage; end
          def process_memory_virtual; end
          def voluntary_context_switches; end
          def involuntary_context_switches; end
          def page_faults_major; end
          def page_faults_minor; end
          def process_uptime; end
        end

        module Darwin
          class Platform < AbstractPlatform
            def initialize
              @data_source = PSDataSource.new
              super
            end
          end

          class PSDataSource < AbstractDataSource
            private

            def data_class
              PSData
            end

            def fetch_raw_data(pid)
              `ps -p #{pid} -O utime,time,rss,vsz,nvcsw,nivcsw,majflt,etime`
            end
          end

          class PSData < AbstractData
            def self.parse(raw)
              output = raw.lines
              header = output.shift.strip.split(/\s+/)
              new(header.zip(output.first.strip.split(/\s+/)).reject { |_, v| v == '-' }.to_h)
            end

            def cpu_time_user
              return unless (raw_utime = data['UTIME'])

              parse_ps_time(raw_utime).to_i
            end

            def cpu_time_system
              return unless (utime = cpu_time_user) && (raw_time = data['TIME'])

              parse_ps_time(raw_time).to_i - utime
            end

            def process_memory_usage
              data['RSS']&.to_i
            end

            def process_memory_virtual
              data['VSZ']&.to_i
            end

            # FIXME: on at least one macos version/architecture, these are all blank
            def voluntary_context_switches
              data['NVCSW']
            end

            # FIXME: on at least one macos version/architecture, these are all blank
            def involuntary_context_switches
              data['NIVCSW']
            end

            # FIXME: on at least one macos version/architecture, these are all blank
            def page_faults_major
              data['MAJFLT']
            end

            # Instrumentations SHOULD use a gauge with type double and measure uptime in seconds as a
            # floating point number with the highest precision available
            def process_uptime
              return unless (raw_etime = data['ELAPSED']) # aka 'etime'

              parse_ps_time(raw_etime)
            end

            private

            def parse_ps_time(str)
              time, days = str.split('-', 2).reverse
              days = days ? days.to_i : 0

              seconds, minutes, hours = time.split(':', 3).reverse

              (
                (Integer(days || 0) * 86_400) \
               + (Integer(hours || 0) * 3600) \
               + (Integer(minutes || 0) * 60) \
               + Float(seconds)
              )
            end
          end
        end

        module Linux
          def self.clock_tick
            # should be safe not to mutex this
            @clock_tick ||= begin
              require 'etc'
              Etc.sysconf(Etc::SC_CLK_TCK)
            end
          end

          class Platform < AbstractPlatform
            def initialize
              @data_source = ProcCompoundDataSource.new
            end
          end

          class ProcStatData < AbstractData
            # https://man7.org/linux/man-pages/man5/proc_pid_stat.5.html

            FIELDS = %w[
              pid
              comm
              state
              ppid
              pgrp
              session
              tty_nr
              tpgid
              flags
              minflt
              cminflt
              majflt
              cmajflt
              utime
              stime
              cutime
              cstime
              priority
              nice
              num_threads
              itrealvalue
              starttime
              vsize
              rss
              rsslim
              startcode
              endcode
              startstack
              kstkesp
              kstkeip
              signal
              blocked
              sigignore
              sigcatch
              wchan
              nswap
              cnswap
              exit_signal
              processor
              rt_priority
              policy
              delayacct_blkio_ticks
              guest_time
              cguest_time
              start_data
              end_data
              start_brk
              arg_start
              arg_end
              env_start
              env_end
              exit_code
            ].freeze

            def self.parse(raw)
              # process name is always in brackets, but may contain brackets itself.
              # There won't be brackets to the right of the last enclosing bracket.
              comm_start = raw.index('(')
              comm_end = raw.rindex(')')

              pid = raw[0...comm_start].strip
              comm = raw[comm_start..comm_end]
              rest = raw[(comm_end + 1)..-1].strip.split(/\s+/)

              new(FIELDS.zip([pid, comm, *rest]).to_h)
            end

            def cpu_time_user
              utime_clock_ticks&./(Linux.clock_tick)
            end

            def cpu_time_system
              stime_clock_ticks&./(Linux.clock_tick)
            end

            def process_memory_usage
              # NOTE: rss is known to be inaccurate
              # Some of these values are inaccurate because of a kernel-
              # internal scalability optimization.  If accurate values are
              # required, use /proc/pid/smaps or /proc/pid/smaps_rollup
              # instead, which are much slower but provide accurate,
              # detailed information.
              data['rss']&.to_i
            end

            def process_memory_virtual
              data['vsize']&.to_i
            end

            def page_faults_major
              data['majflt']&.to_i
            end

            def page_faults_minor
              data['minflt']&.to_i
            end

            if defined?(Process::CLOCK_BOOTTIME)
              def process_uptime
                return unless (ticks = start_time_ticks)

                # FIXME: does Process::CLOCK_BOOTTIME need to be cached on this snapshot?

                (ticks.to_f / Linux.clock_tick) - Process.clock_gettime(Process::CLOCK_BOOTTIME)
              end
            else
              def process_uptime
                # In practice this should never be called, except perhaps in tests running on non-linux platforms
              end
            end

            private

            def utime_clock_ticks
              data['utime']&.to_i
            end

            def stime_clock_ticks
              data['stime']&.to_i
            end

            def start_time_ticks
              # The time the process started after system boot.
              data['starttime']&.to_i
            end
          end

          class ProcStatDataSouce < AbstractDataSource
            private

            def data_class
              ProcStatData
            end

            def fetch_raw_data(pid)
              File.read("/proc/#{pid}/stat")
            end
          end

          class ProcStatusData < AbstractData
            def self.parse(raw)
              data = {}
              raw.lines.each do |line|
                key, value = line.strip.split(":\t")

                next unless key && value

                data[key] = value
              end

              new(data)
            end

            def cpu_time_user; end
            def cpu_time_system; end
            def process_memory_usage; end
            def process_memory_virtual; end

            def voluntary_context_switches
              data['voluntary_ctxt_switches']&.to_i
            end

            def involuntary_context_switches
              data['nonvoluntary_ctxt_switches']&.to_i
            end

            def page_faults_major; end
            def page_faults_minor; end
            def process_uptime; end
          end

          class ProcStatusDataSource < AbstractDataSource
            private

            def data_class
              ProcStatusData
            end

            def fetch_raw_data(pid)
              File.read("/proc/#{pid}/status")
            end
          end

          # FIXME: this might be overkill; stat is a better source for most of this data
          # but context switches aren't listed there.
          class ProcCompoundData < AbstractData
            def self.parse(raw)
              status = ProcStatusData.parse(raw[:status]) if raw[:status]

              stat = ProcStatData.parse(raw[:stat]) if raw[:stat]

              new(stat: stat, status: status)
            end

            def initialize(data)
              super(nil)
              @stat = data[:stat]
              @status = data[:status]
            end

            attr_reader :stat, :status

            def cpu_time_user
              stat&.cpu_time_user
            end

            def cpu_time_system
              stat&.cpu_time_system
            end

            def process_memory_usage
              stat&.process_memory_usage
            end

            def process_memory_virtual
              stat&.process_memory_virtual
            end

            def voluntary_context_switches
              status&.voluntary_context_switches
            end

            def involuntary_context_switches
              status&.involuntary_context_switches
            end

            def page_faults_major
              stat&.page_faults_major
            end

            def page_faults_minor
              stat&.page_faults_minor
            end

            def process_uptime
              stat&.process_uptime
            end
          end

          class ProcCompoundDataSource < AbstractDataSource
            def initialize
              super
              @proc_status_data_source = ProcStatusDataSource.new
              @proc_stat_data_source = ProcStatDataSource.new
            end

            private

            def data_class
              ProcCompoundData
            end

            def fetch_raw_data(pid)
              {
                status: @proc_status_data_source.send(:fetch_raw_data, pid),
                stat: @proc_stat_data_source.send(:fetch_raw_data, pid)
              }
            end
          end
        end
      end
    end
  end
end
