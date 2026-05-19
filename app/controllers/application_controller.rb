class ApplicationController < ActionController::API
  include ActionController::MimeResponds

  # All error responses share a stable shape so the frontend can branch
  # reliably and redirect (e.g. 403/404 -> a "no access" / not-found
  # screen). Keys: error (human text), code (machine-readable), plus
  # optional detail/details. Existing keys are preserved.
  #
  # NOTE: permission failures return 403 (authenticated but not allowed).
  # To instead MASK a sensitive resource as 404 in a specific controller,
  # rescue CanCan::AccessDenied there and call
  #   render_api_error(code: "not_found", message: "Not found", status: :not_found)
  rescue_from CanCan::AccessDenied do |e|
    render_api_error(code: "forbidden",
      message: "You do not have permission to perform this action.",
      status: :forbidden, detail: e.message)
  end

  rescue_from ActiveRecord::RecordNotFound do
    render_api_error(code: "not_found",
      message: "The requested resource was not found.",
      status: :not_found)
  end

  rescue_from ActiveRecord::RecordInvalid do |e|
    render json: {
      error: "Validation failed", code: "validation_failed",
      details: e.record.errors.full_messages
    }, status: :unprocessable_entity
  end

  rescue_from ActionController::ParameterMissing do |e|
    render_api_error(code: "bad_request", message: "Bad request",
      status: :bad_request, detail: e.message)
  end

  def current_ability
    @current_ability ||= Ability.new(current_user)
  end

  # Catch-all for unknown API routes (wired in routes.rb) so a bad URL
  # returns the same JSON shape instead of Rails' HTML 404 page.
  def route_not_found
    render_api_error(code: "not_found",
      message: "The requested resource was not found.",
      status: :not_found)
  end

  private

  def render_api_error(code:, message:, status:, detail: nil)
    body = { error: message, code: code }
    body[:detail] = detail if detail
    render json: body, status: status
  end

  def render_error(message, status: :unprocessable_entity)
    render json: { error: message, code: "error" }, status: status
  end
end
