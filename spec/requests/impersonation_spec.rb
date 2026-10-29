require "rails_helper"

RSpec.describe "Impersonation", type: :request do
  let(:admin) { create(:user, admin: true, email: "staff@example.com") }
  let(:user) { create(:user, first_name: "Jane", last_name: "Grower", email: "jane@example.com") }

  def impersonate(target = user)
    sign_in admin
    get root_path
    post admin_user_impersonation_path(target)
  end

  it "isn't for yourself or another admin" do
    other = create(:user, admin: true)
    [admin, other].each do |target|
      impersonate(target)
      expect(response).to redirect_to(admin_user_path(target))
      expect(flash[:alert]).to eq("You can't sign in as yourself or another admin.")
      get root_path
      expect(inertia.props[:auth][:user][:id]).to eq(admin.id)
      expect(inertia.props[:auth][:impersonator]).to be_nil
    end
  end

  it "signs the admin in as the user in their own operation, without touching their sign-in history" do
    admin_group = create(:group)
    create(:membership, user: admin, group: admin_group)
    create(:membership, user:, group: admin_group)
    sign_in admin
    patch current_group_path, params: {group_id: admin_group.id}

    allow(Rails.logger).to receive(:info).and_call_original
    expect { post admin_user_impersonation_path(user) }.not_to change { user.reload.attributes.slice("sign_in_count", "current_sign_in_at", "current_sign_in_ip") }
    expect(response).to redirect_to(root_path)
    expect(Rails.logger).to have_received(:info).with("Impersonation started: admin #{admin.id} as user #{user.id}")

    get root_path
    expect(inertia.props[:auth][:user][:id]).to eq(user.id)
    expect(inertia.props[:auth][:group][:id]).to eq(user.groups.order(:id).first.id)
    expect(inertia.props[:auth][:impersonator]).to eq({"name" => admin.display_name, "email" => "staff@example.com"})
    # The user isn't an admin, so the admin pages are hidden again
    get admin_users_path
    expect(response).to have_http_status(:not_found)
  end

  describe "while signed in as someone else" do
    before { impersonate }

    it "refuses changing the email or password and deleting the account" do
      patch user_registration_path, params: {user: {email: "new@example.com", current_password: "correct horse battery"}}
      expect(flash[:alert]).to eq("That's turned off while you're signed in as someone else.")
      expect(user.reload.unconfirmed_email).to be_nil

      expect { delete user_registration_path }.not_to change(User, :count)
      expect(flash[:alert]).to eq("That's turned off while you're signed in as someone else.")
    end

    it "refuses the test digest" do
      expect { post test_email_alerts_path }.not_to have_enqueued_mail(DigestMailer, :test_daily)
      expect(flash[:alert]).to eq("That's turned off while you're signed in as someone else.")
    end

    it "can't start another impersonation" do
      post admin_user_impersonation_path(create(:user))
      expect(response).to have_http_status(:not_found)
    end

    it "allows the user's settings" do
      patch settings_path, params: {user: {first_name: "Janet"}}
      expect(user.reload.first_name).to eq("Janet")
    end

    it "returns to admin in their own operation, on the user's admin page" do
      admin_group = admin.groups.sole
      expect { delete impersonation_path }.not_to change { admin.reload.sign_in_count }
      expect(response).to redirect_to(admin_user_path(user))

      get root_path
      expect(inertia.props[:auth][:user][:id]).to eq(admin.id)
      expect(inertia.props[:auth][:group][:id]).to eq(admin_group.id)
      expect(inertia.props[:auth][:impersonator]).to be_nil
      expect(session[:impersonator_id]).to be_nil
    end

    it "signs out if the admin is no longer one" do
      admin.update!(admin: false)
      delete impersonation_path
      expect(response).to redirect_to(new_user_session_path)
      get settings_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it "ends both on signing out" do
      delete destroy_user_session_path
      get settings_path
      expect(response).to redirect_to(new_user_session_path)
      expect(session[:impersonator_id]).to be_nil
    end

    it "ignores and clears a stale key once someone else is signed in" do
      sign_in admin # as remember-me does after the impersonated session times out
      get root_path
      expect(inertia.props[:auth][:user][:id]).to eq(admin.id)
      expect(inertia.props[:auth][:impersonator]).to be_nil
      expect(session[:impersonator_id]).to be_nil
    end
  end

  it "does nothing to return to when not signed in as someone else" do
    sign_in user
    get root_path
    delete impersonation_path
    expect(response).to redirect_to(root_path)
    get root_path
    expect(inertia.props[:auth][:user][:id]).to eq(user.id)
  end
end
