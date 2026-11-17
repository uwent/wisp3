# The public example farm (PLAN.md G.8): /example puts this browser's session in example mode, which
# shows the example group (Group.example) read-only on the app's own pages, as of its example_as_of
# (Current.as_of), to anyone, signed in or not. Leaving it (DELETE /example) or signing in ends it.
# AuthenticatedController lets example mode reach only the actions a controller allows with
# allow_example, and only to read.
module ExampleMode
  extend ActiveSupport::Concern

  SESSION_KEY = :example

  # Page loads in example mode per address, each a few balances, before it asks them to wait
  def self.limit(ip) = WindowLimit.new("example-ip:#{ip}", limit: 300, window: 10.minutes)

  included do
    helper_method :example_group
  end

  private

  # The example farm while this browser is viewing it, or nil; a session left in example mode after
  # the example was removed leaves it
  def example_group
    return @example_group if defined?(@example_group)

    @example_group = session[SESSION_KEY] ? Group.example : nil
    session.delete(SESSION_KEY) if session[SESSION_KEY] && !@example_group
    @example_group
  end

  def leave_example = session.delete(SESSION_KEY)
end
