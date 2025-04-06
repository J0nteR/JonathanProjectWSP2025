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

  @receptdata = db.execute("SELECT * FROM recipes WHERE id = ?", [@receptid])
  @receptinstruktioner = db.execute("SELECT * FROM instructions WHERE recipe_id = ? ORDER BY step_num ASC", [@receptid])
  @receptingredienser = db.execute(
    "SELECT
        ingredients.name,
        relations.quantity,
        ingredients.unit
    FROM
        recipes
    JOIN
        relations ON recipes.id = relations.recipe_id
    JOIN
        ingredients ON relations.ingredient_id = ingredients.id
    WHERE
        recipes.id = ?", [@receptid]
  )
  slim :recipe
end

get('/saved') do

  slim :saved
end



get('/login') do
  slim :login
end

get('/clear_session') do
  session.clear
  redirect('/')
end

post('/login') do
  session[:name] = params[:username]
  session[:password] = params[:password]
  redirect('/login')
end
