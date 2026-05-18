# Serializes Active Storage attachments to relative URLs. Using
# only_path: true avoids depending on default_url_options[:host], which
# is brittle in an API-only app. The frontend prefixes its API origin.
module AttachmentSerializer
  module_function

  def one(attachment)
    return nil unless attachment&.attached?

    {
      filename: attachment.filename.to_s,
      content_type: attachment.content_type,
      byte_size: attachment.byte_size,
      url: blob_path(attachment)
    }
  end

  def many(attachments)
    return [] unless attachments

    attachments.map do |a|
      {
        id: a.id,
        filename: a.filename.to_s,
        content_type: a.content_type,
        byte_size: a.byte_size,
        url: blob_path(a)
      }
    end
  end

  def blob_path(attachment)
    Rails.application.routes.url_helpers.rails_blob_path(
      attachment, only_path: true
    )
  rescue StandardError
    nil
  end
end
