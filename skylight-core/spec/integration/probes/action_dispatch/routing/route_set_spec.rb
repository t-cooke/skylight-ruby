require "spec_helper"

if defined?(ActionDispatch)
  require "./lib/skylight/core/probes/action_dispatch/routing/route_set"

  describe "ActionDispatch::Routing::RouteSet integration", :'action_dispatch/routing/route_set_probe', :agent do
    around do |example|
      TestNamespace.mock!
      TestNamespace.trace("test") { example.run }
      TestNamespace.stop!
    end

    class CustomError < RuntimeError; end

    let(:route_set) do
      ActionDispatch::Routing::RouteSet.new.tap do |routes|
        routes.draw do
          get("/foo", to: -> (*) { [204, {}, []] })
          get("/error", to: -> (*) { raise CustomError })
        end
      end
    end

    let(:trace) do
      TestNamespace.instrumenter.current_trace
    end

    before do
      expect(trace).to receive(:instrument).with(
        "rack.app", "ActionDispatch::Routing::RouteSet", nil, nil
      )
    end

    specify do
      response = Rack::MockRequest.new(route_set).get("/foo")
      expect(response.status).to eq(204)
    end

    specify do
      response = Rack::MockRequest.new(route_set).get("/missing")
      expect(response.status).to eq(404)
    end

    specify do
      expect { Rack::MockRequest.new(route_set).get("/error") }.to raise_error(CustomError)
    end
  end
end
