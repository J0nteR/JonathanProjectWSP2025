require 'sqlite3'
require 'bcrypt'

# Hanterar databasanslutningen.
def db_connection
  db = SQLite3::Database.new("db/project2025.db")
  db.results_as_hash = true
  return db
end

# @!group Recept

# Hämtar alla recept från databasen.
# @return [Array<Hash>] En array av receptdata.
def get_all_recipes
  db = db_connection
  recipes = db.execute("SELECT * FROM recipes")
  db.close
  return recipes
end

# Hämtar ett specifikt recept från databasen.
# @param id [Integer] Receptets ID.
# @return [Hash] Receptdata.
def get_recipe_by_id(id)
  db = db_connection
  recipe = db.execute("SELECT * FROM recipes WHERE id = ?", [id]).first
  db.close
  return recipe
end

# Hämtar instruktioner för ett recept.
# @param recipe_id [Integer] Receptets ID.
# @return [Array<Hash>] En array av instruktioner.
def get_instructions_for_recipe(recipe_id)
  db = db_connection
  instructions = db.execute("SELECT * FROM instructions WHERE recipe_id = ? ORDER BY step_num ASC", [recipe_id])
  instructions = [] unless instructions
  db.close
  return instructions
end

# Hämtar ingredienser för ett recept.
# @param recipe_id [Integer] Receptets ID.
# @return [Array<Hash>] En array av ingredienser.
def get_ingredients_for_recipe(recipe_id)
  db = db_connection
  ingredients = db.execute(
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
        recipes.id = ?", [recipe_id]
  )
  ingredients = [] unless ingredients
  db.close
  return ingredients
end

# Skapar ett nytt recept i databasen.
# @param author_id [Integer] ID för receptets författare.
# @param title [String] Receptets titel.
# @param description [String] Receptets beskrivning.
# @param time_needed [Integer] Tillagningstid i minuter.
# @param portions [Integer] Antal portioner.
# @return [Integer] ID för det nyligen skapade receptet.
def create_recipe(author_id, title, description, time_needed, portions)
  db = db_connection
  db.execute(
    "INSERT INTO recipes (author_id, title, description, time_needed, portions) VALUES (?, ?, ?, ?, ?)",
    [author_id, title, description, time_needed, portions]
  )
  recipe_id = db.last_insert_row_id
  db.close
  return recipe_id
end

# Uppdaterar ett recept i databasen.
# @param id [Integer] ID för receptet som ska uppdateras.
# @param title [String] Uppdaterad titel.
# @param description [String] Uppdaterad beskrivning.
# @param time_needed [Integer] Uppdaterad tillagningstid.
# @param portions [Integer] Uppdaterat antal portioner.
# @return [void]
def update_recipe(id, title, description, time_needed, portions)
  db = db_connection
  db.execute(
    "UPDATE recipes SET title = ?, description = ?, time_needed = ?, portions = ? WHERE id = ?",
    [title, description, time_needed, portions, id]
  )
  db.close
end

# Tar bort ett recept från databasen.
# @param id [Integer] ID för receptet som ska tas bort.
# @return [void]
def delete_recipe(id)
  db = db_connection
  db.execute("DELETE FROM recipes WHERE id = ?", [id])
  db.execute("DELETE FROM instructions WHERE recipe_id = ?", [id])
  db.execute("DELETE FROM relations WHERE recipe_id = ?", [id])
  db.close
end

# @!group Instruktioner

# Skapar en ny instruktion för ett recept.
# @param recipe_id [Integer] ID för receptet.
# @param step_num [Integer] Stegnummer.
# @param description [String] Instruktionens beskrivning.
# @return [void]
def create_instruction(recipe_id, step_num, description)
  db = db_connection
  db.execute(
    "INSERT INTO instructions (recipe_id, step_num, description) VALUES (?, ?, ?)",
    [recipe_id, step_num, description]
  )
  db.close
end

# @!group Ingredienser

# Skapar en ny ingrediens i databasen (om den inte redan finns) och skapar en relation till receptet.
# @param recipe_id [Integer] ID för receptet.
# @param name [String] Ingrediensens namn.
# @param unit [String] Ingrediensens enhet.
# @param quantity [Integer] Ingrediensens mängd.
# @return [void]
def create_ingredient_relation(recipe_id, name, unit, quantity)
  db = db_connection
  ingredient = db.execute("SELECT id FROM ingredients WHERE name = ?", [name]).first
  if ingredient
    ingredient_id = ingredient["id"]
  else
    db.execute("INSERT INTO ingredients (name, unit) VALUES (?, ?)", [name, unit])
    ingredient_id = db.last_insert_row_id
  end

  db.execute(
    "INSERT INTO relations (recipe_id, ingredient_id, quantity) VALUES (?, ?, ?)",
    [recipe_id, ingredient_id, quantity]
  )
  db.close
end

# @!group Användare

# Hämtar en användare från databasen baserat på användarnamn.
# @param username [String] Användarnamnet.
# @return [Hash, nil] Användardata eller nil om användaren inte hittas.
def get_user_by_username(username)
  db = db_connection
  user = db.execute("SELECT id, username, password, is_admin FROM user WHERE username = ?", [username]).first
  db.close
  return user
end

# Skapar en ny användare i databasen.
# @param username [String] Användarnamnet.
# @param password_hash [String] Hashat lösenord.
# @param is_admin [Integer] Adminstatus (0 eller 1).
# @return [void]
def create_user(username, password_hash, is_admin)
  db = db_connection
  db.execute(
    "INSERT INTO user (username, password, is_admin) VALUES (?, ?, ?)",
    [username, password_hash, is_admin]
  )
  db.close
end

# @!group Validering

# Validerar användarregistreringsdata.
# @param params [Hash] Parametrar från registreringsformuläret.
# @return [Array<String>] En array av felmeddelanden (tom om ingen fel).
def validate_user_registration(params)
  errors = []
  errors << "Användarnamn krävs." if params[:username].nil? || params[:username].empty?
  errors << "Lösenord krävs." if params[:password].nil? || params[:password].empty?
  errors << "Lösenorden matchar inte." if params[:password] != params[:password_confirmation]
  return errors
end

# Validerar receptdata.
# @param params [Hash] Parametrar från receptformuläret.
# @return [Array<String>] En array av felmeddelanden (tom om ingen fel).
def validate_recipe_data(params)
  errors = [].tap do |e|
    e << "Titel är obligatoriskt." if params[:title].nil? || params[:title].empty?
    e << "Beskrivning är obligatoriskt." if params[:description].nil? || params[:description].empty?
    e << "Tid att laga är obligatoriskt." if params[:time_needed].nil? || params[:time_needed].empty?
    e << "Antal portioner är obligatoriskt." if params[:portions].nil? || params[:portions].empty?
    e << "Minst en instruktion krävs." if params[:instructions].nil? || params[:instructions].empty?
    e << "Minst en ingrediens krävs." if params[:ingredient_names].nil? || params[:ingredient_names].empty?
  end
  return errors
end

# Hämtar receptets författare.
# @param id [Integer] ID för receptet.
# @return [Hash, nil] Receptets författare eller nil om receptet inte hittas.
def get_recipe_author(id)
  db = db_connection
  author = db.execute("SELECT author_id FROM recipes WHERE id = ?", [id]).first
  db.close
  return author
end

# Tar bort instruktioner för ett recept.
# @param recipe_id [Integer] ID för receptet.
# @return [void]
def delete_instructions_for_recipe(recipe_id)
  db = db_connection
  db.execute("DELETE FROM instructions WHERE recipe_id = ?", [recipe_id])
  db.close
end

# Tar bort relationer för ett recept.
# @param recipe_id [Integer] ID för receptet.
# @return [void]
def delete_relations_for_recipe(recipe_id)
  db = db_connection
  db.execute("DELETE FROM relations WHERE recipe_id = ?", [recipe_id])
  db.close
end

# Hämtar recept från en viss författare
# @param author_id [Integer] ID för receptets författare.
# @return [Array<Hash>] En array av receptdata.
def get_recipes_by_author(author_id)
  db = db_connection
  recipes = db.execute("SELECT *, author_id FROM recipes WHERE author_id = ?", [author_id])
  db.close
  return recipes
end
