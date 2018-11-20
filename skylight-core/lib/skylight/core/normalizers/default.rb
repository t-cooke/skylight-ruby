module Skylight::Core
  module Normalizers
    # The default normalizer, used if no other is found.
    class Default
      # @param trace [Skylight::Messages::Trace::Builder] ignored, only present to match API
      # @param name [String]
      # @param payload [Hash]
      # @option payload [String] :title
      # @option payload [String] :description
      # @return [Array, :skip] the normalized array or `:skip` if `name` is not part of a known {Skylight::TIERS tier}
      def normalize(_trace, name, payload)
        if name =~ Skylight::TIER_REGEX
          [
            name,
            payload[:title],
            payload[:description]
          ]
        else
          :skip
        end
      end
    end
  end
end
