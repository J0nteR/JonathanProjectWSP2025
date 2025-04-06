require 'sinatra'
require 'slim'
require 'sqlite3'
require 'sinatra/reloader'
require 'bcrypt'

enable :sessions

before do
  @db = SQLite3::Database.new("db/project2025.db")
  @db.results_as_hash = true

  if session[:user_id]
    @current_user_id = session[:user_id]
  else
    @current_user_id = nil
  end
end

after do
  @db.close if @db  #  Stäng anslutningen efter varje begäran
end

get('/') do
  @data = @db.execute("SELECT * FROM recipes")
  slim :home
end

get('/recipe/:nummer') do
  @receptid = params[:nummer].to_i
  @receptdata = @db.execute("SELECT * FROM recipes WHERE id = ?", [@receptid])
  @receptinstruktioner = @db.execute("SELECT * FROM instructions WHERE recipe_id = ? ORDER BY step_num ASC", [@receptid])
  @receptingredienser = @db.execute(
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
  if @current_user_id
    @dinarecept = @db.execute("SELECT * FROM recipes WHERE author_id = ?", [@current_user_id])
  else
    @dinarecept = []  # Returnera en tom array om användaren inte är inloggad
    @login_required = true
  end
  slim :saved
end



get('/create') do
  slim :create
end

post('/add_recipe') do
  # Validering
  errors = [].tap do |e|
    e << "Titel är obligatoriskt." if params[:title].nil? || params[:title].empty?
    e << "Beskrivning är obligatoriskt." if params[:description].nil? || params[:description].empty?
    e << "Tid att laga är obligatoriskt." if params[:time_needed].nil? || params[:time_needed].empty?
    e << "Antal portioner är obligatoriskt." if params[:portions].nil? || params[:portions].empty?
    e << "Minst en instruktion krävs." if params[:instructions].nil? || params[:instructions].empty?
    e << "Minst en ingrediens krävs." if params[:ingredient_names].nil? || params[:ingredient_names].empty?
  end

  if errors.any?
    @errors = errors
    status 400
    slim(:create)
  else
    if @current_user_id
      author_id = @current_user_id
    else
      @not_logged_in = true
      slim(:create)
      return
    end

    @db.execute(
      "INSERT INTO recipes (author_id, title, description, time_needed, portions) VALUES (?, ?, ?, ?, ?)",
      [author_id, params[:title], params[:description], params[:time_needed], params[:portions]]
    )

    recipe_id = @db.last_insert_row_id

    if params[:instructions]
      step_number = 1
      params[:instructions].each do |instruction|
        @db.execute(
          "INSERT INTO instructions (recipe_id, step_num, description) VALUES (?, ?, ?)",
          [recipe_id, step_number, instruction]
        )
        step_number += 1
      end
    end

    if params[:ingredient_names] && params[:quantities] && params[:units]
      params[:ingredient_names].each_with_index do |name, index|
        ingredient = @db.execute("SELECT id FROM ingredients WHERE name = ?", [name]).first
        if ingredient
          ingredient_id = ingredient["id"]
        else
          @db.execute("INSERT INTO ingredients (name, unit) VALUES (?, ?)", [name, params[:units][index]])
          ingredient_id = @db.last_insert_row_id
        end

        quantity = params[:quantities][index].nil? || params[:quantities][index].empty? ? 0 : params[:quantities][index].to_i
        @db.execute(
          "INSERT INTO relations (recipe_id, ingredient_id, quantity) VALUES (?, ?, ?)",
          [recipe_id, ingredient_id, quantity]
        )
      end
    end

    redirect '/'
  end
end

get('/login') do
  slim :login
end

get('/clear_session') do
  session.clear
  redirect '/'
end

post '/login' do
  user = @db.execute("SELECT id, username, password, is_admin FROM user WHERE username = ?", [params[:username]]).first

  if user && BCrypt::Password.new(user["password"]) == params[:password]
    session[:user_id] = user["id"]
    session[:username] = user["username"]
    session[:is_admin] = user["is_admin"]
    redirect '/saved'
  else
    @login_error = "Felaktigt användarnamn eller lösenord."
    slim :login
  end
end

get '/signup' do
  slim(:signup)
end

post '/signup' do
  # Validering
  errors = [].tap do |e|
    e << "Användarnamn krävs." if params[:username].nil? || params[:username].empty?
    e << "Lösenord krävs." if params[:password].nil? || params[:password].empty?
    e << "Lösenorden matchar inte." if params[:password] != params[:password_confirmation]
  end

  if errors.any?
    @signup_error = errors.join("<br>")
    slim(:signup)
  else
    # Hasha lösenordet
    password_hash = BCrypt::Password.create(params[:password])

    begin
      # Försök att skapa användaren
      @db.execute(
        "INSERT INTO user (username, password, is_admin) VALUES (?, ?, ?)",
        [params[:username], password_hash, 0]
      )
      # Registreringen lyckades
      puts "Användare skapad. Omdirigerar till /login"
      redirect '/login'
    rescue SQLite3::ConstraintException => e
      if e.message.include?("UNIQUE constraint failed: user.username")
        @signup_error = "Användarnamnet är redan taget."
      else
        @signup_error = "Ett fel uppstod vid registreringen."
      end
      slim(:signup) # Korrekt användning av slim
    rescue SQLite3::Exception => e
      puts "Databasfel vid registrering: #{e.message}"
      @signup_error = "Ett databasfel uppstod."
      slim(:signup) # Korrekt användning av slim
    rescue => e
      puts "Oväntat fel vid registrering: #{e.message}"
      @signup_error = "Ett oväntat fel uppstod."
      slim(:signup) # Korrekt användning av slim
    end
  end
end