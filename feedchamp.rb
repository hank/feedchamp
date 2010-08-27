require 'rubygems'
require 'camping'
require 'yaml'
require 'fileutils'
require 'simple-rss'
require 'net/http'
require 'time'

Camping.goes :FeedChamp

FeedChamp::Models::Base.logger = Logger.new('feedchamp.log')
FeedChamp::Models::Base.logger.level = Logger::WARN

class << FeedChamp
  def root
    File.dirname(__FILE__)
  end 
   
  def config
    @config ||= YAML.load(IO.read(File.join(root, 'config.yml'))).symbolize_keys
  end
  
  def feeds
    config[:feeds]
  end
  
  def title
    config[:title]
  end
  
  def feed
    config[:external_feed] || '/feed.xml'
  end
  
  def id
    config[:id]
  end
  
  def author
    config[:author] || title
  end

end

module FeedChamp::Models
  class Cache
    cattr_accessor :cache_directory
    self.cache_directory = File.join(FeedChamp.root, "cache")

    cattr_accessor :expire_time
    self.expire_time = 2.hours
    
    cattr_accessor :logger
    self.logger = FeedChamp::Models::Base.logger
    
    def self.rss_for(url)
      SimpleRSS.parse(File.read(filename_for(url)))
    end
    
    def self.filename_for(url)
      File.join(cache_directory, url.tr(':/', '_'))
    end

    def self.check_for_updates(url)
      filename = filename_for(url)
      FileUtils.mkpath(File.dirname(filename))
      last_modified = (File.exist?(filename) ? File.mtime(filename) : Time.at(0))
      if expire_time.ago > last_modified
        uri = URI::parse(url)
        http = Net::HTTP.start(uri.host, uri.port)
        response = http.get(uri.request_uri, "If-Modified-Since" => last_modified.httpdate)
        case response.code
        when '304'
          FileUtils.touch(filename)
          false
        when '200'
          open(filename, 'w') { |f| f.write(response.body) }
          true
        else
          logger.error("Invalid response code #{response.code} for feed <#{url}>")
          false
        end
      else
        false
      end
    end
  end

  class Entry < Base
    class << self
      def find_recent(limit = 50, hidden = false, starred = false)
        conditions = {}
        if !hidden 
          conditions[:hidden] = false
        end
        if starred
          conditions[:starred] = true
        end
        find(:all, :limit => limit, :order => "updated DESC", 
             :conditions => conditions)
      end
      def process_feeds(feeds = FeedChamp.feeds)
        feeds.each do |feed|
          begin
            process_feed(Cache.rss_for(feed)) if Cache.check_for_updates(feed)
          rescue SimpleRSSError => e
            logger.error("#{e} <#{feed}>")
          end
        end
      end  
      def process_feed(rss)
        rss.items.each do |item|
          unless Entry.exists?(guid_for(item))
            Entry.create(
              :title => item.title,
              :content => fix_content(item.content || item.content_encoded || 
                          item.description || item.summary, rss.feed.link),
              :author => item.author || item.contributor || item.dc_creator,
              :link => item.link,
              :updated => item.updated || item.published || item.pubDate,
              :guid => guid_for(item),
              :site_link => rss.feed.link,
              :site_title => rss.feed.title
            )
          end
        end
      end
      def exists?(guid)
        !!find_by_guid(guid)
      end
      def guid_for(item)
        return item[:id] if item[:id]
        (%r{^(http|urn|tag):}i =~ item.guid ? item.guid : item.link)
      end
      def fix_content(content, site_link)
        return content if content.nil?
        content = CGI.unescapeHTML(content) unless /</ =~ content
        correct_urls(content, site_link)
      end
      def correct_urls(text, site_link)
        site_link += '/' unless site_link[-1..-1] == '/'
        text.gsub(%r{(src|href)=(['"])(?!http)([^'"]*?)}) do
          first_part = "#{$1}=#{$2}" 
          url = $3
          url = url[1..-1] if url[0..0] == '/'
          "#{first_part}#{site_link}#{url}"
        end
      end
    end
  end
  
  class CreateTheBasics < V 1.0
    def self.up
      create_table :feedchamp_entries, :force => true do |t|
        t.column :id,           :integer,  :null => false
        t.column :title,        :string
        t.column :description,  :text
        t.column :author,       :string
        t.column :link,         :string
        t.column :date,         :date
        t.column :guid,         :string
        t.column :site,         :string
      end
    end
    def self.down
      drop_table :feedchamp_entries
    end
  end

  class ImproveSiteHandling < V 1.1
    def self.up
      rename_column :feedchamp_entries, :site, :site_link
      add_column :feedchamp_entries, :site_title, :string
      Entry.delete_all
    end
    def self.down
      remove_column :feedchamp_entries, :site_title
      rename_column :feedchamp_entries, :site_link, :site
    end
  end
  
  class SwitchDateToUpdated < V 1.2
    def self.up
      remove_column :feedchamp_entries, :date
      add_column :feedchamp_entries, :updated, :datetime
      Entry.delete_all
    end
    def self.down
      remove_column :feedchamp_entries, :updated
      add_column :feedchamp_entries, :date, :date
      Entry.delete_all
    end
  end
  
  class CleanUpNaming < V 1.3
    def self.up
      rename_column :feedchamp_entries, :description, :content
    end
    def self.down
      rename_column :feedchamp_entries, :content, :description
    end
  end

  class AddFlags < V 1.4
    def self.up
      add_column :feedchamp_entries, :read, :boolean, :default => false
      add_column :feedchamp_entries, :starred, :boolean, :default => false
      add_column :feedchamp_entries, :hidden, :boolean, :default => false
    end
    def self.down
      remove_column :feedchamp_entries, :read
      remove_column :feedchamp_entries, :starred
      remove_column :feedchamp_entries, :hidden
    end
  end
end

module FeedChamp::Controllers
  class Index < R '/'
    def get
      Entry.process_feeds
      unless @input['num'].nil?
        @num = @input['num']
      else
        @num = 50
      end
      @entries = Entry.find_recent(@num, false)
      @unread = true
      render :index
    end
  end

  class All < R '/all'
    def get
      Entry.process_feeds
      unless @input['num'].nil?
        @num = @input['num']
      else
        @num = 50
      end
      @entries = Entry.find_recent(@num, true, false)
      @all = true
      render :index
    end
  end

  class Starred < R '/starred'
    def get
      Entry.process_feeds
      unless @input['num'].nil?
        @num = @input['num']
      else
        @num = 50
      end
      @entries = Entry.find_recent(@num, false, true)
      render :index
    end
  end

  class Read < R '/read/(\d+)'
    def get(id)
      e = Entry.find(id)
      e.read = true;
      e.save
      "Entry #{id} read."
    end
  end

  class Star < R '/star/(\d+)'
    def get(id)
      e = Entry.find(id)
      e.starred = true;
      e.save
      "Entry #{id} starred."
    end
  end

  class Unstar < R '/unstar/(\d+)'
    def get(id)
      e = Entry.find(id)
      e.starred = false;
      e.save
      "Entry #{id} unstarred."
    end
  end

  class Clear < R '/clear'
    def get 
      en = Entry.find(:all, :conditions => { :read => true} )
      en.each {|e| e.hidden = true; e.save}
    end
  end
  
  class Feed < R '/feed.xml'
    def get
      Entry.process_feeds
      @entries = Entry.find_recent(15, false)
      @headers["Content-Type"] = "application/atom+xml; charset=utf-8"
      render :feed
    end
  end

  class JQuery < R '/jquery.js'
    def get
      sendfile("text/javascript; charset=utf-8", "jquery.js")
    end
  end

  class StarIcon < R '/star.png'
    def get
      sendfile("image/png", "star.png")
    end
  end

  class DarkStarIcon < R '/darkstar.png'
    def get
      sendfile("image/png", "darkstar.png")
    end
  end

  class LoadlJS < R '/local.js'
    def get
      sendfile("text/javascript; charset=utf-8", "local.js")
    end
  end
  
  class Style < R '/styles.css'
    def get
      sendfile("text/css; charset=utf-8", "styles.css")
    end
  end

  # Privates...
  def sendfile(content_type, filename)
    current_dir = File.expand_path(File.dirname(__FILE__))
    @headers['Content-Type'] = content_type
    @headers['X-Sendfile'] = "#{current_dir}/#{filename}"
  end
end

module FeedChamp::Views
  def index
    html do
      head do
        title FeedChamp.title
        link :rel => 'stylesheet', :type => 'text/css', :href => '/styles.css', :media => 'screen'
        link :href => FeedChamp.feed, :rel => "alternate", :title => "Primary Feed", 
             :type => "application/atom+xml"
        script :src => 'jquery.js'
        script :src => 'local.js'
      end
      body do
        div.header! do
          h1 { a(FeedChamp.title, :href => "/") }
          if @all
            span.menu{ a("Unread", :href => "/") }
          elsif @unread
            span.menu{ a("All", :href => "/all") }
          else
            span.menu{ a("Unread", :href => "/") }
            span.menu{ a("All", :href => "/all") }
          end
          span.menu{ a("Starred", :href => '/starred') }
          span.menu{ a("Clear Read", :href => "javascript:void(0);", 
                                     :onclick => 'clear_read();') }
          span.menu{"Entries: "}
          select(:id => 'num') do
            option(@num.to_i == 10 ? {:selected => true} : {}){ "10" }
            option(@num.to_i == 50 ? {:selected => true} : {}){ "50" }
            option(@num.to_i == 100 ? {:selected => true} : {}){ "100" }
          end
        end
        div.content! do
          @entries.each do |entry|
            a(:name => 'anchor'+entry.id.to_s)
            div(:id => 'entry'+entry.id.to_s, 
                :class => entry.read ? 'entry read' : 'entry') do
              p do
                i = [span.date(entry.updated.strftime('%B %d, %Y'))]
                i << span.site_title{entry.site_title}
                i << span.title{a(entry.title, :href => "javascript:read('#{entry.id}');")}
                i << img(:src => entry.starred ? "star.png" : "darkstar.png", 
                         :onclick => "toggle_star(#{entry.id})", :id => "star#{entry.id}")
                i << a.orig_link(CGI.unescapeHTML("Original"), :href => entry.link)
                i.join(" ")
              end
              div.details(:id => "details"+entry.id.to_s, :style => 'display: none;') do
                 p.info do
                   "by #{extract_author(entry.author)}" if entry.author
                 end
                 text entry.content.to_s
               end
            end
          end
        end
      end
    end
  end
  
  def feed
    text %(<?xml version="1.0" encoding="utf-8"?>)
    text %(<feed xmlns="http://www.w3.org/2005/Atom">)
    text %(  <id>#{FeedChamp.id}</id>)
    text %(  <title>#{FeedChamp.title}</title>)
    text %(  <updated>#{@entries.first.updated.to_time.xmlschema}</updated>)
    text %(  <author><name>#{FeedChamp.author}</name></author>)
    text %(  <link href="http:#{URL().to_s}"/>)
    text %(  <link rel="self" href="http:#{URL('/feed.xml').to_s}"/>)
    text %(  <generator>FeedChamp</generator>)
    @entries.each do |entry|
      text %(  <entry>)
      text %(    <id>#{entry.guid.to_s}</id>)
      text %(    <title>#{entry.title.to_s}</title>)
      text %(    <updated>#{entry.updated.to_time.xmlschema}</updated>)
      text %(    <author><name>#{entry.author.to_s}</name></author>) if entry.author
      text %(    <content type="html">#{CGI.escapeHTML(entry.content.to_s)}</content>)
      text %(    <link rel="alternate" href="#{entry.link.to_s}"/>)
      text %(  </entry>)
    end
    text %(</feed>)
  end
  
  private
    def extract_author(author)
      if author =~ /\((.*?)\)/
        $1
      else
        author
      end
    end
    
    def text(t)
      super("#{t}\n")
    end
end

def FeedChamp.create
  FeedChamp::Models.create_schema :assume => (FeedChamp::Models::Entry.table_exists? ? 1.0 : 0.0)
end
