# Q8: a group's members are owners or members. The old admin flag becomes the owner flag, and
# every group gets at least one owner (its earliest member).
class RenameMembershipAdminToOwner < ActiveRecord::Migration[8.1]
  def up
    rename_column :memberships, :admin, :owner
    execute <<~SQL
      UPDATE memberships SET owner = true
      WHERE id IN (
        SELECT DISTINCT ON (group_id) id FROM memberships
        WHERE group_id NOT IN (SELECT group_id FROM memberships WHERE owner)
        ORDER BY group_id, created_at, id
      )
    SQL
  end

  def down
    rename_column :memberships, :owner, :admin
  end
end
