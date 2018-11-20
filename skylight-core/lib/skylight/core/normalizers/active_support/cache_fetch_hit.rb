module Skylight::Core
  module Normalizers
    module ActiveSupport
      class CacheFetchHit < Cache
        register "cache_fetch_hit.active_support"

        CAT = "app.cache.fetch_hit".freeze
        TITLE = "cache fetch hit".freeze

        def normalize(_trace, _name, _payload)
          [CAT, TITLE, nil]
        end
      end
    end
  end
end
