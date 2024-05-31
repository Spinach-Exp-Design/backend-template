from flask import Flask
from flask_cors import CORS
import os

app = Flask(__name__)
CORS(app, origins=["*"])

@app.route("/flask")
def hello():
    return "flask inside Docker thru github!! using ECS"


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    app.run(debug=True,host='0.0.0.0',port=port)
