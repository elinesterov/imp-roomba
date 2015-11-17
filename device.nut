hardware.pin2.configure(DIGITAL_OUT);
roombaWakeupPin <- hardware.pin2;
roombaWakeupPin.write(1);

const SENSORS = 142;
const PACKET_CODE_GROUP_3 = 3;

status <- "";
runningCommand <- "";
commands <- {"clean":1, 
                  "sleep":1, 
                  "doc":1, 
                  "spot":1,
                  "status":1
};

hardware.uart57.configure(115200, 8, PARITY_NONE, 1, NO_CTSRTS);

function bytesToInt(byte1, byte2){
    // convert two bytes to unsugned int
    local res = ((byte1 & 0xFF) << 8) | (byte2 & 0xFF);
    return res;
}

function toSignedInt(data){
    // convert 2 bytes signed int from roomba to 4 bytes signed int in squirrel
    local signedInt = (data << (32 - 16)) >> (32 - 16);
    return signedInt
}

function wakeup(){
    //funstion to wake up imp
    roombaWakeupPin.write(0);
    imp.sleep(0.5);
    roombaWakeupPin.write(1);
    imp.sleep(0.5);
}

function start(){
    //command start
    hardware.uart57.write(128);
}
 
function controlMode(){
    // select control mode
    hardware.uart57.write(130);
}
function safeMode(){
    //select safe mode
    hardware.uart57.write(131);
}
function fullMode(){
    //select full mode
    hardware.uart57.write(132);
}
 
function sleep(){
    // sleep command
    server.log("sleeping");
    status = "sleep";
    hardware.uart57.write(133);
}

function spot(){
    //spot command
    status = "spot";
    hardware.uart57.write(134);
}
function clean(){
    // clean command
    status = "clean"
    hardware.uart57.write(135);
}

function maxClean(){
    // max clean command
    status = "max_clean";
    hardware.uart57.write(136);
}

function doc(){
    // doc command
    server.log("docking");
    status = "doc";
    hardware.uart57.write(143);
}

function resumeCommand(){
    local command = status;
    if (command in commands){
        runCommand(command);
    }
}

function isDocked(){
    // check docked satate based on current
    // if current >= 0 then roomba is in doc
    // if curren < 0 then it is discharging => not in doc
    // it doesn't handle a case when roomba is in doc but power is off
    local sensors = {};
    sensors = getSensorsData();
    local current = sensors.currentData.current;
    
    if (current >= 0){
        return true
    }
    else{
        return false
    }
}

function readAllSensors(){
    // function to read data form sensors
    local sensorByte = 0;
    local arrayLenght = 10;
    local sensorDataArray = array(arrayLenght); 

    hardware.uart57.write(SENSORS);
    hardware.uart57.write(PACKET_CODE_GROUP_3);   
    
    local data = hardware.uart57.read();
    // waiting for a first byte to arrive
    while (data == -1){
        imp.sleep(0.01);
        data = hardware.uart57.read();
    }
    
    while (data != -1){
        sensorDataArray[sensorByte] = data;
        sensorByte++;
        data = hardware.uart57.read();
        // FIXME: sleep 10ms to before trying to read next byte
        imp.sleep(0.001);
    }

    return sensorDataArray;
}

function getSensorsData(){
    // receive data from sensors and process it

    // read data from sensors
    local d = readAllSensors();

    // Voltage
    // 2 bytes unsigned
    local voltage = bytesToInt(d[1], d[2]);
    
    // Current
    // positiv means charging, negative, means roomba is running
    // signed int 2 bytes
    local current =  toSignedInt(bytesToInt(d[3], d[4]));

    // Battery temperature
    // one byte signed
    local batteryTemperature = d[5];
    
    // Charge in mAh
    // 2 bytes unsigned
    local currentCharge = bytesToInt(d[6], d[7]);
    
    // Capacity 
    // When the Charge value reaches the Capacity value, the battery is fully
    // charged.
    // 2 bytes unsigned    
    local currentCapacity = bytesToInt(d[8], d[9]);
    local docState;
    
    if (current >= 0){
        docState = true;
    }
    else{
        docState = false
    }
    
    local test_data = {"chargingState": d[0],
                 "charge": currentCharge,
                 "capacity": currentCapacity,
                 "current": current,
                 "status": status,
                 "doc_state": docState
    }
    
    local data = { currentData = test_data};
    return data;
}

function runCommand(command){
    // run command processor

    local res = {};
    local data = null;

    server.log("Processing command: " + command);

    if (command == "clean"){
        clean();
    }
    else if (command == "spot"){
        spot();
    }
    else if (command == "doc"){
        //need send sleep before doc
        // normally when you use hw buttons on roomba
        // you cannot doc if device is running
        // so we need to emulate sleep and only after that 
        // we can send doc command
        // of course we need send wake up and start commands
        // before that
        if ("status" != "sleep"){
            sleep();
            imp.sleep(0.5);
            wakeup();
            start();   
        }
        doc();
    }
    else if (command == "sleep"){
        sleep();
    }
    else if (command == "status"){
        data = getSensorsData();
    }

    // prepeare response
    if (data != null){
            res = {result = "ok", data = data, command = command};        
        }
        else{
            res = {result = "ok", command = status};
        }
    return res;
}


function commandProcesser(data){
    server.log("Received command: " + data.r);
    // TODO: need to check if device already wake up
    // the only way probably using HW input
    wakeup();
    start();
    
    local command = data.r;
    server.log("Current status: " + status);

    if (isDocked() == true){
        status = "doc"
    }
    
    if (command != status){

        if (command in commands){
            server.log("Processing command " + command + " on device");
            local result = runCommand(command);
            data.d = result;
            agent.send("asyncdata", data);
        }
    }
    else {
        data.d = {result = "error", "error": "already running command", "command": command};
        agent.send("asyncdata", data);
    }

}

// function getMacAddress(data){
//     //returns imp mac address
//     server.log(imp.getmacaddress());
//     agent.send("setMac", imp.getmacaddress());
// }

agent.on("processCommand", commandProcesser);
// agent.on("getImpMac", getMacAddress);
server.log("Device started");