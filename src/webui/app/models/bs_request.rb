class BsRequest < ActiveXML::Base

  class ListError < Exception; end
  class ModifyError < Exception; end

  default_find_parameter :id

  class << self
    def make_stub(opt)
      option = source_package = target_package = ""
      opt[:description] = "" if !opt.has_key? :description or opt[:description].nil?
      if opt[:targetpackage] and not opt[:targetpackage].empty?
        target_package = "package=\"#{opt[:targetpackage].to_xs}\""
      end

      # set request-specific options
      case opt[:type]
        when "submit" then
          # use source package name if no target package name is given for a submit request
          target_package = "package=\"#{opt[:package].to_xs}\"" if target_package.empty?
          # set target package is the same as the source package if no target package is specified
          revision_option = "rev=\"#{opt[:rev].to_xs}\"" unless opt[:rev].blank?
          action = "<source project=\"#{opt[:project]}\" package=\"#{opt[:package]}\" #{revision_option}/>"
          action += "<target project=\"#{opt[:targetproject].to_xs}\" #{target_package}/>"
          action += "<options><sourceupdate>#{opt[:sourceupdate]}</sourceupdate></options>" unless opt[:sourceupdate].blank?
        when "add_role" then
          action = "<group name=\"#{opt[:group]}\" role=\"#{opt[:role]}\"/>" unless opt[:group].blank?
          action = "<person name=\"#{opt[:person]}\" role=\"#{opt[:role]}\"/>" unless opt[:person].blank?
          action += "<target project=\"#{opt[:targetproject].to_xs}\" #{target_package}/>"
        when "set_bugowner" then
          action = "<person name=\"#{opt[:person]}\" role=\"#{opt[:role]}\"/>"
          action += "<target project=\"#{opt[:targetproject].to_xs}\" #{target_package}/>"
        when "change_devel" then
          action = "<source project=\"#{opt[:project]}\" package=\"#{opt[:package]}\"/>"
          action += "<target project=\"#{opt[:targetproject].to_xs}\" #{target_package}/>"
        when "maintenance_incident" then
          action = "<source project=\"#{opt[:project]}\" />"
          action += "<target project=\"#{opt[:targetproject].to_xs}\" />" unless opt[:targetproject].blank?
        when "maintenance_release" then
          action = "<source project=\"#{opt[:project]}\" />"
          action += "<target project=\"#{opt[:targetproject].to_xs}\" />" unless opt[:targetproject].blank?
        when "delete" then
          action = "<target project=\"#{opt[:targetproject].to_xs}\" #{target_package}/>"
      end
      # build the request XML
      reply = <<-EOF
        <request>
          <action type="#{opt[:type]}">
            #{action}
          </action>
          <state name="new"/>
          <description>#{opt[:description].to_xs}</description>
        </request>
      EOF
      return reply
    end

    def addReview(id, opts)
      opts = {:user => nil, :group => nil, :project => nil, :package => nil, :comment => nil}.merge opts

      transport ||= ActiveXML::Config::transport_for :bsrequest
      path = "/request/#{id}?cmd=addreview"
      path << "&by_user=#{CGI.escape(opts[:user])}" unless opts[:user].blank?
      path << "&by_group=#{CGI.escape(opts[:group])}" unless opts[:group].blank?
      path << "&by_project=#{CGI.escape(opts[:project])}" unless opts[:project].blank?
      path << "&by_package=#{CGI.escape(opts[:package])}" unless opts[:package].blank?
      begin
        r = transport.direct_http URI("#{path}"), :method => "POST", :data => opts[:comment]
        BsRequest.free_cache(id)
        return true
      rescue ActiveXML::Transport::ForbiddenError => e
        message, _, _ = ActiveXML::Transport.extract_error_message e
        raise ModifyError, message
      rescue ActiveXML::Transport::NotFoundError => e
        message, _, _ = ActiveXML::Transport.extract_error_message e
        raise ModifyError, message
      end
    end

    def modifyReview(id, changestate, opts)
      unless (changestate=="accepted" || changestate=="declined")
        raise ModifyError, "unknown changestate #{changestate}"
      end

      transport ||= ActiveXML::Config::transport_for :bsrequest
      path = "/request/#{id}?newstate=#{changestate}&cmd=changereviewstate"
      path << "&by_user=#{CGI.escape(opts[:user])}" unless opts[:user].blank?
      path << "&by_group=#{CGI.escape(opts[:group])}" unless opts[:group].blank?
      path << "&by_project=#{CGI.escape(opts[:project])}" unless opts[:project].blank?
      path << "&by_package=#{CGI.escape(opts[:package])}" unless opts[:package].blank?
      begin
        transport.direct_http URI("#{path}"), :method => "POST", :data => opts[:comment]
        BsRequest.free_cache(id)
        return true
      rescue ActiveXML::Transport::ForbiddenError, ActiveXML::Transport::NotFoundError, ActiveXML::Transport::Error => e
        message, _, _ = ActiveXML::Transport.extract_error_message e
        raise ModifyError, message
      end
    end

    def modify(id, changestate, opts)
      opts = {:superseded_by => nil, :force => false, :reason => ''}.merge opts
      if ["accepted", "declined", "revoked", "superseded", "new"].include?(changestate)
        transport ||= ActiveXML::Config::transport_for :bsrequest
        path = "/request/#{id}?newstate=#{changestate}&cmd=changestate"
        path += "&superseded_by=#{opts[:superseded_by]}" unless opts[:superseded_by].blank?
        path += "&force=1" if opts[:force]
        begin
          transport.direct_http URI("#{path}"), :method => "POST", :data => opts[:reason].to_s
          BsRequest.free_cache(id)
          return true
        rescue ActiveXML::Transport::ForbiddenError => e
          message, _, _ = ActiveXML::Transport.extract_error_message e
          raise ModifyError, message
        rescue ActiveXML::Transport::NotFoundError => e
          message, _, _ = ActiveXML::Transport.extract_error_message e
          raise ModifyError, message
        end
      end
      raise ModifyError, "unknown changestate #{changestate}"
    end

    def find_last_request(opts)
      unless opts[:targetpackage] and opts[:targetproject] and opts[:sourceproject] and opts[:sourcepackage]
        raise RuntimeError, "missing parameters"
      end
      pred = "(action/target/@package='#{opts[:targetpackage]}' and action/target/@project='#{opts[:targetproject]}' and action/source/@project='#{opts[:sourceproject]}' and action/source/@package='#{opts[:sourcepackage]}' and action/@type='submit')"
      requests = Collection.find_cached :what => :request, :predicate => pred
      last = nil
      requests.each_request do |r|
        last = r if not last or r.value(:id).to_i > last.value(:id).to_i
      end
      return last
    end

    def list(opts)
      unless opts[:states] or opts[:reviewstate] or opts[:roles] or opts[:types] or opts[:user] or opts[:project]
        raise RuntimeError, "missing parameters"
      end

      opts.delete(:types) if opts[:types] == 'all' # All types means don't pass 'type' to backend

      transport ||= ActiveXML::Config::transport_for :bsrequest
      path = "/request?view=collection"
      path << "&states=#{CGI.escape(opts[:states])}" unless opts[:states].blank?
      path << "&roles=#{CGI.escape(opts[:roles])}" unless opts[:roles].blank?
      path << "&reviewstates=#{CGI.escape(opts[:reviewstates])}" unless opts[:reviewstates].blank?
      path << "&types=#{CGI.escape(opts[:types])}" unless opts[:types].blank? # the API want's to have it that way, sigh...
      path << "&user=#{CGI.escape(opts[:user])}" unless opts[:user].blank?
      path << "&project=#{CGI.escape(opts[:project])}" unless opts[:project].blank?
      path << "&package=#{CGI.escape(opts[:package])}" unless opts[:package].blank?
      begin
        logger.debug "Fetching request list from api"
        response = transport.direct_http URI("#{path}"), :method => "GET"
        return Collection.new(response).each # last statement, implicit return value of block, assigned to 'request_list' non-local variable
      rescue ActiveXML::Transport::Error => e
        message, _, _ = ActiveXML::Transport.extract_error_message e
        raise ListError, message
      end
    end

    def creator(req)
      if req.has_element?(:history)
        #NOTE: 'req' can be a LibXMLNode or not. Depends on code path.
        if req.history.class == ActiveXML::LibXMLNode
          return req.history.who
        else
          return req.history.first[:who]
        end
      else
        return req.state.who
      end
    end

    def created_at(req)
      if req.has_element?(:history)
        #NOTE: 'req' can be a LibXMLNode or not. Depends on code path.
        if req.history.class == ActiveXML::LibXMLNode
          return req.history.when
        else
          return req.history.first[:when]
        end
      else
        return req.state.when
      end
    end
  end

  def creator
    return BsRequest.creator(self)
  end

  def created_at
    return BsRequest.created_at(self)
  end

  def history
    ret = []
    self.each_history do |h|
      ret << { :who => h.who, :when => Time.parse(h.when), :name => h.name, :comment => h.value(:comment) }
    end if self.has_element?(:history)
    h = self.state
    ret << { :who => h.who, :when => Time.parse(h.when), :name => h.name, :comment => h.value(:comment) }
    return ret
  end

  def events
    # Try to find out what happened over time...
    events = {}
    previous_item = nil
    self.each_history do |item|
      what, color = "", nil
      case item.name
        when "new" then
          if previous_item && previous_item.name == "review"
            what, color = "accepted review", "green" # Moving back to state 'new'
          elsif previous_item && previous_item.name == "declined"
            what, color = "reopened", "maroon"
          else
            what = "created request" # First history item, regardless of 'state' (may be 'review')
          end
        when "review" then
          if !previous_item # First history item
            what = "created request"
          elsif previous_item && previous_item.name == "declined"
            what = "reopened review"
          else # Other items...
            what = "added review"
          end
        when "accepted" then what, color = "accepted request", "green"
        when "declined" then
          color = "red"
          if previous_item
            case previous_item.name
              when "review" then what = "declined review"
              when "new" then what = "declined request"
            end
          end
        when "superseded" then what = "superseded request"
      end

      events[item.when] = {:who => item.who, :what => what, :when => item.when, :comment => item.value('comment')}
      events[item.when][:color] = color if color
      previous_item = item
    end
    self.each_review do |item|
      if ['accepted', 'declined'].include?(item.state)

        reviewer = ''
        if item.by_group
          reviewer = item.value('by_group')
        elsif item.by_project
          reviewer = item.value('by_project')
        elsif item.by_package
          reviewer = item.value('by_package')
        elsif item.by_user
          reviewer = item.value('by_user')
        end
        events[item.when] = {:who => item.who, :what => "#{item.state} review for #{reviewer}", :when => item.when, :comment => item.value('comment')}
        events[item.when][:color] = "green" if item.state == "accepted"
        events[item.when][:color] = "red" if item.state == "declined"
      end
    end
    # The <state ... /> element describes the last event in request's history:
    state, what, color = self.state, "", ""
    case state.value('name')
      when "accepted" then what, color = "accepted request", "green"
      when "declined" then what, color = "declined request", "red"
      when "new", "review"
        if previous_item # Last history entry
          what, color = "accepted review", "green"
        else
          what = "created request"
        end
      when "superseded" then what = "superseded request"
    end

    events[state.when] = {:who => state.who, :what => what, :when => state.when, :comment => state.value('comment')}
    events[state.when][:color] = color if color
    events[state.when][:superseded_by] = @superseded_by if @superseded_by
    # That wasn't all to difficult, no? ;-)

    sorted_events = [] # Store events sorted by key (i.e. datetime)
    events.keys.sort.each { |key| sorted_events << events[key] }
    return sorted_events
  end

end
