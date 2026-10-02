# Per-request state, set by AuthenticatedController. Queries for group-owned records start
# from Current.group so a user can never reach another group's data by ID.
class Current < ActiveSupport::CurrentAttributes
  attribute :user, :group
end
