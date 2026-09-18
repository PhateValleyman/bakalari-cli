#!/usr/bin/env python3
"""Minimal local Bakalari API mock used by the smoke tests."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs
import json
import sys

TOKEN = "test-token"

TIMETABLE = {
    "Subjects": [
        {"Id": "10", "Abbrev": "M", "Name": "Matematika"},
        {"Id": "57", "Abbrev": "Hv", "Name": "Hudební výchova"},
    ],
    "Teachers": [
        {"Id": "1", "Name": "Jan Test"},
    ],
    "Hours": [
        {"Id": 1, "Caption": "1", "BeginTime": "08:00", "EndTime": "08:45"},
        {"Id": 2, "Caption": "2", "BeginTime": "08:55", "EndTime": "09:40"},
    ],
    "Days": [
        {
            "DayOfWeek": 1,
            "Atoms": [
                {"HourId": 1, "SubjectId": "10", "TeacherId": "1"},
                {"HourId": 2, "SubjectId": "57", "TeacherId": "1"},
            ],
        }
    ],
}

HOMEWORKS = {
    "Homeworks": [
        {
            "IsDone": False,
            "Content": "Smoke test",
            "DateEnd": "2099-01-01T12:00:00",
            "Subject": {"Abbrev": "M"},
        }
    ]
}

MARKS = {
    "Subjects": [
        {
            "Subject": {"Id": "10", "Abbrev": "M", "Name": "Matematika"},
            "AverageText": "1,50",
            "Marks": [
                {"MarkText": "1", "Caption": "Smoke", "MarkDate": "2099-01-01T00:00:00", "Weight": 1, "IsNew": True}
            ]
        }
    ]
}

ABSENCE = {
    "PercentageThreshold": 0.18,
    "Absences": [
        {"Date": "2099-01-01T00:00:00", "Unsolved": 0, "Ok": 5, "Missed": 1, "Late": 1, "Soon": 0}
    ],
    "AbsencesPerSubject": [
        {"SubjectName": "Matematika", "LessonsCount": 6, "Base": 1, "Late": 1, "Soon": 0}
    ]
}


class Handler(BaseHTTPRequestHandler):
    def _json(self, status, payload):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _authorized(self):
        return self.headers.get("Authorization") == f"Bearer {TOKEN}"

    def do_POST(self):
        if self.path != "/api/login":
            self._json(404, {"error": "not_found"})
            return

        length = int(self.headers.get("Content-Length", "0"))
        fields = parse_qs(self.rfile.read(length).decode())
        if fields.get("username") == ["test-user"] and fields.get("password") == ["test-pass"]:
            self._json(200, {"access_token": TOKEN, "token_type": "bearer"})
        else:
            self._json(401, {"error": "invalid_grant"})

    def do_GET(self):
        if not self._authorized():
            self._json(401, {"error": "unauthorized"})
            return

        if self.path == "/api/3/timetable/actual":
            self._json(200, TIMETABLE)
        elif self.path == "/api/3/homeworks":
            self._json(200, HOMEWORKS)
        elif self.path == "/api/3/marks":
            self._json(200, MARKS)
        elif self.path == "/api/3/absence/student":
            self._json(200, ABSENCE)
        else:
            self._json(404, {"error": "not_found"})

    def log_message(self, fmt, *args):
        return


def main():
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    print(server.server_port, flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
