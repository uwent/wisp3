# Per-request state, set by AuthenticatedController. Queries for group-owned records start
# from Current.group so a user can never reach another group's data by ID.
#
# as_of: the day pages show the operation as of, set only for the example farm (PLAN.md G.8, always
# July 20 of its season); today is that day, or the real one. Code that means "today" on a page's
# path reads Current.today, never Date.current, so the example's pages agree on it.
class Current < ActiveSupport::CurrentAttributes
  attribute :user, :group, :membership, :as_of

  def self.owner? = membership&.owner? || false

  def self.today = as_of || Date.current
end
