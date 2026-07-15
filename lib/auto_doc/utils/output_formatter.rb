# frozen_string_literal: true

require "json"

module AutoDoc
  module Utils
    # Formats output data in three modes:
    #   :text  — pass-through to the provided say callback (current behavior)
    #   :json  — pretty-printed JSON with all fields
    #   :agent — compact JSON with essential keys only, stripped of timestamps/noise
    class OutputFormatter
      FORMATS = %i[text json agent].freeze

      # Format +data+ according to +format+ and send the result to +say+.
      #
      # @param data [Hash, Array, String] The data to format
      # @param format [Symbol] One of :text, :json, :agent
      # @param say [Proc] Callback for output (default: puts)
      def self.format(data, format: :text, say: method(:puts))
        format_sym = format.to_sym
        raise ArgumentError, "Unknown format: #{format} (valid: #{FORMATS.join(', ')})" unless FORMATS.include?(format_sym)

        case format_sym
        when :json
          say.call(JSON.pretty_generate(data))
        when :agent
          compact = compact_for_agent(data)
          say.call(JSON.generate(compact))
        else
          say.call(data)
        end
      end

      # Recursively strip presentation-oriented keys (timestamps, formatting noise)
      # from data hashes for agent-optimized output.
      #
      # @param data [Object] Hash, Array, or scalar
      # @return [Object] Compact version of input
      def self.compact_for_agent(data)
        case data
        when Hash
          data.each_with_object({}) do |(k, v), h|
            key_str = k.to_s
            # Skip timestamp-ish and formatting-noise keys
            next if key_str.match?(/generated_at|timestamp|^_/i)

            new_key = key_str.gsub(/([a-z])([A-Z])/, '\1_\2').downcase.to_sym
            h[new_key] = compact_for_agent(v)
          end
        when Array
          data.map { |v| compact_for_agent(v) }
        else
          data
        end
      end
    end
  end
end
