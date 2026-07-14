# frozen_string_literal: true

require "json"

# Utility functions for common mathematical operations.
module MathUtils
  # Returns the average of an array of numbers.
  def self.mean(numbers)
    return 0 if numbers.empty?
    sum = numbers.sum.to_f
    sum / numbers.size
  end

  # Returns the median value from a sorted array of numbers.
  def self.median(sorted_numbers)
    n = sorted_numbers.sort.size
    return 0 if n.zero?
    mid = (n - 1) / 2

    if n.even?
      (sorted_numbers[mid] + sorted_numbers[mid + 1]).to_f / 2
    else
      sorted_numbers[mid]
    end
  end

  # Formats a number as JSON-safe string with given decimal places.
  def self.format_number(value, decimals = 2)
    value.round(decimals).to_s
  end
end
