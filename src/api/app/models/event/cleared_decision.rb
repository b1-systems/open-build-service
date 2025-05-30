module Event
  class ClearedDecision < Decision
    self.description = 'Reported content cleared'
    self.notification_explanation = 'Receive notifications for cleared report decisions.'

    receiver_roles :reporter

    def subject
      decision = ::Decision.find(payload['id'])
      "Cleared #{decision.reports.first.reportable&.class&.name || decision.reports.first.reportable_type} Report".squish
    end
  end
end

# == Schema Information
#
# Table name: events
#
#  id          :bigint           not null, primary key
#  eventtype   :string(255)      not null, indexed
#  mails_sent  :boolean          default(FALSE), indexed
#  payload     :text(16777215)
#  undone_jobs :integer          default(0)
#  created_at  :datetime         indexed
#  updated_at  :datetime
#
# Indexes
#
#  index_events_on_created_at  (created_at)
#  index_events_on_eventtype   (eventtype)
#  index_events_on_mails_sent  (mails_sent)
#
