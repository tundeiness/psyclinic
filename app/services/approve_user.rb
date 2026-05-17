# Admin action: approve a pending user. Idempotent-ish — calling it on an
# already-approved user is a no-op success.
class ApproveUser
  Result = Struct.new(:success?, :user, :error, keyword_init: true)

  def self.call(...) = new(...).call

  def initialize(user:)
    @user = user
  end

  def call
    return Result.new(success?: false, error: "Cannot approve an admin") if @user.admin?
    return Result.new(success?: true, user: @user) if @user.approved?

    @user.update!(status: :approved)

    Notify.call(
      user: @user,
      kind: "application_approved",
      title: "Your application was approved",
      body: "You can now sign in and use your account."
    )
    UserMailer.application_approved(@user).deliver_later

    Result.new(success?: true, user: @user)
  rescue ActiveRecord::RecordInvalid => e
    Result.new(success?: false, error: e.message)
  end
end
