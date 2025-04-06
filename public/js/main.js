document.getElementById('add-instruction').addEventListener('click', function() {
    console.log('add-instruction klickad'); // Lägg till denna rad
    let container = document.getElementById('instructions-container');
    let stepNumber = container.children.length + 1;
    let newInput = document.createElement('div');
    newInput.classList.add('instruction-input');
    newInput.innerHTML = `
      <label for="instruction${stepNumber}">Steg ${stepNumber}:</label>
      <textarea id="instruction${stepNumber}" name="instructions[]"></textarea>
    `;
    container.appendChild(newInput);
  });
  
  document.getElementById('add-ingredient').addEventListener('click', function() {
    console.log('add-ingredient klickad'); // Lägg till denna rad
    let container = document.getElementById('ingredients-container');
    let ingredientNumber = container.children.length + 1;
    let newInput = document.createElement('div');
    newInput.classList.add('ingredient-input');
    newInput.innerHTML = `
      <label for="ingredient_name${ingredientNumber}">Ingrediensnamn:</label>
      <input type="text" id="ingredient_name${ingredientNumber}" name="ingredient_names[]">
      <label for="quantity${ingredientNumber}">Mängd:</label>
      <input type="number" id="quantity${ingredientNumber}" name="quantities[]">
      <label for="unit${ingredientNumber}">Enhet:</label>
      <input type="text" id="unit${ingredientNumber}" name="units[]">
    `;
    container.appendChild(newInput);
  });