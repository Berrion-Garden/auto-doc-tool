#!/usr/bin/env ruby
# Test flatten behavior and fnmatch errors

puts "=== flatten tests ==="
puts "flat array:    #{%w[a b c].flatten(1).inspect}"
puts "nested array:  #{[[["a", "b"], ["c"]]].flatten(1).inspect}"

def deep_merge(hash1, hash2)
  result = hash1.dup
  hash2.each do |key, value|
    if result[key].is_a?(Hash) && value.is_a?(Hash)
      result[key] = deep_merge(result[key], value)
    else
      result[key] = value
    end
  end
  result
end

puts "\n=== deep_merge tests ==="
defaults  = { exclude_patterns: %w[vendor/**/* node_modules/**/* spec/**/*] }
overrides = { exclude_patterns: [%w[spec test vendor node_modules]] }  # nested array!
result = deep_merge(defaults, overrides)
puts "merged: #{result[:exclude_patterns].inspect}"

flat = Array(result[:exclude_patterns]).flatten(1)
puts "flattened(1): #{flat.inspect}"

# Test fnmatch with the flattened array
puts "\n=== fnmatch test ==="
begin
  flat.each do |p|
    puts "pattern=#{p.inspect}, is_array?=#{p.is_a?(Array)}"
    File.fnmatch?(p, "foo/bar.rb")
  end
rescue TypeError => e
  puts "TypeError: #{e.message}"
end

# Now test the actual case that triggers the error from the task description
# What if flatten(1) doesn't fully flatten?
puts "\n=== double-nested test ==="
double_nested = [[%w[a b]]]  # [["a", "b"]]
after_flatten = Array(double_nested).flatten(1)
puts "after flatten(1): #{after_flatten.inspect}"

begin
  after_flatten.each do |p|
    puts "calling fnmatch with: #{p.inspect} (class=#{p.class})"
    File.fnmatch?(p, "foo/bar.rb")
  end
rescue TypeError => e
  puts "TypeError: #{e.message}"
end
