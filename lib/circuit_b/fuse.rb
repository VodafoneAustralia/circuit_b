require 'circuit_b/storage/base'

module CircuitB
  class Fuse
    # Maximum time the handler is allowed to execute
    DEFAULT_BREAK_HANDLER_TIMEOUT = 5

    # Standard handlers that can be refered by their names
    STANDARD_HANDLERS = {
      rails_log: lambda do |fuse|
        log_error "CircuitB: Fuse '#{fuse.name}' has broken"
      end
    }

    attr_reader :name, :config
    attr_accessor :break_handler_timeout

    def initialize(name, state_storage, config)
      fail 'Name must be specified' if name.nil?
      fail 'Storage must be specified' if state_storage.nil?
      fail 'Storage must be of CircuitB::Storage::Base kind' unless state_storage.is_a?(CircuitB::Storage::Base)
      fail 'Config must be specified' if config.nil?

      @name          = name
      @state_storage = state_storage
      @config        = config

      @break_handler_timeout = DEFAULT_BREAK_HANDLER_TIMEOUT
    end

    def wrap(&block)
      close_if_cooled_off if open?
      fail CircuitB::FastFailure if open?

      begin
        result = nil

        if @config[:timeout] && @config[:timeout].to_f > 0
          Timeout.timeout(@config[:timeout].to_f) { result = block.call }
        else
          result = block.call
        end

        put(:failures, 0)

        return result
      rescue => e
        # Save the time of the last failure
        put(:last_failure_at, Time.now.to_i)

        # Increment the number of failures and open if the limit has been reached
        failures = inc(:failures)
        open if failures >= @config[:allowed_failures]

        # Re-raise the original exception
        raise e
      end
    end

    def open?
      get(:state).to_sym == :open if get(:state)
    end

    def failures
      get(:failures).to_i
    end

    def reset
      put(:state, :closed)
      put(:failures, 0)
      put(:last_failure_at, nil)
    end

    private

    def close_if_cooled_off
      return unless Time.now.to_i - get(:last_failure_at).to_i > config[:cool_off_period]
      put(:state, :closed)
      put(:failures, 0)

      Fuse.log_info "Closing fuse=#{@name}"
    end

    # Open the fuse
    def open
      put(:state, :open)
      return unless config[:on_break]
      require 'timeout'

      handlers = [config[:on_break]].flatten.map do |handler|
        handler.is_a?(Symbol) ? STANDARD_HANDLERS[handler] : handler
      end.compact

      handlers.each do |handler|
        begin
          Timeout.timeout(@break_handler_timeout) do
            handler.call(self)
          end
        rescue Timeout::Error
          # We ignore handler timeouts
        rescue
          # We ignore handler errors
        end
      end
    end

    def get(field)
      @state_storage.get(@name, field)
    end

    def put(field, value)
      @state_storage.put(@name, field, value)
    end

    def inc(field)
      @state_storage.inc(@name, field)
    end

    def self.log_info(message)
      ::Rails.logger.info(message) if defined?(::Rails.logger)
    end

    def self.log_error(message)
      ::Rails.logger.error(message) if defined?(::Rails.logger)
    end
  end
end
