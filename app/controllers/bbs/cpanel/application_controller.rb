# coding: utf-8  
class Bbs::Cpanel::ApplicationController < BbsController
  layout "bbs_cpanel"
  before_filter :require_user
  before_filter :require_admin
  
  def require_admin
    if not Setting.admin_emails.index(current_user.email)
      render_404
    end
  end
end
