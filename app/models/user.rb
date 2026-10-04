class User < ApplicationRecord
  devise :database_authenticatable, :registerable, :recoverable, :rememberable,
    :validatable, :confirmable, :trackable, :timeoutable

  UNIT_SYSTEMS = %w[imperial metric].freeze
  MAGIC_LINK_TTL = 15.minutes
  SIGN_IN_CODE_ATTEMPTS = 5
  SIGN_IN_CODE_RESEND_AFTER = 60.seconds

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

  # A six-digit code sent with each sign-in link, for typing in on the device that asked for it
  # (e.g. the email is read on a phone). It shares the link's lifetime, works once, dies after
  # SIGN_IN_CODE_ATTEMPTS wrong guesses, and, like the link, stops working after any sign-in.
  # Requesting a new one replaces it. Returns the code; the caller emails it.
  def generate_sign_in_code!
    code = format("%06d", SecureRandom.random_number(1_000_000))
    update_columns(sign_in_code_digest: sign_in_code_digest_for(code), sign_in_code_sent_at: Time.current,
      sign_in_code_attempts: 0)
    code
  end

  # The resend cooldown; signing in (by any means) ends it
  def sign_in_code_recently_sent?
    sign_in_code_sent_at.present? && sign_in_code_sent_at > SIGN_IN_CODE_RESEND_AFTER.ago &&
      (current_sign_in_at.nil? || sign_in_code_sent_at > current_sign_in_at)
  end

  # True if the code matches the live one, which is then spent. Every try counts toward the
  # attempt limit; both updates are atomic so parallel guesses can't get past it.
  def redeem_sign_in_code!(code)
    return false unless sign_in_code_live?

    live = self.class.where(id:, sign_in_code_digest:)
    return false unless live.where(sign_in_code_attempts: ...SIGN_IN_CODE_ATTEMPTS)
      .update_all("sign_in_code_attempts = sign_in_code_attempts + 1") == 1

    given = sign_in_code_digest_for(code.to_s.gsub(/\D/, ""))
    ActiveSupport::SecurityUtils.secure_compare(given, sign_in_code_digest) &&
      live.update_all(sign_in_code_digest: nil) == 1
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

  # A new, empty group the user owns. Every account starts with one, and gets another if it's
  # removed from (or deletes) its last group.
  def create_personal_group
    transaction do
      group = Group.create!(name: "#{display_name}'s farms")
      memberships.create!(group:, owner: true)
    end
  end

  private

  def sign_in_code_live?
    sign_in_code_digest.present? && sign_in_code_sent_at > MAGIC_LINK_TTL.ago &&
      sign_in_code_attempts < SIGN_IN_CODE_ATTEMPTS &&
      (current_sign_in_at.nil? || sign_in_code_sent_at > current_sign_in_at)
  end

  def sign_in_code_digest_for(code)
    key = Rails.application.key_generator.generate_key("user sign-in code")
    OpenSSL::HMAC.hexdigest("SHA256", key, "#{id}:#{code}")
  end

  # Carried over from the legacy app, which saw spam sign-ups from these domains
  def email_domain_allowed
    errors.add(:email, "can't be from a .ru domain") if email.to_s.match?(/\.ru\z/i)
  end

  # Deleting an account deletes the farm data only it could reach; shared groups stay, and one
  # it was the only owner of passes to its longest-standing member
  def destroy_groups_left_empty
    memberships.includes(:group).find_each do |membership|
      group = membership.group
      others = group.memberships.where.not(id: membership.id)
      if others.none?
        group.destroy!
      elsif membership.owner? && others.owners.none?
        others.order(:created_at, :id).first.update!(owner: true)
      end
    end
  end
end
