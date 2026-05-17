class ApplicationController < ActionController::API
  include ActionController::MimeResponds

  rescue_from CanCan::AccessDenied do |e|
    render json: { error: "Forbidden", detail: e.message }, status: :forbidden
  end

  rescue_from ActiveRecord::RecordNotFound do
    render json: { error: "Not found" }, status: :not_found
  end

  rescue_from ActiveRecord::RecordInvalid do |e|
    render json: { error: "Validation failed", details: e.record.errors.full_messages },
      status: :unprocessable_entity
  end

  rescue_from ActionController::ParameterMissing do |e|
    render json: { error: "Bad request", detail: e.message }, status: :bad_request
  end

  def current_ability
    @current_ability ||= Ability.new(current_user)
  end

  private

  def render_error(message, status: :unprocessable_entity)
    render json: { error: message }, status: status
  end
end
