# coding: UTF-8
class AsksController < ApplicationController
  before_filter :require_user, :only => [:answer,:create,:new]
  before_filter :require_user_js, :only => [:answer,:invite_to_answer]
  before_filter :require_user_text, :only => [:update_topic,:redirect,:spam, :mute, :unmute, :follow, :unfollow]
  
  def index
    @per_page = 20
    @asks = Ask.where(:type=>nil).normal.recent.includes(:user).paginate(:page => params[:page], :per_page => @per_page)
    set_seo_meta("所有点评")
  end

  def search
    # @asks = Ask.search_title(params["w"],:limit => 20)[:items]
    set_seo_meta("关于“#{params[:w]}”的搜索结果")
    render "index"
  end

  def show
    begin
      @ask = Ask.where(_id:BSON::ObjectId(params[:id])).first
    rescue => e
      render_404
      return
    end
    
    if !@ask
      render_404
      return
    end
    @ask.view!

    if !@ask.redirect_ask_id.blank?
      if params[:nr].blank?
        # 转向点评
        redirect_to ask_path(@ask.redirect_ask_id,:rf => params[:id], :nr => "1")
        return
      else
        @r_ask = Ask.find(@ask.redirect_ask_id)
      end
    end

    if params[:rf]
      @rf_ask = Ask.find(params[:rf])
      if !@ask.redirect_ask_id.blank?
        @r_ask = Ask.find(@ask.redirect_ask_id)
      end
    end
    
    # 由于 voteable_mongoid 目前的按 votes_point 排序有点评，没投过票的无法排序
    @answers = @ask.answers.includes(:user).order_by(:spams_count.asc,:"votes.uc".desc,:"votes.dc".asc,:"created_at".asc)
    @answer = Answer.new
    # 推荐话题,如果没有设置话题的话
    @suggest_topics = AskSuggestTopic.find_by_ask(@ask)
    set_seo_meta(@ask.title)

    respond_to do |format|
      format.html # show.html.erb
      format.json
    end
  end

  def redirect
    return render :text => "-2" if params[:id] == params[:new_id]
    @ask = Ask.find(params[:id])
    if params[:cancel].blank?
      render :text => @ask.redirect_to_ask(params[:new_id])
    else
      @ask.redirect_cancel
      render :text => "1"
    end
  end

  def share
    @ask = Ask.find(params[:id])
    if request.get?
#      if current_user
        render "share", :layout => false
#      else
#        render_404
#      end
    else
      case params[:type]
      when "email"
        UserMailer.simple(params[:to], params[:subject], params[:body].gsub("\n","<br />")).deliver
        @success = true
        @msg = "已经将点评连接发送到了 #{params[:to]}"
      end
    end

  end

  def answer
    @answer = Answer.new(params[:answer])
    @answer.ask_id = params[:id]
    @answer.user_id = current_user.id

    @answer.body = simple_format(@answer.body.strip) if params[:did_editor_content_formatted] == "no"

    if @answer.save 
      @success = true
    else
      @success = false
    end
    respond_to do |format|
      format.html{redirect_to "/asks/#{@answer.ask.id}"}
      format.js
    end
  end

  def spam 
    @ask = Ask.find(params[:id])
    size = 1
    if(Setting.admin_emails.include?(current_user.email))
      size = Setting.ask_spam_max
    end
    count = @ask.spam(current_user.id,size)
    render :text => count
  end

  def follow
    @ask = Ask.find(params[:id])
    if params[:follow].blank?
      follow = false
    else
      follow = true
    end
    res = current_user.follow_ask(@ask,follow)
    render :text => res
  end
  
  def new
    @ask = Ask.new

    respond_to do |format|
      format.html # new.html.erb
      format.json
    end
  end
  
  def edit
    @ask = Ask.find(params[:id])
  end
  
  def create
    @ask = Ask.where(title:params[:ask][:title],topic:params[:topic]).first
    params_ask_to_user_id = nil
    if(!params[:onlyhim])
      # PSVR>
      # in which circumstances
      # it should be made like create and invite
      params_ask_to_user_id = params[:ask][:to_user_id]
      params[:ask][:to_user_id] = nil
    end
    if @ask and (!(params[:ask][:to_user_id]||@ask.to_user_id) || @ask.to_user_id==params[:ask][:to_user_id])
      flash[:notice] = "已有相同的点评存在。"
      redirect_to ask_path(@ask.id)
      return 
    end
    @ask = Ask.new(params[:ask])
    if params_ask_to_user_id
      @touser = User.where(_id:params_ask_to_user_id).first
      @ask.title = "#{current_user.name}请问#{@touser.name}，#{@ask.title}"
    end
    @ask.user_id = current_user.id
    @ask.followers << current_user
    @ask.topics << params[:topic]
    unless params[:topic].blank?
      @ask.title = "#{current_user.name}问[#{params[:topic]}]： " + @ask.title
    end
    @ask.current_user_id = current_user.id
    
    respond_to do |format|
      if @ask.save
        if(params_ask_to_user_id)
          @invite = AskInvite.invite(@ask.id, params_ask_to_user_id, current_user.id)
        end

        AskSuggestTopic.find_by_ask(@ask).each do |name|
          @ask.update_topics(name,"1",current_user.id)
        end
        format.html { redirect_to(ask_path(@ask.id), :notice => '问题创建成功。') }
        format.json
      else
        format.html { render :action => "new" }
        format.json
      end
    end
  end
  
  def update
    @ask = Ask.find(params[:id])
    @ask.current_user_id = current_user.id

    respond_to do |format|
      if @ask.update_attributes(params[:ask])
        format.html { redirect_to(ask_path(@ask.id), :notice => '点评更新成功。') }
        format.json
      else
        format.html { render :action => "edit" }
        format.json
      end
    end
  end

  def update_topic
    @name = params[:name].strip
    @add = params[:add] == "1" ? true : false

    @ask = Ask.find(params[:id])
    if @ask.update_topics(@name,@add,current_user.id)
    current_user.follow_topic(Topic.find_by_name(@name))
      @success = true
    else
      @success = false
    end
    if not @add
      render :text => @success
    end
  end

  def mute
    @ask = Ask.find(params[:id])
    if not @ask
      render :text => "0"
      return
    end
    current_user.mute_ask(@ask.id)
    render :text => "1"
  end
  
  def unmute
    @ask = Ask.find(params[:id])
    if not @ask
      render :text => "0"
      return
    end
    current_user.unmute_ask(@ask.id)
    render :text => "1"
  end
  
  def follow
    @ask = Ask.find(params[:id])
    if not @ask
      render :text => "0"
      return
    end
    current_user.follow_ask(@ask)
    render :text => "1"
  end
  
  def unfollow
    @ask = Ask.find(params[:id])
    if not @ask
      render :text => "0"
      return
    end
    current_user.unfollow_ask(@ask)
    render :text => "1"
  end

  def invite_to_answer
    drop = params[:drop] == "1" ? true : false
    if drop
      @id=params[:i_id]
      @ask= AskInvite.cancel(params[:i_id], current_user.id)
      render :action=>'invite_to_answer_drop'
    else
      if (current_user.id.to_s != params[:user_id].to_s)
        @invite = AskInvite.invite(params[:id], params[:user_id], current_user.id)
        @success = true
      else
        @success = false
      end
    end
  end
  
end
