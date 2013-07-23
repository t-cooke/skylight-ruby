require 'socket'

module Skylight
  module Worker
    # TODO:
    #   - Shutdown if no connections for over a minute
    class Server
      LOCKFILE_PATH      = 'SKYLIGHT_LOCKFILE_PATH'.freeze
      LOCKFILE_ENV_KEY   = 'SKYLIGHT_LOCKFILE_FD'.freeze
      UDS_SRV_FD_KEY     = 'SKYLIGHT_UDS_FD'.freeze
      KEEPALIVE_KEY      = 'SKYLIGHT_KEEPALIVE'.freeze

      include Util::Logging

      attr_reader \
        :pid,
        :tick,
        :config,
        :keepalive,
        :lockfile_path,
        :sockfile_path

      def initialize(config, lockfile, srv, lockfile_path)

        unless lockfile && srv
          raise ArgumentError, "lockfile and unix domain server socket are required"
        end

        @pid           = Process.pid
        @run           = true
        @tick          = 1
        @socks         = []
        @config        = config
        @server        = srv
        @lockfile      = lockfile
        @collector     = Collector.new(config)
        @keepalive     = @config[:'agent.keepalive']
        @connections   = {}
        @lockfile_path = lockfile_path
        @sockfile_path = @config[:'agent.sockfile_path']
      end

      # Called from skylight.rb on require
      def self.boot
        fail = lambda do |msg|
          STDERR.puts msg
          exit 1
        end

        config = Config.load_from_env

        unless fd = ENV[LOCKFILE_ENV_KEY]
          fail.call "missing lockfile FD"
        end

        unless fd =~ /^\d+$/
          fail.call "invalid lockfile FD"
        end

        begin
          lockfile = IO.open(fd.to_i)
        rescue Exception => e
          fail.call "invalid lockfile FD: #{e.message}"
        end

        unless lockfile_path = ENV[LOCKFILE_PATH]
          fail.call "missing lockfile path"
        end

        unless config[:'agent.sockfile_path']
          fail.call "missing sockfile path"
        end

        srv = nil
        if fd = ENV[UDS_SRV_FD_KEY]
          srv = UNIXServer.for_fd(fd.to_i)
        end

        server = new(
          config,
          lockfile,
          srv,
          lockfile_path)

        server.run
      end

      def self.exec(cmd, config, lockfile, srv, lockfile_path)
        env = config.to_env
        env.merge!(
          STANDALONE_ENV_KEY => STANDALONE_ENV_VAL,
          LOCKFILE_PATH      => lockfile_path,
          LOCKFILE_ENV_KEY   => lockfile.fileno.to_s)

        if srv
          env[UDS_SRV_FD_KEY] = srv.fileno.to_s
        end

        opts = {}
        args = [env] + cmd + [opts]

        unless RUBY_VERSION < '1.9'
          [lockfile, srv].each do |io|
            next unless io
            fd = io.fileno.to_i
            opts[fd] = fd
          end
        end

        Kernel.exec(*args)
      end

      def run
        init
        work
      ensure
        cleanup
      end

    private

      def init
        trap('TERM') { @run = false }
        trap('INT')  { @run = false }

        info "starting skylight daemon"
        @collector.spawn
      end

      def work
        @socks << @server

        now = Time.now.to_i
        next_sanity_check_at = now + tick
        had_client_at = now

        trace "starting IO loop"
        begin
          # Wait for something to do
          r, _, _ = IO.select(@socks, [], [], tick)

          if r
            r.each do |sock|
              if sock == @server
                # If the server socket, accept
                # the incoming connection
                if client = accept
                  connect(client)
                end
              else
                # Client socket, lookup the associated connection
                # state machine.
                unless conn = @connections[sock]
                  # No associated connection, weird.. bail
                  client_close(sock)
                  next
                end

                begin
                  # Pop em while we got em
                  while msg = conn.read
                    handle(msg)
                  end
                rescue SystemCallError, EOFError
                  client_close(sock)
                rescue IpcProtoError => e
                  error "Server#work - IPC protocol exception: %s", e.message
                  client_close(sock)
                end
              end
            end
          end

          now = Time.now.to_i

          if @socks.length > 1
            had_client_at = now
          end

          if keepalive < now - had_client_at
            info "no clients for #{keepalive} sec - shutting down"
            @run = false
          elsif next_sanity_check_at <= now
            next_sanity_check_at = now + tick
            sanity_check
          end

        rescue SignalException => e
          error "Did not handle: #{e.class}"
          @run = false
        rescue WorkerStateError => e
          info "#{e.message} - shutting down"
          @run = false
        rescue Exception => e
          error "Loop exception: %s (%s)", e.message, e.class
          puts e.backtrace
          return false
        rescue Object => o
          error "Unknown object thrown: `%s`", o.to_s
          return false
        end while @run

        true # Successful return
      end

      # Handles an incoming message. Will be instances from
      # the Messages namespace
      def handle(msg)
        case msg
        when nil
          return
        when Messages::Hello
          if msg.newer?
            info "newer version of agent deployed - restarting; curr=%s; new=%s", VERSION, msg.version
            reload(msg)
          end
        when Messages::Trace
          t { "received trace" }
          @collector.submit(msg)
        when :unknown
          debug "received unknown message"
        else
          debug "recieved: %s", msg
        end
      end

      def reload(hello)
        # Close all client connections
        trace "closing all client connections"
        clients_close

        # Re-exec the process
        trace "re-exec"
        Server.exec(hello.cmd, @config, @lockfile, @server, lockfile_path)
      end

      def accept
        @server.accept_nonblock
      rescue Errno::EWOULDBLOCK, Errno::EAGAIN, Errno::ECONNABORTED
      end

      def connect(sock)
        trace "client accepted"
        @socks << sock
        @connections[sock] = Connection.new(sock)
      end

      def cleanup
        # The lockfile is not deleted. There is no way to atomically ensure
        # that we are deleting the lockfile for the current process.
        cleanup_curr_sockfile
        close
        @lockfile.close
      end

      def close
        @server.close if @server
        clients_close
      end

      def clients_close
        @connections.keys.each do |sock|
          client_close(sock)
        end
      end

      def client_close(sock)
        trace "closing client connection; fd=%d", sock.fileno
        @connections.delete(sock)
        @socks.delete(sock)
        sock.close rescue nil
      end

      def sockfile
        "#{sockfile_path}/skylight-#{pid}.sock"
      end

      def sockfile?
        File.exist?(sockfile)
      end

      def cleanup_curr_sockfile
        File.unlink(sockfile) rescue nil
      end

      def sanity_check
        if !File.exist?(lockfile_path)
          raise WorkerStateError, "lockfile gone"
        end

        pid = File.read(lockfile_path) rescue nil

        unless pid
          raise WorkerStateError, "could not read lockfile"
        end

        unless pid == Process.pid.to_s
          raise WorkerStateError, "lockfile points to different process"
        end

        unless sockfile?
          raise WorkerStateError, "sockfile gone"
        end
      end
    end
  end
end
