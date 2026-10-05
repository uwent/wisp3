# Phase 6: the daily digest email. On by default; digest_sent_on keeps a rerun of the job from
# sending twice. Every field in a user's operations is included unless excluded here, by operation,
# farm or field, so new fields join the digest unless their farm or operation is left out.
class CreateDigestSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :digest, :boolean, default: true, null: false
    add_column :users, :digest_sent_on, :date

    create_table :digest_exclusions do |t|
      t.references :user, null: false, foreign_key: {on_delete: :cascade}, index: false
      t.references :subject, polymorphic: true, null: false
      t.timestamps
    end
    add_index :digest_exclusions, [:user_id, :subject_type, :subject_id], unique: true
  end
end
