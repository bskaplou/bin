require 'mongo'

module ActiveSupport
  module Cache
    class Bin < Store
      attr_reader :collection, :options, :mult

      def initialize(collection, options={})
        @collection, @options, @mult = collection, options, false
      end

      def expires_in
        @expires_in ||= options[:expires_in] || 1.year
      end

      def delete_matched(matcher, options=nil)
        collection.remove(:_id => matcher)
      end

      def increment(key, amount=1, options=nil)
        counter_key_upsert(:increment, key, amount, options)
      end

      def decrement(key, amount=1, options=nil)
        counter_key_upsert(:decrement, key, -amount.abs, options)
      end

      def clear
        collection.remove
      end

      def stats
        collection.stats
      end

      def multi
        @mult = true
        @store = []
        yield
        @mult = false
        collection.insert(@store)
      end

    private
      def insert(key, value, expires, raw)
        doc = {
            :_id        => key,
            :value      => value,
            :expires_at => expires
        }
        doc[:raw] = raw if raw
        if ! mult
          collection.insert(doc)
        else
          @store << doc
        end
      end

      def counter_key_upsert(action, key, amount, options)
        options = merged_options(options)
        instrument(action, key, :amount => amount) do
          key = namespaced_key(key, options)
          collection.update(
            {:_id => key}, {
              '$inc' => {:value => amount},
              '$set' => {
                :expires_at => Time.now.utc + 1.year,
                :raw        => true
              },
            }, :upsert => true)
        end
      end

      def deserialize_doc(doc)
        return nil if doc.nil?

        entry = doc['raw'] ? doc['value'] : Marshal.load(doc['value'].to_s)
        entry.is_a?(Entry) ? entry : Entry.new(entry)
      end

      def read_entry(key, options)
        query = {:_id => key, :expires_at => {'$gt' => Time.now.utc}}
        deserialize_doc(collection.find_one(query))
      end


      def write_entry(key, entry, options)
        expires = Time.now.utc + options.fetch(:expires_in, expires_in)
        value   = options[:raw] ? entry.value : BSON::Binary.new(Marshal.dump(entry.value))
        if options[:once]
          insert(key, value, expires, options[:raw])
        else
          query   = {:_id => key}
          updates = {'$set' => {
            :value      => value,
            :expires_at => expires,
          }}
          updates['$set'][:raw] = options[:raw] if options[:raw]
          collection.update(query, updates, :upsert => true)
        end
      end

      def delete_entry(key, options)
        collection.remove(:_id => key)
      end
    end
  end
end
