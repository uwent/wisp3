class FieldGroupMember < ApplicationRecord
  belongs_to :field_group
  belongs_to :field

  validates :field_id, uniqueness: {scope: :field_group_id}
  validate :same_group

  private

  def same_group
    return unless field_group && field
    errors.add(:field, "belongs to another account") unless field.farm.group_id == field_group.group_id
  end
end
