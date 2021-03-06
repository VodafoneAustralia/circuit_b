module CircuitB
  module Storage
    storage_ops = lambda do

      describe 'storage' do
        before do
          @store.put('fuse_name', 'field', 0)
        end

        it 'stores fuse states with put and return value' do
          val = @store.put('fuse_name', 'field', 'value')
          assert_equal val, 'value'
        end

        it 'gets fuse states with get' do
          @store.put('fuse_name', 'field', 'value')
          val = @store.get('fuse_name', 'field')
          assert_equal val, 'value'
        end

        it 'increments fuses with inc and return counter' do
          val1 = @store.inc('fuse_name', 'field')
          assert_equal val1, 1
          val2 = @store.inc('fuse_name', 'field')
          assert_equal val2, 2
        end
      end
    end

    describe 'base store' do
      before do
        @store = Base.new
      end

      it 'fails put with NotImplementedError' do
        begin
          @store.put('fuse_name', 'field', nil)
        rescue NotImplementedError => e
          assert_equal e.class, NotImplementedError
        end
      end

      it 'fails get with NotImplementedError' do
        begin
          @store.get('fuse_name', 'field')
        rescue NotImplementedError => e
          assert_equal e.class, NotImplementedError
        end
      end

      it 'fails inc with NotImplementedError' do
        begin
          @store.inc('fuse_name', 'field')
        rescue NotImplementedError => e
          assert_equal e.class, NotImplementedError
        end
      end
    end

    describe 'memory store' do
      before do
        @store = Memory.new
      end
      storage_ops.call
    end

    describe 'redis store' do
      before do
        @store = Redis.new
      end
      storage_ops.call
    end

    describe 'rails cache store memory_store' do
      before do
        @store = RailsCache.new
      end
      storage_ops.call
    end

    describe 'rails cache store redis_store' do
      ::Rails.cache = ActiveSupport::Cache.lookup_store :redis_store
      before do
        @store = RailsCache.new
      end
      storage_ops.call
      ::Rails.cache = ActiveSupport::Cache.lookup_store :memory_store
    end
  end
end
