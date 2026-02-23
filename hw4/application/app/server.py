from flask import Flask, render_template, request, make_response, g, before_request, after_request, teardown_request,
import tempfile
import os

from style_transfer import process_image

from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST

app = Flask(__name__)
app.config['MAX_CONTENT_LENGTH'] = 20 * 1024 * 1024
ALLOWED_MODELS = ['feathers', 'mosaic', 'the_scream']

REQUESTS_TOTAL = Counter(
    "http_requests_total",
    "Total number of HTTP requests",
    ["method", "status"],
)

REQUEST_LATENCY_SECONDS = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency in seconds",
    ["method", "status"],
    buckets=(
        0.01, 0.02, 0.03, 0.04, 0.05,
        0.06, 0.07, 0.08, 0.09, 0.10,
        0.15, 0.20, 0.25, 0.30, 0.40, 0.50,
        0.75, 1.00, 1.50, 2.00, 3.00, 5.00, 10.00
    )
)


def on_request_finish(status):
    method = request.method

    start = getattr(g, "_start_time", None)
    if start is not None:
        duration = time.perf_counter() - start
    else:
        duration = None

    REQUESTS_TOTAL.labels(method=method, status=status).inc()

    if duration is not None:
        REQUEST_LATENCY_SECONDS.labels(method=method, status=status).observe(duration)


@app.before_request
def start_timer():
    g._start_time = time.perf_counter()


@app.after_request
def observe_request(response):
    on_request_finish(str(response.status_code))

    return response


@app.teardown_request
def observe_exceptions(exc):
    if exc is None:
        return

    on_request_finish("500")


@app.get("/metrics")
def metrics():
    data = generate_latest()
    return Response(data, mimetype=CONTENT_TYPE_LATEST)


@app.route('/', methods=['GET', 'POST'])
def apply_model():
    if request.method == 'POST':
        if 'model' not in request.form:
            return 'no model selected', 400
        model = request.form['model']
        if model not in ALLOWED_MODELS:
            return 'incorrect model', 400

        if 'image' not in request.files:
            return 'no image', 400
        image = request.files['image']
        if image.filename == '':
            return 'no image selected', 400
        with tempfile.NamedTemporaryFile() as input_file:
            image.save(input_file.name)
            with tempfile.NamedTemporaryFile(suffix='.jpg') as output_file:
                model_path = os.path.join(app.root_path, 'models', model + '.t7')
                process_image(input_file.name, model_path, output_file.name)
                response = make_response(output_file.read())
        response.headers.set('Content-Type', 'image/jpeg')
        return response

    return render_template('upload.html')
