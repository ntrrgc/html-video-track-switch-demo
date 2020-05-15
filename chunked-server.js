var finalhandler = require('finalhandler')
var http = require('http')
var serveStatic = require('serve-static')
var fs = require("fs")
const {Transform} = require("stream")

// Serve up public/ftp folder
var serve = serveStatic('.', {'index': ['index.html', 'index.htm']})

function pad2(n) {
    if (n < 0) {
        throw new Error(`pad2 received negative number: ${n}`)
    }
    if (n < 10) {
        return `0${n}`;
    } else {
        return `${n}`;
    }
}

function formatTime(millis) {
    const hours = Math.floor(millis / 1000 / 3600);
    let remainder = millis - hours * 1000 * 3600;
    const minutes = Math.floor(remainder / 1000 / 60);
    remainder = remainder - minutes * 1000 * 60;
    const seconds = Math.floor(remainder / 1000);
    return `${pad2(hours)}:${pad2(minutes)}:${pad2(seconds)}`;
}

class ProgressReport extends Transform {
    constructor(opts) {
        super(opts);
        this.accumulatedBytes = 0;
        this.startTime = new Date();
    }

    _transform(data, enconding, done) {
        const time = new Date().getTime() - this.startTime.getTime();
        const start = this.accumulatedBytes;
        const end = start + data.length;
        this.accumulatedBytes = end;
        console.log(`${formatTime(time)}: Sent [${start}, ${end})`);
        done(null, data);
    }
}

// Create server
var server = http.createServer(function onRequest(req, res) {
    if (req.url.indexOf("/assets/") == 0) {
        console.log("Received an assets request, serving chunked...");
        res.writeHead(200, {
            "Content-Type": "video/mp4",
            // "Accept-Ranges": "none",
        });

        fs.createReadStream(req.url.substring(1))
            .pipe(new ProgressReport())
            .pipe(res);
        return;
    }

    serve(req, res, finalhandler(req, res))
})

// Listen
server.listen(3600)
