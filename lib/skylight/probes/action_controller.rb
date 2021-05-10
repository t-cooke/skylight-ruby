module Skylight
  module Probes
    module ActionController
      class Probe
        def install
          # Prepending doesn't work here since this a module that's already been included
          ::ActionController::Instrumentation.class_eval do
            private

            alias_method :append_info_to_payload_without_sk, :append_info_to_payload
            def append_info_to_payload(payload)
              append_info_to_payload_without_sk(payload)

              payload[:sk_rendered_format] = sk_rendered_mime.try(:ref)
              payload[:sk_variant] = request.respond_to?(:variant) ? request.variant : nil
            end

            def sk_rendered_mime
              if respond_to?(:media_type)
                mt = media_type
                return mt && Mime::Type.lookup(mt)
              end

              if content_type.is_a?(Mime::Type)
                content_type
              elsif content_type.respond_to?(:to_s)
                type_str = content_type.to_s.split(";").first
                Mime::Type.lookup(type_str) unless type_str.blank?
              elsif respond_to?(:rendered_format) && rendered_format
                rendered_format
              end
            rescue StandardError
              # There are cases in which actionpack can return
              # a stringified representation of a Mime::NullType instance,
              # which is invalid for a number of reasons. This string raises
              # errors when piped through Mime::Type.lookup, so it's probably
              # best to just return nil in those cases.
              nil
            end
          end
        end
      end
    end

    register(
      :action_controller,
      "ActionController::Instrumentation",
      "action_controller/metal/instrumentation",
      ActionController::Probe.new
    )
  end
end
