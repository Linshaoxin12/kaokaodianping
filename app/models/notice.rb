class Notice
  include Mongoid::Document
  include Mongoid::Timestamps

  field :body
  field :end_at, :type => DateTime

  index :end_at
end
