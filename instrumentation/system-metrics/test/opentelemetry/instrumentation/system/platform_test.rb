# frozen_string_literal: true

# Copyright The OpenTelemetry Authors
#
# SPDX-License-Identifier: Apache-2.0

require 'test_helper'
require_relative '../../../../lib/opentelemetry/instrumentation/system/platform'

describe OpenTelemetry::Instrumentation::System::Platform do
  let(:proc_status_raw) do
    %(
      Name:\tirb\nUmask:\t0022\nState:\tR (running)\nTgid:\t14\nNgid:\t0\nPid:\t14\nPPid:\t1\nTracerPid:\t0\nUid:\t0\t0\t0\t0\nGid:\t0\t0\t0\t0\nFDSize:\t256\nGroups:\t0 \nNStgid:\t14\nNSpid:\t14\nNSpgid:\t14\nNSsid:\t1\nKthread:\t0\nVmPeak:\t  480820 kB\nVmSize:\t  480756 kB\nVmLck:\t       0 kB\nVmPin:\t       0 kB\nVmHWM:\t   21020 kB\nVmRSS:\t   21020 kB\nRssAnon:\t   14208 kB\nRssFile:\t    6812 kB\nRssShmem:\t       0 kB\nVmData:\t  460748 kB\nVmStk:\t    8188 kB\nVmExe:\t       4 kB\nVmLib:\t    9356 kB\nVmPTE:\t     156 kB\nVmSwap:\t       0 kB\nHugetlbPages:\t       0 kB\nCoreDumping:\t0\nTHP_enabled:\t0\nuntag_mask:\t0xffffffffffffff\nThreads:\t2\nSigQ:\t0/31324\nSigPnd:\t0000000000000000\nShdPnd:\t0000000000000000\nSigBlk:\t0000000000000000\nSigIgn:\t0000000000000000\nSigCgt:\t0000000142017e4f\nCapInh:\t0000000000000000\nCapPrm:\t00000000a80425fb\nCapEff:\t00000000a80425fb\nCapBnd:\t00000000a80425fb\nCapAmb:\t0000000000000000\nNoNewPrivs:\t0\nSeccomp:\t0\nSeccomp_filters:\t0\nSpeculation_Store_Bypass:\tthread vulnerable\nSpeculationIndirectBranch:\tunknown\nCpus_allowed:\t3ff\nCpus_allowed_list:\t0-9\nMems_allowed:\t1\nMems_allowed_list:\t0\nvoluntary_ctxt_switches:\t119345\nnonvoluntary_ctxt_switches:\t7\n
    )
  end

  let(:proc_stat_raw) do
    "14 (irb) R 1 14 1 34816 14 4194560 3832 0 0 0 2657 1499 0 0 20 0 2 0 22878 492294144 5255 18446744073709551615 187650009333760 187650009337256 281474020148384 0 0 0 0 0 1107394127 0 0 0 17 8 0 0 0 0 0 187650009464144 187650009464936 187650643861504 281474020150775 281474020150814 281474020150814 281474020151269 0\n"
  end
  describe OpenTelemetry::Instrumentation::System::Platform::Linux::ProcStatusData do
    let(:parsed) do
      OpenTelemetry::Instrumentation::System::Platform::Linux::ProcStatusData.parse(proc_status_raw)
    end

    it 'works' do
      parsed
    end
  end

  describe OpenTelemetry::Instrumentation::System::Platform::Linux::ProcStatData do
    let(:raw) do
    end

    let(:parsed) do
      OpenTelemetry::Instrumentation::System::Platform::Linux::ProcStatData.parse(proc_stat_raw)
    end

    it 'works' do
      parsed
    end
  end

  describe OpenTelemetry::Instrumentation::System::Platform::Linux::ProcCompoundData do
    let(:parsed) { OpenTelemetry::Instrumentation::System::Platform::Linux::ProcCompoundData.parse(stat: proc_stat_raw, status: proc_status_raw) }

    it 'works' do
      parsed
      _(parsed.cpu_time_user).must_equal(26)
      _(parsed.cpu_time_system).must_equal(14)
      _(parsed.process_memory_usage).must_equal(5255)
      _(parsed.process_memory_virtual).must_equal(492_294_144)
      _(parsed.voluntary_context_switches).must_equal(119_345)
      _(parsed.involuntary_context_switches).must_equal(7)
      _(parsed.page_faults_major).must_equal(0)
      _(parsed.page_faults_minor).must_equal(3832)

      # _(parsed.process_uptime).must_equal(0) if defined?(Process::CLOCK_BOOTTIME)
    end
  end
end
