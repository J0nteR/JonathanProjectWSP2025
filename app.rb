require 'sinatra'
require 'slim'
require 'sqlite3'
require 'sinatra/reloader'
require 'bcrypt'
require_relative 'model'

enable :sessions

MAX_LOGIN_ATTEMPTS = 5
COOL_DOWN_PERIOD = 60
$login_attempts = {}

before do
  if session[:user_id]
    @current_user_id = session[:user_id]
  else
    @current_user_id = nil
  end
end

# @!group Generella Routes

#  Visar startsidan med alla recept.
# @return [void]
get '/' do
  @data = get_all_recipes()
  slim :home
end

#  Visar detaljer för ett specifikt recept.
# @param id [Integer] Receptets ID.
# @return [void]
get '/recipes/:id' do
  @recept_id = params[:id].to_i
  @receptdata = get_recipe_by_id(@recept_id)
  @receptinstruktioner = get_instructions_for_recipe(@recept_id)
  @receptingredienser = get_ingredients_for_recipe(@recept_id)
  slim :recipe
end

# @!group Användarhantering

#  Visar inloggningssidan.
# @return [void]
get '/login' do
  slim :login
end

#  Visar errorsidan.
# @return [void]
get '/error' do
  @login_error = "För många misslyckade försök. Vänligen vänta #{COOL_DOWN_PERIOD} sekunder."
  slim :error
end

#  Hanterar inloggning av användare med cool-down och loggning.
# @param username [String] Användarnamnet.
# @param password [String] Användarens lösenord.
# @return [void] Omdirigerar till '/saved' vid lyckad inloggning, annars visar inloggningssidan med felmeddelande.
post '/login' do
  username = params[:username]
  password = params[:password]

  begin
    # Kontrollera cool-down
    if cool_down_active?(username)
      redirect '/error'
      return
    end

    user = get_user_by_username(username)

    if user
      if BCrypt::Password.new(user["password"]) == password
        # Inloggning lyckades
        session[:user_id] = user["id"]
        session[:username] = user["username"]
        session[:is_admin] = user["is_admin"]
        log_login(username, true)
        reset_login_attempts(username)
        redirect '/saved'
      end
    else
      @login_error = "Felaktigt användarnamn eller lösenord."
      log_login(username, false)
      increment_login_attempts(username)
      slim :login
    end

  rescue SQLite3::Exception => e
    # Databasfel
    puts "Databasfel vid inloggning: #{e.message}"
    @login_error = "Ett databasfel uppstod. Vänligen försök igen."
    log_login(username, false)
    redirect '/error'
  rescue BCrypt::Errors::InvalidHash => e
    # BCrypt-fel
    puts "BCrypt-fel: #{e.message}"
    @login_error = "Ett fel uppstod vid verifiering av lösenordet. Vänligen försök igen."
    log_login(username, false)
    redirect '/error'
  rescue => e
    # Övriga fel
    puts "Oväntat fel vid inloggning: #{e.message}"
    @login_error = "Ett oväntat fel uppstod. Vänligen försök igen."
    log_login(username, false)
    redirect '/error'
  end
end

#  Visar registreringssidan.
# @return [void]
get '/signup' do
  slim :signup
end

#  Hanterar registrering av ny användare.
# @param username [String] Det önskade användarnamnet.
# @param password [String] Det önskade lösenordet.
# @param password_confirmation [String] Lösenordet igen för bekräftelse.
# @return [void] Omdirigerar till '/login' vid lyckad registrering, annars visar registreringssidan med felmeddelanden.
post '/signup' do
  require 'bcrypt'

  # Validering
  errors = validate_user_registration(params)

  if errors.any?
    @signup_error = errors.join("<br>")
    slim(:signup)
  else
    # Hasha lösenordet
    password_hash = BCrypt::Password.create(params[:password])

    begin
      # Försök att skapa användaren
      create_user(params[:username], password_hash, 0)
      puts "Användare skapad. Omdirigerar till /login"
      redirect '/login'
    rescue SQLite3::ConstraintException => e
      if e.message.include?("UNIQUE constraint failed: user.username")
        @signup_error = "Användarnamnet är redan taget."
      else
        @signup_error = "Ett fel uppstod vid registreringen."
      end
      slim(:signup)
    rescue SQLite3::Exception => e
      puts "Databasfel vid registrering: #{e.message}"
      @signup_error = "Ett databasfel uppstod."
      slim(:signup)
    rescue => e
      puts "Oväntat fel vid registrering: #{e.message}"
      @signup_error = "Ett oväntat fel uppstod."
      slim(:signup)
    end
  end
end

#  Loggar ut användaren och rensar sessionen.
# @return [void] Omdirigerar till startsidan.
get '/clear_session' do
  session.clear
  redirect '/'
end

# @!group Recepthantering

#  Visar sidan för att visa sparade recept.
# @return [void] Visar en lista över sparade recept för den inloggade användaren, eller ett meddelande om att användaren måste logga in.
get '/saved' do
  if @current_user_id
    if session[:is_admin] == 1 # Kontrollera om användaren är admin
      @dinarecept = get_all_recipes()
    else
      @dinarecept = get_recipes_by_author(@current_user_id)
    end
  else
    @dinarecept = []
    @login_required = true
  end
  slim :saved
end

#  Visar sidan för att skapa ett nytt recept.
# @return [void]
get '/create' do
  slim :create
end

#  Hanterar skapandet av ett nytt recept.
# @param title [String] Receptets titel.
# @param description [String] Receptets beskrivning.
# @param time_needed [Integer] Tid det tar att laga receptet (i minuter).
# @param portions [Integer] Antal portioner receptet ger.
# @param instructions [Array<String>] En array av instruktioner för receptet.
# @param ingredient_names [Array<String>] En array av ingrediensnamn.
# @param quantities [Array<Integer>] En array av mängder för varje ingrediens.
# @param units [Array<String>] En array av enheter för varje ingrediens.
# @return [void] Omdirigerar till '/saved' vid lyckat skapande, annars visar sidan för att skapa recept med felmeddelanden.
post '/add_recipe' do
  # Validering
  errors = validate_recipe_data(params)

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

    recipe_id = create_recipe(author_id, params[:title], params[:description], params[:time_needed], params[:portions])

    if params[:instructions]
      step_number = 1
      params[:instructions].each do |instruction|
        create_instruction(recipe_id, step_number, instruction)
        step_number += 1
      end
    end

    if params[:ingredient_names] && params[:quantities] && params[:units]
      params[:ingredient_names].each_with_index do |name, index|
        create_ingredient_relation(recipe_id, name, params[:units][index], params[:quantities][index].to_i)
      end
    end

    redirect '/saved'
  end
end

#  Visar sidan för att redigera ett recept.
# @param id [Integer] ID för receptet som ska redigeras.
# @return [void] Visar redigeringsformuläret med förifylld data, eller ett felmeddelande om receptet inte hittas.
get '/recipes/:id/edit' do
  @recept_id = params[:id].to_i
  @recept = get_recipe_by_id(@recept_id)
  @instruktioner = get_instructions_for_recipe(@recept_id)
  @ingredienser = get_ingredients_for_recipe(@recept_id)

  if @recept
    slim(:edit)
  else
    @error = "Receptet hittades inte."
    slim(:error)
  end
end

#  Hanterar uppdatering av ett recept.
# @param id [Integer] ID för receptet som ska uppdateras.
# @param title [String] Den uppdaterade titeln för receptet.
# @param description [String] Den uppdaterade beskrivningen för receptet.
# @param time_needed [Integer] Den uppdaterade tillagningstiden.
# @param portions [Integer] Det uppdaterade antalet portioner.
# @param instructions [Array<String>] En array av uppdaterade instruktioner.
# @param ingredient_names [Array<String>] En array av uppdaterade ingrediensnamn.
# @param quantities [Array<Integer>] En array av uppdaterade mängder för ingredienser.
# @param units [Array<String>] En array av uppdaterade enheter för ingredienser.
# @return [void] Omdirigerar till receptdetaljsidan vid lyckad uppdatering, annars visar redigeringssidan med felmeddelanden.
put '/recipes/:id' do
  @recept_id = params[:id].to_i
  @recept = get_recipe_by_id(@recept_id)
  errors = validate_recipe_data(params)

  if errors.any?
    @errors = errors
    slim :edit
  else
    if session[:is_admin] == 1 || @recept['author_id'] == @current_user_id # Admin eller författare
      update_recipe(@recept_id, params[:title], params[:description], params[:time_needed], params[:portions])

      # Uppdatera instruktioner
      delete_instructions_for_recipe(@recept_id)
      if params[:instructions]
        step_number = 1
        params[:instructions].each do |instruction|
          create_instruction(@recept_id, step_number, instruction)
          step_number += 1
        end
      end

      # Uppdatera ingredienser
      delete_relations_for_recipe(@recept_id)
      if params[:ingredient_names] && params[:quantities] && params[:units]
        params[:ingredient_names].each_with_index do |name, index|
          create_ingredient_relation(@recept_id, name, params[:units][index], params[:quantities][index].to_i)
        end
      end

      redirect "/recipes/#{@recept_id}"
    else
      @error = "Du har inte behörighet att redigera detta recept."
      slim :error
    end
  end
end

#  Hanterar borttagning av ett recept.
# @param id [Integer] ID för receptet som ska tas bort.
# @return [void] Omdirigerar till '/saved' vid lyckad borttagning, annars visar ett felmeddelande.
delete '/recipes/:id' do
  @recept_id = params[:id].to_i
  @recept = get_recipe_author(@recept_id)

  if session[:is_admin] == 1 || (@recept && @recept['author_id'] == @current_user_id) # Admin eller författare
    delete_recipe(@recept_id)

    redirect '/saved'
  else
    @error = "Du har inte behörighet att ta bort detta recept."
    slim :error
  end
end
