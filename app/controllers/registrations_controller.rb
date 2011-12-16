# -*- encoding : utf-8 -*-
class RegistrationsController < ApplicationController
  prepend_before_filter :require_no_authentication, :only => [ :new, :create, :cancel ]
  prepend_before_filter :authenticate_scope!, :only => [:edit, :update, :destroy]
  include Devise::Controllers::InternalHelpers

  # GET /resource/sign_up
  def new
    set_seo_meta("注册")
    build_resource({})
    render_with_scope :new
  end

  # POST /resource
  def create
    if not Setting.allow_register
      render_404
      return false
    end

    build_resource    

    if resource.save
      if resource.active?
        set_flash_message :notice, :signed_up
        UserMailer.welcome(resource.id.to_s).deliver
        sign_in_and_redirect(resource_name, resource)
      else
        set_flash_message :notice, :inactive_signed_up, :reason => resource.inactive_message.to_s
        expire_session_data_after_sign_in!
        redirect_to after_inactive_sign_up_path_for(resource)
      end
    else
      clean_up_passwords(resource)
      render_with_scope :new
    end
  end

  # GET /resource/edit
  def edit
    set_seo_meta("个人设置")
    render_with_scope :edit
  end

  # PUT /resource
  def update
    param = params[resource_name]
    unless param[:password].blank?
      if param[:password]!=param[:password_confirmation]
        flash[:alert]='密码与确认密码不符'
        render_with_scope :edit
        return
      end
    end
    if resource.update_attributes(params[resource_name])
      set_flash_message :notice, :updated
      sign_in resource_name, resource, :bypass => true
      redirect_to edit_user_registration_path
    else
      #clean_up_passwords(resource)
      render_with_scope :edit
    end
  end

  # DELETE /resource
  def destroy
    resource.soft_delete
    sign_out_and_redirect("/login")
    set_flash_message :notice, :destroyed
  end

  # GET /resource/cancel
  # Forces the session data which is usually expired after sign
  # in to be expired now. This is useful if the user wants to
  # cancel oauth signing in/up in the middle of the process,
  # removing all OAuth session data.
  def cancel
    expire_session_data_after_sign_in!
    redirect_to new_registration_path(resource_name)
  end

  protected

    # Build a devise resource passing in the session. Useful to move
    # temporary session data to the newly created user.
    def build_resource(hash=nil)
      hash ||= params[resource_name] || {}
      self.resource = resource_class.new_with_session(hash, session)
    end

    # The path used after sign up. You need to overwrite this method
    # in your own RegistrationsController.
    def after_sign_up_path_for(resource)
      after_sign_in_path_for(resource)
    end

    # Overwrite redirect_for_sign_in so it takes uses after_sign_up_path_for.
    def redirect_location(scope, resource) #:nodoc:
      stored_location_for(scope) || after_sign_up_path_for(resource)
    end

    # The path used after sign up for inactive accounts. You need to overwrite
    # this method in your own RegistrationsController.
    def after_inactive_sign_up_path_for(resource)
      root_path
    end

    # The default url to be used after updating a resource. You need to overwrite
    # this method in your own RegistrationsController.
    def after_update_path_for(resource)
      if defined?(super)
        ActiveSupport::Deprecation.warn "Defining after_update_path_for in ApplicationController " <<
          "is deprecated. Please add a RegistrationsController to your application and define it there."
        super
      else
        after_sign_in_path_for(resource)
      end
    end

    # Authenticates the current scope and gets a copy of the current resource.
    # We need to use a copy because we don't want actions like update changing
    # the current user in place.
    def authenticate_scope!
      send(:"authenticate_#{resource_name}!", true)
      self.resource = resource_class.to_adapter.get!(send(:"current_#{resource_name}").to_key)
    end
end
