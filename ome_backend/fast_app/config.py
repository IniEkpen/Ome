import os
from dotenv import load_dotenv

load_dotenv();

def get_ocr_key():
    return os.getenv("LLAMA_API_KEY");

if __name__ == "__main__":
    print(get_ocr_key());