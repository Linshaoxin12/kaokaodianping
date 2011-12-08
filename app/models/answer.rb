# coding: utf-8
require 'nokogiri'
class Answer
  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::Voteable


  # 投票对应的分数
  voteable self, :up => +1, :down => -1

  field :body
  field :comments_count, :type => Integer, :default => 0

  belongs_to :ask, :inverse_of => :answers, :counter_cache => true
  belongs_to :user, :inverse_of => :answers, :counter_cache => true
  has_many :logs, :class_name => "Log", :foreign_key => "target_id"

  index :ask_id
  index :user_id
  
  field :spams_count, :type => Integer, :default => 0
  
  # 正常可显示的点评, 前台调用都带上这个过滤
  scope :normal, where(:spams_count.lt => Setting.answer_spam_max)
  def is_normal?
    spams_count < Setting.answer_spam_max
  end

  field :spam_voter_ids, :type => Array, :default => []
  
  has_many :comments, :conditions => {:commentable_type => "Answer"}, :foreign_key => "commentable_id", :class_name => "Comment",dependent: :destroy

  scope :recent, desc("created_at")  
  validates_presence_of :user_id, :body
  validates_uniqueness_of :user_id, :scope => [:ask_id]
  validates_length_of :body,:maximum=>2000
  validate :check_to_user
  def check_to_user
    ask = self.ask
    if !ask.to_user.blank? and self.user_id != ask.to_user_id
      errors.add_to_base('这个点评是定向提问，您不是提问对象故不能点评')
    end
  end
  # 支持者
  def up_voters
    # TODO: 这里需要加上缓存
    ids = self.up_voter_ids[0,(self.up_voter_ids.count > 30 ? 30 : self.up_voter_ids.count)]
    items = User.find(ids)
    items.sort { |y,x| x.score <=> y.score }
  end

  # 敏感词验证
  before_validation :check_spam_words
  def check_spam_words
    if self.spam?("body")
      return false
    end
  end

  after_create :mail_deliver_new_answer
  after_create :increase_answers_count
  def increase_answers_count
    topic = Topic.where(name:self.ask.jigou).first
    if topic
      topic.answers_count += 1
      topic.save!
    end
  end
  def mail_deliver_new_answer
    UserMailer.new_answer_to_followers(self.id)
  end
  
  def chomp_body(length=3000,opts={})
    if opts[:nobr]
      chomped = Nokogiri.HTML(self.body).text().split("\n").join('　')
    else
      chomped = self.body
    end
    while chomped =~ /<div><br><\/div>$/i
      chomped = chomped.gsub(/<div><br><\/div>$/i, "")
    end
    if chomped.length>length
      chomped = chomped[0..length-1]
      chomped += '...'
    end
    return chomped
  end

  # 没有帮助
  def spam(voter_id,size = 1)
    self.spams_count ||= 0
    self.spam_voter_ids ||= []
    # 限制 spam ,一人一次
    return self.spams_count if self.spam_voter_ids.index(voter_id)
    self.spams_count += size
    self.spam_voter_ids << voter_id
    self.save()
    return self.spams_count
  end

  after_create :save_to_ask_and_update_answered_at
  before_update :log_update
  
  def log_update
    insert_action_log("EDIT") if self.body_changed?
  end
  
  def save_to_ask_and_update_answered_at
    self.ask.update_attributes({:answered_at => self.created_at, 
                               :last_answer_id => self.id,
                               :last_answer_user_id => self.user_id, 
                               :current_user_id => self.user_id })
    self.ask.inc(:answers_count,1)
    
    # 回答默认关注点评
    self.user.follow_ask(self.ask) if !self.user.ask_followed?(self.ask)
    
    # 保存用户回答过的点评列表
    if !self.user.answered_ask_ids.index(self.ask_id)
      self.user.answered_ask_ids << self.ask_id
      self.user.save
    end

    insert_action_log("NEW")
  end
  
  include BaseModel  
  protected
  
    def insert_action_log(action)
      begin
        log = AnswerLog.new
        log.user_id = self.user_id
        log.title = self.body
        log.answer = self
        log.target_id = self.id
        log.target_attr = self.body_changed? ? "BODY" : "" if action == "EDIT"
        log.action = action
        log.target_parent_id = self.ask_id
        log.target_parent_title = self.ask.title
        log.diff = ""
        log.save
      rescue Exception => e
        
      end
      
    end
  
end
