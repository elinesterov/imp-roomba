commands <- {"clean":1, 
                  "sleep":1, 
                  "doc":1, 
                  "spot":1,
                  "status":1
            };

mac <- "";

// get imp's mac
device.send("getImpMac", "test");

device.on("setMac", function(data){
    mac = data;
    
    } );

server.log("Agent Started");
server.log("Imp mac: " + mac);

const TIMEOUT = 15; // close hanging async requests after 15 seconds
responses <- {};

// create unique keys for responses table
function generateKey() {
    local key = math.rand();
    while (key in responses) key = math.rand();
    return key.tostring();
}

// check every second if response is wayting > TIMEOUT
// send timeout error if true
function responsesHandler() {
    imp.wakeup(1, responsesHandler);
    local t = time();
    foreach(key, response in responses) {
        if (t - response.t > TIMEOUT) {
            local response = http.jsonencode({ "result": "error", "error": "Agent timeout"});
            responses[key].resp.header("Content-type", "application/json");
            responses[key].resp.send(408, response);
            delete responses[key];
        }
    }
} responsesHandler();

// send response back when data received from device
device.on("asyncdata", function(data) {
    //server.log("sending response");
    if (!(data.k in responses)) {
        //server.log(format("response %s already timed-out.", data.t));
        return;
    }
    local response = responses[data.k].resp;
    response.header("Content-type", "application/json");
    response.send(200, http.jsonencode(data.d));

    delete responses[data.k];
});

function httpHandler(req, resp) {

    local path = split(req.path, "/");
    local imp_mac = "";
    local command = "";
    //server.log(imp_mac);

    //extract imp mac from a path if any
    if (path.len() >= 2){
        imp_mac = path[1];
    }
    
    // check if mac is right
    // TODO: get it from device via variable?
    server.log("Mac : " + mac);


    if (imp_mac == mac){
        //server.log("Rigth request");
    
        // before processing any request need to check whether device is connected
        //server.log("Device is connected: " + device.isconnected());
        if (device.isconnected()){

            // get command from request
            if (req.method == "GET"){
                if ("status" in req.query){
                    //server.log("Processing status update command");
                    command = "status";
                }
                if ("command" in req.query){
                    //server.log("Procesing command : " + req.query["command"]);
                    
                    if (req.query["command"] in commands){
                        command = req.query["command"];
                        //server.log("Command request: " + command);
                    }
                }
                
            }
            // else if (req.method == "POST"){
            //     //server.log("POST request received: " + req.body);
            //     local body = http.jsondecode(req.body)
            //     //server.log("Body: " + body);
            //     if ("command" in body){
            //         //server.log("Command: " + body["command"]);

            //         //if (body["command"] == "start" || body["command"] == "stop"){
            //         if (body["command"] in commands){
            //             command = body["command"];
            //             //server.log("Command request: " + command);
            //         }
            //     }
            // }
            
            //send command to device
            if (command != ""){

                // generate key, and store the response object
                local responseKey = generateKey();
                responses[responseKey] <- { resp = resp, t = time() } ;

                local data = { k = responseKey, r = command, d = null };
                device.send("processCommand" data);
            }
            //wrong command need to send response about it
            else {
                local response = http.jsonencode({ "result": "error", "command": "unknown", "error": "unknown command"});
                resp.header("Content-type", "application/json");
                resp.send(200, response);
                
            }
            return;
        }
         // if diconnected response with error
        else {
            //if we can find command in request
            local response = {};
            if (req.query["command"]){
                response = http.jsonencode({ "result": "error", "error": "Device offline", "command": req.query["command"]});
            }
            else{
                response = http.jsonencode({ "result": "error", "error": "Device offline", "command": "unknown"});                
            }
            resp.header("Content-type", "application/json");
            resp.send(200, response);
            
        }
        

    }
    else{
        resp.send(401, "Unauthorized");
    }
    
}

http.onrequest(httpHandler);