Pick the ConnectWise ticket type and subtype for this support request. Reply with one JSON object in this shape:
{"type": "...", "subtype": "...", "reason": "one short sentence"}

Allowed choices, one per line as Type > Subtype (choose exactly one line, copying the names exactly):
{{ nodes.read.output.options }}

The request (JSON, written by the client):
{{ nodes.read.output.facts_json }}