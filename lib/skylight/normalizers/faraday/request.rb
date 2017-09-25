module Skylight
  module Normalizers
    module Faraday
      class Request < Normalizer
        register "request.faraday"

        DISABLED_KEY = :__skylight_faraday_disabled

        def self.disable
          Thread.current[DISABLED_KEY] = true
          yield
        ensure
          Thread.current[DISABLED_KEY] = false
        end

        def disabled?
          !!Thread.current[DISABLED_KEY]
        end

        def normalize(_trace, _name, payload)
          uri = payload[:url]

          if disabled?
            return :skip
          end

          opts = Formatters::HTTP.build_opts(payload[:method], uri.scheme,
          uri.host, uri.port, uri.path, uri.query)
          description = opts[:title]

          [opts[:category], "Faraday", description]
        end
      end
    end
  end
end
