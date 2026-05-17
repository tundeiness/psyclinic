# A delivery method that writes the full email to the Rails logger
# instead of sending it. Used in development so emails are observable
# via `docker compose logs web` with no SMTP server or extra gems.
class LoggerDelivery
  def initialize(settings = {})
    @settings = settings
  end

  def deliver!(mail)
    Rails.logger.info(<<~EMAIL)
      \n========== OUTGOING EMAIL ==========
      To:      #{mail.to&.join(', ')}
      From:    #{mail.from&.join(', ')}
      Subject: #{mail.subject}
      ------------------------------------
      #{mail.body.decoded}
      ====================================
    EMAIL
    mail
  end
end

ActiveSupport.on_load(:action_mailer) do
  ActionMailer::Base.add_delivery_method :logger_delivery, LoggerDelivery
end
