# A user's place in a group (Q8): owners manage the group (its name and rainfall setting, its
# members, deleting farms, pivots and fields, and deleting the group); members do everything else.
class Membership < ApplicationRecord
  belongs_to :user
  belongs_to :group

  validates :user_id, uniqueness: {scope: :group_id, message: "is already a member"}

  scope :owners, -> { where(owner: true) }

  # Why this membership can't end, or nil. A group always keeps an owner, and its last member
  # deletes the group instead of leaving it empty.
  def removal_error
    others = group.memberships.where.not(id:)
    if others.none?
      "#{user.display_name} is the only member. Delete the operation instead."
    elsif owner? && others.owners.none?
      "#{user.display_name} is the only owner. Make someone else an owner first."
    end
  end

  # Why this owner can't become a member, or nil
  def demotion_error
    "#{user.display_name} is the only owner. Make someone else an owner first." if owner? && group.memberships.owners.where.not(id:).none?
  end
end
