module Ably::Modules
  # StateEmitter module adds a set of generic state related methods to a class on the assumption that
  # the instance variable @state is used exclusively, the {Enum} STATE is defined prior to inclusion of this
  # module, and the class is an {EventEmitter}.  It then emits state changes.
  #
  # It also ensures the EventEmitter is configured to retrict permitted events to the
  # the available STATEs and :error.
  #
  # @example
  #   class Connection
  #     include Ably::Modules::EventEmitter
  #     extend  Ably::Modules::Enum
  #     STATE = ruby_enum('STATE',
  #       :initialized,
  #       :connecting,
  #       :connected
  #     )
  #     include Ably::Modules::StateEmitter
  #   end
  #
  #   connection = Connection.new
  #   connection.state = :connecting     # emits :connecting event via EventEmitter, returns STATE.Connecting
  #   connection.state?(:connected)      # => false
  #   connection.connecting?             # => true
  #   connection.state                   # => STATE.Connecting
  #   connection.state = :invalid        # raises an Exception as only a valid state can be defined
  #   connection.trigger :invalid        # raises an Exception as only a valid state can be used for EventEmitter
  #   connection.change_state :connected # emits :connected event via EventEmitter, returns STATE.Connected
  #   connection.once_or_if(:connected) { puts 'block called once when state is connected or becomes connected' }
  #
  module StateEmitter
    # Current state {Ably::Modules::Enum}
    #
    # @return [Symbol] state
    def state
      STATE(@state)
    end

    # Evaluates if check_state matches current state
    #
    # @return [Boolean]
    def state?(check_state)
      state == check_state
    end

    # Set the current state {Ably::Modules::Enum}
    #
    # @return [Symbol] new state
    # @api private
    def state=(new_state, *args)
      if state != new_state
        logger.debug("#{self.class}: StateEmitter changed from #{state} => #{new_state}") if respond_to?(:logger, true)
        @state = STATE(new_state)
        trigger @state, *args
      end
    end
    alias_method :change_state, :state=

    # If the current state matches the new_state argument the block is called immediately.
    # Else the block is called once when the new_state is reached.
    #
    # @param [Symbol,Ably::Modules::Enum] new_state
    # @yield block is called if the state is matched immediately or once when the state is reached
    #
    # @return [void]
    def once_or_if(new_state, &block)
      if state == new_state
        block.call
      else
        once new_state, &block
      end
    end

    # Calls the block once when the state changes
    #
    # @yield block is called once the state changes
    # @return [void]
    #
    # @api private
    def once_state_changed(&block)
      once_block = proc do
        off *self.class::STATE.map, &once_block
        yield
      end

      once *self.class::STATE.map, &once_block
    end

    private
    def self.included(klass)
      klass.configure_event_emitter coerce_into: Proc.new { |event|
        if event == :error
          :error
        else
          klass::STATE(event)
        end
      }

      klass::STATE.each do |state_predicate|
        klass.instance_eval do
          define_method("#{state_predicate.to_sym}?") do
            state?(state_predicate)
          end
        end
      end
    end
  end
end
