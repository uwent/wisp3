class MembershipMailer < ApplicationMailer
  # Tells someone an owner added them to a farm operation
  def added(membership, added_by)
    @user = membership.user
    @group = membership.group
    @added_by = added_by
    @owner = membership.owner?
    @url = root_url
    mail to: @user.email, subject: "You've been added to #{@group.name} on WISP"
  end
end
