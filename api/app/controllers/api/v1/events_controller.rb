# frozen_string_literal: true

module Api
  module V1
    class EventsController < ApplicationController
      include Authenticatable
      before_action :authenticate_request
      before_action :require_events_access!

      # GET /api/v1/events
      def index
        events = Event.includes(:village).order(date: :desc)
        events = events.where(status: params[:status]) if params[:status].present?

        render json: {
          events: events.map { |e| event_json(e) }
        }
      end

      # GET /api/v1/events/:id
      def show
        event = Event.includes(event_rsvps: :supporter).find(params[:id])
        render json: { event: event_detail_json(event) }
      end

      # POST /api/v1/events
      def create
        campaign = Campaign.active.first
        event = Event.new(event_params)
        event.campaign = campaign
        event.status = "upcoming"

        if event.save
          # Auto-populate RSVPs from motorcade-available supporters
          if event.event_type == "motorcade"
            MotorcadeInviteJob.perform_later(event_id: event.id)
          end

          render json: { event: event_detail_json(event) }, status: :created
        else
          render json: { errors: event.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/events/:id/check_in
      def check_in
        event = Event.find(params[:id])
        supporter = Supporter.find(params[:supporter_id])

        rsvp = event.event_rsvps.find_or_create_by(supporter: supporter) do |r|
          r.rsvp_status = "confirmed"
        end

        rsvp.check_in!(current_user)

        # Broadcast check-in
        CampaignBroadcast.event_check_in(event, supporter, rsvp)

        render json: {
          message: "#{supporter.print_name} checked in!",
          rsvp: {
            id: rsvp.id,
            supporter_name: supporter.print_name,
            attended: rsvp.attended,
            checked_in_at: rsvp.checked_in_at&.iso8601
          },
          event_stats: {
            invited: event.invited_count,
            attended: event.reload.attended_count,
            quota: event.quota,
            quota_met: event.quota_met?
          }
        }
      end

      # POST /api/v1/events/:id/send_sms
      # Send SMS to all RSVPs with phone numbers
      def send_sms
        unless can_send_sms?
          return render_api_error(message: "SMS permission required", status: :forbidden, code: "sms_permission_required")
        end

        event = Event.find(params[:id])
        message = params[:message]

        if message.blank?
          return render_api_error(message: "Message is required", status: :unprocessable_entity, code: "message_required")
        end

        supporters = Supporter.joins(:event_rsvps)
                              .where(event_rsvps: { event_id: event.id })
                              .where.not(contact_number: [ nil, "" ])
                              .where("TRIM(supporters.contact_number) != ''")
                              .distinct

        count = supporters.count

        if params[:dry_run] == "true"
          return render json: { dry_run: true, recipient_count: count, message: message }
        end

        sent = 0
        failed = 0
        errors = []

        supporters.find_each do |supporter|
          result = ClicksendClient.send_sms(to: supporter.contact_number, body: message)
          if result[:success]
            sent += 1
          else
            failed += 1
            errors << "#{supporter.contact_number}: #{result[:error]}" if errors.length < 10
          end
        end

        AuditLog.create!(
          auditable: event,
          actor_user: current_user,
          action: "event_sms_blast",
          details: { message: message.truncate(200), sent: sent, failed: failed }
        )

        render json: { sent: sent, failed: failed, errors: errors, total: count }
      end

      # POST /api/v1/events/:id/send_email
      # Send email to all RSVPs with email addresses
      def send_email
        unless can_send_email?
          return render_api_error(message: "Email permission required", status: :forbidden, code: "email_permission_required")
        end

        event = Event.find(params[:id])
        subject = params[:subject]
        body = params[:body]

        if subject.blank? || body.blank?
          return render_api_error(message: "Subject and body are required", status: :unprocessable_entity, code: "email_content_required")
        end

        supporters = Supporter.joins(:event_rsvps)
                              .where(event_rsvps: { event_id: event.id })
                              .where.not(email: [ nil, "" ])
                              .distinct

        count = supporters.count

        if params[:dry_run] == "true"
          return render json: { dry_run: true, recipient_count: count, subject: subject }
        end

        result = SupporterEmailService.send_blast(subject: subject, body_html: body, supporters: supporters)

        AuditLog.create!(
          auditable: event,
          actor_user: current_user,
          action: "event_email_blast",
          details: { subject: subject.truncate(200), sent: result[:sent], failed: result[:failed] }
        )

        render json: { sent: result[:sent], failed: result[:failed], errors: result[:errors], total: count }
      end

      # GET /api/v1/events/:id/attendees
      def attendees
        event = Event.find(params[:id])

        rsvps = event.event_rsvps.includes(:supporter).order(:rsvp_status)
        if params[:search].present?
          q = "%#{params[:search].downcase}%"
          rsvps = rsvps.joins(:supporter).where("LOWER(supporters.print_name) LIKE ? OR LOWER(supporters.first_name) LIKE ? OR LOWER(supporters.last_name) LIKE ?", q, q, q)
        end

        render json: {
          attendees: rsvps.map { |r|
            {
              rsvp_id: r.id,
              supporter_id: r.supporter_id,
              first_name: r.supporter.first_name,
              last_name: r.supporter.last_name,
              print_name: r.supporter.print_name,
              contact_number: r.supporter.contact_number,
              village: r.supporter.village&.name,
              rsvp_status: r.rsvp_status,
              attended: r.attended,
              checked_in_at: r.checked_in_at&.iso8601
            }
          },
          stats: {
            total_invited: event.invited_count,
            confirmed: event.confirmed_count,
            attended: event.attended_count,
            show_up_rate: event.show_up_rate,
            quota: event.quota,
            quota_met: event.quota_met?
          }
        }
      end

      private

      def event_params
        params.require(:event).permit(:name, :event_type, :date, :time, :location, :description, :village_id, :quota)
      end

      def event_json(event)
        {
          id: event.id,
          name: event.name,
          event_type: event.event_type,
          date: event.date,
          time: event.time,
          location: event.location,
          village_name: event.village&.name,
          quota: event.quota,
          status: event.status,
          invited_count: event.invited_count,
          attended_count: event.attended_count,
          show_up_rate: event.show_up_rate
        }
      end

      def event_detail_json(event)
        event_json(event).merge(
          description: event.description,
          confirmed_count: event.confirmed_count,
          quota_met: event.quota_met?,
          no_show_count: event.event_rsvps.no_shows.count
        )
      end
    end
  end
end
