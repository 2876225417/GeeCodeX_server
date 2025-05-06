from fastapi import FastAPI, File, UploadFile, HTTPException
from paddlex import create_model
import tempfile
import os
import shutil
import json

MODEL_NAME_OR_PATH = "PP-FormulaNet-S"

app = FastAPI(title="Formula Recognition Service")

model = None

@app.on_event("startup")
async def load_model_on_startup():
    global model
    try:
        print(f"Loading PaddleX model: {MODEL_NAME_OR_PATH}")
        model = create_model(MODEL_NAME_OR_PATH)
        print("PaddleX model loaded successfully.")
    except Exception as e:
        model = None
        print(f"CRITICAL ERROR: Failed to load PaddleX model '{MODEL_NAME_OR_PATH}': {e}")

@app.post("/recognize_formula")
async def recognize_formula_from_image(image_file: UploadFile = File(...)):
    if model is None:
        raise HTTPException(status_code=503, detail="Model not loaded or unvailable. Check server logs.")
    
    temp_dir = tempfile.mkdtemp()
    temp_image_path = os.path.join(temp_dir, image_file.filename if image_file.filename else "uploaded_image.png")

    try:
        with open(temp_image_path, "wb") as buffer:
            shutil.copyfileobj(image_file.file, buffer)
        print(f"Image saved to temporary path: {temp_image_path}")
        print("Performing prediction...")

        prediction_output_list = model.predict(input=temp_image_path, batch_szie=1)
        print(f"Prediction output received (type: {type(prediction_output_list)}, length: {len(prediction_output) if isinstance(prediction_output, list) else 'N/A'})")

        if not prediction_output_list:
            print("Prediction output is empty.")
            raise HTTPException(status_code=400, detail="No formula detected or prediction result is empty")
        
        latex_formulas = []
        for result_item_dict in prediction_output_list:
            if isinstance(result_item_dict, dict) and \
               'res' in result_item_dict and \
               isinstance(result_item_dict['res'], dict) and \
               'rec_formula' in result_item_dict['res'] and \
               isinstance(result_item_dict['res']['rec_formula'], str):
                
                latex_str = result_item_dict['res']['rec_formula']
                if latex_str:
                    latex_formulas.append(latex_str)
                    print(f"Expected LaTeX: {latex_str}")
                else:
                    print(f"Warning: Found 'rec_formula' but it's an empty string for item: {result_item_dict}")
            else:
                print(f"Warning: Unexpected result item structure or missing 'rec_formula': {result_item_dict}")
        
        if not latex_formulas:
            print("No LaTeX formulas extracted after processing prediction output.")
            raise HTTPException(status_code=404, detail="Formulas might be recognized, but no valid LaTeX content could be extracted.")
        
        print(f"Returing LaTeX formulas: {latex_formulas}")
        return {"latex_formulas": latex_formulas}
    
    except HTTPException:
        raise
    except Exception as e:
        print(f"An unexpected error occurred during recognition: {e}")
        raise HTTPException(status_code=500, detail="Internal server error during formula recognition.")
    finally:
        if os.path.exists(temp_dir):
            print(f"Cleaning up temporary directory: {temp_dir}")
            shutil.rmtree(temp_dir)
