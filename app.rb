require 'sinatra'
require 'slim'
require 'sqlite3'
require 'sinatra/reloader'
# require 'becrypt'

enable :sessions

get('/') do
  slim :home
end

get('/saved') do
  slim :saved
end

get('/login') do
  slim :login
end

get('/clear_session') do
  session.clear
  slim(:home)
end

post('/login') do
  session[:name] = params[:username]
  session[:password] = params[:password]
  redirect('/login')
end
