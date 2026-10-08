import json
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, *args):
        pass

    def do_POST(self):
        request = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        assert request["stream"] is True
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Connection", "close")
        self.end_headers()
        targets = json.loads(request["input"])["enabled_targets"].split(",")
        target = "en" if "en" in targets else "id"
        value = "Test" if target == "en" else "Tes"
        self.event({"type": "response.output_text.delta", "delta": '{"source":"zh","' + target + '":"' + value + '",'})
        time.sleep(0.6 if target == "en" else 1.2)
        result = {"source": "zh", "zh": "测试", "en": "Test" if "en" in targets else "", "id": "Tes" if "id" in targets else "", "note": ""}
        response = {"status": "completed", "output": [{"content": [{"type": "output_text", "text": json.dumps(result)}]}]}
        self.event({"type": "response.completed", "response": response})

    def event(self, value):
        self.wfile.write(("data: " + json.dumps(value) + "\n\n").encode())
        self.wfile.flush()


ThreadingHTTPServer(("127.0.0.1", 18973), Handler).serve_forever()
