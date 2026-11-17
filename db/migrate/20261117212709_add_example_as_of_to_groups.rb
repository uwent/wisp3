# The public example farm (PLAN.md G.8): one group, shown read-only to anyone as of this day
class AddExampleAsOfToGroups < ActiveRecord::Migration[8.1]
  def change
    add_column :groups, :example_as_of, :date
    add_index :groups, :example_as_of, unique: true, where: "example_as_of IS NOT NULL", name: "index_groups_one_example"
  end
end
