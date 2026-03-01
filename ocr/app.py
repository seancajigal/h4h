from flask import Flask, request, jsonify

app = Flask(__name__)

def ocr(image_path, language="en"):
    from paddleocr import PaddleOCR

    ocr_engine = PaddleOCR(
    use_doc_orientation_classify=False,
    use_doc_unwarping=False,
    use_textline_orientation=False)

    results = ocr_engine.predict(input=image_path)
    print(results)

    return results


def analyze_and_anonymize(input_text):
    from presidio_analyzer import AnalyzerEngine
    from presidio_anonymizer import AnonymizerEngine   

    analyzer = AnalyzerEngine()
    anonymizer = AnonymizerEngine()

    results = analyzer.analyze(
    text=input_text,
    entities=[
        # Personal
        "PERSON",
        "EMAIL_ADDRESS",
        "PHONE_NUMBER",
        "AGE",
        "NRP",
        # Financial
        "CREDIT_CARD",
        "BANK_ACCOUNT",
        "IBAN_CODE",
        "US_BANK_NUMBER",
        "US_SSN",
        "US_ITIN",
        "CRYPTO",
        # Location
        "LOCATION",
        "US_DRIVER_LICENSE",
        "US_PASSPORT",
        # Medical
        "MEDICAL_LICENSE",
        "US_DEA_NUMBER",
        # Network / Tech
        "IP_ADDRESS",
        # IDs / Numbers
        "UK_NHS",
        "SG_NRIC_FIN",
        "AU_ABN",
        "AU_ACN",
        "AU_TFN",
        "AU_MEDICARE",
        "IN_PAN",
        "IN_AADHAAR",
        "IN_PASSPORT",
        "IN_VOTER",
    ],
    language="en"
    )

    # Redact
    anonymized = anonymizer.anonymize(text=input_text, analyzer_results=results)
    return anonymized.text

@app.route("/api/endpoint", methods=["POST"])
def submit():

    data = request.get_json()

    if not data:
        return jsonify({"error": "Request body must be JSON"}), 400

    input_text = data.get("text")
    url = data.get("url")

    result = {"output": {}}

    if url and not input_text:
        ocr_data = ocr(url)

        # need to check if ocr was successful and returned text before trying to access it
        if not ocr_data or not ocr_data[0]['rec_texts']:
            return jsonify({"error": "OCR failed to extract text from the image"}), 400
        
        text_array = ocr_data[0]['rec_texts']
        text = ' '.join(text_array)

    elif input_text:
        text = input_text
    else:
        return jsonify({"error": "Provide at least one of: 'text', 'url'"}), 400

    anonymized = analyze_and_anonymize(text)

    result["output"]["anonymized_text"] = anonymized
    result["status"] = "ok" 
    return jsonify(result), 200


@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok"}), 200


if __name__ == "__main__":
    app.run(debug=True, port=5000)