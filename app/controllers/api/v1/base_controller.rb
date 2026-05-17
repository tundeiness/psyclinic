module Api
  module V1
    class BaseController < ApplicationController
      before_action :authenticate_user!

      private

      def current_client_profile
        @current_client_profile ||= current_user.client_profile
      end

      def current_therapist_profile
        @current_therapist_profile ||= current_user.therapist_profile
      end
    end
  end
end
