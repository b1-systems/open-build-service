class Issue < ActiveRecord::Base
  has_many :db_package_issues, :foreign_key => 'issue_id', :dependent => :destroy
  has_one :owner, :class_name => "User", :foreign_key => 'id'
  belongs_to :issue_tracker

  def self.get_by_name_and_tracker( name, issue_tracker_name, force_update=nil )
    issue_tracker = IssueTracker.find_by_name( issue_tracker_name )
    raise IssueTrackerNotFoundError.new( "Error: Issue Tracker '#{issue_tracker_name}' not found." ) unless issue_tracker

    issue = Issue.find_by_name name, :conditions => [ "issue_tracker_id = BINARY ?", issue_tracker.id ]
    raise IssueNotFoundError.new( "Error: Issue '#{name}' not found." ) unless issue
    
    if force_update
      issue.fetch_updates
      return Issue.find_by_name name, :conditions => [ "issue_tracker_id = BINARY ?", issue_tracker.id ]
    end

    return issue
  end

  def self.find_or_create_by_name_and_tracker( name, issue_tracker_name, force_update=nil )
    return self.find_by_name_and_tracker( name, issue_tracker_name, force_update=force_update, create_missing=true )
  end

  def self.find_by_name_and_tracker( name, issue_tracker_name, force_update=nil, create_missing=nil )
    issue_tracker = IssueTracker.find_by_name( issue_tracker_name )
    raise IssueTrackerNotFoundError.new( "Error: Issue Tracker '#{issue_tracker_name}' not found." ) unless issue_tracker

    # find existing
    issue = Issue.find_by_name name, :conditions => [ "issue_tracker_id = BINARY ?", issue_tracker.id ]

    # create missing
    issue = Issue.create( :name => name, :issue_tracker => issue_tracker ) if issue.nil? and create_missing

    # force update
    if force_update and not issue.nil?
      issue.fetch_updates
      return Issue.find_by_name name, :conditions => [ "issue_tracker_id = BINARY ?", issue_tracker.id ]
    end

    return issue
  end

  def self.states
    {
        'OPEN' => 1,
        'CLOSED' => 2,
        'UNKNOWN' => 3,
    }
  end

  def self.bugzilla_state( string )
    return self.states['OPEN'] if [ 'NEW', 'NEEDINFO', 'REOPENED', 'ASSIGNED' ].include? string
    return self.states['CLOSED'] if [ 'RESOLVED', 'CLOSED', 'VERIFIED' ].include? string
    return self.states['UNKNOWN']
  end

  def after_create
    # inject update job after issue got created
    require 'workers/fetch_issues.rb'
    Delayed::Job.enqueue FetchIssues.new
  end

  def fetch_updates
    # FIXME: dependency cycle, but not better solvable because multiple issues
    #        may get fetched ?
    self.issue_tracker.fetch_issues([self]) if self.issue_tracker.enable_fetch
  end

  def label
    return self.issue_tracker.label.gsub('@@@', self.name)
  end

  def render_body(node, change=nil)
    p={}
    p[:change] = change if change
    node.issue(p) do |issue|
      issue.created_at(self.created_at)
      issue.updated_at(self.updated_at)   if self.updated_at
      issue.name(self.name)
      issue.tracker(self.issue_tracker.name)
      issue.label(self.label)
      issue.url(self.issue_tracker.show_url.gsub('@@@', self.name))
      issue.state(self.state)             if self.state
      issue.summary(self.summary) if self.summary

      if self.owner_id
        # self.owner must not by used, since it is reserved by rails
        o = User.find_by_id self.owner_id
        issue.owner do |owner|
          owner.login(o.login)
          owner.email(o.email)
          owner.realname(o.realname)
        end
      end
    end
  end

  def render_axml
    builder = Nokogiri::XML::Builder.new do |node|
      self.render_body node
    end
    builder.to_xml :indent => 2, :encoding => 'UTF-8', 
                               :save_with => Nokogiri::XML::Node::SaveOptions::NO_DECLARATION |
                                             Nokogiri::XML::Node::SaveOptions::FORMAT
  end

  def to_axml
    Rails.cache.fetch('issue_%d' % self.id) do
      render_axml
    end
  end

end
