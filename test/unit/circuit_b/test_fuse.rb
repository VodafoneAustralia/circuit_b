module CircuitB
  class TestFuse < Minitest::Spec
    context 'initialization' do
      should 'not allow nil names' do
        begin
          CircuitB::Fuse.new(nil, nil, {})
          fail 'Exception is expected'
        rescue => e
          assert_equal 'Name must be specified', e.message
        end
      end

      should 'not allow nil-storages' do
        begin
          CircuitB::Fuse.new('name', nil, {})
          fail 'Exception is expected'
        rescue => e
          assert_equal 'Storage must be specified', e.message
        end
      end

      should 'disallow storages of the wrong type' do
        begin
          CircuitB::Fuse.new('name', '', nil)
          fail 'Exception is expected'
        rescue => e
          assert_equal 'Storage must be of CircuitB::Storage::Base kind', e.message
        end
      end

      should 'not allow nil-configs' do
        begin
          CircuitB::Fuse.new('name', CircuitB::Storage::Memory.new, nil)
          fail 'Exception is expected'
        rescue => e
          assert_equal 'Config must be specified', e.message
        end
      end
    end

    context 'operation' do
      setup do
        @fuse = memory_fuse
      end

      should 'open when the allowed failures reached' do
        assert !@fuse.open?
        do_failure(@fuse)
        assert @fuse.open?
      end

      should 'reset the failures counter when the attempt succeeds' do
        @fuse = memory_fuse(allowed_failures: 2)

        do_failure(@fuse)
        assert_equal 1, @fuse.failures

        @fuse.wrap do
          # Successful code
        end

        assert_equal 0, @fuse.failures
      end

      should 'fail fast when open' do
        # Open the fuse and verify it's open
        do_failure(@fuse)
        assert @fuse.open?

        begin
          @fuse.wrap do
            fail 'Must not execute as fail-fast exception is expected'
          end
        rescue => e
          assert e.is_a?(CircuitB::FastFailure), "Wrong exception: #{e.inspect}"
        end
      end

      should 'close after the cooling period' do
        do_failure(@fuse)

        Timecop.travel(Time.now + @fuse.config[:cool_off_period] + 1) do
          @fuse.send(:close_if_cooled_off)

          assert !@fuse.open?
          assert_equal 0, @fuse.failures
        end
      end

      should 'not count fast failure as an error' do
        do_failure(@fuse)

        # Get the fast failure
        Timecop.travel(Time.now + @fuse.config[:cool_off_period] / 2) do
          begin
            do_failure(@fuse, true)
            fail 'Fast failure is expected'
          rescue CircuitB::FastFailure
            # Expected
          end
        end

        # The above fast failure should not affect the cooling off schedule
        Timecop.travel(Time.now + @fuse.config[:cool_off_period] + 1) do
          @fuse.send(:close_if_cooled_off)
          assert !@fuse.open?
        end
      end

      context 'on-break handlers' do
        should 'call single handler' do
          handler_fuse = nil
          handler = ->(fuse) { handler_fuse = fuse }
          @fuse = memory_fuse(on_break: handler)

          do_failure(@fuse)

          assert_equal @fuse, handler_fuse
        end

        should 'call standard rails_log handler' do
          @fuse = memory_fuse(on_break: :rails_log)

          do_failure(@fuse)

          assert_equal ::Rails.logger.last, "CircuitB: Fuse 'name' has broken"
        end

        should 'call all of handlers' do
          handler_calls = 0
          handler = ->(_fuse) { handler_calls += 1 }
          @fuse = memory_fuse(on_break: [handler, handler])

          do_failure(@fuse)

          assert_equal 2, handler_calls
        end

        should 'ignore failures of handlers' do
          handler_calls = 0
          handler = ->(_fuse) { handler_calls += 1 }
          failing_handler = ->(_fuse) { fail 'Handling error' }
          @fuse = memory_fuse(on_break: [failing_handler, handler])

          do_failure(@fuse)

          assert_equal 1, handler_calls
        end

        should 'interrupt long handlers (no more than 5 seconds)' do
          handler_calls = 0
          long_handler = lambda do |_fuse|
            sleep 10
            handler_calls += 1
          end
          short_handler   = ->(_fuse) { handler_calls += 1 }
          @fuse = memory_fuse(on_break: [long_handler, short_handler])
          @fuse.break_handler_timeout = 0.1

          do_failure(@fuse)

          assert_equal 1, handler_calls
        end
      end

      context 'execution timeouts' do
        should 'fail long tasks' do
          @fuse = memory_fuse(timeout: 0.1)
          begin
            @fuse.wrap do
              sleep 0.2
            end
            fail 'Timeout::Error should be thrown'
          rescue Timeout::Error
            assert @fuse.open?
          end
        end
      end
    end

    interface_tests = lambda do
      describe 'fuse#failures' do
        should 'be 0 when initialized' do
          assert_equal 0, @fuse.failures
        end

        should 'be 1 after failure' do
          do_failure(@fuse)
          assert_equal 1, @fuse.failures
        end
      end
    end

    context 'storage adapter' do

      options = { allowed_failures: 1, cool_off_period: 60 }

      context 'memory' do
        before do
          @fuse = memory_fuse
          @fuse.reset
        end
        interface_tests.call
      end

      context 'redis' do
        before do
          @fuse = CircuitB::Fuse.new('name', CircuitB::Storage::Redis.new, options)
          @fuse.reset
        end
        interface_tests.call
      end

      context 'railscache' do
        before do
          @fuse = CircuitB::Fuse.new('name', CircuitB::Storage::RailsCache.new, options)
          @fuse.reset
        end
        interface_tests.call
      end
    end

    def do_failure(_fuse, rethrow = false)
      @fuse.wrap do
        fail 'Exceptional code'
      end
    rescue => e
      raise e if rethrow
    end

    def memory_fuse(options = {})
      options = { allowed_failures: 1, cool_off_period: 60 }.merge(options)
      CircuitB::Fuse.new('name', CircuitB::Storage::Memory.new, options)
    end
  end
end
