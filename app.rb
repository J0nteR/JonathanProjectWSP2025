require 'sinatra'
require 'slim'
require 'sqlite3'
require 'sinatra/reloader'
# require 'becrypt'

enable :sessions

get('/') do
  db = SQLite3::Database.new("db/project2025.db")
  db.results_as_hash = true

  @data = db.execute("SELECT * FROM recipes")
  slim :home
end

get('/recipe/:nummer') do
  @receptid = params[:nummer].to_i
  db = SQLite3::Database.new("db/project2025.db")
  db.results_as_hash = true

  @data2 = db.execute("SELECT * FROM recipes WHERE id = #{@receptid}")

  slim :saved
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
