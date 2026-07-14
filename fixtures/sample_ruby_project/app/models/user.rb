# frozen_string_literal: true

require "active_record" if defined?(ActiveRecord)

# Represents a registered user in the system.
class User < ActiveRecord::Base
  include Enumerable

  # Returns users matching the given email address.
  def self.find_by_email(email)
    where(email: email).first
  end

  # Validates whether this user record is complete and saveable.
  def valid?
    !name.empty? && !email.empty?
  end

  # Returns a display name for the user, falling back to email if needed.
  def display_name
    name.presence || email.split("@").first
  end
end
