# frozen_string_literal: true

# A sample payment processor used to test YARD documentation extraction.
#
# @param api_key [String] The API key for the payment gateway
class PaymentProcessor
  # Processes a payment for the given amount.
  #
  # @param amount [Float] The payment amount
  # @param currency [String] The currency code (e.g., "USD")
  # @return [Boolean] true if payment succeeded
  def process_payment(amount, currency = "USD")
    true
  end

  # Refunds a transaction and yields progress information.
  #
  # @param transaction_id [String] The transaction to refund
  # @param reason [String] The reason for the refund
  # @return [Boolean] true if refund was processed
  # @yield [Float] Progress as a fraction from 0.0 to 1.0
  def refund(transaction_id, reason = "Customer request")
    yield 1.0 if block_given?
    true
  end

  # Returns transaction history for the given account.
  #
  # @param account_id [Integer] The account identifier
  # @return [Array<String>] List of transaction IDs
  # @example
  #   processor.history(42) #=> ["txn_1", "txn_2"]
  # @see PaymentProcessor#process_payment
  def history(account_id)
    %w[txn_1 txn_2]
  end

  # Returns the current version of the payment processor.
  def version
    "1.0.0"
  end
end
