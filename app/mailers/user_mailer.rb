class UserMailer < ApplicationMailer
  def application_pending(user)
    @user = user
    mail(to: @user.email, subject: "Your PsyClinic application is pending review")
  end

  def application_approved(user)
    @user = user
    mail(to: @user.email, subject: "Your PsyClinic application has been approved")
  end

  def application_rejected(user)
    @user = user
    mail(to: @user.email, subject: "Update on your PsyClinic application")
  end
end
