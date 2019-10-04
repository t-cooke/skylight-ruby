module Skylight
  module Core
    module Instrumentable
      def self.included(base)
        base.extend(Util::Logging)
        base.extend(ClassMethods)

        base.const_set(:LOCK, Mutex.new)

        base.class_eval do
          at_exit { stop! }
        end

        Skylight::Core::Fanout.register(base)
      end

      module ClassMethods
        def instrumenter_class
          Skylight::Core::Instrumenter
        end

        def instrumenter
          defined?(@instrumenter) && @instrumenter
        end

        def correlation_header
          nil
        end

        def probe(*args)
          Skylight::Core::Probes.probe(*args)
        end

        def enable_normalizer(*names)
          Skylight::Core::Normalizers.enable(*names)
        end

        # Start instrumenting
        def start!(config = nil)
          return instrumenter if instrumenter

          const_get(:LOCK).synchronize do
            return instrumenter if instrumenter

            config ||= {}
            config = config_class.load(config) unless config.is_a?(config_class)

            @instrumenter = instrumenter_class.new(config).start!
          end
        rescue => e
          level, message =
            if e.is_a?(ConfigError)
              [:warn, format("Unable to start Instrumenter due to a configuration error: %<message>s",
                             message: e.message)]
            else
              [:error, format("Unable to start Instrumenter; msg=%<message>s; class=%<klass>s",
                              message: e.message, klass: e.class)]
            end

          if config && config.respond_to?("log_#{level}") && config.respond_to?(:log_trace)
            config.send("log_#{level}", message)
            config.log_trace e.backtrace.join("\n")
          else
            warn "[#{name.upcase}] #{message}"
          end
          false
        end

        def started?
          !!instrumenter
        end

        # Stop instrumenting
        def stop!
          t { "stop!" }

          const_get(:LOCK).synchronize do
            t { "stop! synchronized" }
            return unless instrumenter
            # This is only really helpful for getting specs to pass.
            @instrumenter.current_trace = nil

            @instrumenter.shutdown
            @instrumenter = nil
          end
        end

        # Check tracing
        def tracing?
          t { "checking tracing?; thread=#{Thread.current.object_id}" }
          instrumenter && instrumenter.current_trace
        end

        # Start a trace
        def trace(endpoint = nil, cat = nil, title = nil, meta: nil, segment: nil, component: nil)
          unless instrumenter
            return yield if block_given?
            return
          end

          if instrumenter.poisoned?
            spawn_shutdown_thread!
            return yield if block_given?
            return
          end

          cat ||= DEFAULT_CATEGORY

          if block_given?
            instrumenter.trace(endpoint, cat, title, nil, meta: meta, segment: segment, component: component) { |tr| yield tr }
          else
            instrumenter.trace(endpoint, cat, title, nil, meta: meta, segment: segment, component: component)
          end
        end

        # Instrument
        def instrument(opts = DEFAULT_OPTIONS, &block)
          unless instrumenter
            return yield if block_given?
            return
          end

          if opts.is_a?(Hash)
            category    = opts[:category] || DEFAULT_CATEGORY
            title       = opts[:title]
            desc        = opts[:description]
            meta        = opts[:meta]
            if opts.key?(:annotations)
              warn "call to #instrument included deprecated annotations"
            end
          else
            category    = DEFAULT_CATEGORY
            title       = opts.to_s
            desc        = nil
            meta        = nil
          end

          instrumenter.instrument(category, title, desc, meta, &block)
        end

        def mute
          unless instrumenter
            return yield if block_given?
            return
          end

          instrumenter.mute do
            yield if block_given?
          end
        end

        def unmute
          unless instrumenter
            return yield if block_given?
            return
          end

          instrumenter.unmute do
            yield if block_given?
          end
        end

        def muted?
          instrumenter&.muted?
        end

        def span_correlation_header(span)
          return unless instrumenter
          instrumenter.span_correlation_header(span)
        end

        # End a span
        def done(span, meta = nil)
          return unless instrumenter
          instrumenter.done(span, meta)
        end

        def broken!
          return unless instrumenter
          instrumenter.broken!
        end

        # Temporarily disable
        def disable
          unless instrumenter
            return yield if block_given?
            return
          end

          instrumenter.disable { yield }
        end

        def config
          return unless instrumenter
          instrumenter.config
        end

        # Runs the shutdown procedure in the background.
        # This should do little more than unsubscribe from all ActiveSupport::Notifications
        def spawn_shutdown_thread!
          @shutdown_thread || const_get(:LOCK).synchronize do
            @shutdown_thread ||= Thread.new { @instrumenter&.shutdown }
          end
        end
      end
    end
  end
end
