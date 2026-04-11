class CreatePrAutomationRules < ActiveRecord::Migration[8.1]
  def change
    create_table :pr_automation_rules do |t|
      t.references :github_repository_subscription, null: false,
                   foreign_key: true, index: false
      t.string :trigger, null: false
      t.string :branch_pattern
      t.references :lane, null: false, foreign_key: true

      t.timestamps
    end

    add_index :pr_automation_rules,
              %i[github_repository_subscription_id trigger branch_pattern],
              unique: true, name: 'idx_pr_auto_rules_unique_trigger'
  end
end
