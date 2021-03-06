require "hashie" 
require_relative "auth/github"

# stolen from http://github.com/cschneid/irclogger/blob/master/lib/partials.rb
#   and made a lot more robust by me
# this implementation uses erb by default. if you want to use any other template mechanism
#   then replace `erb` on line 13 and line 17 with `haml` or whatever 
module Sinatra::Partials
  def partial(template, *args)
    template_array = template.to_s.split('/')
    template = template_array[0..-2].join('/') + "/_#{template_array[-1]}"
    options = args.last.is_a?(Hash) ? args.pop : {}
    options.merge!(:layout => false)
    locals = options[:locals] || {}
    if collection = options.delete(:collection) then
      collection.inject([]) do |buffer, member|
        buffer << slim(:"#{template}", options.merge(:layout =>
        false, :locals => {template_array[-1].to_sym => member}.merge(locals)))
      end.join("\n")
    else
      slim(:"#{template}", options)
    end
  end
end

class HuboardApplication < Sinatra::Base

  enable  :sessions
  enable :raise_exceptions

  if File.exists? "#{File.dirname(__FILE__)}/../.settings"
    token_file =  File.new("#{File.dirname(__FILE__)}/../.settings")
    # TODO: read this from a yaml
    eval(token_file.read) 
  elsif ENV['GITHUB_CLIENT_ID']
    set :secret_key, ENV['SECRET_KEY']
    set :team_id, ENV["TEAM_ID"]
    set :user_name, ENV["USER_NAME"]
    set :password, ENV["PASSWORD"]
    GITHUB_CONFIG = {
      :client_id     => ENV['GITHUB_CLIENT_ID'],
      :client_secret => ENV['GITHUB_SECRET'],
      :scope => "public_repo"
    }
    set :session_secret, ENV["SESSION_SECRET"]
    set :socket_backend, ENV["SOCKET_BACKEND"]
    set :socket_secret, ENV["SOCKET_SECRET"]

    set :cache_config, {
      servers: ENV["CACHE_SERVERS"] = ENV["MEMCACHIER_SERVERS"],
      username: ENV["CACHE_USERNAME"] = ENV["MEMCACHIER_USERNAME"],
      password: ENV["CACHE_PASSWORD"] = ENV["MEMCACHIER_PASSWORD"]
    }

  else
    raise "Configuration information not found: you need to provide a .settings file or ENV variables"
  end


  helpers Huboard::Common::Helpers
  helpers Sinatra::Partials

  use Rack::Session::Cookie, :key => 'rack.session', :path => '/', :secret => settings.session_secret
  set :views, File.expand_path("../views",File.dirname(__FILE__))

  use Sinatra::Auth::Github::BadAuthentication
  use Sinatra::Auth::Github::AccessDenied

  use Warden::Manager do |config|
    config.failure_app = Sinatra::Auth::Github::BadAuthentication
    config.default_strategies :github
    config.scope_defaults :default, :config => GITHUB_CONFIG
    config.scope_defaults :private, :config => GITHUB_CONFIG.merge(:scope => 'repo')
  end

  helpers do
    def warden
      env['warden']
    end

    def authenticate!(*args)
      warden.authenticate!(*args)
    end

    def authenticated?(*args)
      warden.authenticated?(*args)
    end

    def logout!
      warden.logout
    end

    def logged_in?
      return authenticated?(:private) || authenticated?
    end

    def github_config 
      return :client_id => GITHUB_CONFIG[:client_id], :client_secret => GITHUB_CONFIG[:client_secret] 
    end

  end

  set :raise_errors, true

  use Rack::Robustness do |g|

    g.no_catch_all
    g.status 302
    g.content_type 'text/html'
    g.body 'A fatal error occured.'
    g.headers "Location" => "/logout"

    g.on(Ghee::Error) 

  end


end
