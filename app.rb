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
  db = SQLite3::Database.new("db/project2025.db")
  db.results_as_hash = true #Få svar i strukturen [{},{},{}]

  @data = db.execute("SELECT * FROM recipes")
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
