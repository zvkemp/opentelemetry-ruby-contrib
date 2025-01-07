# frozen_string_literal: true

# Copyright The OpenTelemetry Authors
#
# SPDX-License-Identifier: Apache-2.0

require 'opentelemetry'
require 'opentelemetry-instrumentation-base'

module OpenTelemetry
  module Instrumentation
    # (see {OpenTelemetry::Instrumentation::System::Instrumentation})
    module System
    end
  end
end

require_relative 'system/instrumentation'
require_relative 'system/version'
require 'opentelemetry/common'
