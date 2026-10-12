class AddAccessTokensToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :access_token, :uuid
    suppress_messages do
      select_values("SELECT id FROM users").each do |id|
        execute "UPDATE users SET access_token = #{connection.quote(SecureRandom.uuid)} WHERE id = #{connection.quote(id)}"
      end
    end
    change_column_null :users, :access_token, false
    add_index :users, :access_token, unique: true
  end

  def down
    remove_column :users, :access_token
  end
end
