require 'google/api_client'

class EventsController < ApplicationController

  before_action :is_authenticated?

  def index
    @event = Event.last
  end

  def show
    @event = Event.find(params[:id])
    @class = Classgroup.find(@event.classgroup_id)
    @students = @class.students.order('name ASC')
    @attendance = Attendance.where(params[:event_id])
  end

  def new
    # render :json => params
    # Make sure the users google token is active if they have one
    @current_user.refresh_token_if_expired
    @event = Event.new
    if params[:classgroup_id]
      @classgroup = @current_user.classgroups.find(params[:classgroup_id])
    else
      @classgroups = @current_user.classgroups
    end
  end

  def create
    # render :json => params

    def create_event(start_dtm,
                    end_dtm,
                    classgroup,
                    street,
                    city,
                    state,
                    zip,
                    google_event_id)

      # Create new event
      event = Event.new
      event.start = start_dtm
      event.end = end_dtm
      event.street_address = street
      event.city = city
      event.state = state
      event.zip = zip
      event.google_event_id = google_event_id
      event.classgroup_id = classgroup.id
      event.save

    end

    def create_google_event(start_dtm,
                            end_dtm,
                            classgroup,
                            street,
                            city,
                            state,
                            zip)

      event = {
        :summary => classgroup.name,
        :description => classgroup.description,
        :location => street + ', ' + city + ' ' + state + ' ' + zip,
        :start => {
          :dateTime => start_dtm
        },
        :end => {
          :dateTime => end_dtm
        }
      }

      client = Google::APIClient.new(:application_name => 'Schedulacity',
                                    :application_version => '1.0')
      client.authorization.access_token = @current_user.provider_hash
      service = client.discovered_api('calendar', 'v3')
      result = client.execute(
        :api_method => service.events.insert,
        :parameters => {
          :calendarId => 'primary',
          },
        :body => JSON.dump(event),
        :headers => {'Content-Type' => 'application/json'})
      if  result.kind_of? Net::HTTPFound # a.k.a. 302 redirect
        result = client.get(result['location'])
      end

      # puts result.body
      result.data.id

      # # http://stackoverflow.com/questions/4708069/google-calendar-data-api-integration
      # # Yep, just dealt with this myself. It says "Moved Temporarily" because it's a redirect,
      # # which the oauth gem unfortunately doesn't follow automatically. You can do something like this:
      # calendar_response = client.get "http://www.google.com/calendar/feeds/default"
      # if calendar_response.kind_of? Net::HTTPFound # a.k.a. 302 redirect
      #   calendar_response = client.get(calendar_response['location'])
      # end

    end

    # Instantiate variables
    start_dtm = DateTime.strptime(params[:event][:start] + ' ' + params[:UTC],
                                  '%m/%d/%Y %H:%M %p %z')
    end_dtm = DateTime.strptime(params[:event][:end] + ' ' + params[:UTC],
                                '%m/%d/%Y %H:%M %p %z')
    classgroup_id = params[:event][:classgroup_id]
    street = params[:event][:street]
    city = params[:event][:city]
    state = params[:event][:state]
    zip = params[:event][:zip]
    repeat = params[:event][:repeat][:repeat]

    classgroup = Classgroup.find(classgroup_id)

    if !repeat
      # Not a repeating event
      # Add single instance of the event

      if @current_user.provider
        puts "Call create google event method"
        google_event_id = create_google_event(start_dtm,
                                              end_dtm,
                                              classgroup,
                                              street,
                                              city,
                                              state,
                                              zip)
      end

      google_event_id = google_event_id || ''
      create_event(start_dtm,
                  end_dtm,
                  classgroup,
                  street,
                  city,
                  state,
                  zip,
                  google_event_id)
    else
      # Repeating event
      # Add multiple instances of the event

      # Get variables
      reoccurrence_type = params[:event][:repeat][:reoccurrence_type]
      reoccurrence_period = params[:event][:repeat][:reoccurrence_period].to_i
      first_event_start = DateTime.strptime(params[:event][:start] + ' ' +
                                            params[:UTC],
                                            '%m/%d/%Y %H:%M %p %z')
      first_event_end = DateTime.strptime(params[:event][:end] + ' ' +
                                          params[:UTC],
                                          '%m/%d/%Y %H:%M %p %z')
      days = []
      params[:event][:repeat][:days].each do |k,v|
        days << v.to_i
      end
      occurrences = (params[:event][:repeat][:occurrences] || '9999999999').to_i
      last_event = Date.strptime(params[:event][:repeat][:end_date] ||
                                        '12/31/9999', '%m/%d/%Y')

      # eventObj = {}
      # eventObj['reoccurrence_type'] = reoccurrence_type
      # eventObj['reoccurrence_period'] = reoccurrence_period
      # eventObj['first_event_start'] = first_event_start
      # eventObj['first_event_end'] = first_event_end
      # eventObj['days'] = days
      # eventObj['occurrences'] = occurrences
      # eventObj['last_event'] = last_event
      # render :json => eventObj

      event_start = first_event_start
      event_end = first_event_end
      events_created = 0
      week = 1

      loop do
        days.each_with_index do |day,idx|
          # If it's the first week and the day is less than the event start day,
          # skip to the next day
          next if week == 1 && day < event_start.wday

          # If the event_start is greater than the last event or if we have
          # already created enough occurrences, break out of the loop
          # puts "Event Start: #{event_start} \n Last Event: #{last_event + 1.day} \n Events Created: #{events_created} \n Occurrences: #{occurrences}"
          break if event_start > last_event + 1.day || events_created >= occurrences

          # Check if user has linked their google account and if so create
          # the event with google too
          if @current_user.provider
            google_event_id = create_google_event(event_start,
                                                  event_end,
                                                  classgroup,
                                                  street,
                                                  city,
                                                  state,
                                                  zip)
          end

          google_event_id = google_event_id || ''
          create_event(event_start,
                      event_end,
                      classgroup,
                      street,
                      city,
                      state,
                      zip,
                      google_event_id)

          # Update the number of events created
          events_created += 1

          # Update the next event_start date
          if idx < days.length - 1
            days_to_change = days[idx+1] - day
            event_start += days_to_change.day
            event_end += days_to_change.day
          end

        end

        # Update the week counter
        week += 1

        days_to_change = days.last - days.first
        event_start += reoccurrence_period.week
        event_end += reoccurrence_period.week
        event_start -= days_to_change.day
        event_end -= days_to_change.day

        # puts "Event Start: #{event_start} \n Last Event: #{last_event + 1.day} \n Events Created: #{events_created} \n Occurrences: #{occurrences}"
        break if event_start > last_event || events_created >= occurrences
      end
    end # end if !repeat

    redirect_to events_path

  end # end def create

  def edit
    @event = Event.find(params[:id])
  end

  def update
    # render :json => params

    @event = Event.find(params[:id])

    if params[:event].length == 1 && params[:event][:note]
      # This path is for when a user is just editing the events note from
      # the event show page
      @event.update(:note => params[:event][:note])
      flash[:info] = "Note saved"
    else
      # This path is for when a user is editing the event on the event
      # edit page
      start_dtm = DateTime.strptime(params[:event][:start] + ' ' + params[:UTC],
                                  '%m/%d/%Y %H:%M %p %z')
      end_dtm = DateTime.strptime(params[:event][:end] + ' ' + params[:UTC],
                                '%m/%d/%Y %H:%M %p %z')
      @event.update(:note => params[:event][:note],
                    :street_address => params[:event][:street_address],
                    :city => params[:event][:city],
                    :state => params[:event][:state],
                    :zip => params[:event][:zip],
                    :start => start_dtm,
                    :end => end_dtm
                    )
      flash[:info] = "Event updated"
    end

    redirect_to event_path(params[:id])
  end

  def destroy
    # render :json => params
    event = Event.find(params[:id])
    classgroup = Classgroup.find(event.classgroup_id)
    attendances = Attendance.where(event_id: event.id)

    attendances.each do |attendance|
      attendance.destroy
    end

    Event.destroy(params[:id])

    redirect_to classgroup_path(classgroup)
  end

  ### METHOD TO DISPLAY CALENDAR EVENTS ###
  respond_to :json
  def get_events
    @current_user = current_user
    events = []
    @current_user.classgroups.where(active: true).each do |c|
      c.events.each do |event|
        events << {:id => event.id, :title => Classgroup.find(event.classgroup_id).name, :start => event.start, :end => event.end, :url => "#{request.base_url}/events/#{event.id}"}
      end
    end
    render :text => events.to_json
  end

end
