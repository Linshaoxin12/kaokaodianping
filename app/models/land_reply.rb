# coding: utf-8  
class LandReply
  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::SoftDelete

  field :body
  field :source  
  field :message_id
  
  belongs_to :user, :inverse_of => :replies
  belongs_to :topic, :class_name => 'LandTopic',:foreign_key=>'topic_id', :inverse_of => :replies
  
  attr_protected :user_id, :topic_id

  validates_presence_of :body
  scope :recent, :order => "id desc"
  after_create :update_parent_last_replied
  def update_parent_last_replied
    self.topic.replied_at = Time.now
    self.topic.last_reply_user_id = self.user_id
    self.topic.replies_count = self.topic.replies.count
    self.topic.save
    # 清除用户读过记录
    self.topic.clear_user_readed
  end
  
  def self.cached_count
    return Rails.cache.fetch("replies/count",:expires_in => 1.hours) do
      self.count
    end
  end
end
