# frozen_string_literal: true

# Copyright The OpenTelemetry Authors
#
# SPDX-License-Identifier: Apache-2.0

require 'test_helper'
require_relative '../../../../lib/opentelemetry/instrumentation/system'

describe OpenTelemetry::Instrumentation::System::Instrumentation do
  let(:instrumentation) { OpenTelemetry::Instrumentation::System::Instrumentation.instance }

  it 'has #name' do
    _(instrumentation.name).must_equal 'OpenTelemetry::Instrumentation::System'
  end
end
