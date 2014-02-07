require 'sinatra'
require 'pony'
require 'base64'
require 'bigdecimal'
require 'date'
require 'net/http'
require 'net/https'
require 'time'
require 'json'
require 'net/smtp'



# setting up Harvest

class Harvest

  SUBDOMAIN        = 'lightmatter'
  ACCOUNT_EMAIL    =  'ryan@lightmatter.com'
  ACCOUNT_PASSWORD =  'good4now'
  USER_AGENT       = 'Lightmatter HQ'
  HAS_SSL          = true

  def initialize
    @company             = SUBDOMAIN
    @preferred_protocols = [HAS_SSL, ! HAS_SSL]
    connect!
end

  # HTTP headers you need to send with every request.
  def headers
    {
      # Declare that you expect response in XML after a _successful_
      # response.
      "Accept"        => "application/json",

      # Promise to send XML.
      "Content-Type"  => "application/json; charset=utf-8",

      # All requests will be authenticated using HTTP Basic Auth, as
      # described in rfc2617. Your library probably has support for
      # basic_auth built in, I've passed the Authorization header
      # explicitly here only to show what happens at HTTP level.
      "Authorization" => "Basic #{auth_string}",

      # Tell Harvest a bit about your application.
      "User-Agent"    => USER_AGENT
  }
end

def auth_string
    Base64.encode64("#{ACCOUNT_EMAIL}:#{ACCOUNT_PASSWORD}").delete("\r\n")
end

def request path, method = :get, body = ""
    response = send_request( path, method, body)
    if response.class < Net::HTTPSuccess
      # response in the 2xx range
      on_completed_request
      return response
  elsif response.class == Net::HTTPServiceUnavailable
      # response status is 503, you have reached the API throttle
      # limit. Harvest will send the "Retry-After" header to indicate
      # the number of seconds your boot needs to be silent.
      raise "Got HTTP 503 three times in a row" if retry_counter > 3
      sleep(response['Retry-After'].to_i + 5)
      request(path, method, body)
  elsif response.class == Net::HTTPFound
      # response was a redirect, most likely due to protocol
      # mismatch. Retry again with a different protocol.
      @preferred_protocols.shift
      raise "Failed connection using http or https" if @preferred_protocols.empty?
      connect!
      request(path, method, body)
  else
      dump_headers = response.to_hash.map { |h,v| [h.upcase,v].join(': ') }.join("\n")
      raise "#{response.message} (#{response.code})\n\n#{dump_headers}\n\n#{response.body}\n"
  end
end

private

def connect!
    port = has_ssl ? 443 : 80
    @connection             = Net::HTTP.new("#{@company}.harvestapp.com", port)
    @connection.use_ssl     = has_ssl
    @connection.verify_mode = OpenSSL::SSL::VERIFY_NONE if has_ssl
end

def has_ssl
    @preferred_protocols.first
end

def send_request path, method = :get, body = ''
    case method
    when :get
      @connection.get(path, headers)
  when :post
      @connection.post(path, body, headers)
  when :put
      @connection.put(path, body, headers)
  when :delete
      @connection.delete(path, headers)
  end
end

def on_completed_request
    @retry_counter = 0
end

def retry_counter
    @retry_counter ||= 0
    @retry_counter += 1
end

end

#end Harvest Setup

class Hours
    @users = {"Ben" => "576224", "Greg" => "576227", "Nicole" => "576226", "Ryan" => "576220"}
    @users_time = {}
    @bill_option = ['yes', 'no']
    @harvest = Harvest.new

    def self.get_hours_daily
        start = (Date.today).strftime("%Y/%m/%d")
        finish =   (Date.today+1).strftime("%Y/%m/%d")
        @team_daily_billable_hours = 0
        @team_daily_non_billable_hours = 0
        @users.each do |key, value|
            @total_daily_billable_hours = 0
            @total_daily_non_billable_hours = 0
            @bill_option.each do |b|
                request = @harvest.request "/people/#{value}/entries?from=#{start}&to=#{finish}&billable=#{b}", :get
                response = JSON.parse(request.body)
                x=0
                if b == 'yes'
                    while x < response.length do
                        @total_daily_billable_hours += response[x]["day_entry"]["hours"]
                        x += 1
                    end
                else
                    while x < response.length do
                        @total_daily_non_billable_hours += response[x]["day_entry"]["hours"]
                        x += 1
                    end
                end
            end
            @team_daily_billable_hours += @total_daily_billable_hours
            @team_daily_non_billable_hours += @total_daily_non_billable_hours
            @users_time["#{key} Daily Billable"] = @total_daily_billable_hours.round(2).to_s
            @users_time["#{key} Daily Non-Billable"] = @total_daily_non_billable_hours.round(2).to_s
        end
    end


    def self.get_hours_weekly
        days_of_week = [1,2,3,4,5,6,7]
        current_day =Date.today

        if current_day.monday?
            @start = (DateTime.now).strftime("%Y/%m/%d")
            @finish = (DateTime.now).strftime("%Y/%m/%d")
        elsif current_day.tuesday?
            @start = (DateTime.now-1).strftime("%Y/%m/%d")
            @finish = (DateTime.now  ).strftime("%Y/%m/%d")
        elsif current_day.wednesday?
            @start = (DateTime.now-2).strftime("%Y/%m/%d")
            @finish = (DateTime.now  ).strftime("%Y/%m/%d")
        elsif current_day.thursday?
            @start = (DateTime.now-3).strftime("%Y/%m/%d")
            @finish = (DateTime.now  ).strftime("%Y/%m/%d")
        elsif current_day.friday?
            @start = (DateTime.now-4).strftime("%Y/%m/%d")
            @finish = (DateTime.now  ).strftime("%Y/%m/%d")
        elsif current_day.saturday?
            @start = (DateTime.now-5).strftime("%Y/%m/%d")
            @finish = (DateTime.now).strftime("%Y/%m/%d")
        else
            @start = (DateTime.now-6).strftime("%Y/%m/%d")
            @finish = (DateTime.now).strftime("%Y/%m/%d")
        end

        @team_weekly_billable = 0
        @team_non_billable_weekly = 0

        @users.each do |key, value|
            @total_billable_hours = 0
            @total_non_billable_hours = 0
            @bill_option.each do |b|
                request = @harvest.request "/people/#{value}/entries?from=#{@start}&to=#{@finish}&billable=#{b}", :get
                response = JSON.parse(request.body)
                x=0
                if b == 'yes'
                    while x < response.length do
                        @total_billable_hours += response[x]["day_entry"]["hours"]
                        x += 1
                    end
                else
                    while x < response.length do
                        @total_non_billable_hours += response[x]["day_entry"]["hours"]
                        x += 1
                    end
                end
            end
            @team_weekly_billable += @total_billable_hours
            @team_non_billable_weekly += @total_non_billable_hours
            @users_time["#{key} Weekly Billable"] = @total_billable_hours.round(2).to_s
            @users_time["#{key} Weekly Non-Billable"] = @total_non_billable_hours.round(2).to_s
        end
        @total_logged_weekly = @team_weekly_billable+ @team_non_billable_weekly
    end

    def self.users_time
        @why = ""
        @users_time.each do |key, value|
            @why += "<p> #{key} = #{value}  </p>"
        end
    end



    def self.send_email
      Pony.mail({
        :to => 'ryan@lightmatter.com, team@lightmatter.com',
        :from => 'ryan@lightmatter.com',
        :subject => "#{Time.now.strftime("%d/%m/%Y")} Hours Update",
        :html_body => "<h2> Our Hours: </h2>#{@why} <h2> Team Weekly Billable: #{@team_weekly_billable.round(2)}</h2> <h2>Team Daily Billable: #{@team_daily_billable_hours.round(2)}</h2>",
        :via => :smtp,
        :via_options => {
          :address        => 'smtp.gmail.com',
          :port           => '587',
          :user_name      => 'ryan@lightmatter.com',
          :password       => 'good4now',
          :authentication => :plain,
          :domain         => "self.com"
      }
      })
  end
end


