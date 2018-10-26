module Skylight
  module Util
    class Component

      attr_accessor :environment, :name

      NAME_FORMAT = /\A[a-z0-9-]+\z/
      DEFAULT_NAME = 'web'.freeze
      WORKER_NAME = 'worker'.freeze
      DEFAULT_ENVIRONMENT = 'production'.freeze

      WORKER_PROGRAM_MATCHER = Regexp.union([
        /sidekiq$/i,
        /backburner$/i,
        /delayed_job$/i,
        /que$/i,
        /sneakers$/i,
      ])

      WORKER_RAKE_MATCHER = Regexp.union([
        /\Aresque:/,
        /\Abackburner:/,
        /\Ajobs:/, # DelayedJob. can also be `rake jobs:workoff`
        /\Aqu:/,
        /\Aque:/,
        /\Aqc:/,
        /\Asneakers:/,
      ])

      def initialize(environment, name)
        @environment = environment || DEFAULT_ENVIRONMENT
        @name        = resolve_name(name)

        raise ArgumentError, "environment can't be blank" if @environment.empty?
        validate_string!(@environment, 'environment')
        validate_string!(@name, 'name')
      end

      def to_s
        "#{name}:#{environment}"
      end

      def web?
        name == DEFAULT_NAME
      end

      def worker?
        !web?
      end

      private

      def program_name
        $PROGRAM_NAME
      end

      def argv
        ARGV
      end

      def resolve_name(given_name)
        return DEFAULT_NAME if known_web_context?
        return given_name if given_name
        return WORKER_NAME if known_worker_context?
        DEFAULT_NAME
      end

      def validate_string!(string, kind)
        return true if string =~ NAME_FORMAT
        raise ArgumentError, "#{kind} can only contain lowercase letters, numbers, and dashes"
      end

      def known_web_context?
        rails_server? || rackup?
      end

      def known_worker_context?
        return true if program_name =~ WORKER_PROGRAM_MATCHER
        (program_name[/rake$/]) && argv.any? { |arg| arg =~ WORKER_RAKE_MATCHER }
      end

      def rails_server?
        defined?(Rails::Server)
      end

      def rackup?
        program_name[/rackup$/]
      end
    end
  end
end
