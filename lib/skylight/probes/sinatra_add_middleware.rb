module Skylight
  module Probes
    module Sinatra
      module Instrumentation
        def setup_default_middleware(builder)
          builder.use Skylight::Middleware
          super
        end
      end

      class AddMiddlewareProbe
        def install
          ::Sinatra::Base.singleton_class.prepend(Instrumentation)
        end
      end
    end

    register(:sinatra_add_middleware, "Sinatra::Base", "sinatra/base", Sinatra::AddMiddlewareProbe.new)
  end
end
