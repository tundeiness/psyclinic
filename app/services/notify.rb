# Central place to raise an in-app notification for a user. Email is sent
# separately by the caller via the relevant mailer so notification
# creation stays synchronous and side-effect-light.
class Notify
  def self.call(user:, kind:, title:, body: nil, subject: nil)
    Notification.create!(
      user: user,
      kind: kind,
      title: title,
      body: body,
      subject_type: subject&.class&.name,
      subject_id: subject&.id
    )
  end
end
