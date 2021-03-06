# coding: utf-8
class SearchController < ApplicationController

  def index
    # @asks = Ask.search_title(params["w"].to_s.strip,:limit => 20)
    set_seo_meta("关于“#{params[:w]}”的搜索结果")
    render "/asks/index"
  end

  def all
    result = Redis::Search.complete("Tag",params[:q].strip,:limit => 10,:sort_field=>'topics_count')
    if result.length < 10
      result += Redis::Search.complete("Topic",params[:q].strip,:limit => 10,:sort_field=>'followers_count')
      if result.length < 10
        result += Redis::Search.query("Ask",params[:q].strip,:limit => 10)
        if result.length < 10
          result += Redis::Search.complete("User",params[:q].strip,:limit => 10)
        end
      end
    end

#render text:result ;return
    
    lines = []
    result.each do |item|
if item['title'].length>55
item['title']=item['title'][0..54]
item['title']+='...'
end
      case item['type']
      when "Tag"
        lines << complete_line_tag(item)
      when "Ask"
        lines << complete_line_ask(item)
      when "User"
        lines << complete_line_user(item)
      when "Topic"
        lines << complete_line_topic(item)
      end
    end
    render :text => lines.join("\n")
  end

  def topics
    result = Redis::Search.complete("Topic",params[:q],:limit => 10)
    if params[:format] == "json"
      lines = []
      result.each do |item|
        lines << complete_line_topic(item)
      end
      render :text => lines.join("\n")
    else
      lines = []
      result.each do |item|
        lines << complete_line_topic(item)
      end
      render :text => lines.join("\n") 
    end
  end

  def asks
    result = Redis::Search.query("Ask",params[:q].strip,:limit => 10)
    puts result.inspect
    if params[:format] == "json"
      render :json => result.to_json
    else
      lines = []
      result.each do |item|
        lines << complete_line_ask(item)
      end
      render :text => lines.join("\n") 
    end
  end

  def users 
    params[:q] = params[:q].strip if params[:q]
    result = Redis::Search.complete("User",params[:q],:limit => 10)
    if params[:format] == "json"
      render :json => result.to_json
    else
      lines = []
      result.each do |item|
        lines << complete_line_user(item)
      end
      render :text => lines.join("\n") 
    end
  end

  private
    def complete_line_tag(item,hash=true)
      if hash
        item['title'] = item['title'].strip
        "#{item['title'].escape_javascript}#!##{item['topics_count']}#!#Tag"
      else
        item.name = item.name.strip
        "#{item.name}#!##{item.topics_count}#!#Tag"
      end
    end  
  
    def complete_line_ask(item,hash = true)
      if hash
        item['title'] = item['title'].strip
        "#{item['title'].escape_javascript}#!##{item['id']}#!##{item['topics'].join(',')}#!#Ask"
      else
        item.title = item.title.strip
        "#{item.title.gsub("\n",'')}#!##{item.id}#!##{item.topics.join(',')}#!#Ask"
      end
    end

    def complete_line_topic(item,hash = true)
      if hash
        item['title'] = item['title'].strip
        "#{item['title'].escape_javascript}#!##{item['followers_count']}#!##{item['cover_small']}#!#Topic"
      else
        item.name = item.name.strip
        "#{item.name}#!##{item.followers_count}#!##{item.cover_small}#!#Topic"
      end
    end

    def complete_line_user(item,hash = true)
      if hash
        item['title'] = item['title'].strip
        "#{item['title'].escape_javascript}#!##{item['id']}#!##{item['tagline']}#!##{item['avatar_small']}#!##{item['slug']}#!#User"
      else
        item.name = item.name.strip
        "#{item.name}#!##{item.id}#!##{item.tagline}#!##{item.avatar_small}#!##{item.slug}#!#User"
      end
    end

end
