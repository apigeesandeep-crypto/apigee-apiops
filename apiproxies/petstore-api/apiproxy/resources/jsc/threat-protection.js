var payload = context.getVariable("request.content") || "";
var uri = context.getVariable("request.uri") || "";
var check = payload + uri;

var sqlPatterns = /(\b(SELECT|INSERT|UPDATE|DELETE|DROP|UNION|ALTER|CREATE|EXEC)\b)/gi;
var xssPatterns = /(<script|javascript:|on\w+\s*=)/gi;

if (sqlPatterns.test(check) || xssPatterns.test(check)) {
    throw new Error("ThreatDetected");
}
