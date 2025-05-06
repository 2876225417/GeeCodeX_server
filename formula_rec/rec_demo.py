from paddlex import create_model
model = create_model(model_name="PP-FormulaNet-L")
output = model.predict(input="general_formula_rec_002.png", batch_size=1)
for res in output:
    res.print()
    res.save_to_img(save_path="./output/")
    res.save_to_json(save_path="./output/res.json")
