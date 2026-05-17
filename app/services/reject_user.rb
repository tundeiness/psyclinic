# Admin action: reject a pending user.
class RejectUser
  Result = Struct.new(:success?, :user, :error, keyword_init: true)

  def self.call(...) = new(...).call

  def initialize(user:)
    @user = user
  end

  def call
    return Result.new(success?: false, error: "Cannot reject an admin") if @user.admin?
    return Result.new(success?: true, user: @user) if @user.rejected?

    @user.update!(status: :rejected)

    Notify.call(
      user: @user,
      kind: "application_rejected",
      title: "Your application was not approved",
      body: "Please contact support if you believe this was a mistake."
    )
    UserMailer.application_rejected(@user).deliver_later

    Result.new(success?: true, user: @user)
  rescue ActiveRecord::RecordInvalid => e
    Result.new(success?: false, error: e.message)
  end
end
