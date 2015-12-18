require 'spec_helper'

module Skylight
  describe "Normalizers", "process_action.action_controller", :agent do

    it "updates the trace's endpoint" do
      expect(trace).to receive(:endpoint=).and_call_original
      normalize(controller: "foo", action: "bar")
      expect(trace.endpoint).to eq("foo#bar")
    end

  end
end
