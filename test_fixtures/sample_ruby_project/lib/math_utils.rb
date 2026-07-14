# Math utility functions
module MathUtils
  # Calculate the nth fibonacci number
  def self.fibonacci(n)
    return 0 if n <= 0
    return 1 if n == 1
    fibonacci(n - 1) + fibonacci(n - 2)
  end
end
