require "valium/version"
require 'active_record'

module Valium
  if ActiveRecord::VERSION::MAJOR == 3

    if ActiveRecord::VERSION::MINOR == 0 # We need to use the old deserialize code

      def valium_deserialize(value, klass)
        if value.is_a?(String) && value =~ /^---/
          result = YAML::load(value) rescue value
          if result.nil? || result.is_a?(klass)
            result
          else
            raise SerializationTypeMismatch,
              "Expected a #{klass}, but was a #{result.class}"
          end
        else
          value
        end
      end

    else # we're on 3.1+, yay for coder.load!

      def valium_deserialize(value, coder)
        coder.load(value)
      end

    end # Minor version check

    def [](*attr_names)
      attr_names = attr_names.map(&:to_s)

      if attr_names.size > 1
        valium_select_multiple(attr_names)
      else
        valium_select_one(attr_names.first)
      end
    end

    def valium_select_multiple(attr_names)
      columns = attr_names.map {|n| columns_hash[n]}
      coders  = attr_names.map {|n| serialized_attributes[n]}

      connection.select_rows(
        select(attr_names.map {|n| arel_table[n]}).to_sql
      ).map! do |values|
        values.each_with_index do |value, index|
          values[index] = valium_cast(value, columns[index], coders[index])
        end
      end
    end

    def valium_select_one(attr_name)
      column = columns_hash[attr_name]
      coder  = serialized_attributes[attr_name]

      connection.select_rows(
        select(arel_table[attr_name]).to_sql
      ).map! do |values|
        valium_cast(values[0], column, coder)
      end
    end

    def valium_cast(value, column, coder_or_klass)
      if value.nil? || !column
        value
      elsif coder_or_klass
        valium_deserialize(value, coder_or_klass)
      else
        column.type_cast(value)
      end
    end

    module Relation
      def [](*args)
        if args.size > 0 && args.all? {|a| String === a || Symbol === a}
          scoping { @klass[*args] }
        else
          to_a[*args]
        end
      end
    end

  end # Major version check
end

ActiveRecord::Base.extend Valium
ActiveRecord::Relation.send :include, Valium::Relation