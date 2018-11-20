require "json"

module Skylight::Core
  module Normalizers
    module CouchPotato
      class Query < Normalizer
        register "couch_potato.load"
        register "couch_potato.view"

        CAT = "db.couch_db.query".freeze

        def normalize(_trace, name, payload)
          description = payload[:name] if payload
          name = name.sub("couch_potato.", "")
          [CAT, name, description]
        end
      end
    end
  end
end
