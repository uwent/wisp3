class User < ApplicationRecord
  devise :database_authenticatable, :registerable, :recoverable, :rememberable,
    :validatable, :confirmable, :trackable, :timeoutable

  UNIT_SYSTEMS = %w[imperial metric].freeze
  MAGIC_LINK_TTL = 15.minutes

  has_many :memberships, dependent: :destroy
  has_many :groups, through: :memberships

  validates :unit_system, inclusion: {in: UNIT_SYSTEMS}
  validates :first_name, :last_name, length: {maximum: 100}
  validate :email_domain_allowed

  after_create :create_personal_group
  before_destroy :destroy_groups_left_empty, prepend: true

  # Signing in updates current_sign_in_at (trackable), which invalidates every link issued
  # before it, so each link works once.
  generates_token_for :magic_login, expires_in: MAGIC_LINK_TTL do
    current_sign_in_at
  end

  def name
    [first_name, last_name].compact_blank.join(" ")
  end

  def display_name
    name.presence || email
  end

  # Called when a sign-in link is used: following a link sent to this address proves the
  # user controls it. Only applies to accounts that have never been confirmed; a pending
  # email *change* (unconfirmed_email) still needs its own confirmation.
  def confirm_by_magic_link!
    confirm unless confirmed? || unconfirmed_email.present?
  end

  private

  # Carried over from the legacy app, which saw spam sign-ups from these domains
  def email_domain_allowed
    errors.add(:email, "can't be from a .ru domain") if email.to_s.match?(/\.ru\z/i)
  end

  # Deleting an account deletes the farm data only it could reach; shared groups stay
  def destroy_groups_left_empty
    groups.each { |group| group.destroy! if group.memberships.count == 1 }
  end

  def create_personal_group
    transaction do
      group = Group.create!(name: "#{display_name}'s farms")
      memberships.create!(group:, admin: true)
    end
  end
end
