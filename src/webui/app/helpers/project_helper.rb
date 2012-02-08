module ProjectHelper

  protected
  
  def watch_link_text
    user.watches?(@project.name) ? "Don't watch this project" : "Watch this project"
  end

  def watch_link_image
    user.watches?(@project.name) ? "magnifier_zoom_out.png" : "magnifier_zoom_in.png"
  end

  def show_status_comment( comment, package, firstfail, comments_to_clear )
    status_comment_html = "".html_safe
    if comment
      status_comment_html = ERB::Util::h(comment)
      if !firstfail
        if @project.can_edit?( session[:login] )
          status_comment_html += " ".html_safe + link_to_remote( image_tag('icons/comment_delete.png', :size => "16x16", :alt => 'Clear'), :update => "comment_#{package.gsub(':', '-')}",
          :url => { :action => :clear_failed_comment, :project => @project, :package => package })
          comments_to_clear << package
        end
      elsif @project.can_edit?( session[:login] )
        status_comment_html += " ".html_safe
        status_comment_html += link_to_remote image_tag('icons/comment_edit.png', :alt => "Edit"), :update => "comment_edit_#{package.gsub(':', '-')}",
          :url => { :action => "edit_comment_form", :comment=> ERB::Util::h(comment), :package => package, :project => @project }
      end 
    elsif firstfail
      if @project.can_edit?( session[:login] )
        status_comment_html += " <span class='unknown_failure'>Unknown build failure ".html_safe + link_to_remote( image_tag('icons/comment_edit.png', :size => "16x16", :alt => "Edit"),
          :update => valid_xml_id("comment_edit_#{package}"),
          :url => { :action => "edit_comment_form", :comment=> "", :package => package, :project => @project } )
        status_comment_html += "</span>".html_safe
      else
        status_comment_html += "<span class='unknown_failure'>Unknown build failure</span>".html_safe
      end
    end
    status_comment_html += "<span id='".html_safe + valid_xml_id("comment_edit_#{package}") + "'></span>".html_safe
  end

  def project_bread_crumb(*args)
    @crumb_list = [link_to('Projects', :controller => 'project', :action => :list_public)]
    return if @spider_bot
    prj_parents = nil
    if @namespace # corner case where no project object is available (i.e. 'new' action)
      prj_parents = Project.parent_projects(@namespace)
    else
      #FIXME: Some controller's @project is a Project object whereas other's @project is a String object.
      prj_parents = Project.parent_projects(@project.to_s)
    end
    project_list = []
    prj_parents.each do |name, short_name|
      project_list << link_to(short_name, :controller => 'project', :action => 'show', :project => name)
    end
    @crumb_list << project_list if project_list.length > 0
    @crumb_list = @crumb_list + args
  end

  def format_seconds( secs ) 
    secs = Integer(secs)
    if secs < 3600
      "0:%02d" % (secs / 60)
    else
      hours = secs / 3600
      secs -= hours * 3600
      "%d:%02d" % [ hours, secs / 60]
    end
  end

  def rebuild_time_col( package )
     return '' if package.blank?
     btime, etime = @timings[package]
     link_to( h(package), :controller => :package, :action => :show, :project => @project, :package => package) + " " + format_seconds(btime)
  end

  def short_incident_name(maintenance_project, incident)
    re = Regexp.new("#{@project.name}\:(.*)")
    match = incident.name.match(re)
    return match[1] if match.length > 1
    return match[0]
  end

  def patchinfo_rating_color(rating)
    case rating.to_s
    when 'low' then return 'green'
    when 'moderate' then return 'olive'
    when 'important' then return 'red'
    when 'critical' then return 'maroon'
    else return ''
    end
  end

  def patchinfo_category_color(category)
    case category.to_s
    when 'optional' then return 'olive'
    when 'recommended' then return 'green'
    when 'security' then return 'maroon'
    else return ''
    end
  end

  def incident_issue_color(patchinfo_issues, package_issues)
    return 'red' if package_issues == 0
    if patchinfo_issues == package_issues
      return 'green'
    elsif patchinfo_issues < package_issues
      return 'olive'
    else
      return 'red'
    end
  end

end
