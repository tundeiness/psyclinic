# This app is a JSON API. Clients send already-structured JSON
# (e.g. {"user": {...}}), so Rails' automatic ParamsWrapper — which
# re-wraps the body under the controller-derived key — only causes
# duplicate/conflicting params (notably breaking Devise's
# SessionsController credential extraction). Disable it globally.
ActiveSupport.on_load(:action_controller) do
  wrap_parameters format: []
end
